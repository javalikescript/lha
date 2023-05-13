define(['./web-dashboard.xml'], function(dashboardTemplate) {

  var typeByCapability = {
    "Light": "OnOffProperty",
    "TemperatureSensor": "TemperatureProperty",
    "MotionSensor": "MotionProperty",
    "HumiditySensor": "HumidityProperty",
    "BarometricPressureSensor": "BarometricPressureProperty",
    "SmokeSensor": "SmokeProperty",
    "AlarmSensor": "AlarmProperty"
  };

  var unitAlias = {
    "ampere": "A",
    "degree celsius": "°C",
    "hectopascal": "hPa",
    "hertz": "Hz",
    "kelvin": "K",
    "lux": "lx",
    "percent": "%",
    "volt": "V",
    "voltampere": "VA",
    "watt": "W"
  };

  var unitByType = {
    "BarometricPressureProperty": "hectopascal",
    "BrightnessProperty": "percent",
    "ColorTemperatureProperty": "kelvin",
    "HumidityProperty": "percent",
    "TemperatureProperty": "degree celsius",
    "ApparentPowerProperty": "voltampere",
    "CurrentProperty": "ampere"
  };

  var iconsByType = {
    "default": ["fa-times", "fa-check"],
    "OnOffProperty": ["fa-power-off", "fa-lightbulb"],
    "MotionProperty": ["fa-user-alt-slash", "fa-running"],
    "SmokeProperty": ["fa-smoking-ban", "fa-smoking"],
    "AlarmProperty": ["fa-sun", "fa-exclamation"]
  };

  //var capabilityToType = swapMap(typeByCapability);

  function lightLevelToLux(value) {
    return Math.round((Math.pow(10, value / 10000) - 1) * 100) / 100;
  }

  function isValidValue(value) {
    var valueType = typeof value;
    return (valueType === 'number') || (valueType === 'boolean') || ((valueType === 'string') && (value.trim() !== ''));
  }

  function formatUnit(unit) {
    return unitAlias[unit] || unit || '';
  }

  function formatValue(value, type) {
    // format the value to 6 characters max
    var valueType = typeof value;
    if (valueType === 'number') {
      var s = String(value);
      if (s.indexOf('.') > 0) {
        return value.toFixed(1)
      }
    } else if (valueType === 'boolean') {
      var icons = iconsByType[type] || iconsByType['default'];
      return icons[value ? 1 : 0];
    } else if (valueType === 'string') {
      if (value.trim() === '') {
        return 'n/a';
      }
    } else {
      return '-x-';
    }
    return value;
  }

  function firstOf() {
    for (var i = 0; i < arguments.length; i++) {
      var value = arguments[i];
      if (isValidValue(value)) {
        return value;
      }
    }
    return Math.round((Math.pow(10, value / 10000) - 1) * 100) / 100;
  }

  function reduce(values) {
    if (values.length > 0) {
      var valueType = typeof values[0];
      if (valueType === 'number') {
        return values.reduce(function(s, v) { return s + v; }, 0) / values.length
      } else if (valueType === 'boolean') {
        return values.indexOf(true) >= 0;
      }
    }
  }

  function forEachPropertyPath(things, paths, fn, type) {
    for (var i = 0; i < paths.length; i++) {
      var path = paths[i];
      var parts = path.split('/');
      var thingId = parts[0];
      var name = parts[1];
      var thing = things[thingId];
      if (thing) {
        var property = thing.properties[name];
        if (property) {
          if ((property['@type'] === type) || (type === undefined)) {
            if (fn(thing, thingId, property, name) === true) {
              return;
            }
          }
        }
      }
    }
  }

  function forEachPropertyType(things, type, fn, thingIds) {
    if (isEmpty(thingIds)) {
      thingIds = Object.keys(things);
    }
    for (var i = 0; i < thingIds.length; i++) {
      var thingId = thingIds[i];
      var thing = things[thingId];
      if (thing) {
        for (var name in thing.properties) {
          var property = thing.properties[name];
          if (property['@type'] === type) {
            if (fn(thing, thingId, property, name) === true) {
              return;
            }
            break;
          }
        }
      }
    }
  }

  function processEachTileProperty(tileDef, things, fn) {
    if (tileDef.type) {
      forEachPropertyType(things, tileDef.type, fn, tileDef.thingIds);
    } else if (tileDef.propertyPaths) {
      var type;
      forEachPropertyPath(things, tileDef.propertyPaths, function(thing, thingId, property, propertyName) {
        type = property['@type'];
        return true;
      });
      forEachPropertyPath(things, tileDef.propertyPaths, fn, type);
    }
  }

  function processTile(tileDef, things, properties) {
    if (tileDef.separator) {
      return assignMap({}, tileDef);
    }
    var paths = [];
    var type = tileDef.type;
    var values = [];
    processEachTileProperty(tileDef, things, function(thing, thingId, property, propertyName) {
      if (!type) {
        type = property['@type'];
      }
      if (thing.archiveData && !property.configuration) {
        paths.push(thingId + '/' + propertyName);
      }
      var props = properties[thingId];
      if (props && isValidValue(props[propertyName])) {
        values.push(props[propertyName]);
      }
    });
    var value = reduce(values);
    //console.log('value: ' + value + ', type: ' + type, values);
    return assignMap({}, tileDef, {
      title: firstOf(tileDef.title, type, 'n/a'),
      paths: paths,
      count: values.length,
      value: value,
      unit: formatUnit(unitByType[type])
    });
  }

  function putThingPropertyValue(thingId, propertyName, newValue) {
    var valueByName = {};
    valueByName[propertyName] = newValue;
    return fetch('/things/' + thingId + '/properties', {
      method: 'PUT',
      body: JSON.stringify(valueByName)
    }).then(rejectIfNotOk);
  }

  var extensionId = 'web-dashboard';
  var extensionName = 'Dashboard';

  var dashboardVue = new Vue({
    template: dashboardTemplate,
    data: {
      config: {},
      things: [],
      properties: {},
      tiles: [],
      lastChange: null,
      changeTimer: null
    },
    methods: {
      onShow: function() {
        Promise.all([
          fetch('/engine/configuration/extensions/' + extensionId).then(function(response) {
            return response.json();
          }).then(function(response) {
            return response.value;
          }),
          app.getThingsById(),
          app.getPropertiesByThingId()
        ]).then(apply(this, function(config, things, properties) {
          this.config = config;
          this.processThings(config, things, properties);
        }));
      },
      onLogs: function(logs) {
        if (logs) {
          for (var i = 0; i < logs.length; i++) {
            var log = logs[i];
            if (log.level >= 90) {
              toaster.toast(log.message, 5000);
            }
          }
        }
      },
      onDataChange: function() {
        //console.log('onDataChange');
        Promise.all([
          app.getThingsById(),
          app.getPropertiesByThingId()
        ]).then(apply(this, function(things, properties) {
          this.processThings(this.config, things, properties);
        }));
      },
      processThings: function(config, things, properties) {
        //console.log('processThings()', config, things, properties);
        var tiles = [];
        var tilesDef = config.tiles;
        if (tilesDef) {
          for (var j = 0; j < tilesDef.length; j++) {
            var tileDef = tilesDef[j];
            var tile = processTile(tileDef, things, properties);
            //console.log('tile', JSON.stringify(tile, undefined, 2), JSON.stringify(tileDef, undefined, 2));
            tiles.push(tile);
          }
        }
        //console.log('tiles', JSON.stringify(tiles, undefined, 2));
        this.tiles = tiles;
        this.lastChange = new Date();
        if (this.changeTimer) {
          window.clearTimeout(this.changeTimer);
        }
        var self = this;
        this.changeTimer = window.setTimeout(function() {
          self.changeTimer = null;
        }, 5000);
      },
      formatValue: function(tile) {
        return formatValue(tile.value, tile.type);
      },
      onTileClicked: function(tile) {
        //console.log('onTileClicked() ' + tile.value + ' (' + (typeof tile.value) + ')');
        if ((typeof tile.value !== 'boolean') && (tile.value !== undefined)) {
          return Promise.reject('Unsupported value');
        }
        // if the property has enum then we could roll over values
        app.getThingsById().then(function(things) {
          var promises = [];
          var newValue = !tile.value;
          processEachTileProperty(tile, things, function(thing, thingId, property, propertyName) {
            if (!property.readOnly) {
              if (property.type === 'boolean') {
                promises.push(putThingPropertyValue(thingId, propertyName, newValue));
              }
            }
          }, tile.thingIds);
          if (promises.length > 0) {
            return Promise.all(promises).then(function() {
              tile.value = newValue;
              toaster.toast('Things updated');
              //app.clearCache();
            });
          }
        });
      },
      openHistoricalData: function(paths) {
        //console.log('paths: ' + paths);
        if (paths.length === 1) {
          app.toPage('data-chart', paths[0]);
        } else {
          app.callPage('data-chart', 'loadMultiHistoricalData', paths);
          app.toPage('data-chart');
        }
      },
      onAdd: function() {
      }
    }
  });

  addPageComponent(dashboardVue, 'fa-columns');
  
});
