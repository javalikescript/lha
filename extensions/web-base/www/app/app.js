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
        return;
      }
      var matches = path.match(/^\/([^\/]+)\/(.*)$/);
      if (matches) {
        if (!noHistory) {
          this.pageHistory.push(this.path);
        }
        this.path = path;
        var id = matches[1];
        var pagePath = matches[2];
        //if (this.page === id) {}
        this.selectPage(id, pagePath);
        return true;
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
    selectPage: function(id, path) {
      this.menu = '';
      this.page = id;
      this.$emit('page-selected', id, path);
    },
    showBack: function() {
      var l = this.pageHistory.length
      return l > 0 && this.pageHistory[l - 1] !== 'main';
    },
    back: function() {
      var path = this.pageHistory.pop();
      if (path) {
        this.navigateTo(path, true);
      } else {
        this.toPage('main');
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
        return fetch(path).then(function(response) {
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
  data: function() {
      return {app: app};
  },
  props: {
    id: String,
    title: String,
    homePage: String
  },
  template: '#menu-template'
  /*'<section v-bind:id="id" class="menu" v-bind:class="{ hideLeft: app.menu !== id }"><header>' +
    '<button v-on:click="app.menu = \'\'"><i class="fa fa-window-close"></i></button>' +
    '<h1>{{ title }}</h1><div /></header><slot>Article</slot></section>'*/
});

Vue.component('app-dialog', {
  data: function() {
      return {app: app};
  },
  props: ['id', 'title'],
  template: '#dialog-template'
  /*'<section v-bind:id="id" class="page dialog" v-bind:class="{ hide: app.dialog !== id }">' +
    '<header><div /><h1>{{ title }}</h1><div><slot name="bar-right">' +
    '<button v-on:click="app.dialog = \'\'"><i class="fa fa-window-close"></i></button>' +
    '</slot></div></header><slot>Article</slot></section>'*/
});

Vue.component('app-page', {
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
  template: '#page-template',
  /*'<section v-bind:id="id" v-bind:class="[{page: true}, app.page === id ? \'\' : hideClass]">' +
    '<header><div><button v-on:click="app.menu = \'menu\'" v-if="showMenu"><i class="fa fa-bars"></i></button>' +
    '<button v-on:click="app.back()" v-if="!hideNav"><i class="fa fa-chevron-left"></i></button>' +
    '<button v-on:click="app.toPage(\'main\')" v-if="!hideNav"><i class="fas fa-home"></i></button></div>' +
    '<h1>{{ title }}</h1><div><slot name="bar-right"></slot></div>' +
    '</header><slot>Article</slot></section>'*/
  created: function() {
    //console.log('created() app-page, this.app', this);
    this.app.pages[this.id] = this;
    var page = this;
    app.$on('page-selected', function(id, path) {
      if ((page.id === id) && (page.$parent) && (typeof page.$parent.onShow === 'function')) {
        //console.log('page-article, on page-selected', article);
        page.$parent.onShow(path);
      }
    })
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
    pages: [{
      id: 'things',
      name: 'Things'
    }, {
      id: 'extensions',
      name: 'Extensions'
    }]
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
var main = new Vue({
  el: '#main',
  data: {
    pages: []
  }
});

/************************************************************
 * Engine Information
 ************************************************************/
 new Vue({
  el: '#engineInfo',
  data: {
    clock: '...',
    memory: '...',
    time: '...'
  },
  methods: {
    onShow: function() {
      var page = this;
      fetch('/engine/admin/info').then(function(response) {
        return response.json();
      }).then(function(data) {
        //console.log('fetch(admin/info)', data);
        page.clock = data.clock;
        page.memory = data.memory;
        var clientTime = Math.round(Date.now() / 1000);
        var delta = clientTime - data.time;
        page.time = '' + data.time + ' (' + delta + ')';
        toaster.toast('Refreshed');
      });
    }
  }
});

/************************************************************
 * Engine Configuration
 ************************************************************/
 new Vue({
  el: '#engineConfig',
  data: {
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
    }
  }
});

/************************************************************
 * Load simple pages
 ************************************************************/
new Vue({
  el: '#pages'
});

function addPageComponent(vue) {
  var component = vue.$mount();
  document.getElementById('pages').appendChild(component.$el);
}
