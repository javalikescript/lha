define(['./web-dashboard.xml'], function(dashboardTemplate) {

  var typeByCapability = {
    "Light": "OnOffProperty",
    "TemperatureSensor": "TemperatureProperty",
    "MotionSensor": "MotionProperty",
    "HumiditySensor": "HumidityProperty",
    "BarometricPressureSensor": "BarometricPressureProperty",
    "SmokeSensor": "SmokeProperty"
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
    "watt": "W"
  };

  var unitByType = {
    "BarometricPressureProperty": "hectopascal",
    "BrightnessProperty": "percent",
    "ColorTemperatureProperty": "kelvin",
    "HumidityProperty": "percent",
    "TemperatureProperty": "degree celsius",
  };

  var iconsByType = {
    "default": ["fa-times", "fa-check"],
    "OnOffProperty": ["fa-power-off", "fa-lightbulb"],
    "MotionProperty": ["fa-user-alt-slash", "fa-running"],
    "SmokeProperty": ["fa-smoking-ban", "fa-smoking"]
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

  function isEmpty(obj) {
    return ((obj === null) || (obj === undefined)) || (Array.isArray(obj) && (obj.length === 0)) || (Object.keys(obj).length === 0);
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

  function oneOf() {
    for (var i = 0; i < arguments.length; i++) {
      var value = arguments[i];
      if (isValidValue(value)) {
        return value;
      }
    }
    return Math.round((Math.pow(10, value / 10000) - 1) * 100) / 100;
  }

  var extensionId = 'web-dashboard';
  var extensionName = 'Dashboard';

  var dashboardVue = new Vue({
    template: dashboardTemplate,
    data: {
      config: {},
      things: [],
      properties: {},
      tiles: []
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
      toggleFullScreen: function() {
        if( window.innerHeight == screen.height) {
          document.exitFullscreen();
        } else {
          document.body.requestFullscreen();
        }
      },
      onDataChange: function() {
        console.log('onDataChange');
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
          for (var i = 0; i < tilesDef.length; i++) {
            var tileDef = tilesDef[i];
            var type = tileDef.type;
            var title = tileDef.title || tileDef.type;
            var unit = undefined;
            var values = [];
            var paths = [];
            var thingIds = tileDef.thingIds;
            if (isEmpty(thingIds)) {
              thingIds = Object.keys(things);
            }
            for (var j = 0; j < thingIds.length; j++) {
              var thingId = thingIds[j];
              var thing = things[thingId];
              if (!thing) {
                continue;
              }
              if ((type === 'auto') || !isValidValue(type)) {
                var thingType = thing['@type'][0];
                type = typeByCapability[thingType];
              }
              if (!type) {
                continue;
              }
              if (!isValidValue(title) && (thingIds.length === 1) && isValidValue(thing.title)) {
                title = thing.title;
              }
              var propertyName = undefined;
              for (var propName in thing.properties) {
                var prop = thing.properties[propName];
                var propType = prop['@type'];
                if (propType === type) {
                  propertyName = propName;
                  if (!isValidValue(unit) && (thingIds.length === 1) && isValidValue(prop.unit)) {
                    unit = prop.unit;
                  }
                  break;
                }
              }
              if (!propertyName) {
                continue;
              }
              var props = properties[thingId];
              if (props && isValidValue(props[propertyName])) {
                values.push(props[propertyName]);
              }
              paths.push(thingId + '/' + propertyName);
              //console.log('thing', JSON.stringify(thing, undefined, 2), JSON.stringify(props, undefined, 2));
            }
            var value = undefined;
            if (values.length > 0) {
              var valueType = typeof values[0];
              if (valueType === 'number') {
                value = values.reduce(function(s, v) { return s + v; }, 0) / values.length
              } else if (valueType === 'boolean') {
                value = values.indexOf(true) >= 0;
              }
            }
            console.log('value: ' + value + ', type: ' + type, values);
            if (unitByType[type]) {
              unit = unitByType[type];
            }
            var tile = assignMap({}, tileDef, {
              title: oneOf(title, type, 'n/a'),
              paths: paths,
              count: values.length,
              value: formatValue(value, type),
              icon: (typeof value === 'boolean'),
              unit: formatUnit(unit)
            });
            //console.log('tile', JSON.stringify(tile, undefined, 2), JSON.stringify(tileDef, undefined, 2));
            tiles.push(tile);
          }
        }
        //console.log('tiles', JSON.stringify(tiles, undefined, 2));
        this.tiles = tiles;
      },
      openHistoricalData: function(paths) {
        console.log('paths: ' + paths);
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

  addPageComponent(dashboardVue);

  menu.pages.push({
    id: extensionId,
    name: extensionName
  });
  
  homePage.pages.push({
    id: extensionId,
    name: extensionName
  });
  
});
