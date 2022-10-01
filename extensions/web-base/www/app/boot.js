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

var webBaseConfig = {};
var startCountDown = 1;
var webSocket = null;

function setupWebSocket() {
  if (!webSocket) {
    var protocol = location.protocol.replace('http', 'ws');
    webSocket = new WebSocket(protocol + '//' + location.host + '/ws/');
    webSocket.onmessage = function(event) {
      //console.log('webSocket.onmessage', event);
      if (event.data) {
        app.onMessage(JSON.parse(event.data));  
      }
    };
    webSocket.onclose = function() {
      webSocket = null;
    };
  }
}

var countDownStart = function() {
  startCountDown--;
  if (startCountDown === 0) {
    countDownStart = undefined;
    if (webBaseConfig.theme) {
      setTheme(webBaseConfig.theme);
    }
    app.navigateTo(getLocationPath());
    setupWebSocket();
  }
};

startCountDown++;
fetch('/engine/configuration/extensions/web-base').then(function(response) {
  return response.json();
}).then(function(response) {
  webBaseConfig = response.value || {};
  if (webBaseConfig.title) {
    document.title = webBaseConfig.title;
    homePage.title = webBaseConfig.title;
  }
  countDownStart();
}, function() {
  webBaseConfig = {};
  countDownStart();
});

startCountDown++;
fetch('addon/').then(function(response) {
  return response.json();
}).then(function(addons) {
  if (Array.isArray(addons)) {
    addons.forEach(function(addon) {
      console.log('loading addon ' + addon.id);
      startCountDown++;
      require(['addon/' + addon.id + '/' + addon.script], countDownStart);
    });
  }
  countDownStart();
});

countDownStart();