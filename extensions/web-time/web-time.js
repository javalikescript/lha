define(['./web-time.xml'], function(timeTemplate) {

  var timeVue = new Vue({
    template: timeTemplate,
    data: {
      date: '',
      time: '',
      timer: null
    },
    methods: {
      onShow: function() {
        var self = this;
        var date = new Date();
        self.refresh(date);
        var ms = 1000 - (date.getTime() % 1000);
        setTimeout(function() {
          self.refresh(new Date());
          self.registerTimer(1000);
        }, ms);
      },
      onHide: function() {
        this.clearTimer();
      },
      refresh: function(date) {
        //console.info('refresh at ' + date.toISOString());
        this.date = date.toLocaleDateString(undefined, {dateStyle: 'full'});
        this.time = date.toLocaleTimeString(undefined, {timeStyle: 'short'});
      },
      registerTimer: function(ms) {
        var self = this;
        this.clearTimer();
        this.timer = setInterval(function() {
          self.refresh(new Date());
        }, ms || 60000);
      },
      clearTimer: function() {
        if (this.timer !== null) {
          clearInterval(this.timer);
          this.timer = null;
        }
      }
    }
  });

  addPageComponent(timeVue, 'fa-clock');

});
