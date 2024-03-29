define(['./scripts.xml', './script-blockly.xml', './script-editor.xml', './toolbox.xml', './blocks.json', './blocks-lua'], function(scriptsTemplate, scriptBlocklyTemplate, scriptEditorTemplate, toolboxXml, blocks, blocksLua) {

  function getMatches(s, r) {
    var matches = [];
    var m;
    var re = new RegExp(r, 'g');
    while ((m = re.exec(s)) !== null) {
      matches.push(m[1]);
    }
    return matches;
  }
  function enumToOptions(e) {
    return [e.title, e.const];
  }
  function buildOptions(l) {
    if (isArrayWithItems(l)) {
      return l.map(enumToOptions);
    }
    return [['(no things)', '-empty-']];
  }
  function exportToLua(workspace) {
    //Blockly.Lua.INFINITE_LOOP_TRAP = 'if(--window.LoopTrap == 0) throw "Infinite loop.";\n';
    var lines = [
      "local script = ...",
      "local logger = require('jls.lang.logger')",
      "local Date = require('jls.util.Date')",
      "local utils = require('lha.utils')",
      ""
    ];
    var varRegExp = new RegExp('^[a-zA-Z_][a-zA-Z0-9_]*$'); // Protection against invalid variable names
    var varNames = workspace.getAllVariables().map(function(v) {return v.name;}).filter(function(n) {return varRegExp.test(n)});
    varNames.sort();
    if (varNames.length > 0) {
      lines.push('local ' + varNames.join(', '), '');
    }
    var code = Blockly.Lua.workspaceToCode(workspace);
    // TODO Find a proper way to extract the function names
    var names = getMatches(code, /\nfunction ([a-zA-Z][a-zA-Z0-9_]+)\(/g);
    names.sort();
    if (names.length > 0) {
      lines.push('local ' + names.join(', '), '');
    }
    lines.push(code, '');
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
    //console.log('exportAs()', text);
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
    workspace.registerButtonCallback('showLua', function() {
      var win = window.open('', 'Lua-' + self.scriptId, 'popup=yes,scrollbars=yes,resizable=yes,toolbar=no,location=no,directories=no,status=no,menubar=no');
      win.document.title = 'Lua ' + self.name;
      win.document.body.innerHTML = '<pre>' + exportToLua(workspace) + '</pre>';
    });
    workspace.registerButtonCallback('exportLua', function() {
      exportAs(exportToLua(workspace), 'lha-script-' + self.name.replace(/\W/g, '-') + '.lua');
    });
    workspace.registerButtonCallback('exportXml', function() {
      exportAs(exportToXml(workspace), 'lha-blocks-' + self.name.replace(/\W/g, '-') + '.xml');
    });
    workspace.registerButtonCallback('importXml', function() {
      self.$refs.uploadInput.click();
    });
    return workspace;
  };

  var blockEnv = {
    lhaDataColor: 38,
    lhaEventColor: 58,
    lhaExpressionColor: 78,
    lhaExperimentalColor: 0,
    lhaEventNames: [
      { const: "-disabled-", title: "never" },
      { const: "startup", title: "startup" },
      { const: "poll", title: "polling" },
      { const: "shutdown", title: "shutdown" },
      { const: "heartbeat", title: "heartbeat" },
      { const: "test", title: "testing" }
    ].map(enumToOptions),
    getThingPathOptions: [],
    setThingPathOptions: [],
    eventThingPathOptions: []
  };
  // Register custom blocks
  for (var name in blocks) {
    Blockly.Blocks[name] = (function (name, block) {
      return {
        init: function() {
          //console.log('init block ' + name);
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
    })(name, blocks[name]);
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
        }).then(assertIsOk).then(function() {
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
    }).then(assertIsOk).then(function() {
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
  function onTest() {
    console.log('Testing script');
    fetch('/engine/extensions/' + this.scriptId + '/test', {method: 'POST'});
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
          this.workspace = loadBlockly(this);
        }
        var self = this;
        app.getEnumsById().then(function(enumsById) {
          // Prepare data fields
          assignMap(blockEnv, {
            getThingPathOptions: buildOptions(enumsById.readablePropertyPaths),
            setThingPathOptions: buildOptions(enumsById.writablePropertyPaths),
            eventThingPathOptions: buildOptions(enumsById.allPropertyPaths)
          });
        }).finally(function() {
          if (scriptId) {
            self.scriptId = scriptId;
            self.refresh();
          }
        });
      },
      uploadThenSave: function(event) {
        var input = event.target;
        if (input.files.length !== 1) {
          return;
        }
        var self = this;
        fetch('/engine/scriptFiles/' + self.scriptId + '/blocks.xml', {
          method: 'PUT',
          body: input.files[0]
        }).then(assertIsOk).then(function() {
          toaster.toast('Blocks uploaded');
          self.refresh();
        });
      },
      onLogs: onLogs,
      onDelete: onDelete,
      onRename: onRename,
      onApply: onApply,
      onPoll: onPoll,
      onTest: onTest,
      onSave: function() {
        var scriptId = this.scriptId;
        console.log('scriptsEditor.onSave(), scriptId is "' + scriptId + '"');
        var workspace = this.workspace;
        if (!scriptId || !workspace) {
          return;
        }
        // generate
        var code, xmlText;
        try {
          code = exportToLua(workspace);
          xmlText = exportToXml(workspace);
        } catch (e) {
          toaster.toast('Error');
          return Promise.reject(e);
        }
        // save
        return Promise.all([
          fetch('/engine/scriptFiles/' + scriptId + '/blocks.xml', {
            method: 'PUT',
            body: xmlText
          }).then(assertIsOk),
          fetch('/engine/scriptFiles/' + scriptId + '/script.lua', {
            method: 'PUT',
            body: code
          }).then(assertIsOk)
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
      onTest: onTest,
      onSave: function() {
        var scriptId = this.scriptId;
        console.log('scriptsEditor.onSave(), scriptId is "' + scriptId + '"');
        if (!scriptId) {
          return;
        }
        return fetch('/engine/scriptFiles/' + scriptId + '/script.lua', {
          method: 'PUT',
          body: this.text
        }).then(assertIsOk).then(function() {
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
            }).then(assertIsOk).then(function() {
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
        }).then(assertIsOk);
        this.onShow();
      }
    }
  });

  addPageComponent(scriptsBlocklyVue);
  addPageComponent(scriptsEditorVue);
  addPageComponent(scriptsVue, 'fa-scroll');

});
