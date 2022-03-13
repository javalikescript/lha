define(function() {

  var testVue = new Vue({
    template: '<app-page id="example" title="Sample Page"><page-article><p>Example content</p></page-article></app-page>'
  });
  var testComponent = testVue.$mount();
  document.getElementById('pages').appendChild(testComponent.$el);
  
  menu.pages.push({
    id: 'example',
    name: 'Example'
  });
  
  main.pages.push({
    id: 'example',
    name: 'Example'
  });
  
});
