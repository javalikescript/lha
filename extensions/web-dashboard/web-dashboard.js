define(['./web-dashboard.xml'], function(dashboardTemplate) {

  var typeByCapability = {
    "Light": "OnOffProperty",
    "TemperatureSensor": "TemperatureProperty",
    "MotionSensor": "MotionProperty",
    "HumiditySensor": "HumidityProperty",
    "BarometricPressureSensor": "BarometricPressureProperty",
    "SmokeSensor": "SmokeProperty"
  };

  //var capabilityToType = swapMap(typeByCapability);

  function lightLevelToLux(value) {
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
      processThings: function(config, things, properties) {
        //console.log('processThings()', config, things, properties);
        var tiles = [];
        var thingsDef = config.things;
        if (thingsDef) {
          for (var i = 0; i < thingsDef.length; i++) {
            var thingDef = thingsDef[i];
            var thingId = thingDef.thingId;
            var thing = things[thingId];
            if (!thing) {
              console.log('Thing not found "' + thingId + '"', thingDef);
              continue;
            }
            var tile = Object.assign({
              title: thing.title,
              value: ''
            }, thingDef);
            var type = thingDef.type;
            if ((type === 'auto') || !type) {
              var thingType = thing['@type'][0];
              type = typeByCapability[thingType];
            }
            if (!type) {
              console.log('Thing type not found', tile);
              continue;
            }
            var propertyName;
            var unit;
            for (var propName in thing.properties) {
              var prop = thing.properties[propName];
              var propType = prop['@type'];
              propertyName = propName;
              unit = prop.unit;
              if (propType === type) {
                break;
              }
            }
            if (!propertyName) {
              console.log('Thing property not found', tile);
              continue;
            }
            var props = properties[thingId];
            if (props) {
              tile.value = props[propertyName];
              tile.unit = unit;
            }
            tiles.push(tile);
          }
        }
        console.log('tiles', JSON.stringify(tiles, undefined, 2));
        this.tiles = tiles;
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
  
  main.pages.push({
    id: extensionId,
    name: extensionName
  });
  
});
