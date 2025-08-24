define(['./shares.xml', './share.xml', 'engine/configuration/extensions/share/'], function(sharesTemplate, shareTemplate, shareConfig) {

  var sharesVue = new Vue({
    template: sharesTemplate,
    data: {
      shares: shareConfig.value.shares || []
    },
    methods: {
      openShare: function(share) {
        if (share && share.mode == 'HTML') {
          app.toPage('share', share.name + '/')
        } else {
          toaster.toast('Not an HTML share');
        }
      }
    }
  });

  var shareVue = new Vue({
    template: shareTemplate,
    data: {
      src: ''
    },
    methods: {
      onShow: function(src) {
        this.src = src || '';
      }
    }
  });

  addPageComponent(sharesVue, 'share', true);
  addPageComponent(shareVue);

});
