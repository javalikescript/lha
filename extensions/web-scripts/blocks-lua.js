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
    return Blockly.Lua.nameDB_.getName(fieldValue, Blockly.Names.NameType.VARIABLE);
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
    "lha_data_path": function(block) {
      var path = block.getFieldValue('PATH');
      return [textToLua(path), Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_get_data_path": function(block) {
      var path = Blockly.Lua.valueToCode(block, 'PATH', Blockly.JavaScript.ORDER_NONE);
      var code = "script:getDataValue(" + path + ")";
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_set_data_path": function(block) {
      var path = Blockly.Lua.valueToCode(block, 'PATH', Blockly.JavaScript.ORDER_NONE);
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      return "script:setDataValue(" + path + ", " + value + ")\n";
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
      var factor = parseInt(block.getFieldValue('SECONDS'), 10) * 1000;
      var code = Blockly.Lua.statementToCode(block, 'DO');
      return "script:setTimer(function()\n" + code + "end, " + (value * factor) + ", " + textToLua(name) + ")\n";
    },
    "lha_clear_timer": function(block) {
      var name = block.getFieldValue('NAME');
      return "script:clearTimer(" + textToLua(name) + ")\n";
    },
    "lha_on_event": function(block) {
      var code = Blockly.Lua.statementToCode(block, 'DO');
      var event = block.getFieldValue('EVENT');
      var args = getVariableName(block, 'ARGS');
      return "script:subscribeEvent(" + textToLua(event) + ", function(...)\n  local " + args + " = {...}\n" + code + "end)\n";
    },
    "lha_fire_event": function(block) {
      var event = block.getFieldValue('EVENT');
      var target = block.getFieldValue('TARGET');
      var args = Blockly.Lua.valueToCode(block, 'ARGS', Blockly.JavaScript.ORDER_NONE);
      var code = textToLua(event);
      if ((typeof args === 'string') && (args.length > 0)) {
        code += ", table.unpack(" + args + ")";
      }
      switch(target) {
      case 'OTHERS':
        return "script:fireExtensionEvent(" + code + ")\n";
      case 'ALL':
        return "script.engine:publishEvent(" + code + ")\n";
      } // ME
      return "script:publishEvent(" + code + ")\n";
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
    "lha_day": function(block) {
      var value = block.getFieldValue('NAME');
      return [value, Blockly.JavaScript.ORDER_MEMBER];
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
    "lha_color": function(block) {
      var field = block.getFieldValue('FIELD');
      var value = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      var o = "utils.parseRgbHex(" + value + ")";
      var indices = {"r": 1, "g": 2, "b": 3, "h": 11, "s": 12, "v": 13};
      var n = indices[field];
      if (n > 10) {
        n = n - 10;
        var o = "utils.rgbToHsv(" + o + ")";
      }
      var code = 'select(' + n + ', ' + o + ')';
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_color_hsv": function(block) {
      var h = Blockly.Lua.valueToCode(block, 'HUE', Blockly.JavaScript.ORDER_NONE);
      var s = Blockly.Lua.valueToCode(block, 'SATURATION', Blockly.JavaScript.ORDER_NONE);
      var v = Blockly.Lua.valueToCode(block, 'VALUE', Blockly.JavaScript.ORDER_NONE);
      var code = 'utils.formatRgbHex(utils.hsvToRgb(' + h + ', ' + s + ', ' + v + '))';
      return [code, Blockly.JavaScript.ORDER_MEMBER];
    },
    "lha_color_rgb": function(block) {
      var r = Blockly.Lua.valueToCode(block, 'RED', Blockly.JavaScript.ORDER_NONE);
      var g = Blockly.Lua.valueToCode(block, 'GREEN', Blockly.JavaScript.ORDER_NONE);
      var b = Blockly.Lua.valueToCode(block, 'BLUE', Blockly.JavaScript.ORDER_NONE);
      var code = 'utils.formatRgbHex(' + r + ', ' + g + ', ' + b + ')';
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
