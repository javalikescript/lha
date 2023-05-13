define(['./web-tools.xml'], function(toolsTemplate) {

  function insertTab(e) {
    if (e.key == 'Tab') {
      e.preventDefault();
      var start = this.selectionStart;
      var end = this.selectionEnd;
      this.value = this.value.substring(0, start) + '\t' + this.value.substring(end);
      this.selectionStart = this.selectionEnd = start + 1;
    }
  }

  var toolsVue = new Vue({
    template: toolsTemplate,
    data: {
      logLevel: '',
      lua: '',
      out: ''
    },
    mounted: function() {
      this.$refs.lua.addEventListener('keydown', insertTab);
    },
    methods: {
      onShow: function() {
        var page = this;
        fetch('/engine/admin/getLogLevel').then(function(response) {
          return response.text();
        }).then(function(logLevel) {
          page.logLevel = logLevel.toLowerCase();
        });
      },
      applyLogLevel: function() {
        var logLevel = this.logLevel;
        if (logLevel) {
          fetch('/engine/admin/setLogLevel', {method: 'POST', body: logLevel}).then(assertIsOk).then(function() {
            toaster.toast('Log Level updated to ' + logLevel);
          });
        }
      },
      execute: function() {
        var page = this;
        page.out = '';
        fetch('/engine/tools/execute', {method: 'POST', body: this.lua}).then(assertIsOk).then(function(response) {
          return response.text();
        }).then(function(out) {
          page.out = out;
        });
      },
      clearCache: function() {
        app.clearCache();
      },
      gc: function() {
        var page = this;
        fetch('/engine/admin/gc', {method: 'POST'}).then(assertIsOk).then(function(response) {
          page.refreshInfo();
        });
      },
      pollThings: function() {
        fetch('/engine/poll', {method: 'POST'}).then(assertIsOk).then(function() {
          toaster.toast('Polling triggered');
        });
      },
      refreshThings: function() {
        confirmation.ask('Disable and refresh all things?').then(function() {
          fetch('/engine/refreshThingsDescription', {method: 'POST'}).then(assertIsOk).then(function() {
            toaster.toast('Things refreshed');
          });
        });
      },
      saveConfig: function() {
        fetch('/engine/admin/configuration/save', {method: 'POST'}).then(assertIsOk).then(function() {
          toaster.toast('Configuration saved');
          app.clearCache();
        });
      },
      saveData: function() {
        fetch('/engine/admin/data/save', {method: 'POST'}).then(assertIsOk).then(function() {
          toaster.toast('Data saved');
          app.clearCache();
        });
      },
      reloadExtensions: function() {
        fetch('/engine/admin/reloadExtensions/all', {method: 'POST'}).then(assertIsOk).then(function() {
          toaster.toast('Extensions reloaded');
          app.clearCache();
        });
      },
      reloadScripts: function() {
        fetch('/engine/admin/reloadScripts/all', {method: 'POST'}).then(assertIsOk).then(function() {
          toaster.toast('Scripts reloaded');
          app.clearCache();
        });
      },
      restartServer: function() {
        confirmation.ask('Restart the server?').then(function() {
          fetch('/engine/admin/restart', { method: 'POST'});
        });
      },
      rebootServer: function() {
        confirmation.ask('Reboot the server?').then(function() {
          fetch('/engine/admin/reboot', { method: 'POST'});
        });
      },
      stopServer: function() {
        confirmation.ask('Stop the server?').then(function() {
          return fetch('/engine/admin/stop', { method: 'POST'});
        }).then(assertIsOk).then(function() {
          app.toPage('home');
          toaster.toast('Server stopped');
        });
      }
    }
  });
  
  addPageComponent(toolsVue, 'fa-tools');

});
