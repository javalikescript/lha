(function() {

registerPageVue(new Vue({
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
      fetch('/engine/extensions/' + extension.id + '/poll', {method: 'POST'}).then(assertIsOk).then(function() {
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
}), 'fa-plus-circle');

function onShowExtension(extensionId) {
  if (extensionId) {
    this.extensionId = extensionId;
  }
  return Promise.all([
    fetch('/engine/extensions/' + this.extensionId).then(getJson),
    app.getEnumsById()
  ]).then(apply(this, function(extension, enumsById) {
    if (extension && extension.manifest && extension.manifest.schema) {
      this.schema = populateJsonSchema(extension.manifest.schema, enumsById);
    } else {
      this.schema = false;
    }
    this.extension = extension;
  })).catch(function() {
    this.schema = false;
    this.extension = {config: {}, info: {}, manifest: {}};
  }.bind(this));
}

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
        return fetch('/engine/extensions/' + extensionId + '/disable', {method: 'POST'}).then(assertIsOk).then(function() {
          app.clearCache();
          toaster.toast('Extension disabled');
        });
      });
    },
    onReload: function() {
      var extensionId = this.extensionId;
      if (extensionId) {
        confirmation.ask('Reload the extension?').then(function() {
          fetch('/engine/extensions/' + extensionId + '/reload', {method: 'POST'}).then(assertIsOk).then(function() {
            toaster.toast('Extension reloaded');
          });
        });
      }
    },
    onRefreshThings: function() {
      var extensionId = this.extensionId;
      if (extensionId) {
        confirmation.ask('Disable and refresh all extension things?').then(function() {
          return fetch('/engine/extensions/' + extensionId + '/refreshThingsDescription', {method: 'POST'}).then(assertIsOk).then(function() {
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
        }).then(assertIsOk).then(function() {
          app.clearCache();
          toaster.toast('Extension configuration saved');
        });
      }
    },
    onShow: onShowExtension
  }
});

new Vue({
  el: '#extension-info',
  data: {
    info: {},
    readme: ''
  },
  methods: {
    onShow: function(extensionId) {
      this.readme = '';
      this.info = {};
      fetch('/engine/extensions/' + extensionId + '/info').then(assertIsOk).then(getJson).then(function(info) {
        this.info = info;
        return fetch('/engine/extensions/' + extensionId + '/readme');
      }.bind(this)).then(rejectIfNotOk).then(getResponseText).then(function(content) {
        this.readme = content;
      }.bind(this));
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
      }).then(assertIsOk).then(function() {
        return fetch('/engine/extensions/' + extensionId + '/enable', {method: 'POST'});
      }).then(assertIsOk).then(function() {
        app.clearCache();
        toaster.toast('Extension added');
      });
    },
    onShow: onShowExtension
  }
});

})();
