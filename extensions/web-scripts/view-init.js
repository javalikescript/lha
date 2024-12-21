define(['./config.json', './view.xml'], function(config, viewXml) {

  var viewTemplate = [
    '<app-page id="' + config.id + '" title="' + config.title + '">',
    viewXml,
    '</app-page>'
  ].join('\n');

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
          this.refreshProperties(things, properties);
        }));
      },
      refreshProperties: function(things, properties) {
        var propertyMap = {};
        for (var i = 0; i < config.properties.length; i++) {
          var cfgProp = config.properties[i];
          var parts = cfgProp.path.split('/', 2);
          var thingId = parts[0];
          var propName = parts[1];
          var props = properties[thingId];
          var value;
          if (props) {
            value = props[propName];
            if (value !== undefined) {
              propertyMap[cfgProp.name] = value;
              continue;
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
                value = 0;
                break;
              case 'string':
                value = '';
                break;
              case 'boolean':
                value = false;
                break;
              }
              propertyMap[cfgProp.name] = value;
            }
          }
        }
        this.property = propertyMap;
      }
    }
  });

  addPageComponent(viewVue, config.icon);

});