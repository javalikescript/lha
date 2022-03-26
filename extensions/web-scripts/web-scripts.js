define(['requirePath', './scripts.xml', './script-editor.xml'], function(requirePath, scriptsTemplate, scriptEditorTemplate) {

  var exportToLua = function(workspace) {
    //Blockly.Lua.INFINITE_LOOP_TRAP = 'if(--window.LoopTrap == 0) throw "Infinite loop.";\n';
    var code = Blockly.Lua.workspaceToCode(workspace);
    code = "local script = ...\nlocal logger = require('jls.lang.logger')\n\n" + code;
    return code;
  };
  var exportToXml = function(workspace) {
    var xml = Blockly.Xml.workspaceToDom(workspace);
    // domToPrettyText domToText
    var xmlText = Blockly.Xml.domToPrettyText(xml);
    //console.log('scriptsEditor.save()', xmlText);
    return xmlText;
  };
  var exportAs = function(text, filename, type) {
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
  };

  var loadBlockly = function(self, toolboxXml) {
    //console.log('using toolbox', toolboxXml);
    var workspace = Blockly.inject('scriptsEditorBlocklyDiv', {
      media: '/static/blockly/media/',
      toolbox: toolboxXml
    });
    var lhaEventColor = 48;
    var lhaStatementColor = 58;
    // Prepare data fields
    var dataPathField = {
      "type": "field_input",
      "name": "PATH",
      "text": "some/path"
    };
    if (self.things && self.things.length > 0) {
      // thing in things thing.title
      // v-for="(property, name) in thing.properties thing.thingId + '/' + name  property.title
      var thingPathOptions = [];
      for (var i = 0; i < self.things.length; i++) {
        var thing = self.things[i];
        for (var name in thing.properties) {
          var property = thing.properties[name];
          thingPathOptions.push([
            thing.title + ' - ' + property.title,
            thing.thingId + '/' + name
          ]);
        }
      }
      dataPathField = {
        "type": "field_dropdown",
        "name": "PATH",
        "options": thingPathOptions
      };
    }
    // Register custom blocks
    Blockly.Blocks['lha_poll'] = {
      init: function() {
        this.jsonInit({
          "message0": "On polling",
          "message1": "do %1",
          "args1": [{
            "type": "input_statement",
            "name": "DO"
          }],
          "colour": lhaEventColor
        });
      }
    };
    Blockly.Lua['lha_poll'] = function(block) {
      var code = Blockly.Lua.statementToCode(block, 'DO');
      code = "script:subscribeEvent('poll', function()\n" + code + "end)\n";
      return code;
    };
    Blockly.Blocks['lha_event'] = {
      init: function() {
        this.jsonInit({
          "message0": "On %1",
          "args0": [{
            "type": "field_dropdown",
            "name": "EVENT",
            "options": [
              [ "startup", "startup" ],
              [ "poll", "poll" ],
              [ "shutdown", "shutdown" ]
            ]
          }],
          "message1": "do %1",
          "args1": [{
            "type": "input_statement",
            "name": "DO"
          }],
          "colour": lhaEventColor
        });
      }
    };
    Blockly.Lua['lha_event'] = function(block) {
      var code = Blockly.Lua.statementToCode(block, 'DO');
      var event = block.getFieldValue('EVENT');
      code = "script:subscribeEvent('" + event + "', function()\n" + code + "end)\n";
      return code;
    };
    Blockly.Blocks['lha_log'] = {
      init: function() {
        this.jsonInit({
          "message0": "Log %1 %2",
          "args0": [{
            "type": "field_dropdown",
            "name": "LEVEL",
            "options": [
              [ "ERROR", "ERROR" ],
              [ "WARN", "WARN" ],
              [ "INFO", "INFO" ],
              [ "CONFIG", "CONFIG" ],
              [ "FINE", "FINE" ],
              [ "FINER", "FINER" ],
              [ "FINEST", "FINEST" ]
            ]
          }, {
            "type": "input_value",
            "name": "MESSAGE",
            "check": "String"
          }],
          "previousStatement": null,
          "nextStatement": null,
          "colour": lhaStatementColor
        });
      }
    };
    Blockly.Lua['lha_log'] = function(block) {
      var level = block.getFieldValue('LEVEL')
      //var message = '"' + block.getFieldValue('MESSAGE') + '"';
      var message = Blockly.Lua.valueToCode(block, 'MESSAGE', Blockly.JavaScript.ORDER_NONE);
      return "logger:log(logger." + level + ", tostring(" + message + "))\n";
    };
    Blockly.Blocks['lha_schedule'] = {
      init: function() {
        this.jsonInit({
          "message0": "Every %1",
          "args0": [{
            "type": "field_input",
            "name": "VALUE",
            "text": "0 0 * * *"
          }],
          "message1": "do %1",
          "args1": [{
            "type": "input_statement",
            "name": "DO"
          }],
          "colour": lhaEventColor
        });
      }
    };
    Blockly.Lua['lha_schedule'] = function(block) {
      var code = Blockly.Lua.statementToCode(block, 'DO');
      var value = block.getFieldValue('VALUE');
      code = "script:registerSchedule('" + value + "', function()\n" + code + "end)\n";
      return code;
    };
    Blockly.Blocks['lha_get_data'] = {
      init: function() {
        this.jsonInit({
          "message0": "Get %1",
          "args0": [dataPathField],
          "output": null,
          "colour": lhaStatementColor
        });
      }
    };
    Blockly.Lua['lha_get_data'] = function(block) {
      var path = block.getFieldValue('PATH');
      var code = "script:getDataValue('" + path + "')";
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    };
    Blockly.Blocks['lha_set_data'] = {
      init: function() {
        this.jsonInit({
          "message0": "Set %1 %2",
          "args0": [dataPathField, {
            "type": "input_value",
            "name": "VALUE"
            //"check": "String"
          }],
          "previousStatement": null,
          "nextStatement": null,
          "colour": lhaStatementColor
        });
      }
    };
    Blockly.Lua['lha_set_data'] = function(block) {
      var path = block.getFieldValue('PATH');
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      return "script:setDataValue('" + path + "', " + value + ")\n";
    };
    Blockly.Blocks['lha_watch_data'] = {
      init: function() {
        this.jsonInit({
          "message0": "Watch %1",
          "args0": [dataPathField],
          "message1": "new: %1",
          "args1": [{
            "type": "field_variable",
            "name": "NEW_VALUE",
            "variable": null
          }],
          "message2": "do %1",
          "args2": [{
            "type": "input_statement",
            "name": "DO"
          }],
          "colour": lhaEventColor
        });
      }
    };
    Blockly.Lua['lha_watch_data'] = function(block) {
      var code = Blockly.Lua.statementToCode(block, 'DO');
      var path = block.getFieldValue('PATH');
      var newValue = Blockly.Lua.variableDB_.getName(block.getFieldValue('NEW_VALUE'), Blockly.Variables.NAME_TYPE);
      //var oldValue = Blockly.Lua.variableDB_.getName(block.getFieldValue('OLD_VALUE'), Blockly.Variables.NAME_TYPE);
      var oldValue = '_';
      code = "script:watchValue('data/" + path + "', function(" + newValue + ", " + oldValue + ")\n" + code + "end)\n";
      return code;
    };
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

  var scriptsEditorVue = new Vue({
    template: scriptEditorTemplate,
    data: {
      scriptId: '',
      things: [],
      savedContent: null,
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
            self.things = things;
            return fetch(requirePath + '/toolbox.xml')
          }).then(function(response) {
            return response.text();
          }).then(function(toolboxXml) {
            self.workspace = loadBlockly(self, toolboxXml);
            if (self.scriptId) {
              self.refresh();
            }
          });
        } else if (scriptId) {
          this.scriptId = scriptId;
          this.refresh();
        }
      },
      onDelete: function() {
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
      },
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
        fetch('/engine/scriptFiles/' + scriptId + '/blocks.xml', {
          method: 'PUT',
          body: xmlText
        }).then(function() {
          return fetch('/engine/scriptFiles/' + scriptId + '/script.lua', {
            method: 'PUT',
            body: code
          });
        }).then(function() {
          toaster.toast('Saved');
        });
      },
      refresh: function() {
        var workspace = this.workspace;
        if (workspace) {
          return fetch('/engine/scriptFiles/' + this.scriptId + '/blocks.xml').then(function(response) {
            return response.text();
          }).then(function(xmlText) {
            workspace.clear();
            var xml = Blockly.Xml.textToDom(xmlText);
            Blockly.Xml.domToWorkspace(xml, workspace);
          });
        }
        return Promise.reject('workspace not initialized');
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
      reloadScript: function (script) {
        fetch('/engine/scripts/' + script.id + '/reload', {method: 'POST'}).then(function() {
          toaster.toast('Script reloaded');
        });
      },
      activateScript: function (script) {
        //console.log('activateScript()' + script.active);
        fetch('/engine/configuration/extensions/' + script.id + '/active', {
          method: 'POST',
          body: JSON.stringify({
            value: !script.active
          })
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

  addPageComponent(scriptsEditorVue);
  addPageComponent(scriptsVue);

  menu.pages.push({
    id: 'scripts',
    name: 'Scripts'
  });
  
});
