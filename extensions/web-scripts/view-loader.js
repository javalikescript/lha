define(function() {

  function getPropertyValue(things, properties, path) {
    var parts = path.split('/', 2);
    var thingId = parts[0];
    var propName = parts[1];
    var props = properties[thingId];
    if (props) {
      var value = props[propName];
      if (value !== undefined) {
        return value;
      }
    }
    var thing = things[thingId];
    if (thing) {
      var thgProp = thing.properties[propName];
      if (thgProp) {
        var propType = thgProp['@type'];
        switch (propType) {
        case 'integer':
        case 'number':
          return 0;
        case 'string':
          return '';
        case 'boolean':
          return false;
        }
      }
    }
    return undefined;
  }

  function load(config, viewXml) {
    var script = '';
    for(;;) {
      // type="text/javascript"
      var i = viewXml.indexOf('<script>');
      if (i < 0) {
        break;
      }
      var j = viewXml.indexOf('</script>', i);
      if (j < 0) {
        break;
      }
      script += '\n' + viewXml.substring(i + 8, j);
      viewXml = viewXml.substring(0, i) + viewXml.substring(j + 9);
    }
    var options = {
      template: [
        '<app-page id="' + config.id + '" title="' + config.title + '">',
        viewXml,
        '</app-page>'
      ].join('\n')
    };
    if (config.properties && config.properties.length > 0) {
      assignMap(options, {
        data: {
          property: {}
        },
        methods: {
          onShow: function() {
            this.onDataChange();
          },
          onDataChange: function() {
            Promise.all([
              app.getThings(),
              app.getPropertiesByThingId()
            ]).then(apply(this, function(things, properties) {
              var propertyMap = {};
              for (var i = 0; i < config.properties.length; i++) {
                var cfgProp = config.properties[i];
                propertyMap[cfgProp.name] = getPropertyValue(things, properties, cfgProp.path);
              }
              this.property = propertyMap;
            }));
          },
          getPropertyByPath: function(path) {
            return Promise.all([
              app.getThings(),
              app.getPropertiesByThingId()
            ]).then(apply(this, function(things, properties) {
              return getPropertyValue(things, properties, path);
            }));
          },
          setPropertyByPath: function(path, value) {
            var parts = path.split('/', 2);
            var thingId = parts[0];
            var propName = parts[1];
            var valueByName = {};
            valueByName[propName] = value;
            return putJson('/things/' + thingId + '/properties', valueByName).then(rejectIfNotOk);
          },
          setProperty: function(name, value) {
            for (var i = 0; i < config.properties.length; i++) {
              var cfgProp = config.properties[i];
              if (cfgProp.name === name) {
                return this.setPropertyByPath(cfgProp.path, value);
              }
            }
            return Promise.reject('not found');
          }
        }
      });
    }
    if (script.length > 0) {
      var fn = Function('options', 'config', '"use strict";' + script);
      fn.call(this, options, config);
    }
    var vue = new Vue(options);
    addPageComponent(vue, config.icon || undefined, config.tile, config.menu);
  }

  return {
    load: load
  };

});