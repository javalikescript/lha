define(['./web-example.xml'], function(aPageTemplate) {

  var aVue = new Vue({
    template: aPageTemplate
  });

  addPageComponent(aVue, 'flask', true);

});
