function formatNavigationPath(pageId, path) {
  var encodedPath = path ? path.split('/').map(function(part) { return encodeURIComponent(part); }).join('/') : '';
  return '/' + pageId + '/' + encodedPath;
}

function parseNavigationPath(path) {
  var matches = path.match(/^\/([^\/]+)\/(.*)$/);
  if (matches) {
    matches[2] = matches[2].split('/').map(function(part) { return decodeURIComponent(part); }).join('/');
  }
  return matches
}

var fetchInitNoCache = {
  cache: 'no-store'
};

var unitAlias = {
  "ampere": "A",
  "degree": "°",
  "degree celsius": "°C",
  "hectopascal": "hPa",
  "hertz": "Hz",
  "kelvin": "K",
  "lux": "lx",
  "meter/sec": "m/s",
  "percent": "%",
  "volt": "V",
  "voltampere": "VA",
  "watt": "W"
};

function callVueFromPage(page, name) {
  var parent = page.$parent;
  if (parent) {
    var fn = parent[name];
    if (typeof fn === 'function') {
      var args = Array.prototype.slice.call(arguments, 2);
      return fn.apply(parent, args);
    }
  }
}

function getPageFromVue(vue) {
  if (vue && vue.$children && (vue.$children.length > 0)) {
    var page = vue.$children[0];
    if (page.id && page.title) {
      return page;
    }
  }
}

/************************************************************
 * Toaster
 ************************************************************/
var toaster = new Vue({
  el: '#toaster',
  data: {
    message: '',
    show: false
  },
  methods: {
    toast: function(message, duration) {
      console.log('toast("' + message + '", ' + duration + ')');
      if (this.show) {
        this.message += '\n' + message;
      } else {
        this.message = message;
        this.show = true;
        var self = this;
        setTimeout(function () {
          self.show = false;
        }, duration || 3000)
      }
    }
  }
});

function assertIsOk(response) {
  if (response.ok) {
    return response;
  }
  var message;
  if (response.status === 403) {
    message = 'Sorry you are not authorized';
  } else {
    message = 'Failed due to ' + response.statusText;
  }
  toaster.toast(message);
  return Promise.reject(message);
}

/************************************************************
 * Main application
 ************************************************************/
var app = new Vue({
  el: '#app',
  data: {
    theme: 'boot',
    menu: '',
    hideMenu: window.innerWidth < 360,
    dialog: '',
    dialogs: {},
    watchers: [],
    page: '',
    pages: {},
    cache: {},
    user: {}
  },
  methods: {
    setTheme: function(theme) {
      if (this.theme !== theme) {
        this.theme = theme;
        var body = document.getElementsByTagName('body')[0];
        body.setAttribute('class', 'theme_' + theme);
      }
    },
    getTheme: function() {
      return this.theme;
    },
    toPage: function(id, path) {
      window.location.assign('#' + formatNavigationPath(id, path));
    },
    replacePage: function(id, path) {
      window.location.replace('#' + formatNavigationPath(id, path));
    },
    back: function() {
      window.history.back();
    },
    openDialog: function(id) {
      this.toPage('dialog', id);
    },
    closeDialog: function() {
      this.back();
    },
    onHashchange: function(path) {
      if (this.dialog) {
        var dialog = this.dialogs[this.dialog];
        if (dialog) {
          callVueFromPage(dialog, 'onBeforeHide');
        }
        this.dialog = '';
      }
      var matches = parseNavigationPath(path);
      if (matches) {
        var id = matches[1];
        var pagePath = matches[2];
        if (id === 'dialog') {
          this.dialog = pagePath;
          return;
        }
        var previousId = this.page !== id ? this.page : '';
        if (previousId) {
          var page = this.pages[previousId];
          if (page) {
            var p = callVueFromPage(page, 'onBeforeHide');
            if (p === false) {
              return;
            } else if (p instanceof Promise) {
              p.then(function() {
                this.onHashchange(path, true);
              }.bind(this));
              return;
            }
          }
        }
        if (id in this.pages) {
          var previousId = this.page !== id ? this.page : '';
          this.menu = '';
          this.page = id;
          this.$emit('page-selected', id, pagePath, previousId);
          return;
        }
      }
      this.replacePage('home');
    },
    getPage: function(id) {
      return this.pages[id];
    },
    isActivePage: function(vue) {
      return this.page && this.pages[this.page] === getPageFromVue(vue);
    },
    callPage: function(id, name, arg) {
      var page = this.pages[id];
      if (page) {
        if (arguments.length > 3) {
          var args = Array.prototype.slice.call(arguments, 2);
          return callVueFromPage.apply(null, [page, name].concat(args));
        }
        return callVueFromPage(page, name, arg);
      }
    },
    emitPage: function(id) {
      this.callPage(id, '$emit');
      return this;
    },
    watchDataChange: function(path, fn) {
      var parts = path.split('/', 2);
      var thingId = parts[0];
      var propName = parts[1];
      var watcher = {thingId: thingId, propertyName: propName, fn: fn};
      this.watchers.push(watcher);
      return watcher;
    },
    unwatchDataChange: function(watcherOrFn) {
      var i = 0;
      while (i < this.watchers.length) {
        var watcher = this.watchers[i];
        if (watcher === watcherOrFn || watcher.fn === watcherOrFn) {
          this.watchers.splice(i, 1);
        } else {
          i++;
        }
      }
    },
    onMessage: function(message) {
      //console.log('onMessage', message);
      if (typeof message !== 'object') {
        return;
      }
      switch (message.event) {
      case 'data-change':
        var propsById = this.getFromCache('/engine/properties');
        if (propsById) {
          for (var thingId in message.data) {
            var data = message.data[thingId];
            var props = propsById[thingId];
            if (props) {
              for (var name in data) {
                props[name] = data[name];
              }
            }
          }
        }
        this.watchers.forEach(function(watcher) {
          var thingId = watcher.thingId;
          if (thingId) {
            var props = message.data[thingId];
            if (props) {
              var name = watcher.propertyName;
              if (name) {
                var value = props[name];
                if (value !== undefined) {
                  watcher.fn(value);
                }
              } else {
                watcher.fn(props);
              }
            }
          } else {
            watcher.fn(message.data);
          }
        });
        this.callPage(this.page, 'onDataChange', message.data);
        break;
      case 'logs':
        if (Array.isArray(message.logs)) {
          this.callPage(this.page, 'onLogs', message.logs);
        }
        break;
      case 'notification':
        toaster.toast(message.message);
        break;
      case 'addon-change':
        if (this.reloadTimeoutId) {
          clearTimeout(this.reloadTimeoutId);
        }
        this.reloadTimeoutId = setTimeout(function () {
          toaster.toast('Reloading...');
          setTimeout(function () {
            window.location.reload();
          }, 500);
        }, 500);
        break;
      case 'shutdown':
        if (this.reloadTimeoutId) {
          clearTimeout(this.reloadTimeoutId);
          this.reloadTimeoutId = undefined;
        }
        break;
      }
    },
    clearCache: function() {
      this.cache = {};
    },
    putInCache: function(cacheId, value) {
      if (value === undefined) {
        delete this.cache[cacheId];
      } else {
        this.cache[cacheId] = {
          time: Date.now(),
          value: value
        };
      }
    },
    getFromCache: function(cacheId) {
      var cacheEntry = this.cache[cacheId];
      return cacheEntry ? cacheEntry.value : undefined;
    },
    getWithCache: function(cacheId, getter) {
      var cacheValue = this.getFromCache(cacheId);
      if (cacheValue) {
        return Promise.resolve(cacheValue);
      }
      var self = this;
      return getter(cacheId).then(function(value) {
        self.putInCache(cacheId, value);
        return value;
      });
    },
    fetchWithCache: function(path, fn, text) {
      return this.getWithCache(path, function() {
        return fetch(path, fetchInitNoCache).then(rejectIfNotOk).then(function(response) {
          return text ? response.text() : response.json();
        }).then(function(value) {
          return fn ? fn(value) : value;
        });
      });
    },
    getUnitAliases: function() {
      return unitAlias;
    },
    getThings: function() {
      return this.fetchWithCache('/engine/things', function(things) {
        if (Array.isArray(things)) {
          things.sort(compareByTitle);
          return things;
        }
        return [];
      });
    },
    getThingsById: function() {
      var self = this;
      return this.getWithCache('/engine/things?byId', function() {
        return self.getThings().then(function(things) {
          return toMap(things, 'thingId');
        });
      });
    },
    getExtensions: function() {
      return this.fetchWithCache('/engine/extensions', function(extensions) {
        if (Array.isArray(extensions)) {
          extensions.sort(compareByName);
          return extensions;
        }
        return [];
      });
    },
    getExtensionsById: function() {
      var self = this;
      return this.getWithCache('/engine/extensions?byId', function() {
        return self.getExtensions().then(function(extension) {
          return toMap(extension, 'id');
        });
      });
    },
    getPropertiesByThingId: function() {
      return this.fetchWithCache('/engine/properties');
    },
    getEnumsById: function() {
      var self = this;
      return this.getWithCache('?enumsById', function() {
        return self.getThings().then(function(things) {
          var thingIds = things.map(function(thing) {
            return {
              const: thing.thingId,
              title: thing.title + ' - ' + thing.description
            };
          });
          var countByTitle = {};
          for (var i = 0; i < things.length; i++) {
            var thing = things[i];
            var count = countByTitle[thing.title] || 0;
            countByTitle[thing.title] = count + 1;
          }
          var propertyPaths = [];
          var allPropertyPaths = [];
          var readablePropertyPaths = [];
          var writablePropertyPaths = [];
          for (var i = 0; i < things.length; i++) {
            var thing = things[i];
            for (var name in thing.properties) {
              var property = thing.properties[name];
              var title = thing.title;
              if (countByTitle[title] > 1) {
                title += ' - ' + thing.description;
              }
              var option = {
                const: thing.thingId + '/' + name,
                title: title + ' / ' + property.title
              };
              allPropertyPaths.push(option);
              if (!property.writeOnly && !property.configuration) {
                propertyPaths.push(option);
              }
              if (!property.readOnly) {
                writablePropertyPaths.push(option);
              }
              if (!property.writeOnly) {
                readablePropertyPaths.push(option);
              }
            }
          }
          thingIds.sort(compareByTitle);
          propertyPaths.sort(compareByTitle);
          allPropertyPaths.sort(compareByTitle);
          readablePropertyPaths.sort(compareByTitle);
          writablePropertyPaths.sort(compareByTitle);
          return {
            propertyPaths: propertyPaths,
            allPropertyPaths: allPropertyPaths,
            readablePropertyPaths: readablePropertyPaths,
            writablePropertyPaths: writablePropertyPaths,
            thingIds: thingIds
          };
        });
      });
    }
  },
  computed: {
    canAdminister: function() {
      return this.user && this.user.permission >= 'rwca';
    },
    canConfigure: function() {
      return this.user && this.user.permission >= 'rwc';
    }
  }
});

/************************************************************
 * Registering components
 ************************************************************/

Vue.component('app-menu', {
  template: '#menu-template',
  data: function() {
      return {app: app};
  },
  props: {
    id: String,
    title: String,
    homePage: String
  }
});

Vue.component('app-dialog', {
  template: '#dialog-template',
  data: function() {
      return {app: app};
  },
  props: ['id', 'title'],
  created: function() {
    this.app.dialogs[this.id] = this;
  }
});

Vue.component('app-page', {
  template: '#page-template',
  data: function() {
      return {app: app};
  },
  props: {
    id: String,
    title: String,
    homePage: {
      type: String,
      default: 'home'
    },
    menu: {
      type: String,
      default: 'menu'
    },
    transitionClass: {
      type: String,
      default: 'hideRight'
    }
  },
  created: function() {
    //console.log('created() app-page, this.app', this);
    this.app.pages[this.id] = this;
    var page = this;
    app.$on('page-selected', function(id, path, previousId) {
      if (page.id === previousId) {
        callVueFromPage(page, 'onHide');
      } else if (page.id === id) {
        callVueFromPage(page, 'onShow', path);
      }
    });
  }
});

Vue.component('page-article', {
  template: '<article class="content"><section><slot>Content</slot></section></article>'
});

/************************************************************
 * Menu
 ************************************************************/
var menu = new Vue({
  el: '#menu',
  data: {
    pages: []
  },
  computed: {
    sortedPages: function() {
      var pages = [].concat(this.pages);
      pages.sort(compareByName);
      return pages;
    }
  }
});

/************************************************************
 * Confirmation
 ************************************************************/
var confirmation = new Vue({
  el: '#confirmation',
  data: {
    message: ''
  },
  methods: {
    ask: function(message) {
      this.message = message || 'Are you sure?';
      app.openDialog('confirmation');
      return new Promise(function(resolve, reject) {
        this.apply = function(confirm) {
          if (confirm) {
            resolve();
          } else {
            reject('canceled');
          }
        };
      }.bind(this));
    },
    onBeforeHide: function() {
      this.message = 'Nothing here';
      this.apply(false);
    },
    apply: function() {},
    onConfirm: function() {
      this.apply(true);
      app.closeDialog();
    }
  }
});

/************************************************************
 * Prompt dialog
 ************************************************************/
var promptDialog = new Vue({
  el: '#prompt',
  data: {
    message: 'Nothing here',
    schema: false,
    value: null
  },
  methods: {
    ask: function(schema, message) {
      if (!isObject(schema)) {
        return Promise.reject('invalid schema');
      }
      this.schema = schema;
      if (schema.type === 'object') {
        this.value = {};
      } else if (schema.type === 'array') {
        this.value = [];
      } else {
        this.value = '';
      }
      this.message = message || 'Value?';
      app.openDialog('prompt');
      var self = this;
      return new Promise(function(resolve, reject) {
        self.apply = function(confirm) {
          if (confirm) {
            resolve(self.value);
          } else {
            reject('canceled');
          }
        };
      });
    },
    onBeforeHide: function() {
      this.message = 'Nothing here';
      this.schema = false;
      this.apply(false);
    },
    apply: function() {},
    onConfirm: function() {
      this.apply(true);
      app.closeDialog();
    }
  }
});

/************************************************************
 * Main
 ************************************************************/
var homePage = new Vue({
  el: '#home',
  data: {
    tiles: [],
    title: 'Welcome'
  },
  methods: {
    onTile: function(tile) {
      if (tile) {
        if (tile.id) {
          app.toPage(tile.id);
        } else if (tile.url) {
          if (tile.open) {
            window.open(tile.url);
          } else {
            window.location.assign(tile.url);
          }
        }
      }
    },
    nextTheme: function() {
      var theme = app.getTheme();
      var themes = ['light', 'ms', 'black'];
      var index = (themes.indexOf(theme) + 1) % themes.length;
      app.setTheme(themes[index]);
    }
  },
  computed: {
    sortedTiles: function() {
      var tiles = [].concat(this.tiles);
      tiles.sort(compareByName);
      return tiles;
    }
  }
});

/************************************************************
 * Engine Information
 ************************************************************/
 new Vue({
  el: '#engineInfo',
  data: {
    infos: {}
  },
  methods: {
    onShow: function() {
      var page = this;
      fetch('/engine/admin/info', fetchInitNoCache).then(assertIsOk).then(getJson).then(function(data) {
        console.log('fetch(admin/info)', data);
        var clientTime = Math.round(Date.now() / 1000);
        var serverTime = data['Server Time'];
        data['Delta Time'] = clientTime - serverTime;
        page.infos = data;
        toaster.toast('Refreshed');
      });
    }
  }
});

/************************************************************
 * Engine Configuration
 ************************************************************/
 new Vue({
  el: '#engineSettings',
  data: {
    filename: '',
    schema: {},
    config: {},
    working: false
  },
  methods: {
    onShow: function() {
      Promise.all([
        fetch('/engine/schema', fetchInitNoCache).then(getJson),
        fetch('/engine/configuration/engine', fetchInitNoCache).then(getJson)
      ]).then(apply(this, function(schemaData, configData) {
        this.schema = schemaData;
        this.config = configData.value;
      })).catch(function() {
        this.schema = false;
        this.config = {};
      }.bind(this));
    },
    backup: function() {
      var self = this;
      self.working = true;
      toaster.toast('Backup in progress...');
      fetch('/engine/admin/backup/create', {method: 'POST'}).then(assertIsOk).then(getResponseText).then(function(filename) {
        self.filename = filename;
        toaster.toast('Backup created');
      }).finally(function() {
        self.working = false;
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
      self.working = true;
      var file = input.files[0];
      fetch('/engine/tmp/' + file.name, {
        method: 'PUT',
        headers: {
          "Content-Type": "application/octet-stream"
        },
        body: file
      }).then(assertIsOk).then(function() {
        toaster.toast('Backup uploaded');
        return fetch('/engine/admin/backup/deploy', {
          method: 'POST',
          body: file.name
        });
      }).then(assertIsOk).then(function() {
        toaster.toast('Backup deployed');
        window.location.reload();
      }).finally(function() {
        self.working = false;
      });
    },
    onSave: function() {
      postJson('/engine/configuration/engine', { value: this.config }).then(assertIsOk).then(function() {
        toaster.toast('Engine configuration saved');
        app.clearCache();
      });
    },
    stopServer: function() {
      confirmation.ask('Stop the server?').then(function() {
        fetch('/engine/admin/stop', { method: 'POST'}).then(assertIsOk).then(function() {
          app.toPage('home');
          toaster.toast('Server stopped');
        });
      });
    }
  }
});

/************************************************************
 * Load simple pages
 ************************************************************/
new Vue({
  el: '#pages'
});

function registerPageVue(vue, icon, showTile, showMenu) {
  var page = getPageFromVue(vue);
  if (page) {
    if (showTile) {
      homePage.tiles.push({
        id: page.id,
        name: page.title,
        icon: icon
      });
    }
    if (showMenu) {
      menu.pages.push({
        id: page.id,
        name: page.title
      });
    }
  }
}

function addPageComponent(vue, icon, showTile, showMenu) {
  var component = vue.$mount();
  document.getElementById('pages').appendChild(component.$el);
  if (icon !== undefined) {
    registerPageVue(vue, icon, showTile, showMenu);
  }
}
