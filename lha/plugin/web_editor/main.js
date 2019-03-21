define(function() {

  var aVue = new Vue({
    template: '<app-page id="editor" title="Editor"><page-article>' +
      '<div id="aceEditorDiv" style="height: 100%; width: 100%;"></div>' +
      '</page-article></app-page>',
      data: {
        aceEditor: null
      },
      methods: {
        onShow: function() {
          //console.log('onShow editor');
          if ((this.aceEditor === null) && ace) {
            this.aceEditor = ace.edit('aceEditorDiv');
            this.aceEditor.resize();
          }
        }
      }
  });
  var aComponent = aVue.$mount();
  document.getElementById('pages').appendChild(aComponent.$el);
  
  menu.pages.push({
    id: 'editor',
    name: 'Editor'
  });
  
});
