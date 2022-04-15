var thingsVue = new Vue({
  el: '#things',
  data: {
    edit: false,
    extensionsById: {},
    propertiesById: {},
    things: []
  },
  methods: {
    onShow: function() {
      var self = this;
      app.getThings().then(function(things) {
        self.things = things;
        return fetch('/engine/properties');
      }).then(function(response) {
        return response.json();
      }).then(function(properties) {
        self.propertiesById = {};
        for (var i = 0; i < self.things.length; i++) {
          var thing = self.things[i];
          var props = properties[thing.thingId];
          var propNames = Object.keys(props).filter(function(propName) {
            var propDef = thing.properties[propName];
            return propDef && !propDef.configuration;
          });
          if (propNames.length === 1) {
            var propName = propNames[0];
            var propDef = thing.properties[propName];
            self.propertiesById[thing.thingId] = {
              value: props[propName],
              unit: (propDef.unit || '')
            };
          } else {
            // found the default property
            var thingType = thing['@type'][0];
          }
        }
        //console.log('properties', self.properties);
        return app.getExtensionsById();
      }).then(function(extensionsById) {
        self.extensionsById = extensionsById;
      });

    },
    onArchiveAll: function() {
      for (var i = 0; i < this.things.length; i++) {
        this.things[i].archiveData = true;
      }
    },
    onRemoveAll: function() {
      Promise.all(this.things.map(function(thing) {
        return fetch('/engine/things/' + thing.thingId, {method: 'DELETE'});
      })).then(function() {
        toaster.toast('Things disabled');
        app.clearCache();
      });
    },
    onSave: function() {
      var self = this;
      var config = {things: {}};
      for (var i = 0; i < this.things.length; i++) {
        var thing = this.things[i];
        config.things[thing.thingId] = {
          archiveData: thing.archiveData
        };
      }
      console.log('config', config);
      fetch('/engine/configuration/', {
        method: 'POST',
        body: JSON.stringify({
          value: config
        })
      }).then(function() {
        toaster.toast('Things saved');
        app.clearCache();
        self.edit = false;
      });
    }
  }
});

new Vue({
  el: '#thing',
  data: {
    edit: false,
    thingId: '',
    properties: {},
    props: {},
    thing: {}
  },
  methods: {
    openHistoricalData: function(propertyName) {
      app.toPage('data-chart', this.thingId + '/' + propertyName);
    },
    disableThing: function() {
      return fetch('/engine/things/' + this.thingId, {method: 'DELETE'}).then(function() {
        toaster.toast('Thing disabled');
        app.clearCache();
      });
    },
    refreshThingDescription: function() {
      fetch('/engine/things/' + this.thingId + '/refreshDescription', {method: 'POST'}).then(function() {
        toaster.toast('Thing description refreshed');
        app.clearCache();
      });
    },
    onEdit: function() {
      this.edit = !this.edit;
      if (this.edit) {
        this.props = assignMap({}, this.properties);
      }
    },
    onSave: function() {
      var modifiedProps = {};
      for (var key in this.thing.properties) {
        var tp = this.thing.properties[key];
        var value = parseJsonItemValue(tp.type, this.props[key]);
        //console.info(key, tp.type, value, this.props[key]);
        //if ((value !== null) && (value !== undefined) && (value !== this.properties[key])) {
        if (value !== this.properties[key]) {
          modifiedProps[key] = value;
        }
      }
      //console.info('onSave()', JSON.stringify(modifiedProps, undefined, 2));
      return fetch('/things/' + this.thingId + '/properties', {
        method: 'PUT',
        body: JSON.stringify(modifiedProps)
      }).then(function() {
        toaster.toast('Properties updated');
        app.clearCache();
      });
    },
    onShow: function(thingId) {
      this.edit = false;
      if (thingId) {
        this.thingId = thingId;
      }
      this.thing = {};
      var self = this;
      fetch('/things/' + self.thingId).then(function(response) {
        return response.json();
      }).then(function(thing) {
        self.thing = thing;
        return fetch('/things/' + self.thingId + '/properties');
      }).then(function(response) {
        return response.json();
      }).then(function(properties) {
        if (Array.isArray(properties)) {
          properties.sort(compareByTitle);
        }
        self.properties = properties;
      });
    }
  }
});

new Vue({
  el: '#addThings',
  data: {
    things: []
  },
  methods: {
    onShow: function() {
      this.things = [];
      var self = this;
      fetch('/engine/discoveredThings').then(function(response) {
        return response.json();
      }).then(function(things) {
        if (Array.isArray(things)) {
          things.sort(compareByTitle);
        }
        for (var i = 0; i < things.length; i++) {
          var thing = things[i];
          thing.toAdd = false;
          self.things.push(thing);
        }
        //console.log('things', self.things);
      });
    },
    onAddAll: function() {
      for (var i = 0; i < this.things.length; i++) {
        this.things[i].toAdd = true;
      }
      return this.onSave();
    },
    onSave: function() {
      var thingsToAdd = [];
      for (var i = 0; i < this.things.length; i++) {
        var thing = this.things[i];
        if (thing.toAdd) {
          thingsToAdd.push(thing);
        }
      }
      if (thingsToAdd.length === 0) {
        return Promise.resolve();
      }
      return fetch('/engine/things/', {
        method: 'PUT',
        body: JSON.stringify(thingsToAdd)
      }).then(function() {
        toaster.toast('Things saved');
        app.clearCache();
      });
    }
  }
});

registerPageVue(thingsVue, 'fa-circle');
