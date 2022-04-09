define(['./web-example.xml'], function(aPageTemplate) {

  var aVue = new Vue({
    template: aPageTemplate
  });

  addPageComponent(aVue);

  menu.pages.push({
    id: 'example',
    name: 'Example'
  });
  
  homePage.pages.push({
    id: 'example',
    name: 'Example'
  });
  
});
