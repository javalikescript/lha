define(['./scripts.xml', './script-blockly.xml', './script-editor.xml', './toolbox.xml', './blocks.json', './blocks-lua'], function(scriptsTemplate, scriptBlocklyTemplate, scriptEditorTemplate, toolboxXml, blocks, blocksLua) {

  function exportToLua(workspace) {
    //Blockly.Lua.INFINITE_LOOP_TRAP = 'if(--window.LoopTrap == 0) throw "Infinite loop.";\n';
    var lines = [
      "local script = ...",
      "local logger = require('jls.lang.logger')",
      "local Date = require('jls.util.Date')",
      ""
    ];
    var varNames = workspace.getAllVariables().map(function(v) {return v.name;}).join(', ');
    if (varNames.length > 0) {
      lines.push('local ' + varNames, '');
    }
    lines.push(Blockly.Lua.workspaceToCode(workspace), '');
    return lines.join('\n');
  }
  function exportToXml(workspace) {
    var xml = Blockly.Xml.workspaceToDom(workspace);
    // domToPrettyText domToText
    var xmlText = Blockly.Xml.domToPrettyText(xml);
    //console.log('scriptsEditor.save()', xmlText);
    return xmlText;
  }
  function exportAs(text, filename, type) {
    console.log('exportAs()', text);
    var blob = new window.Blob([text], {type : (type || 'text/plain')});
    var blobUrl = window.URL.createObjectURL(blob);
    var clickHandler = function() {
      setTimeout(function() {
        URL.revokeObjectURL(blobUrl);
      }, 150);
    };
    const a = document.createElement('a');
    a.href = blobUrl;
    a.download = filename || 'download';
    a.addEventListener('click', clickHandler, {capture: false, once: true});
    a.click();
    //window.open(blobUrl);
    //window.URL.revokeObjectURL(blobUrl);
  }
  function loadBlockly(self) {
    //console.log('using toolbox', toolboxXml);
    var workspace = Blockly.inject('scriptsEditorBlocklyDiv', {
      media: '/static/blockly/media/',
      toolbox: toolboxXml
    });
    // Registers action buttons
    workspace.registerButtonCallback('refresh', function() {
      self.refresh().then(function() {
        toaster.toast('Refreshed');
      });
    });
    workspace.registerButtonCallback('clear', function() {
      workspace.clear();
      toaster.toast('Cleared');
    });
    workspace.registerButtonCallback('delete', self.onDelete);
    workspace.registerButtonCallback('save', self.onSave);
    workspace.registerButtonCallback('exportLua', function() {
      exportAs(exportToLua(workspace), 'script.lua');
    });
    workspace.registerButtonCallback('exportXml', function() {
      exportAs(exportToXml(workspace), 'script.xml');
    });
    return workspace;
  };

  var blockEnv = {
    lhaEventColor: 48,
    lhaExpressionColor: 58,
    lhaStatementColor: 68
  };
  // Register custom blocks
  for (var name in blocks) {
    Blockly.Blocks[name] = (function (block) {
      return {
        init: function() {
          var b = deepMap(block, function(v) {
            if ((typeof v === 'string') && (v.charAt(0) === '$')) {
              var vv = blockEnv[v.substring(1)]
              if (vv !== undefined) {
                return vv;
              }
            }
            return v;
          });
          this.jsonInit(b);
        }
      };
    })(blocks[name]);
  }
  for (var name in blocksLua) {
    Blockly.Lua[name] = blocksLua[name];
  }

  function onDelete() {
    var scriptId = this.scriptId;
    console.log('scriptsEditor.onDelete(), scriptId is "' + scriptId + '"');
    if (scriptId) {
      confirmation.ask('Delete the script?').then(function() {
        fetch('/engine/scripts/' + scriptId + '/', {
          method: 'DELETE'
        }).then(function() {
          toaster.toast('Deleted');
        });
      });
    }
  }
  function onRename() {
    var self = this;
    return fetch('/engine/scripts/' + this.scriptId + '/name', {
      method: 'PUT',
      body: this.newName
    }).then(function() {
      self.name = self.newName;
      self.newName = false;
      toaster.toast('Renamed');
    });
  }
  function onApply() {
    var scriptId = this.scriptId;
    return this.onSave().then(function() {
      return fetch('/engine/scripts/' + scriptId + '/reload', {method: 'POST'});
    }).then(function() {
      toaster.toast('Script reloaded');
    });
  }
  function onPoll() {
    return fetch('/engine/extensions/' + this.scriptId + '/poll', {method: 'POST'}).then(function() {
      toaster.toast('Script polled');
    });
  }
  function onLogs(logs) {
    if (logs) {
      for (var i = 0; i < logs.length; i++) {
        var log = logs[i];
        var msg = 'Engine: ' + log.message
        switch (log.level) {
        case 100:
          console.error(msg);
          break;
        case 90:
          console.warn(msg);
          break;
        case 80:
          console.info(msg);
          break;
        case 70:
          console.log(msg);
          break;
        default:
          console.debug(msg);
          break;
        }
      }
    }
  }

  var scriptsBlocklyVue = new Vue({
    template: scriptBlocklyTemplate,
    data: {
      scriptId: '',
      newName: false,
      name: '',
      things: [],
      workspace: null
    },
    methods: {
      onShow: function(scriptId) {
        console.log('scriptsEditor.onShow()');
        if (this.workspace === null) {
          if (scriptId) {
            this.scriptId = scriptId;
          }
          var self = this;
          app.getThings().then(function(things) {
            // Prepare data fields
            var getThingPathOptions = [];
            var setThingPathOptions = [];
            var eventThingPathOptions = [];
            if (things && things.length > 0) {
              // thing in things thing.title
              for (var i = 0; i < things.length; i++) {
                var thing = things[i];
                for (var name in thing.properties) {
                  var property = thing.properties[name];
                  var option = [
                    thing.title + ' - ' + property.title,
                    thing.thingId + '/' + name
                  ];
                  if (!property.readOnly) {
                    setThingPathOptions.push(option);
                  }
                  if (!property.writeOnly) {
                    getThingPathOptions.push(option);
                  }
                  eventThingPathOptions.push(option);
                }
              }
            }
            assignMap(blockEnv, {
              getThingPathOptions: getThingPathOptions,
              setThingPathOptions: setThingPathOptions,
              eventThingPathOptions: eventThingPathOptions
            });
            self.workspace = loadBlockly(self);
            if (self.scriptId) {
              self.refresh();
            }
          });
        } else if (scriptId) {
          this.scriptId = scriptId;
          this.refresh();
        }
      },
      onLogs: onLogs,
      onDelete: onDelete,
      onRename: onRename,
      onApply: onApply,
      onPoll: onPoll,
      onSave: function() {
        var scriptId = this.scriptId;
        console.log('scriptsEditor.onSave(), scriptId is "' + scriptId + '"');
        var workspace = this.workspace;
        if (!scriptId || !workspace) {
          return;
        }
        // generate
        var code = exportToLua(workspace);
        var xmlText = exportToXml(workspace);
        // save
        return Promise.all([
          fetch('/engine/scriptFiles/' + scriptId + '/blocks.xml', {
            method: 'PUT',
            body: xmlText
          }),
          fetch('/engine/scriptFiles/' + scriptId + '/script.lua', {
            method: 'PUT',
            body: code
          })
        ]).then(function() {
          toaster.toast('Saved');
        });
      },
      refresh: function() {
        var workspace = this.workspace;
        if (!workspace) {
          return Promise.reject('workspace not initialized');
        }
        return Promise.all([
          fetch('/engine/scriptFiles/' + this.scriptId + '/blocks.xml').then(function(response) {
            return response.text();
          }),
          fetch('/engine/scriptFiles/' + this.scriptId + '/manifest.json').then(function(response) {
            return response.json();
          })
        ]).then(apply(this, function(xmlText, manifest) {
          workspace.clear();
          var xml = Blockly.Xml.textToDom(xmlText);
          Blockly.Xml.domToWorkspace(xml, workspace);
          this.name = manifest.name;
        }));
      }
    }
  });

  var scriptsEditorVue = new Vue({
    template: scriptEditorTemplate,
    data: {
      scriptId: '',
      newName: false,
      name: '',
      text: ''
    },
    methods: {
      onShow: function(scriptId) {
        if (scriptId) {
          this.scriptId = scriptId;
          this.refresh();
        }
      },
      onLogs: onLogs,
      onDelete: onDelete,
      onRename: onRename,
      onApply: onApply,
      onPoll: onPoll,
      onSave: function() {
        var scriptId = this.scriptId;
        console.log('scriptsEditor.onSave(), scriptId is "' + scriptId + '"');
        if (!scriptId) {
          return;
        }
        return fetch('/engine/scriptFiles/' + scriptId + '/script.lua', {
          method: 'PUT',
          body: this.text
        }).then(function() {
          toaster.toast('Saved');
        });
      },
      refresh: function() {
        return Promise.all([
          fetch('/engine/scriptFiles/' + this.scriptId + '/script.lua').then(function(response) {
            return response.text();
          }),
          fetch('/engine/scriptFiles/' + this.scriptId + '/manifest.json').then(function(response) {
            return response.json();
          })
        ]).then(apply(this, function(luaText, manifest) {
          this.text = luaText;
          this.name = manifest.name;
        }));
      }
    }
  });

  var scriptsVue = new Vue({
    template: scriptsTemplate,
    data: {
      scripts: []
    },
    methods: {
      onShow: function () {
        this.scripts = [];
        var self = this;
        fetch('/engine/scripts/', {
          headers: {
            "Accept": 'application/json'
          }
        }).then(function(response) {
          return response.json();
        }).then(function(scripts) {
          self.scripts = scripts;
        });
      },
      pollScript: function (script) {
        fetch('/engine/extensions/' + script.id + '/poll', {method: 'POST'}).then(function() {
          toaster.toast('Script polled');
        });
      },
      reloadScript: function (script) {
        fetch('/engine/scripts/' + script.id + '/reload', {method: 'POST'}).then(function() {
          toaster.toast('Script reloaded');
        });
      },
      openScript: function (script) {
        app.toPage(script.hasBlocks ? 'scriptsBlockly' : 'scriptsEditor', script.id);
      },
      onTransform: function(script) {
        if (script.id && script.hasBlocks) {
          confirmation.ask('Transform the script?').then(function() {
            script.hasBlocks = false;
            fetch('/engine/scriptFiles/' + script.id + '/blocks.xml', {
              method: 'DELETE'
            }).then(function() {
              toaster.toast('Transformed');
            });
          });
        }
      },
      activateScript: function (script) {
        //console.log('activateScript()' + script.active);
        var activate = !script.active;
        return fetch('/engine/extensions/' + script.id + '/' + (activate ? 'enable' : 'disable'), {method: 'POST'}).then(function() {
          toaster.toast('Script ' + (activate ? 'enabled' : 'disabled'));
        });
      },
      newScript: function () {
        fetch('/engine/scripts/', {
          method: 'PUT'
        });
        this.onShow();
      }
    }
  });

  addPageComponent(scriptsBlocklyVue);
  addPageComponent(scriptsEditorVue);
  addPageComponent(scriptsVue, 'fa-scroll');

});
