define(['./web-settings.xml'], function(settingsTemplate) {

  var settingsVue = new Vue({
    template: settingsTemplate,
    data: {
      filename: '',
      logLevel: ''
    },
    methods: {
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
            app.toPage('main');
            toaster.toast('Server stopped');
          });
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
      backup: function() {
        var self = this;
        fetch('/engine/admin/backup/create', {method: 'POST'}).then(function(response) {
          return response.text();
        }).then(function(filename) {
          self.filename = filename;
        });
      },
      selectFile: function(event) {
        this.$refs.uploadInput.click();
      },
      uploadThenDeploy: function(event) {
        var input = event.target;
        if (input.files.length !== 1) {
          return;
        }
        var file = input.files[0];
        fetch('/engine/tmp/' + file.name, {
          method: 'PUT',
          headers: {
            "Content-Type": "application/octet-stream"
          },
          body: file
        }).then(function() {
          return fetch('/engine/admin/backup/deploy', {
            method: 'POST',
            body: file.name
          });
        });
      }
    }
  });
  
  addPageComponent(settingsVue);

  menu.pages.push({
    id: 'settings',
    name: 'Settings'
  });

});
