define(function() {

  var testVue = new Vue({
    template: '<app-page id="test" title="Test Page"><page-article><p>Test content</p></page-article></app-page>'
  });
  var testComponent = testVue.$mount();
  document.getElementById('pages').appendChild(testComponent.$el);
  
  menu.pages.push({
    id: 'test',
    name: 'Test'
  });
  
});
