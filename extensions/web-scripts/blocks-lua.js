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
    var fieldValue = block.getFieldValue(fieldName);
    return Blockly.Lua.variableDB_.getName(fieldValue, Blockly.Variables.NAME_TYPE);
  }

  return {
    // -- Data --------
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
    // -- Event --------
    "lha_event": function(block) {
      var code = Blockly.Lua.statementToCode(block, 'DO');
      var event = block.getFieldValue('EVENT');
      code = "script:subscribeEvent('" + event + "', function()\n" + code + "end)\n";
      return code;
    },
    "lha_schedule": function(block) {
      var code = Blockly.Lua.statementToCode(block, 'DO');
      var value = block.getFieldValue('VALUE');
      code = "script:registerSchedule('" + value + "', function()\n" + code + "end)\n";
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
    "lha_fire_event": function(block) {
      var value = block.getFieldValue('VALUE');
      var args = Blockly.Lua.valueToCode(block, 'ARGS', Blockly.JavaScript.ORDER_NONE);
      return "script:fireExtensionEvent(" + textToLua(value) + ", table.unpack(" + args + "))\n";
    },
    // -- Expression --------
    "lha_to_string": function(block) {
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      return ["tostring(" + value + ")", Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_type": function(block) {
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      return ["type(" + value + ")", Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_time": function(block) {
      return ["utils.time()", Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_hms": function(block) {
      var value = block.getFieldValue('VALUE');
      var hms = value.split(':').map(function(v) {
        return parseInt(v, 10);
      });
      var code = '' + hms.reverse().reduce(function(pv, cv) {return cv + pv / 60}, 0);
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_parse_time": function(block) {
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      var code = "(utils.timeFromString(tostring(" + value + ")) or 0)";
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_format_time": function(block) {
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      var code = "utils.timeToString(tonumber(" + value + ") or 0)";
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_date": function(block) {
      var field = block.getFieldValue('FIELD');
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      var code;
      if (field === 'H.ms') {
        code = "utils.timeToHms(" + value + ")";
      } else {
        code = "tonumber(os.date('%" + field + "', " + value + "))";
      }
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    },
    // -- Experimental --------
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
    },
    "lha_log": function(block) {
      var level = block.getFieldValue('LEVEL')
      var message = Blockly.Lua.valueToCode(block, 'MESSAGE', Blockly.JavaScript.ORDER_NONE);
      return "logger:log(logger." + level + ", tostring(" + message + "))\n";
    },
    "lha_require": function(block) {
      var name = block.getFieldValue('NAME');
      var code = 'script:require(' + textToLua(name) + ')';
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_call": function(block) {
      var fn = Blockly.Lua.valueToCode(block, 'FUNCTION', Blockly.JavaScript.ORDER_NONE);
      var args = Blockly.Lua.valueToCode(block, 'ARGS', Blockly.JavaScript.ORDER_NONE);
      //var code = "(function(...) local fn = " + fn + "; if type(fn) == 'function' then return fn(...); end; end)(" + value + ")";
      var code = fn + "(table.unpack(" + args + "))";
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_call_no_return": function(block) {
      var fn = Blockly.Lua.valueToCode(block, 'FUNCTION', Blockly.JavaScript.ORDER_NONE);
      var args = Blockly.Lua.valueToCode(block, 'ARGS', Blockly.JavaScript.ORDER_NONE);
      var code = fn + "(table.unpack(" + args + "))";
      return code + "\n";
    }
  };

});
