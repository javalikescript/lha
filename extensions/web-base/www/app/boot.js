/************************************************************
 * Setup AMD
 ************************************************************/
 require(['_AMD'], function(_AMD) {
  _AMD.setLogFunction(console.warn);
  _AMD.setLoadModuleFunction(function(pathname, callback, sync, prefix, suffix) {
    var lastIndex = pathname.length - 1;
    var raw = pathname.charAt(lastIndex) === '!';
    if (raw) {
      pathname = pathname.substring(0, lastIndex)
    }
    fetch(pathname).then(function(response) {
      if (!response.ok) {
        return Promise.reject(response.statusText);
      }
      if (raw) {
        return response.text();
      }
      var dotIndex = pathname.lastIndexOf('.');
      var ext = dotIndex > pathname.lastIndexOf('/') ? pathname.substring(dotIndex + 1) : '';
      var contentType = response.headers.get('Content-Type');
      if (ext === 'js' || contentType === 'text/javascript') {
        return response.text().then(function(content) {
          return Function('"use strict";return ' + prefix + content + suffix)();
        });
      } else if (ext === 'json' || contentType === 'application/json') {
        return response.json();
      }
      return response.text();
    }).then(function(m) {
      callback(m);
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

function replaceLocationByNavigationPath(id, path) {
  window.location.replace(window.location.pathname + '#' + formatNavigationPath(id, path));
}

app.$on('page-selected', replaceLocationByNavigationPath);

window.addEventListener('hashchange', function() {
  app.navigateTo(getLocationPath());
});

// avoid horizontal scroll which could happen on a tab-focused element out of the view
window.addEventListener('scroll', function () {
  if (window.scrollX !== 0) {
    window.scroll(0, window.scrollY);
  }
});

/************************************************************
 * Load web base configuration and addons
 ************************************************************/
 Promise.all([
  fetch('/engine/configuration/extensions/web-base').then(rejectIfNotOk).then(getJson).then(function(response) {
    return response.value;
  }),
  fetch('addon/').then(rejectIfNotOk).then(getJson),
  fetch('/engine/user').then(rejectIfNotOk).then(getJson),
]).then(apply(this, function(webBaseConfig, addons, user) {
  if (webBaseConfig.title) {
    document.title = webBaseConfig.title;
    homePage.title = webBaseConfig.title;
  }
  app.setTheme(webBaseConfig.theme || 'default');
  app.user = user;
  if (Array.isArray(addons)) {
    return Promise.all(addons.map(function(addon) {
      console.log('loading addon ' + addon.id);
      return new Promise(function(resolve) {
        require(['addon/' + addon.id + '/' + addon.script], resolve);
      })
    }));
  }
})).then(function() {
  if (!app.navigateTo(getLocationPath(), true)) {
    replaceLocationByNavigationPath('home');
    app.navigateTo(getLocationPath(), true);
  }
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
