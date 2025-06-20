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
}), 'plus-circle', true, true);

var EXTENSION_DATA = {
  extensionId: '',
  config: {},
  info: {},
  actions: [],
  schema: false
};

function onShowExtension(extensionId) {
  this.schema = false;
  this.config = {};
  this.info = {};
  this.actions = [];
  this.extensionId = '';
  if (!extensionId) {
    return Promise.reject();
  }
  return Promise.all([
    fetch('/engine/extensions/' + extensionId).then(getJson),
    app.getEnumsById()
  ]).then(apply(this, function(extension, enumsById) {
    this.extensionId = extensionId;
    var schema = extension.manifest && extension.manifest.schema;
    this.schema = schema ? populateJsonSchema(schema, enumsById) : false;
    var actions = extension.manifest && extension.manifest.actions;
    if (actions) {
      if (typeof this.active === 'boolean') {
        actions = actions.filter(function(action) {
          return this.active === undefined || action.active === this.active;
        });
      }
      for (var i = 0; i < actions.length; i++) {
        var action = actions[i];
        if (action.arguments) {
          action.arguments = action.arguments.map(function(s) {
            return populateJsonSchema(s, enumsById);
          });
        }
      }
      this.actions = actions;
    } else {
      this.actions = [];
    }
    this.config = extension.config;
    this.info = extension.info;
  }));
}

function refreshConfig() {
  return fetch('/engine/extensions/' + this.extensionId + '/config').then(getJson).then(function(config) {
    this.config = config;
  }.bind(this));
}

function triggerAction(index) {
  //console.info('triggerAction(' + index + ')');
  var action = this.actions[index];
  if (!action) {
    return Promise.reject('No action #' + index);
  }
  Promise.resolve().then(function() {
    if (Array.isArray(action.arguments)) {
      var schema = {
        type: 'array',
        prefixItems: action.arguments,
        minItems: action.arguments.length
      };
      return promptDialog.ask(schema, action.description || action.name);
    }
    return [];
  }).then(function(parameters) {
    return fetch('/engine/extensions/' + this.extensionId + '/action/' + (index + 1), {
      method: 'POST',
      headers: { "Content-Type": 'application/json' },
      body: JSON.stringify(parameters)
    });
  }.bind(this)).then(assertIsOk).then(getJson).then(function(response) {
    if (response.success) {
      toaster.toast('Action triggered, ' + response.message);
      if (action.active === false) {
        refreshConfig.call(this);
      }
    } else {
      toaster.toast('Action failed, ' + response.message);
    }
  }.bind(this)).catch(function(reason) {
    toaster.toast('Action failed, ' + reason);
  });
}

new Vue({
  el: '#extension',
  data: Object.assign({
    active: true
  }, EXTENSION_DATA),
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
      if (this.extensionId && this.config) {
        putJson('/engine/configuration/extensions/' + this.extensionId, { value: this.config }).then(assertIsOk).then(function() {
          app.clearCache();
          toaster.toast('Extension configuration saved');
        });
      }
    },
    triggerAction: triggerAction,
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
        return fetch('/engine/extensions/' + extensionId + '/readme').then(rejectIfNotOk).then(getResponseText).then(function(content) {
          this.readme = content;
        }.bind(this), doNothing);
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
  data: Object.assign({
    active: false
  }, EXTENSION_DATA),
  methods: {
    onAdd: function() {
      console.log('onAdd()', this);
      var extensionId = this.extensionId;
      if (!extensionId || !this.config) {
        return Promise.reject();
      }
      return putJson('/engine/configuration/extensions/' + extensionId, { value: this.config }).then(assertIsOk).then(function() {
        return fetch('/engine/extensions/' + extensionId + '/enable', {method: 'POST'});
      }).then(assertIsOk).then(function() {
        app.clearCache();
        toaster.toast('Extension added');
      });
    },
    triggerAction: triggerAction,
    onShow: onShowExtension
  }
});

})();
