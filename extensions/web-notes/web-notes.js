define(['./web-notes.xml', './web-note.xml', './web-draw.xml'], function(notesTemplate, noteTemplate, drawTemplate) {

  var notesPath = '/user-notes/';

  var notesVue = new Vue({
    template: notesTemplate,
    data: {
      notes: [],
      path: ''
    },
    methods: {
      onShow: function(path) {
        if (!path) {
          path = '';
        }
        this.notes = [];
        this.path = path;
        if (path === '' && app.user && app.user.logged) {
          this.notes.push({name: 'me', type: 'dir'});
        }
        var self = this;
        return fetch(notesPath + path, {
          headers: {
            "Accept": 'application/json'
          }
        }).then(rejectIfNotOk).then(getResponseJson).then(function(response) {
          if (isArrayWithItems(response)) {
            var notes = response.filter(function(note) {
              return !note.isDir;
            }).map(function(note) {
              if (note.isDir) {
                note.type = 'dir';
              } else if (endsWith(note.name, '.txt')) {
                note.type = 'text';
              } else if (endsWith(note.name, '.png')) {
                note.type = 'draw';
              } else if (endsWith(note.name, '.lnk')) {
                note.type = 'link';
                fetch(path + note.name).then(getResponseText).then(function(content) {
                  note.url = content;
                });
              }
              return note;
            });
            self.notes = self.notes.concat(notes);
          }
        });
      },
      openNote: function(note) {
        var path = this.path + note.name;
        console.info('openning note "' + path + '"');
        if (note.type === 'dir') {
          app.toPage('notes', path + '/');
        } else if (note.type === 'text') {
          app.toPage('note', path);
        } else if (note.type === 'draw') {
          app.toPage('draw', path);
        } else if ((note.type === 'link') && note.url) {
          open(note.url, '_blank');
        }
      }
    }
  });

  var noteVue = new Vue({
    template: noteTemplate,
    data: {
      path: '',
      name: '',
      newName: false,
      text: ''
    },
    methods: {
      onShow: function(path) {
        this.path = path;
        this.name = basename(path);
        this.newName = false;
        this.text = '';
        var self = this;
        return fetch(notesPath + this.path).then(rejectIfNotOk).then(getResponseText).then(function(text) {
          self.text = text;
        });
      },
      onRename: function () {
        var self = this;
        this.onDelete().then(function() {
          self.name = self.newName + '.txt';
          var dir = basename(self.path, true);
          self.path = dir ? dir + '/' + self.name : self.name;
          return self.onSave();
        }).then(function() {
          self.newName = false;
        });
      },
      onDelete: function () {
        return fetch(notesPath + this.path, {
          method: 'DELETE' 
        }).then(assertIsOk).then(function() {
          toaster.toast('Note deleted');
        });
      },
      onSave: function () {
        return fetch(notesPath + this.path, {
          method: 'PUT',
          body: this.text
        }).then(assertIsOk).then(function() {
          toaster.toast('Note saved');
        });
      }
    }
  });

  function drawDot(ctx, x, y, size) {
    ctx.fillStyle = "rgba(0,0,0,0.6)";
    ctx.beginPath();
    ctx.arc(x, y, size, 0, Math.PI*2, true); 
    ctx.closePath();
    ctx.fill();
  } 

  var canvas, context, size = 6;
  var mouseX, mouseY, mouseDown = 0;
  var touchX, touchY;

  function onMouseDown() {
    mouseDown = 1;
    drawDot(context , mouseX, mouseY, size);
  }
  function onMouseUp() {
    mouseDown = 0;
  }
  function onMouseMove(event) { 
    getMousePos(event);
    if (mouseDown === 1) {
      drawDot(context, mouseX, mouseY, size);
    }
  }
  function getMousePos(event) {
    if (event.offsetX) {
      mouseX = event.offsetX;
      mouseY = event.offsetY;
    } else if (event.layerX) {
      mouseX = event.layerX;
      mouseY = event.layerY;
    }
   }
  function onTouchStart(event) {
    getTouchPos();
    drawDot(context, touchX, touchY, size);
    event.preventDefault();
  }
  function onTouchMove(event) { 
    getTouchPos(event);
    drawDot(context, touchX, touchY, size);
    event.preventDefault();
  }
  function getTouchPos(event) {
    if(event.touches) {
      if (event.touches.length === 1) {
        var touch = event.touches[0];
        touchX = touch.pageX - touch.target.offsetLeft;
        touchY = touch.pageY - touch.target.offsetTop;
      }
    }
  }
  function resizeCanvas() {
    var draw = document.getElementById('draw');
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight - draw.children[0].offsetHeight;
  }

  var drawVue = new Vue({
    template: drawTemplate,
    methods: {
      onShow: function() {
        canvas = document.getElementById('draw-canvas');
        if (!canvas) {
          return;
        }
        context = canvas.getContext && canvas.getContext('2d');
        if (context) {
          canvas.addEventListener('mousedown', onMouseDown, false);
          canvas.addEventListener('mousemove', onMouseMove, false);
          window.addEventListener('mouseup', onMouseUp, false);
          canvas.addEventListener('touchstart', onTouchStart, false);
          canvas.addEventListener('touchmove', onTouchMove, false);
          window.addEventListener('resize', resizeCanvas, false);
          resizeCanvas();
        }
      },
      onHide: function() {
        canvas.removeEventListener('mousedown', onMouseDown);
        canvas.removeEventListener('mousemove', onMouseMove);
        window.removeEventListener('mouseup', onMouseUp);
        canvas.removeEventListener('touchstart', onTouchStart);
        canvas.removeEventListener('touchmove', onTouchMove);
        window.removeEventListener('resize', resizeCanvas);
      },
      clear: function() {
        context.clearRect(0, 0, canvas.width, canvas.height);
      }
    }
  });

  addPageComponent(notesVue, 'sticky-note');
  addPageComponent(noteVue);
  addPageComponent(drawVue);

});
