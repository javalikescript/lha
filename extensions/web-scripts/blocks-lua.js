define(function() {

  function textToLua(text) {
    if (typeof text !== 'string') {
      text = '' + text;
    }
    return "'" + text.replace(/([\'\\])/g, '\\$1') + "'";
  }
  function nameToLuaKey(name) {
    if (name.match(/^[a-zA-Z_][a-zA-Z0-9_]+$/)) {
      return '.' + name;
    }
    return '[' + textToLua(name) + ']';
  }
  function getVariableName(block, fieldName) {
    return Blockly.Lua.variableDB_.getName(block.getFieldValue(fieldName), Blockly.Variables.NAME_TYPE);
  }

  return {
    "lha_event": function(block) {
      var code = Blockly.Lua.statementToCode(block, 'DO');
      var event = block.getFieldValue('EVENT');
      code = "script:subscribeEvent('" + event + "', function()\n" + code + "end)\n";
      return code;
    },
    "lha_log": function(block) {
      var level = block.getFieldValue('LEVEL')
      //var message = '"' + block.getFieldValue('MESSAGE') + '"';
      var message = Blockly.Lua.valueToCode(block, 'MESSAGE', Blockly.JavaScript.ORDER_NONE);
      return "logger:log(logger." + level + ", tostring(" + message + "))\n";
    },
    "lha_schedule": function(block) {
      var code = Blockly.Lua.statementToCode(block, 'DO');
      var value = block.getFieldValue('VALUE');
      code = "script:registerSchedule('" + value + "', function()\n" + code + "end)\n";
      return code;
    },
    "lha_get_data": function(block) {
      var path = block.getFieldValue('PATH');
      var code = "script:getDataValue('" + path + "')";
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_set_data": function(block) {
      var path = block.getFieldValue('PATH');
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      return "script:setDataValue('" + path + "', " + value + ")\n";
    },
    "lha_watch_data": function(block) {
      var code = Blockly.Lua.statementToCode(block, 'DO');
      var path = block.getFieldValue('PATH');
      var newValue = getVariableName(block, 'NEW_VALUE');
      //var oldValue = getVariableName(block, 'OLD_VALUE');
      code = "script:watchValue('data/" + path + "', function(" + newValue + ")\n" + code + "end)\n";
      return code;
    },
    "lha_timer": function(block) {
      var name = block.getFieldValue('NAME');
      var value = block.getFieldValue('VALUE');
      var millis = parseInt(block.getFieldValue('SECONDS'), 10);
      var code = Blockly.Lua.statementToCode(block, 'DO');
      return "script:setTimer(function()\n" + code + "end, " + (value * millis) + ", " + textToLua(name) + ")\n";
    },
    "lha_clear_timer": function(block) {
      var name = block.getFieldValue('NAME');
      return "script:clearTimer(" + textToLua(name) + ")\n";
    },
    "lha_to_string": function(block) {
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      var code = "tostring(" + value + ")";
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_time": function(block) {
      var code = "os.time()";
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_parse_time": function(block) {
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      var code = "((Date.fromISOString(tostring(" + value + ")) or 0) // 1000)";
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_format_time": function(block) {
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      var code = "Date:new((tonumber(" + value + ") or 0) * 1000):toISOString(true, true)";
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_date": function(block) {
      var field = block.getFieldValue('FIELD');
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      var code;
      if (field === 'H.ms') {
        code = "(function(h, m, s) return tonumber(h) + tonumber(m) / 60 + tonumber(s) / 3600; end)(string.match(os.date('%H %M %S', " + value + "), '(%d+) (%d+) (%d+)'))";
      } else {
        code = "tonumber(os.date('%" + field + "', " + value + "))";
      }
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_get_field": function(block) {
      var name = block.getFieldValue('NAME');
      var obj = getVariableName(block, 'OBJECT');
      //var code = "(type(" + obj + ") == 'table' and " + obj + "[" + textToLua(name) + "])";
      var code = obj + nameToLuaKey(name);
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_set_field": function(block) {
      var name = block.getFieldValue('NAME');
      var obj = getVariableName(block, 'OBJECT');
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      //return "if type(" + obj + ") == 'table' then\n" + obj + "[" + textToLua(name) + "] = " + value + "\nend\n";
      return obj + nameToLuaKey(name) + " = " + value + "\n";
    }
  };

});
