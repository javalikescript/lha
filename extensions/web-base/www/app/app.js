
function setTheme(name) {
  var body = document.getElementsByTagName('body')[0];
  body.setAttribute('class', 'theme_' + name);
}

function formatNavigationPath(pageId, path) {
  return '/' + pageId + '/' + (path ? encodeURIComponent(path) : '');
}

function parseNavigationPath(path) {
  var matches = path.match(/^\/([^\/]+)\/(.*)$/);
  if (matches) {
    matches[2] = decodeURIComponent(matches[2]);
  }
  return matches
}

/************************************************************
 * Main application
 ************************************************************/
var app = new Vue({
  el: '#app',
  data: {
    menu: '',
    dialog: '',
    page: '',
    path: '',
    pages: {},
    pageHistory: [],
    cache: {}
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
      if (message && (message.event === 'data-change')) {
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
        return fetch(path).then(rejectIfNotOk).then(function(response) {
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
        }
        return things;
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
        }
        return extensions;
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
    pages: [],
    title: 'Welcome'
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
      fetch('/engine/admin/info').then(function(response) {
        return response.json();
      }).then(function(data) {
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
    config: {}
  },
  methods: {
    onShow: function() {
      var page = this;
      fetch('/engine/schema').then(function(response) {
        return response.json();
      }).then(function(schemaData) {
        fetch('/engine/configuration/engine').then(function(response) {
          return response.json();
        }).then(function(configData) {
          page.schema = schemaData;
          page.config = configData.value;
        });
      });
    },
    backup: function() {
      var self = this;
      fetch('/engine/admin/backup/create', {method: 'POST'}).then(function(response) {
        return response.text();
      }).then(function(filename) {
        self.filename = filename;
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
      var file = input.files[0];
      fetch('/engine/tmp/' + file.name, {
        method: 'PUT',
        headers: {
          "Content-Type": "application/octet-stream"
        },
        body: file
      }).then(function() {
        return fetch('/engine/admin/backup/deploy', {
          method: 'POST',
          body: file.name
        });
      });
    },
    onSave: function() {
      fetch('/engine/configuration/engine', {
        method: 'POST',
        body: JSON.stringify({
          value: this.config
        })
      }).then(function() {
        toaster.toast('Engine configuration saved');
        app.clearCache();
      });
    },
    stopServer: function() {
      confirmation.ask('Stop the server?').then(function() {
        fetch('/engine/admin/stop', { method: 'POST'}).then(function() {
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
      homePage.pages.push({
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
