define(['./hue-v2.xml'], function(aPageTemplate) {

  var aVue = new Vue({
    template: aPageTemplate,
    methods: {
      touchlink: function() {
        var page = this;
        fetch('/hue-api/config', {
          method: 'PUT',
          body: JSON.stringify({touchlink: true})
        }).then(function(response) {
          return response.text();
        }).then(function(logLevel) {
          page.logLevel = logLevel.toLowerCase();
        });
      }
    }
  });

  addPageComponent(aVue, true);

});
