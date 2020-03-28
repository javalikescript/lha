/************************************************************
 * Main application
 ************************************************************/
var app = new Vue({
  el: '#app',
  data: {
    menu: '',
    settings: '',
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
      this.settings = '';
      this.page = id;
      this.$emit('page-selected', id, path);
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
    getThings: function() {
      var cacheValue = this.getFromCache('/engine/things');
      if (cacheValue) {
        return Promise.resolve(cacheValue);
      }
      var self = this;
      return fetch('/engine/things').then(function(response) {
        return response.json();
      }).then(function(things) {
        if (Array.isArray(things)) {
          things.sort(compareByTitle);
        }
        self.putInCache('/engine/things', things);
        return things;
      });
    },
    getExtensions: function() {
      var cacheValue = this.getFromCache('/engine/extensions');
      if (cacheValue) {
        return Promise.resolve(cacheValue);
      }
      var self = this;
      return fetch('/engine/extensions').then(function(response) {
        return response.json();
      }).then(function(extensions) {
        if (Array.isArray(extensions)) {
          extensions.sort(compareByName);
        }
        self.putInCache('/engine/extensions', extensions);
        return extensions;
      });
    },
    getExtensionsById: function() {
      var cacheValue = this.getFromCache('/engine/extensions?byId');
      if (cacheValue) {
        return Promise.resolve(cacheValue);
      }
      return this.getExtensions().then(function(extensions) {
        var extensionsById = {};
        if (Array.isArray(extensions)) {
          for (var i = 0; i < extensions.length; i++) {
            var extension = extensions[i];
            extensionsById[extension.id] = extension;
          }
        }
        self.putInCache('/engine/extensions?byId', extensionsById);
        return extensionsById;
      });
    }
  }
});
/************************************************************
 * Registering components
 ************************************************************/
// TODO Find a way to remove app
Vue.component('app-root-page', {
  data: function() {
      return {app: app};
  },
  props: ['id', 'title'],
  template: '<section v-bind:id="id" class="page" v-bind:class="{ hideLeft: app.page !== id, hideBottom: app.settings !== \'\' }"><header>' +
    '<button v-on:click="app.menu = \'menu\'"><i class="fa fa-bars"></i></button>' +
    '<h1>{{ title }}</h1>' +
    '<button v-on:click="app.settings = \'settings\'"><i class="fa fa-cog"></i></button>' +
    '</header><slot>Article</slot></section>'
});
Vue.component('app-menu', {
  data: function() {
      return {app: app};
  },
  props: ['id', 'title'],
  template: '<section v-bind:id="id" class="menu" v-bind:class="{ hideLeft: app.menu !== id }"><header>' +
    '<button v-on:click="app.menu = \'\'"><i class="fa fa-window-close"></i></button>' +
    '<h1>{{ title }}</h1><div /></header><slot>Article</slot></section>'
});
Vue.component('app-settings', {
  data: function() {
      return {app: app};
  },
  props: ['id', 'title'],
  template: '<section v-bind:id="id" class="page" v-bind:class="{ hideTop: app.settings !== id }">' +
    '<header><div /><h1>{{ title }}</h1>' +
    '<button v-on:click="app.settings = \'\'"><i class="fa fa-window-close"></i></button>' +
    '</header><slot>Article</slot></section>'
});
Vue.component('app-page', {
  data: function() {
      return {app: app};
  },
  props: ['id', 'title'],
  template: '<section v-bind:id="id" class="page" v-bind:class="{ hideRight: app.page !== id }">' +
    '<header><div><button v-on:click="app.menu = \'menu\'"><i class="fa fa-bars"></i></button>' +
    '<button v-on:click="app.back()"><i class="fa fa-chevron-left"></i></button>' +
    '<button v-on:click="app.toPage(\'main\')"><i class="fas fa-home"></i></button></div>' +
    '<h1>{{ title }}</h1><div><slot name="bar-right"></slot></div>' +
    '</header><slot>Article</slot></section>',
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
/*
Vue.component('switch', {
  template: '<label class="switch"><slot><input type="checkbox" /></slot><span class="slider"></span></label>'
});
*/
Vue.component('json-item', {
  props: ['name', 'obj', 'pobj', 'schema', 'root'],
  data: function() {
    return {
      open: true
    };
  },
  template: '<li class="json"><div @click="toggle">' +
    '<span>{{ label }}:</span><br>' +
    '<input v-if="hasStringValue && !hasEnumValues" v-model="value" type="text" placeholder="String Value">' +
    '<select v-if="hasStringValue && hasEnumValues" v-model="value"><option v-for="ev in enumValues" :value="ev.const">{{ev.title}}</option></select>' +
    '<input v-if="hasNumberValue" v-model="value" type="number" placeholder="Number Value">' +
    '<label v-if="hasBooleanValue" class="switch"><input type="checkbox" v-model="value" /><span class="slider"></span></label>' +
    '</div>' +
    '<ul class="json-properties" v-show="open" v-if="hasProperties"><li is="json-item" v-for="n in propertyNames" :key="n" :name="n" :pobj="obj" :obj="getProperty(n)" :schema="schema.properties[n]" :root="root"></li></ul>' +
    '<ul class="json-items" v-show="open" v-if="isList">' +
    '<li is="json-item" v-for="(so, i) in obj" :key="i" :name="\'#\' + i" :pobj="obj" :obj="so" :schema="schema.items" :root="root"></li>' +
    '<li><button v-on:click="addItem" title="Add Item"><i class="fa fa-plus"></i></button></li>' +
    '</ul>' +
    '</li>',
  computed: {
    label: function() {
      return this.schema && this.schema.title || this.name || 'Value';
    },
    hasStringValue: function() {
      return this.schema && (this.schema.type === 'string');
    },
    hasEnumValues: function() {
      return this.schema && (Array.isArray(this.schema.enum) || Array.isArray(this.schema.enumValues));
    },
    hasNumberValue: function() {
      return this.schema && ((this.schema.type === 'number') || (this.schema.type === 'integer'));
    },
    hasBooleanValue: function() {
      return this.schema && (this.schema.type === 'boolean');
    },
    propertyNames: function() {
      var names = [];
      for (var name in this.schema.properties) {
        names.push(name);
      }
      names.sort(strcasecmp);
      return names;
    },
    enumValues: function() {
      if (Array.isArray(this.schema.enumValues)) {
        return this.schema.enumValues;
      } else if (Array.isArray(this.schema.enum)) {
        return this.schema.enum.map(function(key) {
          return {
            "const": key,
            "title": key
          };
        });
      }
      return [];
    },
    value: {
      get () {
        return this.obj;
      },
      set (val) {
        //console.log('value()', val, this.$vnode.key);
        this.pobj[this.$vnode.key] = parseJsonItemValue(this.schema.type, val);
      }
    },
    isList: function() {
      return this.schema && (this.schema.type === 'array') && (typeof this.schema.items === 'object') && Array.isArray(this.obj);
    },
    hasProperties: function() {
      if (this.schema && (this.schema.type === 'object') && (typeof this.schema.properties === 'object')) {
        for (var name in this.schema.properties) {
          var ss = this.schema.properties[name];
          if (!(name in this.obj)) {
            this.obj[name] = newJsonItem(ss.type);
          }
        }
        return true;
      }
      return false;
    }
  },
  methods: {
    getProperty: function(name) { 
      if (!(name in this.obj)) {
        if (name in this.schema.properties) {
          this.obj[name] = newJsonItem(this.schema.properties[name].type);
        } else {
          this.obj[name] = '';
        }
      }
      return this.obj[name];
    },
    addItem: function() {
      if (this.schema && (this.schema.type === 'array') && (typeof this.schema.items === 'object') && Array.isArray(this.obj)) {
        console.log('addItem()', this.obj, this.schema);
        var item = newJsonItem(this.schema.items.type);
        this.obj.push(item);
        this.$forceUpdate();
      } else {
        console.error('Cannot add item', this.obj, this.schema);
      }
    },
    toggle: function() {
      if (this.schema && ((this.schema.type === 'array') || (this.schema.type === 'object'))) {
        this.open = !this.open
      }
    }
  }
});
Vue.component('json', {
  props: ['name', 'obj', 'schema'],
  template: '<ul class="json-root"><json-item :name="name" :obj="obj" :schema="schema" :root="this"></json-item></ul>'
});

/************************************************************
 * Menu
 ************************************************************/
var menu = new Vue({
  el: '#menu',
  data: {
    pages: [{
      id: 'data-chart',
      name: 'Chart' // time series
    }, {
      id: 'things',
      name: 'Things'
    }, {
      id: 'extensions',
      name: 'Extensions'
    }]
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
      this.message = message || 'Are you sure?';
      app.settings = 'confirmation';
      var self = this;
      return new Promise(function(resolve, reject) {
        self._reply = function(confirm) {
          app.settings = '';
          if (confirm) {
            resolve();
          } else {
            reject();
          }
        };
      });
    },
    onConfirm: function() {
      this._reply(true);
    },
    onCancel: function() {
      this._reply();
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
 * Settings
 ************************************************************/
var settings = new Vue({
  el: '#settings',
  data: {
    clock: '...',
    memory: '...',
    time: '...'
  },
  methods: {
    refreshInfo: function() {
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
    },
    clearCache: function() {
      app.clearCache();
    },
    gc: function() {
      var page = this;
      fetch('/engine/admin/gc', {method: 'POST'}).then(function(response) {
        page.refreshInfo();
      });
    },
    pollThings: function() {
      fetch('/engine/poll', {method: 'POST'}).then(function() {
        toaster.toast('Polling triggered');
      });
    }
  }
});

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
        app.clearCache();
      });
    }
  }
});

new Vue({
  el: '#moreSettings',
  methods: {
    saveConfig: function() {
      fetch('/engine/admin/configuration/save', {method: 'POST'}).then(function() {
        app.clearCache();
      });
    },
    reloadExtensions: function() {
      fetch('/engine/admin/reloadExtensions/all', {method: 'POST'}).then(function() {
        app.clearCache();
      });
    },
    reloadScripts: function() {
      fetch('/engine/admin/reloadScripts/all', {method: 'POST'}).then(function() {
        app.clearCache();
      });
    },
    restartServer: function() {
      confirmation.ask('Restart the server?').then(function() {
        fetch('/engine/admin/restart', { method: 'POST'});
      });
    },
    stopServer: function() {
      fetch('/engine/admin/stop', { method: 'POST'}).then(function() {
        app.toPage('main');
        toaster.toast('Server stopped');
      });
    },
    selectFile: function(event) {
      //this.$els.uploadInput.click();
      this.$refs.uploadInput.click();
    },
    uploadFile: function(event) {
      //console.log('uploadFile', this, arguments);
      var input = event.target;
      if (input.files.length !== 1) {
        return;
      }
      var file = input.files[0];
      console.log('uploadFile', file);
      /*
      var reader = new FileReader();
      reader.onload = function() {
        console.log('reader.result ' + reader.result.length);
      };
      reader.readAsText(file);
      //reader.readAsArrayBuffer(file);
      //reader.readAsBinaryString(file);
      */
      fetch('/engine/tmp/' + file.name, {
        method: 'PUT',
        headers: {
          "Content-Type": "application/octet-stream"
        },
        body: file
      }).then(function() {
        fetch('/engine/admin/deploy/' + file.name, { method: 'POST'});
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
  console.log('countDownStart() ' + startCountDown);
  if (startCountDown === 0) {
    onHashChange();
    if (webBaseConfig.theme) {
      settings.theme = webBaseConfig.theme;
    }
    setTheme(settings.theme);
  }
};

startCountDown++;
fetch('/engine/configuration/extensions/web_base').then(function(response) {
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
  console.log('loading addons', addons);
  if (Array.isArray(addons)) {
    addons.forEach(function(addon) {
      /*fetch('addon/' + addon + '/').then(function(response) {
        return response.json();
      }).then(function(response) {
        console.log('addon ' + addon, response);
      });*/
      console.log('loading addon ' + addon);
      startCountDown++;
      require(['addon/' + addon + '/main.js'], countDownStart);
    });
  }
  countDownStart();
});

countDownStart();