var propertiesVue = new Vue({
  el: '#properties',
  data: {
    edit: false,
    filter: false,
    query: '',
    properties: []
  },
  computed: {
    filteredProperties: function () {
      if ((this.query.length === 0) || !this.filter) {
        return this.properties;
      }
      var query = this.query;
      return this.properties.filter(function(property) {
        // property.extension.description, property.thing.description
        return contains(query, property.name, property.title, property.description, property.extension.name, property.thing.title);
      });
    }
  },
  methods: {
    onShow: function() {
      var self = this;
      var extensionsById = {};
      var things = [];
      app.getThings().then(function(result) {
        things = result;
        return app.getExtensionsById();
      }).then(function(result) {
        extensionsById = result;
        return fetch('/engine/properties');
      }).then(function(response) {
        return response.json();
      }).then(function(properties) {
        self.properties = [];
        self.properties = [];
        for (var i = 0; i < things.length; i++) {
          var thing = things[i];
          var props = properties[thing.thingId];
          for (var name in thing.properties) {
            var property = thing.properties[name];
            property.name = name;
            property.value = props[name];
            property.thing = thing;
            property.extension = extensionsById[thing.extensionId] || {};
            self.properties.push(property);
          }
        }
      });

    }
  }
});

registerPageVue(propertiesVue, 'fa-list');