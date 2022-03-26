define(['./web-dashboard.xml'], function(dashboardTemplate) {

  /*
  We want to present an overview of things on a dashboard.
  The dashboard contains tiles representing one or more aggregated things.
  A tile has a title, an aggegation type, an optional group.
  An aggregation type computes a value, an icon
  The wanted tiles are:
    air condition: temperature, humidity, pressure, smoke
    weather: temperature, humidity, pressure, rain, wind, cloud
    light: on/off, intensity, color
    motion: presence

  */
  var typeByName = {
    temperature: 'temperature',
    presence: 'presence',
    on: 'light'
  };
  var nameByType = swapMap(typeByName);

  function guessAggregation(thing, properties) {
    if (thing && properties) {
      for (var name in typeByName) {
        if (name in properties) {
          return typeByName[name];
        }
      }
    }
    return 'unknown';
  }

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
        var tiles = [];
        var tilesDef = config.tiles;
        if (tilesDef) {
          for (var i = 0; i < tilesDef.length; i++) {
            var tileDef = tilesDef[i];
            //console.log('tile ' + i, JSON.stringify(tileDef, undefined, 2));
            var thingIds = tileDef.thingIds;
            var tile = Object.assign({}, tileDef);
            var list = [];
            var anyProps = {}
            for (var j = 0; j < thingIds.length; j++) {
              var thingId = thingIds[j];
              var thing = things[thingId];
              var props = properties[thingId];
              list.push({
                thing: thing,
                props: props
              });
              anyProps = Object.assign(anyProps, props);
            }
            if (tile.type === 'auto') {
              tile.type = guessAggregation(list[0].thing, anyProps);
            }
            var names = Object.keys(anyProps);
            var aggByName = {};
            var valuesByName = {};
            for (var k = 0; k < names.length; k++) {
              var name = names[k];
              var values = [];
              for (var l = 0; l < list.length; l++) {
                var value = list[l].props[name];
                if (value !== undefined) {
                  values.push(value);
                }
              }
              valuesByName[name] = values;
              var agg;
              switch(typeof values[0]) {
                case 'boolean':
                  agg = values.indexOf(true) >= 0;
                  break;
                case 'number':
                  var sum = values.reduce(function(pv, cv) { return pv + cv; }, 0);
                  agg = sum / values.length;
                  break;
              }
              aggByName[name] = agg;
            }
            tile.aggByName = aggByName;
            var name = nameByType[tile.type];
            if (name in aggByName) {
              tile.value = aggByName[name];
            } else {
              tile.value = '?';
            }
            tiles.push(tile);
          }
        }
        //console.log('tiles', JSON.stringify(tiles, undefined, 2));
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
