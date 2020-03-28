new Vue({
  el: '#extensions',
  data: {
    extensions: []
  },
  methods: {
    pollExtension: function(extension) {
      fetch('/engine/extensions/' + extension.id + '/poll', {method: 'POST'}).then(function() {
        toaster.toast('extension polled');
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
    extension: {config: {}, info: {}, manifest: {}}
  },
  methods: {
    onDisable: function() {
      if (this.extensionId) {
        if (this.extension.config) {
          this.extension.config.active = false;
        }
        fetch('/engine/configuration/extensions/' + this.extensionId, {
          method: 'POST',
          body: JSON.stringify({
            value: {active: false}
          })
        }).then(function() {
          app.clearCache();
        });
      }
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
          method: 'POST',
          body: JSON.stringify({
            value: this.extension.config
          })
        }).then(function() {
          app.clearCache();
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
        //console.log('extension', self.extension);
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
    },
    onSave: function() {
      var config = {extensions: {}};
      // archiveData
      for (var i = 0; i < this.extensions.length; i++) {
        var item = this.extensions[i];
        config.extensions[item.id] = {active: item.active};
      }
      console.log('config', config);
      fetch('/engine/configuration/', {
        method: 'POST',
        body: JSON.stringify({
          value: config
        })
      }).then(function() {
        app.clearCache();
      });
    }
  }
});
