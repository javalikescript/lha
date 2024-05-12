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

/************************************************************
 * Main application
 ************************************************************/
var app = new Vue({
  el: '#app',
  data: {
    menu: '',
    hideMenu: window.innerWidth <= 320,
    dialog: '',
    page: '',
    path: '',
    pages: {},
    pageHistory: [],
    cache: {},
    user: {}
  },
  methods: {
    toPage: function(id, path) {
      this.navigateTo(formatNavigationPath(id, path));
    },
    replacePage: function(id, path) {
      this.navigateTo(formatNavigationPath(id, path), true);
    },
    navigateTo: function(path, noHistory) {
      if (this.path === path) {
        return true;
      }
      var matches = parseNavigationPath(path);
      if (matches) {
        var id = matches[1];
        var pagePath = matches[2];
        if (id in this.pages) {
          if (!noHistory) {
            this.pageHistory.push(this.path);
          }
          this.path = path;
          this.menu = '';
          var previousId = this.page !== id ? this.page : '';
          this.page = id;
          this.$emit('page-selected', id, pagePath, previousId);
          return true;
        }
      }
      return false;
    },
    getPage: function(id) {
      return this.pages[id];
    },
    emitPage: function(id) {
      var page = this.pages[id];
      var emitArgs = Array.prototype.slice.call(arguments, 1);
      if (page.$parent) {
        page = page.$parent;
      }
      page.$emit.apply(page, emitArgs);
      return this;
    },
    callPage: function(id, name) {
      var page = this.pages[id];
      var callArgs = Array.prototype.slice.call(arguments, 2);
      if (page.$parent) {
        page = page.$parent;
      }
      var fn = page[name];
      if (typeof fn === 'function') {
        fn.apply(page, callArgs);
      }
      return this;
    },
    showBack: function() {
      var l = this.pageHistory.length
      return l > 0;
    },
    back: function() {
      var path = this.pageHistory.pop();
      if (path) {
        this.navigateTo(path, true);
      } else {
        this.toPage('home');
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
          this.callPage(this.page, 'onDataChange');
        }
        break;
      case 'logs':
        if (Array.isArray(message.logs)) {
          this.callPage(this.page, 'onLogs', message.logs);
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
  props: ['id', 'title']
});

Vue.component('app-page', {
  template: '#page-template',
  data: function() {
      return {app: app};
  },
  props: {
    id: String,
    title: String,
    hideBack: Boolean,
    homePage: String,
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
      if ((page.id === previousId) && (page.$parent) && (typeof page.$parent.onHide === 'function')) {
        page.$parent.onHide();
      }
      if ((page.id === id) && (page.$parent) && (typeof page.$parent.onShow === 'function')) {
        page.$parent.onShow(path);
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
 * Confirmation
 ************************************************************/
var confirmation = new Vue({
  el: '#confirmation',
  data: {
    message: ''
  },
  methods: {
    ask: function(message) {
      //console.log('confirmation.ask("' + message + '")');
      this.message = message || 'Are you sure?';
      app.dialog = 'confirmation';
      var self = this;
      return new Promise(function(resolve, reject) {
        self._close = function(confirm) {
          if (confirm) {
            resolve();
          } else {
            reject('user did not confirm');
          }
          app.dialog = '';
        };
      });
    },
    onConfirm: function() {
      this._close(true);
    },
    onCancel: function() {
      this._close(false);
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
          window.open(tile.url, '_blank');
        }
      }
    }
  },
  computed: {
    sortedTiles: function() {
      var tiles = [].concat(this.tiles);
      if ((typeof webBaseConfig === 'object') && Array.isArray(webBaseConfig.links)) {
        tiles = tiles.concat(webBaseConfig.links);
      }
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
      })).catch(call(this, function() {
        this.schema = false;
        this.config = {};
      }));
    },
    backup: function() {
      var self = this;
      self.working = true;
      toaster.toast('Backup in progress...');
      fetch('/engine/admin/backup/create', {method: 'POST'}).then(assertIsOk).then(function(response) {
        return response.text();
      }).then(function(filename) {
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
      fetch('/engine/configuration/engine', {
        method: 'POST',
        body: JSON.stringify({
          value: this.config
        })
      }).then(assertIsOk).then(function() {
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

function registerPageVue(vue, icon) {
  if (vue && vue.$children && (vue.$children.length > 0)) {
    var page = vue.$children[0];
    if (page.id && page.title) {
      menu.pages.push({
        id: page.id,
        name: page.title
      });
      homePage.tiles.push({
        id: page.id,
        name: page.title,
        icon: icon
      });
    }
  }
}

function addPageComponent(vue, menuIcon) {
  var component = vue.$mount();
  document.getElementById('pages').appendChild(component.$el);
  if (menuIcon) {
    registerPageVue(vue, typeof menuIcon === 'string' ? menuIcon : undefined);
  }
}
