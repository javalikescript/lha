/************************************************************
 * Setup AMD
 ************************************************************/
 require(['_AMD'], function(_AMD) {
  _AMD.setLogFunction(console.warn);
  _AMD.setLoadModuleFunction(function(pathname, callback, sync, prefix, suffix) {
    var raw = pathname.charAt(pathname.length - 1) === '!';
    if (raw) {
      pathname = pathname.substring(0, pathname.length - 1)
    }
    var slashIndex = pathname.lastIndexOf('/');
    var name = slashIndex < 0 ? pathname : pathname.substring(slashIndex + 1);
    var dotIndex = name.lastIndexOf('.');
    var ext = dotIndex < 0 ? '' : name.substring(dotIndex + 1);
    fetch(pathname).then(function(response) {
      //console.log('module "' + pathname + '" retrieved with extension "' + ext + '"');
      return ext === 'json' && !raw ? response.json() : response.text();
    }).then(function(content) {
      if (raw || ext !== 'js') {
        callback(content);
      } else {
        var src = prefix + content + suffix;
        try {
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
  fetch('/engine/configuration/extensions/web-base').then(rejectIfNotOk).then(getJson),
  fetch('addon/').then(rejectIfNotOk).then(getJson),
  fetch('/engine/user').then(rejectIfNotOk).then(getJson),
]).then(function(results) {
  var webBaseConfig = results[0].value || {};
  if (webBaseConfig.title) {
    document.title = webBaseConfig.title;
    homePage.title = webBaseConfig.title;
  }
  if (webBaseConfig.theme) {
    app.setTheme(webBaseConfig.theme);
  }
  app.user = results[2];
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
