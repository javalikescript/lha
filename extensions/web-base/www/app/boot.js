/************************************************************
 * Setup AMD
 ************************************************************/
 require(['_AMD'], function(_AMD) {
  var extension = function(path) {
    var slashIndex = path.lastIndexOf('/');
    var index = path.lastIndexOf('.');
    return index <= slashIndex ? '' : path.substring(index + 1);
  };
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
          //console.log('module "' + pathname + '" evaluated', m);
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
 var onHashChange = function() {
  var matches = window.location.hash.match(/^#(\/[^\/]+\/.*)$/);
  if (matches) {
    app.navigateTo(matches[1]);
  } else {
    app.toPage('main');
  }
};
app.$on('page-selected', function(id, path) {
  window.location.replace(window.location.pathname + '#' + formatNavigationPath(id, path));
});
window.addEventListener('hashchange', onHashChange);

var webBaseConfig = {};
var startCountDown = 1;

var countDownStart = function() {
  startCountDown--;
  if (startCountDown === 0) {
    onHashChange();
    if (webBaseConfig.theme) {
      setTheme(webBaseConfig.theme);
    }
  }
};

startCountDown++;
fetch('/engine/configuration/extensions/web-base').then(function(response) {
  return response.json();
}).then(function(response) {
  webBaseConfig = response.value || {};
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