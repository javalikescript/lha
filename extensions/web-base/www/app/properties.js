registerPageVue(new Vue({
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
        return contains(query, property.name, property.title, property.description, property.extension.name, property.thing.title);
      });
    }
  },
  methods: {
    onShow: function() {
      Promise.all([
        app.getThings(),
        app.getExtensionsById(),
        app.getPropertiesByThingId()
      ]).then(apply(this, function(things, extensionsById, propertiesByThingId) {
        this.properties = [];
        for (var i = 0; i < things.length; i++) {
          var thing = things[i];
          var props = propertiesByThingId[thing.thingId];
          for (var name in thing.properties) {
            var property = thing.properties[name];
            property.name = name;
            property.value = props[name];
            property.thing = thing;
            property.extension = extensionsById[thing.extensionId] || {};
            this.properties.push(property);
          }
        }
      }));
    },
    onDataChange: function() {
      this.onShow();
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
}), 'list', true, true);
