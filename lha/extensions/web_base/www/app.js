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
 * Helpers
 ************************************************************/
var strcasecmp = function(a, b) {
  var al = ('' + a).toLowerCase();
  var bl = ('' + b).toLowerCase();
  return al === bl ? 0 : (al > bl ? 1 : -1);
};

var compareByName = function(a, b) {
  return strcasecmp(a.name, b.name);
};

var compareByTitle = function(a, b) {
  return strcasecmp(a.title, b.title);
};

var setTheme = function(name) {
  var body = document.getElementsByTagName('body')[0];
  body.setAttribute('class', 'theme_' + name);
};

var formatNavigationPath = function(pageId, path) {
  return '/' + pageId + '/' + (path ? path : '');
};

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

var newJsonItem = function(type) {
  switch(type) {
    case 'string':
      return '';
    case 'integer':
    case 'number':
      return 0;
    case 'boolean':
      return false;
    case 'array':
      return [];
    case 'object':
      return {};
    }
    return undefined;
};

var parseJsonItemValue = function(type, value) {
  if ((value === null) || (value === undefined)) {
    return value;
  }
  var valueType = typeof value;
  if ((valueType !== 'string') && (valueType !== 'number') && (valueType !== 'boolean')) {
    throw new Error('Invalid value type ' + valueType);
  }
  switch(type) {
  case 'string':
    if (valueType !== 'string') {
      value = '' + value;
    }
    break;
  case 'integer':
  case 'number':
    if (valueType === 'string') {
      value = parseFloat(value);
      if (isNaN(value)) {
        return 0;
      }
    } else if (valueType === 'boolean') {
      value = value ? 1 : 0;
    }
    break;
  case 'boolean':
    if (valueType === 'string') {
      value = value.trim().toLowerCase();
      value = value === 'true';
    } else if (valueType === 'number') {
      value = value !== 0;
    }
    break;
  default:
    throw new Error('Invalid type ' + type);
  }
  return value;
};

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
    pageHistory: []
  },
  methods: {
    toPage: function(id, path) {
      if (this.page === id) {
          return;
      }
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
        this.selectPage(matches[1], matches[2]);
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

/************************************************************
 * Application component pages
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
        toaster.toast('Refreshed')
      });
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
    reloadExtensions: function() {
      fetch('/engine/admin/reloadExtensions/all', {method: 'POST'});
    },
    reloadScripts: function() {
      fetch('/engine/admin/reloadScripts/all', {method: 'POST'});
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
    onShow: function(path) {
      if (path) {
        this.loadHistoricalData('/' + path);
      }
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
      var title = this.path || 'multiple values';
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
  el: '#things',
  data: {
    extensionsById: {},
    propertiesById: {},
    things: []
  },
  methods: {
    onShow: function() {
      var self = this;
      fetch('/engine/things').then(function(response) {
        return response.json();
      }).then(function(things) {
        if (Array.isArray(things)) {
          things.sort(compareByTitle);
        }
        self.things = things;
        //console.log('things', self.things);
        return fetch('/engine/properties');
      }).then(function(response) {
        return response.json();
      }).then(function(properties) {
        self.propertiesById = {};
        for (var i = 0; i < self.things.length; i++) {
          var thing = self.things[i];
          var props = properties[thing.thingId];
          var propNames = Object.keys(props);
          if (propNames.length === 1) {
            var propName = propNames[0];
            var propDef = thing.properties[propName];
            self.propertiesById[thing.thingId] = {
              value: props[propName],
              unit: (propDef.unit || '')
            };
          } else {
            // found the default property
            var thingType = thing['@type'][0];
          }
        }
        //console.log('properties', self.properties);
        return fetch('/engine/extensions');
      }).then(function(response) {
        return response.json();
      }).then(function(extensions) {
        var extensionsById = {};
        for (var i = 0; i < extensions.length; i++) {
          var extension = extensions[i];
          extensionsById[extension.id] = extension;
        }
        self.extensionsById = extensionsById;
        //console.log('extensionsById', self.extensionsById);
      });

    },
    onArchiveAll: function() {
      for (var i = 0; i < this.things.length; i++) {
        this.things[i].archiveData = true;
      }
    },
    onRemoveAll: function() {
      Promise.all(this.things.map(function(thing) {
        return fetch('/engine/things/' + thing.thingId, {method: 'DELETE'});
      })).then(function() {
        toaster.toast('Things disabled');
      })
    },
    onSave: function() {
      var config = {things: {}};
      for (var i = 0; i < this.things.length; i++) {
        var thing = this.things[i];
        config.things[thing.thingId] = {
          archiveData: thing.archiveData
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
  el: '#thing',
  data: {
    edit: false,
    thingId: '',
    properties: {},
    props: {},
    thing: {}
  },
  methods: {
    openHistoricalData: function(propertyName) {
      app.toPage('data-chart', this.thingId + '/' + propertyName);
    },
    disableThing: function() {
      fetch('/engine/things/' + this.thingId, {method: 'DELETE'}).then(function() {
        toaster.toast('Thing disabled');
      });
    },
    onEdit: function() {
      this.edit = !this.edit;
      if (this.edit) {
        this.props = Object.assign({}, this.properties);
      }
    },
    onSave: function() {
      var modifiedProps = {};
      for (var key in this.thing.properties) {
        var tp = this.thing.properties[key];
        var value = parseJsonItemValue(tp.type, this.props[key]);
        //console.info(key, tp.type, value, this.props[key]);
        //if ((value !== null) && (value !== undefined) && (value !== this.properties[key])) {
        if (value !== this.properties[key]) {
          modifiedProps[key] = value;
        }
      }
      //console.info('onSave()', JSON.stringify(modifiedProps, undefined, 2));
      fetch('/things/' + this.thingId + '/properties', {
        method: 'PUT',
        body: JSON.stringify(modifiedProps)
      }).then(function() {
        toaster.toast('Properties updated');
      });
    },
    onShow: function(thingId) {
      this.edit = false;
      if (thingId) {
        this.thingId = thingId;
      }
      this.thing = {};
      var self = this;
      fetch('/things/' + self.thingId).then(function(response) {
        return response.json();
      }).then(function(thing) {
        self.thing = thing;
        return fetch('/things/' + self.thingId + '/properties');
      }).then(function(response) {
        return response.json();
      }).then(function(properties) {
        if (Array.isArray(properties)) {
          properties.sort(compareByTitle);
        }
        self.properties = properties;
      });
    }
  }
});

new Vue({
  el: '#addThings',
  data: {
    things: []
  },
  methods: {
    onShow: function() {
      this.things = [];
      var self = this;
      fetch('/engine/discoveredThings').then(function(response) {
        return response.json();
      }).then(function(things) {
        if (Array.isArray(things)) {
          things.sort(compareByTitle);
        }
        for (var i = 0; i < things.length; i++) {
          var thing = things[i];
          thing.toAdd = false;
          self.things.push(thing);
        }
        //console.log('things', self.things);
      });
    },
    onAddAll: function() {
      for (var i = 0; i < this.things.length; i++) {
        this.things[i].toAdd = true;
      }
    },
    onSave: function() {
      var thingsToAdd = [];
      for (var i = 0; i < this.things.length; i++) {
        var thing = this.things[i];
        if (thing.toAdd) {
          thingsToAdd.push(thing);
        }
      }
      if (thingsToAdd.length > 0) {
        fetch('/engine/things/', {
          method: 'PUT',
          body: JSON.stringify(thingsToAdd)
        }).then(function() {
          toaster.toast('Things added');
        });
      }
    }
  }
});

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

new Vue({
  el: '#extensions',
  data: {
    extensions: []
  },
  methods: {
    pollExtension: function(extension) {
      fetch('/engine/extensions/' + extension.id + '/poll', {method: 'POST'}).then(function() {
        toaster.toast('extension polled');
      });
    },
    onShow: function() {
      var self = this;
      fetch('/engine/extensions').then(function(response) {
        return response.json();
      }).then(function(extensions) {
        if (Array.isArray(extensions)) {
          extensions.sort(compareByName);
        }
        self.extensions = extensions;
        //console.log('extensions', self.extensions);
      });
    }
  }
});

new Vue({
  el: '#extension',
  data: {
    extensionId: '',
    extension: {config: {}, info: {}, manifest: {}}
  },
  methods: {
    onDisable: function() {
      if (this.extensionId) {
        if (this.extension.config) {
          this.extension.config.active = false;
        }
        fetch('/engine/configuration/extensions/' + this.extensionId, {
          method: 'POST',
          body: JSON.stringify({
            value: {active: false}
          })
        });
      }
    },
    onReload: function() {
      if (this.extensionId) {
        fetch('/engine/extensions/' + this.extensionId + '/reload', {method: 'POST'}).then(function() {
          toaster.toast('Extension reloaded');
        });
      }
    },
    onSave: function() {
      if (this.extensionId && this.extension.config) {
        fetch('/engine/configuration/extensions/' + this.extensionId, {
          method: 'POST',
          body: JSON.stringify({
            value: this.extension.config
          })
        });
      }
    },
    onShow: function(extensionId) {
      var self = this;
      if (extensionId) {
        this.extensionId = extensionId;
      }
      self.extension = {config: {}, info: {}, manifest: {}};
      fetch('/engine/extensions/' + this.extensionId).then(function(response) {
        return response.json();
      }).then(function(extension) {
        self.extension = extension;
        //console.log('extension', self.extension);
      });
    }
  }
});

new Vue({
  el: '#addExtensions',
  data: {
    extensions: []
  },
  methods: {
    onShow: function() {
      var self = this;
      fetch('/engine/extensions').then(function(response) {
        return response.json();
      }).then(function(extensions) {
        if (Array.isArray(extensions)) {
          extensions.sort(compareByName);
        }
        self.extensions = extensions;
        //console.log('extensions', self.extensions);
      });
    },
    onSave: function() {
      var config = {extensions: {}};
      // archiveData
      for (var i = 0; i < this.extensions.length; i++) {
        var item = this.extensions[i];
        config.extensions[item.id] = {active: item.active};
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