registerPageVue(new Vue({
  el: '#things',
  data: {
    edit: false,
    filter: false,
    query: '',
    extensionsById: {},
    propertiesById: {},
    things: []
  },
  computed: {
    filteredThings: function () {
      if ((this.query.length === 0) || !this.filter) {
        return this.things;
      }
      var query = this.query;
      var extensionsById = this.extensionsById;
      return this.things.filter(function(thing) {
        var extension = extensionsById[thing.extensionId];
        return contains(query, thing.title, thing.description, thing.extensionId, extension ? extension.name : '');
      });
    }
  },
  methods: {
    onShow: function() {
      var self = this;
      app.getThings().then(function(things) {
        self.things = things;
        return fetch('/engine/properties');
      }).then(getJson).then(function(properties) {
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
      })).then(assertIsOk).then(function() {
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
      }).then(assertIsOk).then(function() {
        toaster.toast('Things saved');
        app.clearCache();
        self.edit = false;
      });
    },
    toggleFilter: function(event) {
      this.filter = !this.filter;
      if (this.filter) {
        this.$nextTick(function() {
          tryFocus(findChild(findParent(findAncestor(event.target, 'button')), 'input'));
        });
      }
    }
  }
}), 'circle', true, true);

new Vue({
  el: '#thing',
  data: {
    edit: false,
    thingId: '',
    properties: {},
    editProps: {},
    thing: {},
    editThing: {}
  },
  methods: {
    openHistoricalData: function(propertyName) {
      app.toPage('data-chart', this.thingId + '/' + propertyName);
    },
    disableThing: function() {
      var thingId = this.thingId;
      return confirmation.ask('Disable the thing?').then(function() {
        return fetch('/engine/things/' + thingId, {method: 'DELETE'}).then(assertIsOk).then(function() {
          toaster.toast('Thing disabled');
          app.clearCache();
        });
      });
    },
    onEdit: function() {
      this.edit = !this.edit;
      if (this.edit) {
        this.editProps = assignMap({}, this.properties);
        this.editThing = assignMap({}, this.thing);
      } else {
        this.editProps = {};
        this.editThing = {};
      }
    },
    onSave: function() {
      var modifiedProps = {};
      for (var key in this.thing.properties) {
        var tp = this.thing.properties[key];
        var value = parseJsonItemValue(tp.type, this.editProps[key]);
        //console.info(key, tp.type, value, this.editProps[key]);
        //if ((value !== null) && (value !== undefined) && (value !== this.properties[key])) {
        if (value !== this.properties[key]) {
          modifiedProps[key] = value;
        }
      }
      var modifiedThing = {};
      for (var key in this.thing) {
        var value = this.editThing[key];
        if (value !== this.thing[key]) {
          modifiedThing[key] = value;
        }
      }
      var thingId = this.thingId;
      var resolved = Promise.resolve();
      var p = resolved;
      if (Object.keys(modifiedProps).length > 0) {
        p = p.then(function() {
          return fetch('/things/' + thingId + '/properties', {
            method: 'PUT',
            body: JSON.stringify(modifiedProps)
          }).then(assertIsOk).then(function() {
            toaster.toast('Properties updated');
            app.clearCache();
          });
        });
      }
      if (Object.keys(modifiedThing).length > 0) {
        p = p.then(function() {
          return fetch('/engine/things/' + thingId, {
            method: 'POST',
            body: JSON.stringify(modifiedThing)
          }).then(assertIsOk).then(function() {
            toaster.toast('Thing updated');
            app.clearCache();
          });
        });
      }
      if (p !== resolved) {
        var self = this;
        p = p.then(function() {
          return self.onShow();
        });
      }
      return p;
    },
    onShow: function(thingId) {
      this.edit = false;
      if (thingId) {
        this.thingId = thingId;
      }
      this.thing = {};
      return Promise.all([
        fetch('/things/' + this.thingId).then(assertIsOk).then(getJson),
        fetch('/things/' + this.thingId + '/properties').then(getJson)
      ]).then(apply(this, function(thing, properties) {
        this.thing = thing;
        if (Array.isArray(properties)) {
          properties.sort(compareByTitle);
        }
        this.properties = properties;
      }));
    }
  }
});

new Vue({
  el: '#addThings',
  data: {
    extensionsById: {},
    things: []
  },
  methods: {
    onShow: function() {
      this.things = [];
      var self = this;
      fetch('/engine/discoveredThings').then(getJson).then(function(things) {
        if (Array.isArray(things)) {
          things.sort(compareByTitle);
        }
        for (var i = 0; i < things.length; i++) {
          var thing = things[i];
          thing.toAdd = false;
          self.things.push(thing);
        }
        //console.log('things', self.things);
        return app.getExtensionsById();
      }).then(function(extensionsById) {
        self.extensionsById = extensionsById;
      });
    },
    onSelectAll: function(toAdd) {
      if (typeof toAdd !== 'boolean') {
        var allToAdd = true;
        for (var i = 0; i < this.things.length; i++) {
          if (!this.things[i].toAdd) {
            allToAdd = false;
            break;
          }
        }
        toAdd = !allToAdd;
      }
      for (var i = 0; i < this.things.length; i++) {
        this.things[i].toAdd = toAdd;
      }
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
      }).then(assertIsOk).then(function() {
        toaster.toast('Things saved');
        app.clearCache();
      });
    }
  }
});

