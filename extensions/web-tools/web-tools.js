define(['./web-tools.xml'], function(toolsTemplate) {

  var toolsVue = new Vue({
    template: toolsTemplate,
    data: {
      logLevel: ''
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
          fetch('/engine/admin/setLogLevel', {method: 'POST', body: logLevel}).then(function() {
            toaster.toast('Log Level updated to ' + logLevel);
          });
        }
      },
      clearCache: function() {
        app.clearCache();
      },
      gc: function() {
        var page = this;
        fetch('/engine/admin/gc', {method: 'POST'}).then(function(response) {
          page.refreshInfo();
        });
      },
      pollThings: function() {
        fetch('/engine/poll', {method: 'POST'}).then(function() {
          toaster.toast('Polling triggered');
        });
      },
      saveConfig: function() {
        fetch('/engine/admin/configuration/save', {method: 'POST'}).then(function() {
          toaster.toast('Configuration saved');
          app.clearCache();
        });
      },
      reloadExtensions: function() {
        fetch('/engine/admin/reloadExtensions/all', {method: 'POST'}).then(function() {
          toaster.toast('Extensions reloaded');
          app.clearCache();
        });
      },
      reloadScripts: function() {
        fetch('/engine/admin/reloadScripts/all', {method: 'POST'}).then(function() {
          toaster.toast('Scripts reloaded');
          app.clearCache();
        });
      },
      restartServer: function() {
        confirmation.ask('Restart the server?').then(function() {
          fetch('/engine/admin/restart', { method: 'POST'});
        });
      },
      stopServer: function() {
        confirmation.ask('Stop the server?').then(function() {
          fetch('/engine/admin/stop', { method: 'POST'}).then(function() {
            app.toPage('home');
            toaster.toast('Server stopped');
          });
        });
      }
    }
  });
  
  addPageComponent(toolsVue, 'fa-tools');

});
