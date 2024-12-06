define(['./owm.xml'], function(owmTemplate) {

  var unitAlias = app.getUnitAliases();
  var directionLabels = ['-', 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  var directions = ['\u21BB', '\u2191', '\u2197', '\u2192', '\u2198', '\u2193', '\u2199', '\u2190', '\u2196'];

  function compare(a, b) {
    return a === b ? 0 : (a > b ? 1 : -1);
  }
  function compareTimes(a, b) {
    return compare(a.time, b.time);
  }
  function formatIcon(props) {
    if (props.rain) {
      if (props.rain > 10) {
        return 'cloud-showers-heavy';
      }
      return props.cloud < 66 ? 'cloud-sun-rain' : 'cloud-rain';
    } else if (props.cloud > 33) {
      return props.cloud < 66 ? 'cloud-sun' : 'cloud';
    }
    return 'sun';
  }
  function formatDirection(direction, speed, label) {
    var i = 0;
    if (typeof speed !== 'number' || speed > 0) {
      i = Math.round(direction / 45) % 8 + 1;
    }
    if (label) {
      return directionLabels[i];
    }
    return directions[i];
  }

  var owmVue = new Vue({
    template: owmTemplate,
    data: {
      empty: true,
      unit: {},
      times: []
    },
    methods: {
      onDataChange: function() {
        Promise.all([
          app.getThings(),
          app.getPropertiesByThingId()
        ]).then(apply(this, function(things, properties) {
          this.refresh(things, properties);
        }));
      },
      onShow: function() {
        this.onDataChange();
      },
      formatDirection: function(d) {
        return formatDirection(d);
      },
      extractUnits: function(thing) {
        for (var name in thing.properties) {
          var unit = thing.properties[name].unit;
          if (unit) {
            this.unit[name] = unitAlias[unit] || unit;
          }
        }
      },
      refresh: function(things, properties) {
        var now = Date.now();
        var times = [];
        for (var i = 0; i < things.length; i++) {
          var thing = things[i];
          if (thing.extensionId === 'owm') {
            if (this.empty) {
              this.empty = false;
              this.extractUnits(thing);
              //console.info('units:', this.unit);
            }
            var props = properties[thing.thingId];
            if (props && thing.properties.date) {
              var t = props.date ? new Date(props.date).getTime() : 0;
              var h = t > now ? Math.floor((t - now) / 3600000) : 0;
              var item = Object.assign({
                title: thing.title,
                label: h < 24 ? (h + 'h'): (Math.floor(h / 24) + 'd'),
                time: t,
                faIcon: 'fa-' + formatIcon(props)
              }, props);
              times.push(item);
            }
          }
        }
        times.sort(compareTimes);
        //console.info('times:', times);
        this.times = times;
      }
    }
  });

  addPageComponent(owmVue, 'fa-umbrella');
  
});
