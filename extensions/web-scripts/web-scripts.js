define(['./scripts.xml', './scripts-add.xml', './scripts-rename.xml',
  './script-blockly.xml', './toolbox.xml', './blocks.json', './blocks-lua',
  './script-view.xml', './script-view-config.xml', './view-schema.json',
  './script-editor.xml', './dependencies.js'],
  function(scriptsTemplate, scriptsAddTemplate, scriptsRenameTemplate,
    scriptBlocklyTemplate, toolboxXml, blocks, blocksLua,
    scriptViewTemplate, scriptViewConfigTemplate, scriptsViewConfigSchema,
    scriptEditorTemplate)
{

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

  var scriptPath = '/engine/scripts/';
  var scriptFilesPath = '/engine/scriptFiles/';

  var blockEnv = {
    lhaDataColor: 38,
    lhaEventColor: 58,
    lhaExpressionColor: 78,
    lhaExperimentalColor: 0,
    lhaEventNames: [
      { const: "-disabled-", title: "never" },
      { const: "startup", title: "startup" },
      { const: "shutdown", title: "shutdown" },
      { const: "poll", title: "polling" },
      { const: "data", title: "data" },
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
        fetch(scriptPath + scriptId + '/', {
          method: 'DELETE'
        }).then(assertIsOk).then(function() {
          app.replacePage('scripts');
          toaster.toast('Deleted');
        });
      });
    }
  }
  function onRename() {
    var self = this;
    return fetch(scriptPath + this.scriptId + '/name', {
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
      return fetch(scriptPath + scriptId + '/reload', {method: 'POST'});
    }).then(function() {
      toaster.toast('Script reloaded');
    });
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
        fetch(scriptFilesPath + self.scriptId + '/blocks.xml', {
          method: 'PUT',
          body: input.files[0]
        }).then(assertIsOk).then(function() {
          toaster.toast('Blocks uploaded');
          self.refresh();
        });
      },
      onPoll: function() {
        return fetch('/engine/extensions/' + this.scriptId + '/poll', {method: 'POST'}).then(function() {
          toaster.toast('Script polled');
        });
      },
      onTest: function() {
        console.log('Testing script');
        return fetch('/engine/extensions/' + this.scriptId + '/test', {method: 'POST'});
      },
      onLogs: function(logs) {
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
      },
      onDelete: onDelete,
      onRename: onRename,
      onApply: onApply,
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
          fetch(scriptFilesPath + scriptId + '/blocks.xml', {
            method: 'PUT',
            body: xmlText
          }).then(assertIsOk),
          fetch(scriptFilesPath + scriptId + '/script.lua', {
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
          fetch(scriptFilesPath + this.scriptId + '/blocks.xml').then(getResponseText),
          fetch(scriptFilesPath + this.scriptId + '/manifest.json').then(getResponseJson)
        ]).then(apply(this, function(xmlText, manifest) {
          workspace.clear();
          var xml = Blockly.Xml.textToDom(xmlText);
          Blockly.Xml.domToWorkspace(xml, workspace);
          this.name = manifest.name;
        }));
      }
    }
  });

  var scriptsViewVue = new Vue({
    template: scriptViewTemplate,
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
      onDelete: onDelete,
      onRename: onRename,
      onApply: onApply,
      onSave: function() {
        console.log('scriptsEditor.onSave(), scriptId is "' + this.scriptId + '"');
        if (!this.scriptId) {
          return;
        }
        return fetch(scriptFilesPath + this.scriptId + '/view.xml', {method: 'PUT', body: this.text}).then(assertIsOk).then(function() {
          toaster.toast('Saved');
        });
      },
      refresh: function() {
        return Promise.all([
          fetch(scriptFilesPath + this.scriptId + '/view.xml').then(assertIsOk).then(getResponseText),
          fetch(scriptFilesPath + this.scriptId + '/manifest.json').then(assertIsOk).then(getJson)
        ]).then(apply(this, function(text, manifest) {
          this.text = text;
          this.name = manifest.name;
        }));
      }
    }
  });

  var scriptsViewConfigVue = new Vue({
    template: scriptViewConfigTemplate,
    data: {
      scriptId: '',
      schema: {},
      config: {}
    },
    methods: {
      onShow: function(scriptId) {
        this.scriptId = scriptId;
        return Promise.all([
          fetch(scriptFilesPath + this.scriptId + '/config.json').then(getJson),
          app.getEnumsById()
        ]).then(apply(this, function(config, enumsById) {
          //console.info('schema:', populateJsonSchema(scriptsViewConfigSchema, enumsById));
          this.schema = populateJsonSchema(scriptsViewConfigSchema, enumsById);
          this.config = config;
        }));
      },
      onSave: function() {
        return putJson(scriptFilesPath + this.scriptId + '/config.json', this.config).then(assertIsOk).then(function() {
          app.back();
          toaster.toast('Saved');
        });
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
      onDelete: onDelete,
      onRename: onRename,
      onApply: onApply,
      onSave: function() {
        var scriptId = this.scriptId;
        console.log('scriptsEditor.onSave(), scriptId is "' + scriptId + '"');
        if (!scriptId) {
          return;
        }
        return fetch(scriptFilesPath + scriptId + '/script.lua', {
          method: 'PUT',
          body: this.text
        }).then(assertIsOk).then(function() {
          toaster.toast('Saved');
        });
      },
      refresh: function() {
        return Promise.all([
          fetch(scriptFilesPath + this.scriptId + '/script.lua').then(assertIsOk).then(getResponseText),
          fetch(scriptFilesPath + this.scriptId + '/manifest.json').then(assertIsOk).then(getJson)
        ]).then(apply(this, function(luaText, manifest) {
          this.text = luaText;
          this.name = manifest.name;
        }));
      }
    }
  });

  var scriptsAddVue = new Vue({
    template: scriptsAddTemplate,
    methods: {
      newScript: function () {
        fetch(scriptPath, {method: 'PUT'}).then(assertIsOk).then(function() {
          app.replacePage('scripts');
        });
      },
      newBlocks: function () {
        fetch(scriptPath, {method: 'PUT', headers: {'LHA-Name': 'New Blocks'}}).then(assertIsOk).then(getResponseText).then(function(scriptId) {
          return fetch(scriptFilesPath + scriptId + '/blocks.xml', {
            method: 'PUT',
            body: '<xml xmlns="http://www.w3.org/1999/xhtml"></xml>'
          });
        }).then(function() {
          app.replacePage('scripts');
        });
      },
      newView: function () {
        fetch(scriptPath, {method: 'PUT', headers: {
          'LHA-Name': 'New View',
          'LHA-Script': '//web-scripts/view-addon.lua'
        }}).then(assertIsOk).then(getResponseText).then(function(scriptId) {
          return Promise.all([
            fetch(scriptFilesPath + scriptId + '/view.xml', {method: 'PUT', body: '<!-- View content -->'}),
            fetch(scriptFilesPath + scriptId + '/config.json', {method: 'PUT', body: [
              '{',
              '  "id": "view-' + scriptId + '",',
              '  "title": "View ' + scriptId + '"',
              '}'
            ].join('\n')}),
            fetch(scriptFilesPath + scriptId + '/init.js', {method: 'PUT', body: [
              "define(['addon/web-scripts/view-loader.js', './config.json', './view.xml'], function(viewLoader, config, viewXml) {",
              "  viewLoader.load(config, viewXml);",
              "});"
            ].join('\n')})
          ]);
        }).then(function() {
          app.replacePage('scripts');
        });
      }
    }
  });

  var scriptsRenameVue = new Vue({
    template: scriptsRenameTemplate,
    data: {
      properties: [],
      count: 0,
      fromPath: '',
      toPath: ''
    },
    methods: {
      onShow: function () {
        app.getEnumsById().then(function(enumsById) {
          this.properties = enumsById.allPropertyPaths;
        }.bind(this));
      },
      rename: function (from, to) {
        var headers = {'LHA-RenameProperty': from};
        if (to) {
          headers['LHA-To'] = to;
        }
        return fetch(scriptPath, {method: 'POST', headers: headers}).then(assertIsOk).then(getJson);
      },
      preview: function () {
        this.count = 0;
        return this.rename(this.fromPath).then(function(r) {
          this.count = r.count;
        }.bind(this));
      },
      onRename: function () {
        return this.rename(this.fromPath, this.toPath).then(function(r) {
          toaster.toast(r.fileCount + ' file(s) in ' + r.count + ' script(s)');
        });
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
        fetch(scriptPath, {headers: {"Accept": 'application/json'}}).then(getResponseJson).then(function(scripts) {
          self.scripts = scripts;
        });
      },
      pollScript: function (script) {
        fetch('/engine/extensions/' + script.id + '/poll', {method: 'POST'}).then(function() {
          toaster.toast('Script polled');
        });
      },
      reloadScript: function (script) {
        fetch(scriptPath + script.id + '/reload', {method: 'POST'}).then(function() {
          toaster.toast('Script reloaded');
        });
      },
      openScript: function (script) {
        var pageId = 'scriptsEditor';
        if (script.hasBlocks) {
          pageId = 'scriptsBlockly';
        } else if (script.hasView) {
          pageId = 'scriptsView';
        }
        app.toPage(pageId, script.id);
      },
      activateScript: function (script) {
        //console.log('activateScript()' + script.active);
        var activate = !script.active;
        return fetch('/engine/extensions/' + script.id + '/' + (activate ? 'enable' : 'disable'), {method: 'POST'}).then(function() {
          toaster.toast('Script ' + (activate ? 'enabled' : 'disabled'));
        });
      },
      onNew: function() {
        app.toPage('scripts-add');
      }
    }
  });

  addPageComponent(scriptsAddVue);
  addPageComponent(scriptsRenameVue);
  addPageComponent(scriptsBlocklyVue);
  addPageComponent(scriptsViewVue);
  addPageComponent(scriptsViewConfigVue);
  addPageComponent(scriptsEditorVue);
  addPageComponent(scriptsVue, 'scroll', true, true);

});
