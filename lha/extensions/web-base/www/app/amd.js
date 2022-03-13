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
          console.log('fail to eval module "' + pathname + '" due to:', e);
          callback(null, e);
        }
      }
    }, function(reason) {
      callback(null, reason || ('fail to fetch "' + pathname + '"'));
    });
  });
});
