define(['./web-tools.xml'], function(toolsTemplate) {

  var toolsVue = new Vue({
    template: toolsTemplate,
    data: {
      logConfig: '',
      logLevel: '',
      lua: '',
      luaOut: '',
      cmd: '',
      cmdOut: ''
    },
    methods: {
      onShow: function() {
        var page = this;
        fetch('/engine/admin/getLogLevel').then(getResponseText).then(function(logLevel) {
          page.logLevel = logLevel.toLowerCase();
        });
      },
      applyLogConfig: function() {
        fetch('/engine/admin/setLogConfig', {method: 'POST', body: this.logConfig}).then(assertIsOk).then(function() {
          toaster.toast('Log configuration applied');
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
        page.cmdOut = '';
        fetch('/engine/tools/execute', {method: 'POST', body: this.cmd}).then(assertIsOk).then(getResponseText).then(function(out) {
          page.cmdOut = out;
        });
      },
      run: function() {
        var page = this;
        page.luaOut = '';
        fetch('/engine/tools/run', {method: 'POST', body: this.lua}).then(assertIsOk).then(getResponseText).then(function(out) {
          page.luaOut = out;
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
      postAction: function(path, ask, message, clearCache) {
        var action = function() {
          var p = fetch('/engine/' + path, {method: 'POST'});
          if (message || clearCache) {
            p.then(assertIsOk).then(function() {
              if (message) {
                toaster.toast(message);
              }
              if (clearCache) {
                app.clearCache();
              }
            });
          }
        };
        if (ask) {
          confirmation.ask(ask).then(action);
        } else {
          action();
        }
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
  
  if (app.canAdminister) {
    addPageComponent(toolsVue, 'tools', true);
  }

});
