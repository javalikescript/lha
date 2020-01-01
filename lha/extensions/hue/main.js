define(function() {

  var testVue = new Vue({
    template: '<app-page id="hue_lights" title="Hue Lights"><page-article><table>' +
    '<tr><th>Name</th><th>Active</th></tr>' +
    '<tr v-for="light in lights"><td>{{light.id}}</td><td style="text-align: center; "><input type="checkbox" v-model="light.active" /></td></tr>' +
    '</table></page-article></app-page>',
    data: {
      lights: []
    },
    methods: {
      onShow: function () {
        var self = this;
        /*
        fetch('/engine/admin/plugin/hue/listDevices').then(function(response) {
          return response.json();
        }).then(function(lights) {
          self.lights = lights;
          console.log('lights', self.lights);
        });
        */
      }
    }
  });
  var testComponent = testVue.$mount();
  document.getElementById('pages').appendChild(testComponent.$el);
  
  menu.pages.push({
    id: 'hue_lights',
    name: 'Hue Lights'
  });
  
});
