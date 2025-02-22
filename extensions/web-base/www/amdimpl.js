/*
 * Asynchronous Module Definition (AMD) API implementation for JLS.
 * The following code creates a 'require' function to load modules.
 * See https://github.com/amdjs/amdjs-api
 */
(function() {
  /* Helper functions */
  function extension(path) {
    var index = path.lastIndexOf('.');
    if (index !== -1) {
      var slashIndex = path.lastIndexOf('/');
      if (index > slashIndex) {
        return path.substring(index + 1);
      }
    }
    return '';
  }
  function basename(path) {
    var index = path.lastIndexOf('/');
    return index === -1 ? path : path.substring(index + 1);
  }
  function dirname(path) {
    var index = path.lastIndexOf('/');
    return index === -1 ? '' : path.substring(0, index);
  }
  function endsWith(value, search) {
    return value.substring(value.length - search.length) === search;
  }
  function startsWith(value, search) {
    return value.substring(0, search.length) === search;
  }
  function concatPath(a, b) {
    var pathItems = b.split('/');
    if ((a !== '.') && ((pathItems[0] === '.') || (pathItems[0] === '..'))) {
      pathItems = a.split('/').concat(pathItems);
    }
    for (var i = 0; i < pathItems.length; i++) {
      var pathItem = pathItems[i];
      if ((pathItem === '.') || (pathItem === '')) {
        pathItems.splice(i, 1);
        i--;
      } else if ((i > 0) && (pathItem === '..')) {
        pathItems.splice(i - 1, 2);
        i -= 2;
      }
    }
    var path = pathItems.join('/');
    if (startsWith(b, '/')) {
      path = '/' + path;
    }
    if (endsWith(b, '/')) {
      path = path + '/';
    }
    return path;
  }
  function basemodule(path) {
    var index = path.indexOf('$');
    return index === -1 ? path : path.substring(0, index);
  }
  function submodule(module, path) {
    if (typeof path !== 'string') {
      return module;
    }
    var index = path.indexOf('$');
    if (index === -1) {
      return module;
    }
    var subpath = path.substring(index + 1);
    // TODO handle sub sub...
    return module[subpath];
  }
  /* Miscellaneous functions */
  var warn, log, debug, loadModule;
  log = debug = warn = function(msg) {};
  var previousDefine = undefined;
  loadModule = function(path, callback, sync, prefix, suffix) {};
  var fullyQualifiedRequire, createRequire, fullyQualifiedDefine;
  /* The cache is a map containing the defined module by absolute path (module identifier) */
  var cache = {};
  /* The AMD specific define entry */
  var amd = {
      multiversion: true
  };
  /*  */
  var CacheEntry = function(path, sync, module) {
    this.path = path || null;
    this.module = module || undefined;
    this.exports = null;
    this.sync = sync || false;
    this.paths = null;
    this.callback = null;
    this.defined = false;
    this.loading = false;
    this.dependencies = [];
    this.count = 0;
    this.waiters = [];
    if (path) {
      cache[path] = this;
    }
    log('CacheEntry("' + path + '", ' + sync + ', ' + module + ')');
  };
  CacheEntry.prototype.declare = function(paths, callback) {
    log('declare([' + paths + '], ...) "' + this.path + '"');
    this.paths = paths || null;
    this.callback = callback || null;
  };
  CacheEntry.prototype.onDefined = function(module) {
    log('onDefined(...) "' + this.path + '"');
    this.module = module || null;
    if ((this.exports !== null) && (typeof this.exports !== 'undefined')) {
      var singleKey = null;
      for (var k in this.exports) {
        if (singleKey === null) {
          singleKey = k;
        } else {
          singleKey = null;
          break;
        }
      }
      if (singleKey === null) {
        this.module = this.exports;
      } else {
        this.module = this.exports[singleKey];
      }
    }
    // Play dependencies
    for (var index = 0; index < this.waiters.length; index++) {
      this.waiters[index].notify(this);
    }
    // TODO Cleanup dependencies...
    this.waiters = [];
  };
  CacheEntry.prototype.onLoaded = function(fnOrContent, err) {
    var t = typeof fnOrContent;
    debug('onLoaded(' + t + ', ' + err + ') "' + this.path + '"');
    var m = null;
    if (err) {
      warn('Exception raised while loading "' + this.path + '": ' + err);
    } else {
      var self = this;
      if (t === 'function') {
        try {
          /* Creates a define function suitable for this module */
          var defined = false;
          var defineFn = function(id, dependencies, factory) {
            if (typeof id === 'function') {
              factory = id;
              dependencies = null;
              id = undefined;
            } else if (typeof dependencies === 'function') {
              factory = dependencies;
              dependencies = id;
              id = undefined;
            }
            fullyQualifiedRequire(self.path, dependencies, factory, self.sync);
            defined = true;
          };
          m = fnOrContent(defineFn);
          if (defined) {
            return;
          }
        } catch (e) {
          warn('Exception raised while evaluating "' + this.path + '": ' + e);
        }
      } else if ((t === 'string') || (t === 'object')) {
        m = fnOrContent;
      } else {
        warn('Invalid argument while loading "' + this.path + '" (' + t + ')');
      }
    }
    if (typeof m === 'object' && typeof m.then === 'function') {
      m.then(function(n) {
        self.onDefined(n);
      }, function(e) {
        warn('Exception raised while loading "' + self.path + '": ' + e);
        self.onDefined(null);
      });
    } else {
      this.onDefined(m);
    }
  };
  CacheEntry.prototype.load = function() {
    debug('load() "' + this.path + '"');
    var self = this;
    var path = this.path;
    var ext = extension(path);
    if (ext === '' && !endsWith(path, '/')) {
      path += '.js';
    }
    this.loading = true;
    loadModule(path, function(fnOrContent, err) {
      self.onLoaded.call(self, fnOrContent, err);
    }, this.sync, '(function() { return function(define) { ', ' }; })();');
  };
  CacheEntry.prototype.notify = function(entry) {
    debug('notify("' + entry.path + '") "' + this.path + '"');
    for (var index = 0; index < this.paths.length; index++) {
      var path = basemodule(this.paths[index]);
      if (path === entry.path) {
        this.setDependency(index, entry.module);
        break;
      }
    }
  };
  CacheEntry.prototype.isDependent = function(entry) {
    debug('isDependent("' + entry.path + '") "' + this.path + '"');
    if (entry.path === null) {
      return false;
    }
    for (var index = 0; index < this.waiters.length; index++) {
      var waiter = this.waiters[index];
      if ((waiter.path !== null) && ((waiter.path === entry.path) || (waiter.isDependent(entry)))) {
        return true;
      }
    }
    return false;
  };
  CacheEntry.prototype.wait = function(entry) {
    debug('wait("' + entry.path + '") "' + this.path + '"');
    if (this.isDependent(entry)) {
      throw 'Cyclic dependency detected between ' + this.path + ' and ' + entry.path;
    }
    entry.waiters.push(this);
  };
  CacheEntry.prototype.isLoading = function() {
    return this.loading;
  };
  CacheEntry.prototype.isLoaded = function() {
    return typeof this.module !== 'undefined';
  };
  CacheEntry.prototype.isModule = function() {
    return this.path !== null;
  };
  CacheEntry.prototype.isDeclared = function() {
    return (this.callback !== null) || this.isLoaded();
  };
  CacheEntry.prototype.setDependency = function(index, value) {
    var path = this.paths[index];
    this.dependencies[index] = submodule(value, path);
    this.count++;
    debug('setDependency(' + index + ', ...) "' + this.path + '" ' + this.count + '/' + this.paths.length);
    this.wakeup();
  };
  CacheEntry.prototype.wakeup = function() {
    if ((this.callback) && ((this.paths === null) || (this.count === this.paths.length))) {
      debug('wakeup() "' + this.path + '"');
      var fn = this.callback;
      var dep = this.dependencies;
      this.paths = null;
      this.callback = null;
      this.dependencies = null;
      var module = fn.apply(null, dep);
      this.onDefined(this.isModule() ? module : null);
    }
  };
  /* Base require/define function that use a fully qualified module id */
  fullyQualifiedRequire = function(moduleId, ids, callback, sync, dl) {
    if (typeof callback !== 'function') {
      throw 'Invalid arguments';
    }
    sync = (typeof sync === 'boolean') ? sync : false;
    dl = (typeof dl === 'boolean') ? dl : false;
    var basepath = dirname(moduleId || '');
    var name = basename(moduleId || '');
    var paths = [];
    if ((ids !== null) && ('length' in ids)) {
      for (var index = 0; index < ids.length; index++) {
        var id = ids[index];
        if (id === '.') {
          id = './main';
        }
        paths.push(concatPath(basepath, id));
      }
    }
    if (name === '?') {
      moduleId = null;
    }
    var entry;
    if (moduleId) {
      if (moduleId in cache) {
        // Check sync ?
        entry = cache[moduleId];
      } else {
        entry = new CacheEntry(moduleId, sync, undefined);
      }
      entry.defined = true;
    } else {
      entry = new CacheEntry(null, sync, undefined);
    }
    entry.declare(paths, callback);
    for (var index = 0; index < paths.length; index++) {
      var path = basemodule(paths[index]);
      var depEntry;
      try {
        if (path === 'require') {
          entry.setDependency(index, createRequire(basepath));
        } else if (path === 'requirePath') {
          entry.setDependency(index, basepath);
        } else if (path === 'exports') {
          entry.setDependency(index, entry.exports = {});
        } else if (path in cache) {
          depEntry = cache[path];
          if (depEntry.isLoaded()) {
            entry.setDependency(index, depEntry.module);
          } else {
            // TODO Check sync
            entry.wait(depEntry);
            if (! (dl || depEntry.isLoading())) {
              depEntry.load();
            }
          }
        } else {
          depEntry = new CacheEntry(path, sync);
          entry.wait(depEntry);
          if (! dl) {
            depEntry.load();
          }
        }
      }
      catch (e) {
        warn('Exception raised: ' + e);
        //debug(e.name + ': ' + e.message);
        entry.setDependency(index, null);
      }
    }
    entry.wakeup();
  };
  /* Returns a require function suitable for a specific path */
  createRequire = function(path) {
    return function(ids, callback) {
      var async = true;
      var rmod = null;
      if (typeof ids === 'string') {
        ids = [ids];
      }
      if (typeof callback === 'undefined') {
        async = false;
        callback = function(module) {
          if ((typeof module === 'undefined') || (module === null)) {
            warn('Fail to require "' + ids[0] + '"');
          }
          rmod = module;
        };
      }
      fullyQualifiedRequire(path + '/?', ids, callback, !async);
      return async ? undefined : rmod;
    };
  };
  /* Define function that use a fully qualified module id */
  fullyQualifiedDefine = function(id, dependencies, factory) {
    log('define(' + id + ')');
    fullyQualifiedRequire(id, dependencies, factory, true, true);
  };
  // Populate default cache values
  new CacheEntry('_AMD', true, {
    cache : cache,
    setLogFunction: function(fn, level) {
      switch(level) {
      default:
      case 'warn': warn = fn; break;
      case 'log': log = fn; break;
      case 'debug': debug = fn; break;
      case 'all': log = debug = warn = fn; break;
      }
    },
    enableDefine: function() {
      log('enableDefine()');
      previousDefine = (typeof define !== 'undefined') ? define : undefined;
      // global define function
      define = fullyQualifiedDefine;
    },
    disableDefine: function() {
      log('disableDefine()');
      define = previousDefine;
    },
    setLoadModuleFunction: function(fn) {
      loadModule = fn;
    },
    setEvalScriptFunction: function(fn) {
      loadModule = fn;
    },
    getModuleId: function(obj) {
      for (var id in cache) {
        if (cache[id].module === obj.constructor) {
          return id;
        }
      }
      return null;
    },
    status: function() {
      log('AMD Cache status:');
      var lm = [], wm = [];
      for (var path in cache) {
        (cache[path].module ? lm : wm).push(path);
      }
      lm.sort(); wm.sort();
      for (var i = 0; i < lm.length; i++) {
        log(' "' + lm[i] + '" loaded');
      }
      for (var i = 0; i < wm.length; i++) {
        var path = wm[i];
        var ce = cache[path];
        var paths = '';
        if (ce.paths !== null) {
          for (var j = 0; j < ce.paths.length; j++) {
            paths += (paths === '' ? '' : ', ') + (ce.dependencies[j] !== null ? '!' : '') + ce.paths[j];
          }
        }
        log(' "' + path + '"(' + paths + ') ' + ce.waiters.length + ' waiting callback(s)');
      }
    },
    lazyRequire : function(ids, callback) {
      if (arguments.length < 2) {
        return;
      }
      fullyQualifiedRequire('/?', ids, callback, true, true);
    },
    dirname : dirname,
    basename : basename,
    concatPath : concatPath,
    createRequire : createRequire,
    fullyQualifiedDefine : fullyQualifiedDefine,
    fullyQualifiedRequire : fullyQualifiedRequire
  });
  // global require function
  require = createRequire('');
})();
