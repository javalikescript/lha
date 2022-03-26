define(function() {

  var aVue = new Vue({
    template: '<app-page id="editor" title="Editor"><article class="content">' +
      '<div id="aceEditorDiv" style="height: 100%; width: 100%;"></div>' +
      '</article></app-page>',
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

  addPageComponent(aVue);

  menu.pages.push({
    id: 'editor',
    name: 'Editor'
  });
  
});
