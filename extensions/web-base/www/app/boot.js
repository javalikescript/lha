/************************************************************
 * Setup AMD
 ************************************************************/
 require(['_AMD'], function(_AMD) {
  var extension = function(path) {
    var slashIndex = path.lastIndexOf('/');
    var index = path.lastIndexOf('.');
    return index <= slashIndex ? '' : path.substring(index + 1);
  };
  _AMD.setLogFunction(console.warn);
  _AMD.setLoadModuleFunction(function(pathname, callback, sync, prefix, suffix) {
    var ext = extension(pathname);
    fetch(pathname).then(function(response) {
      //console.log('module "' + pathname + '" retrieved with extension "' + ext + '"');
      if (ext === 'json') {
        return response.json();
      } else {
        return response.text();
      }
    }).then(function(content) {
      if (ext !== 'js') {
        callback(content);
      } else {
        var src = prefix + content + suffix;
        try {
          //var m = window.eval(src);
          var m = Function('"use strict";return ' + src)();
          //console.log('module "' + pathname + '" evaluated', m, src);
          callback(m);
        } catch(e) {
          console.warn('fail to eval module "' + pathname + '" due to:', e);
          callback(null, e);
        }
      }
    }, function(reason) {
      callback(null, reason || ('fail to fetch "' + pathname + '"'));
    });
  });
});

/************************************************************
 * Route application using location hash
 ************************************************************/
function getLocationPath() {
  var matches = parseNavigationPath(window.location.hash.substring(1))
  if (matches) {
    return formatNavigationPath(matches[1], matches[2]);
  }
  return formatNavigationPath('home');
}

app.$on('page-selected', function(id, path) {
  window.location.replace(window.location.pathname + '#' + formatNavigationPath(id, path));
});

window.addEventListener('hashchange', function() {
  app.navigateTo(getLocationPath());
});

/************************************************************
 * Load web base configuration and addons
 ************************************************************/
 Promise.all([
  fetch('/engine/configuration/extensions/web-base').then(getJson),
  fetch('addon/').then(getJson)
]).then(function(results) {
  var webBaseConfig = results[0].value || {};
  if (webBaseConfig.title) {
    document.title = webBaseConfig.title;
    homePage.title = webBaseConfig.title;
  }
  if (webBaseConfig.theme) {
    var body = document.getElementsByTagName('body')[0];
    body.setAttribute('class', 'theme_' + webBaseConfig.theme);
  }
  var addons = results[1];
  if (Array.isArray(addons)) {
    return Promise.all(addons.map(function(addon) {
      console.log('loading addon ' + addon.id);
      return new Promise(function(resolve) {
        require(['addon/' + addon.id + '/' + addon.script], resolve);
      })
    }));
  }
}).then(function() {
  app.navigateTo(getLocationPath());
  function setupWebSocket() {
    var protocol = location.protocol.replace('http', 'ws');
    var url = protocol + '//' + location.host + '/ws/';
    var webSocket = new WebSocket(url);
    webSocket.onmessage = function(event) {
      //console.log('webSocket.onmessage', event);
      if (event.data) {
        app.onMessage(JSON.parse(event.data));  
      }
    };
    webSocket.onopen = function() {
      console.log('WebSocket opened at ' + url);
    };
    webSocket.onclose = function() {
      console.log('WebSocket closed');
      webSocket = null;
      setTimeout(setupWebSocket, 3000);
    };
  }
  setupWebSocket();
});
