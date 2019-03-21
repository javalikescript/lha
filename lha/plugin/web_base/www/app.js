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

/************************************************************
 * Main application
 ************************************************************/
var setTheme = function(name) {
  var body = document.getElementsByTagName('body')[0];
  body.setAttribute('class', 'theme_' + name);
};

var app = new Vue({
  el: '#app',
  data: {
    menu: '',
    settings: '',
    page: '',
    pages: {},
    pageHistory: []
  },
  methods: {
    toPage: function(id) {
      if (this.page === id) {
          return;
      }
      this.pageHistory.push(id);
      this.selectPage(id);
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
    selectPage: function(id) {
      this.menu = '';
      this.settings = '';
      this.page = id;
      this.$emit('page-selected', id);
    },
    back: function() {
      this.pageHistory.pop();
      if (this.pageHistory.length > 0) {
        this.selectPage(this.pageHistory[this.pageHistory.length - 1]);
      } else {
        this.toPage('main');
      }
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
  template: '<section v-bind:id="id" class="page" v-bind:class="{ hideLeft: app.page !== id, hideBottom: app.settings !== \'\' }">' +
    '<header><button v-on:click="app.menu = \'menu\'"><i class="fa fa-bars"></i></button>' +
    '<span class="toolbar"><button v-on:click="app.settings = \'settings\'"><i class="fa fa-cog"></i></button></span>' +
    '<h1>{{ title }}</h1></header>' +
    '<slot>Article</slot></section>'
});
Vue.component('app-menu', {
  data: function() {
      return {app: app};
  },
  props: ['id', 'title'],
  template: '<section v-bind:id="id" class="menu" v-bind:class="{ hideLeft: app.menu !== id }">' +
    '<header><button v-on:click="app.menu = \'\'"><i class="fa fa-window-close"></i></button><h1>{{ title }}</h1></header>' +
    '<slot>Article</slot></section>'
});
Vue.component('app-settings', {
  data: function() {
      return {app: app};
  },
  props: ['id', 'title'],
  template: '<section v-bind:id="id" class="page" v-bind:class="{ hideTop: app.settings !== id }">' +
    '<header><span class="toolbar"><button v-on:click="app.settings = \'\'"><i class="fa fa-window-close"></i></button></span>' +
    '<h1>{{ title }}</h1></header>' +
    '<slot>Article</slot></section>'
});
Vue.component('app-page', {
  data: function() {
      return {app: app};
  },
  props: ['id', 'title'],
  template: '<section v-bind:id="id" class="page" v-bind:class="{ hideRight: app.page !== id }">' +
    '<header>' +
    '<button v-on:click="app.menu = \'menu\'"><i class="fa fa-bars"></i></button>' +
    '<button v-on:click="app.back()"><i class="fa fa-chevron-left"></i></button>' +
    '<button v-on:click="app.toPage(\'main\')"><i class="fas fa-home"></i></button>' +
    '<h1>{{ title }}</h1></header>' +
    '<slot>Article</slot></section>',
  created: function() {
    //console.log('created() app-page, this.app', this);
    this.app.pages[this.id] = this;
    var page = this;
    app.$on('page-selected', function(id) {
      if ((page.id === id) && (page.$parent) && (typeof page.$parent.onShow === 'function')) {
        //console.log('page-article, on page-selected', article);
        page.$parent.onShow();
      }
    })
  }
});
Vue.component('tree-item', {
  props: ['model', 'tree'],
  data: function() {
    return {
      open: true
    };
  },
  //{{ model.value }}
  template: '<li class="tree"><div @click="toggle"><i :class="iconClass"></i>' +
    '{{ model.name }}<span v-if="showValue" v-bind:contenteditable="tree.editable" class="tree-value" @blur="updateValue" v-text="model.value"></span></div>' +
    '<ul v-show="open" v-if="isFolder"><tree-item v-for="(model, index) in model.children" :key="index" :model="model" :tree="tree"></tree-item></ul></li>',
  computed: {
    isFolder: function() {
      return this.model.children && this.model.children.length;
    },
    iconClass: function() {
      var c = 'tree-icon '
      if (this.model.children && this.model.children.length) {
        c += this.open ? 'fa fa-caret-down' : 'fa fa-caret-right';
      } else {
        // thermometer-half
        c += (typeof this.model.value === 'number') ? 'fas fa-chart-line' : 'far fa-square'
      }
      return c;
    },
    showValue: function() {
      return (this.model.value !== undefined) && this.tree.showValue;
    }
  },
  methods: {
    updateValue: function(evt) {
      var newValue;
      switch(typeof this.model.value) {
      case 'boolean':
        newValue = evt.target.innerText.trim().toLowerCase();
        if ((newValue !== 'true') && (newValue !== 'false')) {
          return;
        }
        newValue = newValue === 'true';
        break;
      case 'number':
        newValue = parseFloat(evt.target.innerText);
        if (isNaN(newValue)) {
          return;
        }
        break;
      case 'string':
      default:
        newValue = evt.target.innerText;
        break;
      }
      this.model.value = newValue;
    },
    toggle: function() {
      if (this.isFolder) {
        this.open = !this.open
      } else {
        //console.log('path: ' + this.model.path);
        this.tree.$emit('tree-path-selected', this.model.path, this.model.value);
      }
    }
  }
});
Vue.component('tree', {
  props: ['model', 'showValue', 'editable'],
  template: '<tree-item :model="model" :tree="this"></tree-item>'
});
Vue.component('page-article', {
  template: '<article class="content"><slot>Content</slot></article>'
});

/************************************************************
 * Application component pages
 ************************************************************/
var menu = new Vue({
  el: '#menu',
  data: {
    pages: [{
      id: 'historicalData',
      name: 'Historical Data'
    }, {
      id: 'liveData',
      name: 'Data'
    }, {
      id: 'plugins',
      name: 'Plugins'
    }, {
      id: 'devices',
      name: 'Devices'
    }, {
      id: 'config',
      name: 'Configuration'
    }]
  }
});

var toaster = new Vue({
  el: '#toaster',
  data: {
    message: '',
    show: false
  },
  methods: {
    toast: function(message, duration) {
      console.log('toast("' + message + '", ' + duration + ')');
      this.message = message;
      this.show = true;
      var self = this;
      setTimeout(function () {
        self.show = false;
      }, duration || 3000)
    }
  }
});

var main = new Vue({
  el: '#main',
  data: {
    pages: []
  }
});

var settings = new Vue({
  el: '#settings',
  data: {
    clock: '...',
    memory: '...',
    time: '...',
    theme: 'ms'
  },
  methods: {
    onShow: function() {
      var page = this;
      //console.log('onShow() server', this);
      fetch('/engine/admin/info').then(function(response) {
        return response.json();
      }).then(function(data) {
        //console.log('fetch(admin/info)', data);
        page.clock = data.clock;
        page.memory = data.memory;
        var clientTime = Math.round(Date.now() / 1000);
        var delta = clientTime - data.time;
        page.time = '' + data.time + ' (' + delta + ')';
        toaster.toast('Refreshed')
      });
    },
    gc: function() {
      var page = this;
      fetch('/engine/admin/gc', {method: 'POST'}).then(function(response) {
        page.onShow();
      });
    },
    changeTheme: function() {
      //console.log('changeTheme() ' + this.theme);
      setTheme(this.theme);
      fetch('/engine/configuration/plugin/web_base/theme', {
        method: 'POST',
        body: JSON.stringify({
          value: this.theme
        })
      });
      toaster.toast('Theme is now ' + this.theme);
    },
    pollDevices: function() {
      fetch('/engine/admin/pollDevices', {method: 'POST'}).then(function() {
        toaster.toast('Polling triggered');
      });
    }
  }
});

new Vue({
  el: '#moreSettings',
  methods: {
    saveConfig: function() {
      fetch('/engine/admin/configuration/save', {method: 'POST'});
    },
    reloadPlugins: function() {
      fetch('/engine/admin/reloadPlugins', {method: 'POST'});
    },
    reloadScripts: function() {
      fetch('/engine/admin/reloadScripts', {method: 'POST'});
    },
    restartServer: function() {
      fetch('/engine/admin/restart', { method: 'POST'});
    },
    stopServer: function() {
      fetch('/engine/admin/stop', { method: 'POST'});
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

var jsonToTree = function(name, obj, path) {
  var treeItem = {
    name: name,
    path: path
  };
  if (Array.isArray(obj)) {
    treeItem.children = [];
    for (var i = 0; i < obj.length; i++) {
      treeItem.children.push(jsonToTree('#' + i, obj[i], path + '/' + i));
    }
  } else if ((typeof obj === 'object') && (obj !== null)) {
    treeItem.children = [];
    var keys = Object.keys(obj).sort();
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i];
      treeItem.children.push(jsonToTree(key, obj[key], path + '/' + key));
    }
  } else {
    treeItem.value = obj;
  }
  return treeItem;
};

var treeToJson = function(treeItem) {
  if (Array.isArray(treeItem.children)) {
    var obj = {};
    for (var i = 0; i < treeItem.children.length; i++) {
      var child = treeItem.children[i];
      obj[child.name] = treeToJson(child);
    }
    return obj
  }
  return treeItem.value;
};

new Vue({
  el: '#config',
  data: {
    root: {}
  },
  methods: {
    onShow: function() {
      var self = this;
      fetch('/engine/configuration/').then(function(response) {
        return response.json();
      }).then(function(response) {
        self.root = jsonToTree('configuration', response.value, '');
      });
    },
    onSave: function() {
      var obj = treeToJson(this.root);
      console.log('saving:', obj);
      fetch('/engine/configuration/', {
        method: 'POST',
        body: JSON.stringify({
          value: obj
        })
      });
    },
    onTreePathSelected: function(path) {
      console.log('selected path: ' + path);
    }
  }
});

new Vue({
  el: '#itemConfig',
  data: {
    path: '',
    root: {}
  },
  methods: {
    onShow: function() {
      var self = this;
      fetch('/engine/configuration/' + this.path).then(function(response) {
        return response.json();
      }).then(function(response) {
        self.root = jsonToTree(self.path, response.value, '');
      });
    },
    setPath: function(path) {
      //console.log('itemConfig path: ' + path);
      this.path = path || '';
    },
    onSave: function() {
      var obj = treeToJson(this.root);
      console.log('saving:', obj);
      fetch('/engine/configuration/' + this.path, {
        method: 'POST',
        body: JSON.stringify({
          value: obj
        })
      });
    }
  }
});

new Vue({
  el: '#liveData',
  data: {
    root: {}
  },
  methods: {
    onShow: function() {
      var self = this;
      fetch('/engine/data/').then(function(response) {
        return response.json();
      }).then(function(response) {
        self.root = jsonToTree('data', response.value, '');
      });
    },
    onSave: function() {
      var obj = treeToJson(this.root);
      console.log('saving:', obj);
      fetch('/engine/data/', {
        method: 'POST',
        body: JSON.stringify({
          value: obj
        })
      });
    }
  }
});

new Vue({
  el: '#itemData',
  data: {
    path: '',
    root: {}
  },
  methods: {
    onShow: function() {
      var self = this;
      fetch('/engine/data/' + this.path).then(function(response) {
        return response.json();
      }).then(function(response) {
        self.root = jsonToTree('data', response.value, '');
      });
    },
    setPath: function(path) {
      //console.log('itemConfig path: ' + path);
      this.path = path || '';
    },
    onSave: function() {
      var obj = treeToJson(this.root);
      console.log('saving:', obj);
      fetch('/engine/data/' + this.path, {
        method: 'POST',
        body: JSON.stringify({
          value: obj
        })
      });
    }
  }
});

var hsvToRgb = function(h, s, v) {
  var r, g, b;
  var i = Math.floor(h * 6);
  var f = h * 6 - i;
  var p = v * (1 - s);
  var q = v * (1 - f * s);
  var t = v * (1 - (1 - f) * s);
  switch (i % 6) {
  case 0: r = v, g = t, b = p; break;
  case 1: r = q, g = v, b = p; break;
  case 2: r = p, g = v, b = t; break;
  case 3: r = p, g = q, b = v; break;
  case 4: r = t, g = p, b = v; break;
  case 5: r = v, g = p, b = q; break;
  }
  return 'rgb(' + Math.floor(r * 255) + ',' + Math.floor(g * 255) + ',' + Math.floor(b * 255) + ')';
};

var hashString = function(value) {
  var hash = 0;
  if (typeof value === 'string') {
    for (var i = 0; i < value.length; i++) {
      hash = ((hash << 5) - hash) + value.charCodeAt(i);
      hash = hash & hash; // Convert to 32bit integer
    }
  }
  return hash;
};

var SEC_IN_HOUR = 60 * 60;
var SEC_IN_DAY = SEC_IN_HOUR * 24;

var dateToSec = function(date) {
  return Math.floor(date.getTime() / 1000);
};

var parseBoolean = function(value) {
  switch (typeof value) {
  case 'boolean':
    return value;
  case 'string':
    return value.toLowerCase() === 'true';
  }
  return false;
};

var createNumberChartDataSets = function(dataPointSet, datasets, prefix) {
  datasets = datasets || [];
  prefix = prefix || '';
  var avgSerie = [];
  var minSerie = [];
  var maxSerie = [];
  dataPointSet.forEach(function(item) {
    var avg = item.average;
    if ((typeof avg === 'number') && !Number.isInteger(avg)) {
      avg = Math.floor(avg * 100) / 100;
    }
    avgSerie.push(avg);
    minSerie.push(item.min);
    maxSerie.push(item.max);
  });
  var hue = (Math.abs(hashString(prefix)) % 240) / 240;
  var maxColor = hsvToRgb(hue, 0.7, 0.8);
  var avgColor = hsvToRgb(hue, 0.5, 0.8);
  var minColor = hsvToRgb(hue, 0.3, 0.8);
  datasets.push({
    label: prefix + 'Average',
    backgroundColor: Chart.helpers.color(avgColor).alpha(0.5).rgbString(),
    borderColor: avgColor,
    fill: false,
    data: avgSerie
  }, {
    label: prefix + 'Max',
    hidden: true,
    backgroundColor: Chart.helpers.color(maxColor).alpha(0.5).rgbString(),
    borderColor: maxColor,
    fill: false,
    data: maxSerie
  }, {
    label: prefix + 'Min',
    hidden: true,
    backgroundColor: Chart.helpers.color(minColor).alpha(0.5).rgbString(),
    borderColor: minColor,
    fill: false,
    data: minSerie
  });
  return datasets;
};
var createMappedChartDataSets = function(dataPointSet, datasets, prefix, map) {
  datasets = datasets || [];
  prefix = prefix || '';
  var chgSerie = [];
  var valSerie = [];
  dataPointSet.forEach(function(item) {
    chgSerie.push(item.changes);
    valSerie.push(item.index);
  });
  var hue = (Math.abs(hashString(prefix) + 120) % 240) / 240;
  var hue2 = (Math.abs(hashString(prefix) + 180) % 240) / 240;
  var valColor = hsvToRgb(hue, 0.5, 0.8);
  var chgColor = hsvToRgb(hue2, 0.5, 0.8);
  datasets.push({
    label: prefix + 'Values',
    backgroundColor: Chart.helpers.color(valColor).alpha(0.5).rgbString(),
    borderColor: valColor,
    fill: false,
    steppedLine: 'after',
    pointStyle: 'rectRot',
    //pointRadius: 3,
    //yAxisID: 'map',
    map: map,
    data: valSerie
  });
  datasets.push({
    label: prefix + 'Changes',
    hidden: true,
    backgroundColor: Chart.helpers.color(chgColor).alpha(0.5).rgbString(),
    borderColor: chgColor,
    fill: false,
    steppedLine: 'after',
    pointStyle: 'triangle',
    data: chgSerie
  });
  return datasets;
};
var createChangesChartDataSets = function(dataPointSet, datasets, prefix) {
  datasets = datasets || [];
  prefix = prefix || '';
  var chgSerie = [];
  dataPointSet.forEach(function(item) {
    chgSerie.push(item.changes);
  });
  var hue = (Math.abs(hashString(prefix) + 60) % 240) / 240;
  var chgColor = hsvToRgb(hue, 0.5, 0.8);
  datasets.push({
    label: prefix + 'Changes',
    backgroundColor: Chart.helpers.color(chgColor).alpha(0.5).rgbString(),
    borderColor: chgColor,
    fill: true,
    data: chgSerie
  });
  return datasets;
};
var listDates = function(dataPointSet) {
  var dates = [];
  var labels = [];
  dataPointSet.forEach(function(item) {
    var date = new Date(item.time * 1000);
    dates.push(date);
    labels.push(date.toISOString().substring(11, 16));
  });
  return dates;
};
var createChartDataSets = function(dataPointSet, datasets, prefix) {
  if (dataPointSet.length === 0) {
    return [];
  }
  var firstItem = dataPointSet[0];
  var lastItem = dataPointSet[dataPointSet.length - 1];
  if ('average' in lastItem) {
    return createNumberChartDataSets(dataPointSet, datasets, prefix);
  }
  if ('map' in firstItem) {
    return createMappedChartDataSets(dataPointSet, datasets, prefix, firstItem.map);
  }
  if ('changes' in lastItem) {
    return createChangesChartDataSets(dataPointSet, datasets, prefix);
  }
  return [];
};

new Vue({
  el: '#historicalData',
  data: {
    toDays: 0,
    root: {}
  },
  methods: {
    onShow: function() {
      //this.toDays = 0;
      this.loadHistoricalData();
    },
    loadHistoricalData: function() {
      var toDays = parseFloat(this.toDays);
      var headers = {};
      if (toDays > 0) {
        var toDate = new Date(Date.now() - (toDays * SEC_IN_DAY * 1000));
        headers = {
          "X-TO-TIME": dateToSec(toDate)
        };
      }
      var self = this;
      fetch('/engine/historicalData/', {
        method: 'GET',
        headers: headers
      }).then(function(response) {
        return response.json();
      }).then(function(response) {
        //console.log('fetch()', response);
        self.root = jsonToTree('historicalData', response.value, '');
      });
    },
    onTreePathSelected: function(path, value) {
      app.callPage('data-chart', 'loadHistoricalData', path);
      app.toPage('data-chart');
    }
  }
});
new Vue({
  el: '#data-chart',
  data: {
    chartType: 'line',
    chartTension: 0,
    chartBeginAtZero: true,
    path: '',
    paths: [],
    toDays: 0,
    duration: 43200,
    period: 0,
    chart: null
  },
  methods: {
    getHistoricalDataHeaders: function() {
      var duration = parseInt(this.duration, 10);
      var period = parseInt(this.period, 10);
      if (period <= 0) {
        period = duration / 120; // how many data points
        period = Math.floor(period / 300) * 300; // round to 5 min
        period = Math.max(900, Math.min(period, SEC_IN_DAY)); // between 15 min to one day
        console.log('auto period is ' + period);
      }
      var toDays = parseInt(this.toDays, 10);
      var toDate = new Date(Date.now() - (toDays * SEC_IN_DAY * 1000));
      var nextHour = new Date(toDate.getFullYear(), toDate.getMonth(), toDate.getDate(), toDate.getHours() + 1);
      var tomorrow = new Date(toDate.getFullYear(), toDate.getMonth(), toDate.getDate() + 1);
      var toTime = dateToSec(duration > SEC_IN_DAY ? tomorrow : nextHour);
      var fromTime = toTime - duration;
      return {
        "X-FROM-TIME": fromTime,
        "X-TO-TIME": toTime,
        "X-PERIOD": period
      };
    },
    loadMultiHistoricalData: function(paths) {
      this.paths = paths;
      var headers = this.getHistoricalDataHeaders();
      headers["X-PATHS"] = paths.join(',');
      var self = this;
      fetch('/engine/historicalData/', {
        method: 'GET',
        headers: headers
      }).then(function(response) {
        return response.json();
      }).then(function(dataPointSets) {
        //console.log('fetch()', response);
        var dates = null;
        var datasets = [];
        dataPointSets.forEach(function(dataPointSet, i) {
          if (dates === null) {
            dates = listDates(dataPointSet);
          }
          createChartDataSets(dataPointSet, datasets, '' + (i + 1) + ' ');
        });
        self.createChart(dates, datasets);
      });
    },
    loadHistoricalData: function(path) {
      this.path = path;
      var self = this;
      fetch('/engine/historicalData' + path, {
        method: 'GET',
        headers: this.getHistoricalDataHeaders()
      }).then(function(response) {
        return response.json();
      }).then(function(dataPointSet) {
        //console.log('fetch()', response);
        self.createChart(listDates(dataPointSet), createChartDataSets(dataPointSet));
      });
    },
    cleanMultiHistoricalData: function() {
      this.paths = [];
    },
    pushMultiHistoricalData: function() {
      if (this.path) {
        this.paths.push(this.path);
        this.path = '';
        this.reloadHistoricalData();
      }
    },
    reloadHistoricalData: function() {
      if (this.path) {
        this.loadHistoricalData(this.path);
      } else if (this.paths.length > 0) {
        this.loadMultiHistoricalData(this.paths);
      }
    },
    createChart: function(dates, datasets) {
      if (this.chart) {
        this.chart.destroy();
      }
      var title = this.path;
      //var lastIndex = title.lastIndexOf('/');
      //if (lastIndex > 0) { title = title.substring(lastIndex + 1); }
      var chartTension = parseFloat(this.chartTension);
      var chartBeginAtZero = parseBoolean(this.chartBeginAtZero);
      var yAxes = [{
        scaleLabel: {
          labelString: 'Value',
          //display: true
        },
        //display: true,
        //position: 'left',
        ticks: {
          //suggestedMin: 10,
          //callback: ticksCallback,
          //suggestedMax: suggestedMax,
          beginAtZero: chartBeginAtZero
        }
      }];
      datasets.forEach(function(dataset, index) {
        if ('map' in dataset) {
          // https://www.chartjs.org/samples/latest/scales/non-numeric-y.html
          var map = dataset.map;
          delete dataset.map;
          dataset.yAxisID = 'map';
          yAxes.push({
            id: dataset.yAxisID,
            //type: 'category',
            //display: true,
            position: 'right',
            ticks: {
              beginAtZero: true,
              callback: function(value) {
                if (Number.isInteger(value) && (value >= 1) && (value <= map.length)) {
                  return map[value - 1];
                }
                return undefined;
              },
              suggestedMax: 3
            }
          });
        }
      });
      console.info('chart', datasets, yAxes);
      this.chart = new Chart('chart-data-view-canvas', {
        type: this.chartType,
        data: {
          labels: dates,
          datasets: datasets
        },
        options: {
          title: {
            display: true,
            text: 'Historical data for ' + title
          },
          //responsive: true,
          elements: {
            line: {
              tension: chartTension
            },
            rectangle: {
              borderWidth: 1
            }
          },
          legend: {
            display: true,
            position: 'bottom'
          },
          scales: {
            xAxes: [{
              type: 'time',
              time: {
                format: 'MM/DD/YYYY HH:mm',
                tooltipFormat: 'll HH:mm'
              },
              scaleLabel: {
                display: true,
                labelString: 'Date'
              }
            }],
            yAxes: yAxes
          }
        }
      });
    }
  }
});

new Vue({
  el: '#devices',
  data: {
    devices: []
  },
  methods: {
    openDevice: function(device) {
      app.callPage('itemConfig', 'setPath', 'device/' + device.id);
      app.toPage('itemConfig');
    },
    openDeviceData: function(device) {
      app.callPage('itemData', 'setPath', 'device/' + device.id);
      app.toPage('itemData');
    },
    pollDevice: function(device) {
      fetch('/engine/admin/device/' + device.id + '/poll', {method: 'POST'}).then(function() {
        toaster.toast('Polling triggered');
      });
    },
    reloadDevice: function(device) {
      fetch('/engine/admin/device/' + device.id + '/reload', {method: 'POST'}).then(function() {
        toaster.toast('Device reloaded');
      });
    },
    onShow: function() {
      var self = this;
      fetch('/engine/admin/listDevices').then(function(response) {
        return response.json();
      }).then(function(devices) {
        self.devices = devices;
        //console.log('devices', self.devices);
      });
    },
    onSave: function() {
      var config = {device: {}};
      for (var i = 0; i < this.devices.length; i++) {
        var device = this.devices[i];
        config.device[device.id] = {
          active: device.active,
          archiveData: device.archiveData
        };
      }
      console.log('config', config);
      fetch('/engine/configuration/', {
        method: 'POST',
        body: JSON.stringify({
          value: config
        })
      });
    }
  }
});

new Vue({
  el: '#plugins',
  data: {
    plugins: []
  },
  methods: {
    openPlugin: function(plugin) {
      app.callPage('itemConfig', 'setPath', 'plugin/' + plugin.id);
      app.toPage('itemConfig');
    },
    reloadPlugin: function(plugin) {
      fetch('/engine/admin/plugin/' + plugin.id + '/reload', {method: 'POST'}).then(function() {
        toaster.toast('plugin reloaded');
      });
    },
    onShow: function() {
      var self = this;
      fetch('/engine/admin/listPlugins').then(function(response) {
        return response.json();
      }).then(function(plugins) {
        self.plugins = plugins;
        //console.log('plugins', self.plugins);
      });
    },
    onSave: function() {
      var config = {};
      // archiveData
      for (var i = 0; i < this.plugins.length; i++) {
        var item = this.plugins[i];
        var typeConfig = config[item.type];
        if (!typeConfig) {
          config[item.type] = typeConfig = {};
        }
        typeConfig[item.id] = {active: item.active};
      }
      console.log('config', config);
      fetch('/engine/configuration/', {
        method: 'POST',
        body: JSON.stringify({
          value: config
        })
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
  var matches = window.location.hash.match(/^#\/([^\/]+)\/.*$/);
  if (matches) {
    app.toPage(matches[1]);
  } else {
    app.toPage('main');
  }
};
app.$on('page-selected', function(id) {
  window.location.replace(window.location.pathname + '#/' + id + '/');
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
fetch('/engine/configuration/plugin/web_base').then(function(response) {
  return response.json();
}).then(function(response) {
  webBaseConfig = response.value;
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