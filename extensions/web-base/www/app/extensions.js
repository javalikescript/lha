new Vue({
  el: '#extensions',
  data: {
    extensions: []
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
      if (!this.extensionId) {
        return Promise.reject();
      }
      return fetch('/engine/extensions/' + this.extensionId + '/disable', {method: 'POST'}).then(function() {
        app.clearCache();
        toaster.toast('Extension disabled');
      });
    },
    onReload: function() {
      if (this.extensionId) {
        fetch('/engine/extensions/' + this.extensionId + '/reload', {method: 'POST'}).then(function() {
          toaster.toast('Extension reloaded');
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
        return app.getThings();
      }).then(function(things) {
        if (self.extension && self.extension.manifest && self.extension.manifest.schema) {
          self.schema = computeJsonSchema(self.extension.manifest.schema, things);
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
        return app.getThings();
      }).then(function(things) {
        if (self.extension && self.extension.manifest && self.extension.manifest.schema) {
          self.schema = computeJsonSchema(self.extension.manifest.schema, things);
        }
        //console.log('extension', self.extension, 'schema', self.schema);
      });
    }
  }
});
