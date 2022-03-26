define(['./web-overview.xml'], function(pageXml) {

  var lightLevelToLux = function(value) {
    return Math.round((Math.pow(10, value / 10000) - 1) * 100) / 100;
  };
  
  var componentVue = new Vue({
    template: pageXml,
    data: {
      externalTemperature: 0,
      externalRelativeHumidity: 0,
      internalTemperature: 0,
      internalRelativeHumidity: 0,
      internalLightLevel: 0,
      pressure: 0
    },
    methods: {
      onShow: function () {
        var self = this;
        var toDate = new Date();
        var nextHour = new Date(toDate.getFullYear(), toDate.getMonth(), toDate.getDate(), toDate.getHours() + 1);
        var toTime = dateToSec(nextHour);
        var fromTime = toTime - SEC_IN_HOUR * 25;
        var names = [
          'internalLightLevel',
          'internalTemperature',
          'externalRelativeHumidity',
          'externalTemperature',
          'internalRelativeHumidity',
          'pressure'
        ];
        var paths = [
          'hue_motion/lightlevel',
          'hue_motion/temperature',
          'serial_THGR122NX/humidity',
          'serial_THGR122NX/temperature',
          'serial_DHT11/humidity',
          'serial_BMP280/pressure'
        ];
        fetch('/engine/historicalData/device/', {
          method: 'GET',
          headers: {
            "X-FROM-TIME": fromTime,
            "X-TO-TIME": toTime,
            "X-PERIOD": SEC_IN_HOUR,
            "X-PATHS": paths.join(',')
          }
        }).then(function(response) {
          return response.json();
        }).then(function(response) {
          //console.log('fetch()', response);
          for (var i = 0; i < names.length; i++) {
            var name = names[i];
            var items = response[i];
            var lastIndex = items.length - 1;
            if (items[lastIndex].count == 0) {
              lastIndex--;
            }
            var item = items[lastIndex];
            var previousItem = items[lastIndex - 1];
            var firstItem = items[0];
            var value = item.count > 0 ? item.average : 0;
            //var previousValue = previousItem.count > 0 ? previousItem.average : 0;
            //var firstValue = firstItem.count > 0 ? firstItem.average : 0;
            //var shortTendency = (value - previousValue) / value;
            switch(name) {
            case 'internalLightLevel':
              value = Math.round(lightLevelToLux(value));
              break;
            case 'pressure':
              value = Math.round(value) / 100;
              break;
            default:
              value = Math.round(value * 10) / 10;
              break;
            }
            self[name] = value;
          }
        });
        /*
        fetch('/engine/historicalData/').then(function(response) {
          return response.json();
        }).then(function(response) {
          var device = response.value.device;
          if ('serial_THGR122NX' in device) {
            self.externalTemperature = device.serial_THGR122NX.temperature;
            self.externalRelativeHumidity = device.serial_THGR122NX.humidity;
          }
          if ('hue_motion' in device) {
            self.internalTemperature = device.hue_motion.temperature;
            self.internalLightLevel = lightLevelToLux(device.hue_motion.lightlevel);
          }
          self.internalRelativeHumidity = device.serial_DHT11 ? device.serial_DHT11.humidity : 0;
          if (device.serial_BMP280 && device.serial_BMP280.pressure) {
            self.pressure = Math.round(device.serial_BMP280.pressure) / 100;
          }
        });
        */
      }
    }
  });
  
  addPageComponent(componentVue);

  main.pages.push({
    id: 'overview',
    name: 'Overview'
  });

});
