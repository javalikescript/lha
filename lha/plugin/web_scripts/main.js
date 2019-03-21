define(['requirePath'], function(requirePath) {
//define(['./toolbox.xml'], function(toolboxXml) {

  var loadBlockly = function(self, toolboxXml) {
    //console.log('using toolbox', toolboxXml);
    var workspace = Blockly.inject('scriptsEditorBlocklyDiv', {
      media: '/static/blockly/media/',
      toolbox: toolboxXml
    });
    var lhaColor = 58;
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
          "colour": lhaColor
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
          "colour": lhaColor
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
              [ "DEBUG", "DEBUG" ],
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
          "colour": lhaColor
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
          "message0": "When %1",
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
          "colour": lhaColor
        });
      }
    };
    Blockly.Lua['lha_schedule'] = function(block) {
      var code = Blockly.Lua.statementToCode(block, 'DO');
      var value = block.getFieldValue('VALUE');
      code = "script:registerSchedule('" + value + "', function()\n" + code + "end)\n";
      return code;
    };
    var lhaPrefixes = [
      [ "data", "data/" ],
      [ "configuration", "configuration/" ]
    ];
    Blockly.Blocks['lha_get'] = {
      init: function() {
        this.jsonInit({
          "message0": "Get %1 %2",
          "args0": [{
            "type": "field_dropdown",
            "name": "PREFIX",
            "options": lhaPrefixes
          }, {
            "type": "field_input",
            "name": "PATH",
            "text": "some/path"
          }],
          "output": null,
          "colour": lhaColor
        });
      }
    };
    Blockly.Lua['lha_get'] = function(block) {
      var prefix = block.getFieldValue('PREFIX')
      var path = block.getFieldValue('PATH');
      var code = "script:getValue('" + prefix + path + "')";
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    };
    Blockly.Blocks['lha_set'] = {
      init: function() {
        this.jsonInit({
          "message0": "Set %1 %2 %3",
          "args0": [{
            "type": "field_dropdown",
            "name": "PREFIX",
            "options": lhaPrefixes
          }, {
            "type": "field_input",
            "name": "PATH",
            "text": "some/path"
          }, {
            "type": "input_value",
            "name": "VALUE"
            //"check": "String"
          }],
          "previousStatement": null,
          "nextStatement": null,
          "colour": lhaColor
        });
      }
    };
    Blockly.Lua['lha_set'] = function(block) {
      var prefix = block.getFieldValue('PREFIX')
      var path = block.getFieldValue('PATH');
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      return "script:setValue('" + prefix + path + "', " + value + ")\n";
    };
    Blockly.Blocks['lha_fire'] = {
      init: function() {
        this.jsonInit({
          "message0": "Fire %1 %2 %3",
          "args0": [{
            "type": "field_dropdown",
            "name": "PREFIX",
            "options": lhaPrefixes
          }, {
            "type": "field_input",
            "name": "PATH",
            "text": "some/path"
          }, {
            "type": "input_value",
            "name": "VALUE"
            //"check": "String"
          }],
          "previousStatement": null,
          "nextStatement": null,
          "colour": lhaColor
        });
      }
    };
    Blockly.Lua['lha_fire'] = function(block) {
      var prefix = block.getFieldValue('PREFIX')
      var path = block.getFieldValue('PATH');
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      return "script:fireChange('" + prefix + path + "', " + value + ")\n";
    };
    Blockly.Blocks['lha_watch'] = {
      init: function() {
        this.jsonInit({
          "message0": "Watch %1 %2",
          "args0": [{
            "type": "field_dropdown",
            "name": "PREFIX",
            "options": lhaPrefixes
          }, {
            "type": "field_input",
            "name": "PATH",
            "text": "some/path"
          }],
          //"message1": "new: %1, previous: %2",
          "message1": "new: %1",
          "args1": [{
            "type": "field_variable",
            "name": "NEW_VALUE",
            "variable": null
          }/*, {
            "type": "field_variable",
            "name": "OLD_VALUE",
            "variable": null
          }*/],
          "message2": "do %1",
          "args2": [{
            "type": "input_statement",
            "name": "DO"
          }],
          "colour": lhaColor
        });
      }
    };
    Blockly.Lua['lha_watch'] = function(block) {
      var code = Blockly.Lua.statementToCode(block, 'DO');
      var prefix = block.getFieldValue('PREFIX')
      var path = block.getFieldValue('PATH');
      //var newValue = Blockly.Lua.valueToCode(block, 'NEW_VALUE', Blockly.JavaScript.ORDER_NONE);
      //var oldValue = Blockly.Lua.valueToCode(block, 'OLD_VALUE', Blockly.JavaScript.ORDER_NONE);
      //var newValue = block.getFieldValue('NEW_VALUE');
      //var oldValue = block.getFieldValue('OLD_VALUE');
      var newValue = Blockly.Lua.variableDB_.getName(block.getFieldValue('NEW_VALUE'), Blockly.Variables.NAME_TYPE);
      //var oldValue = Blockly.Lua.variableDB_.getName(block.getFieldValue('OLD_VALUE'), Blockly.Variables.NAME_TYPE);
      var oldValue = '_';
      code = "script:watchValue('" + prefix + path + "', function(" + newValue + ", " + oldValue + ")\n" + code + "end)\n";
      return code;
    };
    // Registers action buttons
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
    var saveAs = function(text, type, filename) {
      var blob = new window.Blob([text], {type : (type || 'text/plain')});
      var blobUrl = window.URL.createObjectURL(blob);
      window.open(blobUrl, 'script')
    };
    workspace.registerButtonCallback('refresh', function() {
      self.refresh();
      toaster.toast('Refreshed');
    });
    workspace.registerButtonCallback('clear', function() {
      workspace.clear();
      toaster.toast('Clear');
    });
    workspace.registerButtonCallback('delete', function() {
      if (!self.name) {
        return;
      }
      fetch('/engine/scripts/' + self.name + '.xml', {
        method: 'DELETE'
      }).then(function() {
        toaster.toast('Deleted');
        fetch('/engine/scripts/' + self.name + '.lua', {
          method: 'DELETE'
        });
      });
    });
    workspace.registerButtonCallback('save', function() {
      if (!self.name) {
        return;
      }
      // generate
      var code = exportToLua(workspace);
      var xmlText = exportToXml(workspace);
      // save
      fetch('/engine/scripts/' + self.name + '.xml', {
        method: 'PUT',
        body: xmlText
      }).then(function() {
        return fetch('/engine/scripts/' + self.name + '.lua', {
          method: 'PUT',
          body: code
        });
      }).then(function() {
        toaster.toast('Saved');
      });
    });
    workspace.registerButtonCallback('exportLua', function() {
      saveAs(exportToLua(workspace));
    });
    workspace.registerButtonCallback('exportXml', function() {
      saveAs(exportToXml(workspace));
    });
    return workspace;
  };

  var scriptsEditorVue = new Vue({
    template: '<app-page id="scriptsEditor" title="Scripts Editor"><page-article>' +
      '<div id="scriptsEditorBlocklyDiv" style="height: 100%; width: 100%;"></div>' +
      '</page-article></app-page>',
    data: {
      name: '',
      savedContent: null,
      workspace: null
    },
    methods: {
      onShow: function() {
        console.log('scriptsEditor.onShow()');
        if (this.workspace === null) {
          var self = this;
          fetch(requirePath + '/toolbox.xml').then(function(response) {
            return response.text();
          }).then(function(toolboxXml) {
            self.workspace = loadBlockly(self, toolboxXml);
            if (self.name) {
              self.refresh();
            }
          });
        }
      },
      load: function(name) {
        this.name = name;
        this.refresh();
      },
      refresh: function() {
        var workspace = this.workspace;
        if (workspace) {
          fetch('/engine/scripts/' + this.name + '.xml').then(function(response) {
            return response.text();
          }).then(function(xmlText) {
            workspace.clear();
            var xml = Blockly.Xml.textToDom(xmlText);
            Blockly.Xml.domToWorkspace(xml, workspace);
          });
        }
      }
    }
  });
  


  var scriptsVue = new Vue({
    template: '<app-page id="scripts" title="Scripts"><page-article>' +
      '<table><tr><th>Name</th><th>Active</th></tr><tr v-for="script in scripts">' +
      '<td v-on:click="openScript(script.id)">{{script.id}}</td>' +
      '<td style="text-align: center; "><input v-bind:disabled="!script.loaded" type="checkbox" v-model="script.active" v-on:click="activateScript(script)" /></td>' +
      '</tr></table><br />' +
      '<input v-model="newName" type="text" placeholder="New Script Id">' +
      '<button v-on:click="newScript"><i class="fas fa-plus"></i>&nbsp;New</button>' +
      '</page-article></app-page>',
    data: {
      newName: '',
      scripts: []
    },
    methods: {
      onShow: function () {
        var self = this;
        fetch('/engine/scripts/', {
          headers: {
            "Accept": 'application/json'
          }
        }).then(function(response) {
          return response.json();
        }).then(function(files) {
          self.scripts = files.filter(function(file) {
            return file.isDirectory === false && file.name.endsWith('.xml');
          }).map(function(file) {
            return {
              id: file.name.substring(0, file.name.lastIndexOf('.')),
              loaded: false,
              active: false
            };
          });
          fetch('/engine/admin/listScripts').then(function(response) {
            return response.json();
          }).then(function(scripts) {
            self.scripts.forEach(function(script) {
              for (var i = 0; i < scripts.length; i++) {
                var s = scripts[i];
                if (s.id === script.id) {
                  script.loaded = true;
                  script.active = s.active;
                  break;
                }
              }
            });
          });
          console.log('scripts', self.scripts);
        });
      },
      openScript: function (name) {
        app.toPage('scriptsEditor');
        app.callPage('scriptsEditor', 'load', name);
      },
      activateScript: function (script) {
        //console.log('activateScript()' + script.active);
        fetch('/engine/configuration/script/' + script.id + '/active', {
          method: 'POST',
          body: JSON.stringify({
            value: !script.active
          })
        });
      },
      newScript: function () {
        fetch('/engine/scripts/' + this.newName + '.xml', {
          method: 'PUT',
          body: '<xml xmlns="http://www.w3.org/1999/xhtml"></xml>'
        });
        this.newName = '';
        this.onShow();
      }
    }
  });
  
  var scriptEditorComponent = scriptsEditorVue.$mount();
  document.getElementById('pages').appendChild(scriptEditorComponent.$el);
  
  var scriptsComponent = scriptsVue.$mount();
  document.getElementById('pages').appendChild(scriptsComponent.$el);

  menu.pages.push({
    id: 'scripts',
    name: 'Scripts'
  });
  
});
