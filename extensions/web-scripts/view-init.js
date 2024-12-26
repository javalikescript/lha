define(['./config.json', './view.xml'], function(config, viewXml) {

  var viewTemplate = [
    '<app-page id="' + config.id + '" title="' + config.title + '">',
    viewXml,
    '</app-page>'
  ].join('\n');

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

  var viewVue = new Vue({
    template: viewTemplate,
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
        return fetch('/things/' + thingId + '/properties', {
          method: 'PUT',
          body: JSON.stringify(valueByName)
        }).then(rejectIfNotOk);
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

  addPageComponent(viewVue, config.icon);

});