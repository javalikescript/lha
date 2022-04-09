define(['./web-chart.xml'], function(pageXml) {

  function isInteger(value) {
    return (typeof value === 'number') && isFinite(value) && (Math.floor(value) === value);
  };

  function isFloat(value) {
    return (typeof value === 'number') && isFinite(value) && (Math.floor(value) !== value);
  };

  function countDigits(value) {
    var s = String(value);
    var i = s.indexOf('.');
    return i > 0 ? s.length - i - 1 : 0;
  };

  var createNumberChartDataSets = function(dataPointSet, datasets, prefix) {
    datasets = datasets || [];
    prefix = prefix || '';
    var avgSerie = [];
    var minSerie = [];
    var maxSerie = [];
    var maxDigits = 0;
    dataPointSet.forEach(function(item) {
      var digits = countDigits(item.min);
      if (digits > maxDigits) {
        maxDigits = digits;
      }
      minSerie.push(item.min);
      maxSerie.push(item.max);
    });
    dataPointSet.forEach(function(item) {
      var avg = item.average;
      if (isFloat(avg)) {
        avg = avg.toFixed(maxDigits);
      }
      avgSerie.push(avg);
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
    console.log('createChartDataSets()', dataPointSet, datasets, prefix);
    if (dataPointSet.length === 0) {
      return [];
    }
    var firstItem = dataPointSet[0];
    if ('map' in firstItem) {
      return createMappedChartDataSets(dataPointSet, datasets, prefix, firstItem.map);
    }
    if ((firstItem.type === 'number') || (firstItem.type === 'integer')) {
      return createNumberChartDataSets(dataPointSet, datasets, prefix);
    }
    // TODO Remove
    var lastItem = dataPointSet[dataPointSet.length - 1];
    if ('average' in lastItem) {
      return createNumberChartDataSets(dataPointSet, datasets, prefix);
    }
    if ('changes' in lastItem) {
      return createChangesChartDataSets(dataPointSet, datasets, prefix);
    }
    return [];
  };
  
  /************************************************************
   * Chart
   ************************************************************/
  var vue = new Vue({
    template: pageXml,
    data: {
      chartType: 'line',
      chartTension: 0,
      chartBeginAtZero: true,
      path: '',
      paths: [],
      toDays: 0,
      things: [],
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
        fetch('/engine/historicalData/' + path, {
          method: 'GET',
          headers: this.getHistoricalDataHeaders()
        }).then(function(response) {
          return response.json();
        }).then(function(dataPointSet) {
          //console.log('fetch()', response);
          self.createChart(listDates(dataPointSet), createChartDataSets(dataPointSet));
        });
      },
      openPath: function() {
        console.info('openPath() ' + this.path);
        if (this.path) {
          app.toPage('data-chart', this.path);
        }
      },
      onShow: function(path) {
        if (path) {
          this.loadHistoricalData(path);
        }
        console.log('onShow(' + path + ') path = "' + this.path + '"');
        var self = this;
        app.getThings().then(function(things) {
          self.things = things;
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
                  if (isInteger(value) && (value >= 1) && (value <= map.length)) {
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
  
  addPageComponent(vue);
  
  menu.pages.push({
    id: 'data-chart',
    name: 'Chart'
  });

});
