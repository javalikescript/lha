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
        this.clearTimer();
        var ms = 1000 - (date.getTime() % 1000);
        // TODO Interval refresh should be provided by the app.
        this.timer = setTimeout(function() {
          if (app.isActivePage(self)) {
            self.refresh(new Date());
            self.registerTimer(1000);
          }
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

  addPageComponent(timeVue, 'clock');

});
