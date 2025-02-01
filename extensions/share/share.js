define(['./share.xml', 'engine/configuration/extensions/share/'], function(shareTemplate, shareConfig) {

  var shareVue = new Vue({
    template: shareTemplate,
    data: {
      shares: shareConfig.value.shares || []
    }
  });

  addPageComponent(shareVue, 'share', true);

});
