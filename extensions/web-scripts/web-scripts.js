define(['requirePath', './scripts.xml', './script-editor.xml'], function(requirePath, scriptsTemplate, scriptEditorTemplate) {

  var exportToLua = function(workspace) {
    //Blockly.Lua.INFINITE_LOOP_TRAP = 'if(--window.LoopTrap == 0) throw "Infinite loop.";\n';
    return [
      "local script = ...",
      "local logger = require('jls.lang.logger')",
      "local Date = require('jls.util.Date')",
      "",
      Blockly.Lua.workspaceToCode(workspace)
    ].join('\n');
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
    var getThingPathOptions = [];
    var setThingPathOptions = [];
    var eventThingPathOptions = [];
    if (self.things && self.things.length > 0) {
      // thing in things thing.title
      for (var i = 0; i < self.things.length; i++) {
        var thing = self.things[i];
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
    // Register custom blocks
    Blockly.Blocks['lha_event'] = {
      init: function() {
        this.jsonInit({
          "message0": "on %1",
          "args0": [{
            "type": "field_dropdown",
            "name": "EVENT",
            "options": [
              [ "startup", "startup" ],
              [ "polling", "poll" ],
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
          "message0": "log %1 %2",
          "args0": [{
            "type": "field_dropdown",
            "name": "LEVEL",
            "options": [
              [ "error", "ERROR" ],
              [ "warn", "WARN" ],
              [ "info", "INFO" ],
              [ "config", "CONFIG" ],
              [ "fine", "FINE" ],
              [ "finer", "FINER" ],
              [ "finest", "FINEST" ]
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
          "message0": "every %1",
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
          "message0": "get %1",
          "args0": [{
            "type": "field_dropdown",
            "name": "PATH",
            "options": getThingPathOptions
          }],
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
          "message0": "set %1 %2",
          "args0": [{
            "type": "field_dropdown",
            "name": "PATH",
            "options": setThingPathOptions
          }, {
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
          "message0": "watch %1",
          "args0": [{
            "type": "field_dropdown",
            "name": "PATH",
            "options": eventThingPathOptions
          }],
          "message1": "new: %1",
          "args1": [{
            "type": "field_variable",
            "name": "NEW_VALUE",
            "variable": "value"
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
      code = "script:watchValue('data/" + path + "', function(" + newValue + ")\n" + code + "end)\n";
      return code;
    };
    Blockly.Blocks['lha_timer'] = {
      init: function() {
        this.jsonInit({
          "message0": "set timer %1",
          "args0": [{
            "type": "field_input",
            "name": "NAME",
            "text": "my timer"
          }],
          "message1": "in %1 %2",
          "args1": [{
            "type": "field_input",
            "name": "VALUE",
            "text": "1"
          }, {
            "type": "field_dropdown",
            "name": "SECONDS",
            "options": [
              [ "seconds", "1" ],
              [ "minutes", "60" ],
              [ "hours", "3600" ]
            ]
          }],
          "message2": "do %1",
          "args2": [{
            "type": "input_statement",
            "name": "DO"
          }],
          "previousStatement": null,
          "nextStatement": null,
          "colour": lhaStatementColor
        });
      }
    };
    Blockly.Lua['lha_timer'] = function(block) {
      var name = block.getFieldValue('NAME');
      var value = block.getFieldValue('VALUE');
      var millis = parseInt(block.getFieldValue('SECONDS'), 10);
      var code = Blockly.Lua.statementToCode(block, 'DO');
      return "script:setTimer(function()\n" + code + "end, " + (value * millis) + ", '" + name + "')\n";
    };
    Blockly.Blocks['lha_clear_timer'] = {
      init: function() {
        this.jsonInit({
          "message0": "clear timer %1",
          "args0": [{
            "type": "field_input",
            "name": "NAME",
            "text": "my timer"
          }],
          "previousStatement": null,
          "nextStatement": null,
          "colour": lhaStatementColor
        });
      }
    };
    Blockly.Lua['lha_clear_timer'] = function(block) {
      var name = block.getFieldValue('NAME');
      return "script:clearTimer('" + name + "')\n";
    };
    Blockly.Blocks['lha_to_string'] = {
      init: function() {
        this.jsonInit({
          "message0": "to String %1",
          "args0": [{
            "type": "input_value",
            "name": "VALUE"
          }],
          "output": null,
          "colour": lhaStatementColor
        });
      }
    };
    Blockly.Lua['lha_to_string'] = function(block) {
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      var code = "tostring(" + value + ")";
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    };
    Blockly.Blocks['lha_time'] = {
      init: function() {
        this.jsonInit({
          "message0": "get time",
          "args0": [],
          "output": null,
          "colour": lhaStatementColor
        });
      }
    };
    Blockly.Lua['lha_time'] = function(block) {
      var code = "os.time()";
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    };
    Blockly.Blocks['lha_parse_time'] = {
      init: function() {
        this.jsonInit({
          "message0": "parse date time from %1",
          "args0": [{
            "type": "input_value",
            "name": "VALUE"
          }],
          "output": null,
          "colour": lhaStatementColor
        });
      }
    };
    Blockly.Lua['lha_parse_time'] = function(block) {
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      var code = "((Date.fromISOString(tostring(" + value + ")) or 0) // 1000)";
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    };
    Blockly.Blocks['lha_format_time'] = {
      init: function() {
        this.jsonInit({
          "message0": "format date time from %1",
          "args0": [{
            "type": "input_value",
            "name": "VALUE"
          }],
          "output": null,
          "colour": lhaStatementColor
        });
      }
    };
    Blockly.Lua['lha_format_time'] = function(block) {
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      var code = "Date:new((tonumber(" + value + ") or 0) * 1000):toISOString(true, true)";
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    };
    Blockly.Blocks['lha_date'] = {
      init: function() {
        this.jsonInit({
          "message0": "get date field %1 from %2",
          "args0": [{
            "type": "field_dropdown",
            "name": "FIELD",
            "options": [
              [ "hours (decimal)", "H.ms" ],
              [ "weekday (0-6)", "w" ],
              [ "month (1-12)", "m" ],
              [ "day", "d" ],
              [ "hours", "H" ],
              [ "minutes", "M" ],
              [ "seconds", "S" ],
              [ "yearweek (0-53)", "W" ],
              [ "year", "Y" ]
            ]
          }, {
            "type": "input_value",
            "name": "VALUE"
          }],
          "output": null,
          "colour": lhaStatementColor
        });
      }
    };
    Blockly.Lua['lha_date'] = function(block) {
      var field = block.getFieldValue('FIELD');
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      var code;
      if (field === 'H.ms') {
        code = "(function(h, m, s) return tonumber(h) + tonumber(m) / 60 + tonumber(s) / 3600; end)(string.match(os.date('%H %M %S', " + value + "), '(%d+) (%d+) (%d+)'))";
      } else {
        code = "tonumber(os.date('%" + field + "', " + value + "))";
      }
      return [code, Blockly.JavaScript.ORDER_MEMBER];
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
      newName: false,
      name: '',
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
      onRename: function () {
        var self = this;
        return fetch('/engine/scripts/' + this.scriptId + '/name', {
          method: 'PUT',
          body: this.newName
        }).then(function() {
          self.name = self.newName;
          self.newName = false;
          toaster.toast('Renamed');
        });
      },
      onApply: function () {
        var scriptId = this.scriptId;
        return this.onSave().then(function() {
          return fetch('/engine/scripts/' + scriptId + '/reload', {method: 'POST'});
        }).then(function() {
          toaster.toast('Script reloaded');
        });
      },
      onPoll: function () {
        return fetch('/engine/extensions/' + this.scriptId + '/poll', {method: 'POST'}).then(function() {
          toaster.toast('Script polled');
        });
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

  addPageComponent(scriptsEditorVue);
  addPageComponent(scriptsVue, 'fa-scroll');

});
