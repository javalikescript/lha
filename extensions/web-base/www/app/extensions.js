var extensionsVue =new Vue({
  el: '#extensions',
  data: {
    extensions: [],
    filter: false,
    query: ''
  },
  computed: {
    filteredExtensions: function () {
      if ((this.query.length === 0) || !this.filter) {
        return this.extensions;
      }
      var query = this.query;
      return this.extensions.filter(function(extension) {
        return contains(query, extension.name, extension.description, extension.id);
      });
    }
  },
  methods: {
    pollExtension: function(extension) {
      fetch('/engine/extensions/' + extension.id + '/poll', {method: 'POST'}).then(function() {
        toaster.toast('Extension polled');
      });
    },
    onShow: function() {
      var self = this;
      app.getExtensions().then(function(extensions) {
        self.extensions = extensions;
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
});

new Vue({
  el: '#extension',
  data: {
    extensionId: '',
    extension: {config: {}, info: {}, manifest: {}},
    schema: false
  },
  methods: {
    onDisable: function() {
      var extensionId = this.extensionId;
      if (!extensionId) {
        return Promise.reject();
      }
      return confirmation.ask('Disable the extension?').then(function() {
        return fetch('/engine/extensions/' + extensionId + '/disable', {method: 'POST'}).then(function() {
          app.clearCache();
          toaster.toast('Extension disabled');
        });
      });
    },
    onReload: function() {
      var extensionId = this.extensionId;
      if (extensionId) {
        confirmation.ask('Reload the extension?').then(function() {
          fetch('/engine/extensions/' + extensionId + '/reload', {method: 'POST'}).then(function() {
            toaster.toast('Extension reloaded');
          });
        });
      }
    },
    onRefreshThings: function() {
      var extensionId = this.extensionId;
      if (extensionId) {
        confirmation.ask('Disable and refresh all extension things?').then(function() {
            fetch('/engine/extensions/' + extensionId + '/refreshThingsDescription', {method: 'POST'}).then(function() {
            toaster.toast('Extension things refreshed');
          });
        });
      }
    },
    onSave: function() {
      if (this.extensionId && this.extension.config) {
        fetch('/engine/configuration/extensions/' + this.extensionId, {
          method: 'PUT',
          body: JSON.stringify({
            value: this.extension.config
          })
        }).then(function() {
          app.clearCache();
          toaster.toast('Extension configuration saved');
        });
      }
    },
    onShow: function(extensionId) {
      var self = this;
      if (extensionId) {
        this.extensionId = extensionId;
      }
      self.extension = {config: {}, info: {}, manifest: {}};
      fetch('/engine/extensions/' + this.extensionId).then(function(response) {
        return response.json();
      }).then(function(extension) {
        self.extension = extension;
        return app.getEnumsById();
      }).then(function(enumsById) {
        if (self.extension && self.extension.manifest && self.extension.manifest.schema) {
          self.schema = populateJsonSchema(self.extension.manifest.schema, enumsById);
        }
        //console.log('extension', self.extension, 'schema', JSON.stringify(self.schema, undefined, 2));
      });
    }
  }
});

new Vue({
  el: '#addExtensions',
  data: {
    extensions: []
  },
  methods: {
    onShow: function() {
      var self = this;
      app.getExtensions().then(function(extensions) {
        self.extensions = extensions;
      });
    }
  }
});

new Vue({
  el: '#addExtension',
  data: {
    extensionId: '',
    extension: {config: {}, info: {}, manifest: {}},
    schema: false
  },
  methods: {
    onAdd: function() {
      console.log('onAdd()', this);
      var extensionId = this.extensionId;
      if (!extensionId || !this.extension.config) {
        return Promise.reject();
      }
      return fetch('/engine/configuration/extensions/' + extensionId, {
        method: 'PUT',
        body: JSON.stringify({
          value: this.extension.config
        })
      }).then(function() {
        return fetch('/engine/extensions/' + extensionId + '/enable', {method: 'POST'});
      }).then(function() {
        app.clearCache();
        toaster.toast('Extension added');
      });
    },
    onShow: function(extensionId) {
      if (extensionId) {
        this.extensionId = extensionId;
      }
      this.extension = {config: {}, info: {}, manifest: {}};
      var self = this;
      fetch('/engine/extensions/' + this.extensionId).then(function(response) {
        return response.json();
      }).then(function(extension) {
        self.extension = extension;
        return app.getEnumsById();
      }).then(function(enumsById) {
        if (self.extension && self.extension.manifest && self.extension.manifest.schema) {
          self.schema = populateJsonSchema(self.extension.manifest.schema, enumsById);
        }
        //console.log('extension', self.extension, 'schema', self.schema);
      });
    }
  }
});

registerPageVue(extensionsVue, 'fa-plus-circle');
