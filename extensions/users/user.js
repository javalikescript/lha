define(['./user.xml'], function(loginTemplate) {

  var userVue = new Vue({
    template: loginTemplate,
    data: {
      logged: false,
      name: '',
      password: ''
    },
    methods: {
      onShow: function() {
        this.logged = app.user.logged === true;
        this.name = app.user.name || '';
        this.password = '';
      },
      login: function() {
        var body = new URLSearchParams({
          name: this.name,
          password: this.password
        });
        this.password = '';
        fetch('/login', {
          method: 'POST',
          headers: {
            "Content-Type": "application/x-www-form-urlencoded"
          },
          body: body
        }).then(assertIsOk).then(function() {
          window.location.reload();
        });
      },
      logout: function() {
        fetch('/logout', {
          method: 'POST'
        }).then(assertIsOk).then(function() {
          window.location.reload();
        });
      }
    }
  });
  
  addPageComponent(userVue, 'fa-user');

});
