define(['./web-notes.xml', './web-note.xml', './web-draw.xml'], function(notesTemplate, noteTemplate, drawTemplate) {

  var NOTES_PATH = '/user-notes/';

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
        return fetch(NOTES_PATH + path, {
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
        } else if (note.type === 'link') {
          fetch(NOTES_PATH + path).then(getResponseText).then(function(content) {
            open(content, '_blank');
          });
        }
      }
    }
  });

  var SHARED_DATA = {
    path: '',
    name: '',
    extension: '',
    newName: false,
    saved: true
  };

  function onShow(path) {
    this.path = path;
    this.name = basename(path);
    this.extension = extname(path);
    this.newName = false;
  }

  function onDelete() {
    return fetch(NOTES_PATH + this.path, {
      method: 'DELETE' 
    }).then(assertIsOk).then(function() {
      toaster.toast('Note deleted');
    });
  }

  function onRename() {
    fetch(NOTES_PATH + this.path, {
      method: 'DELETE' 
    }).then(function() {
      this.saved = false;
      this.name = this.newName;
      if (this.extension) {
        this.name += '.' + this.extension;
      }
      var dir = basename(this.path, true);
      this.path = dir ? dir + '/' + this.name : this.name;
      return this.onSave();
    }.bind(this)).then(function() {
      this.newName = false;
      app.replacePage(app.page, this.path);
    }.bind(this));
  }

  function onSave(content) {
    return fetch(NOTES_PATH + this.path, {
      method: 'PUT',
      body: content
    }).then(assertIsOk).then(function() {
      toaster.toast('Note saved');
    });
  }

  var noteVue = new Vue({
    template: noteTemplate,
    data: Object.assign({
      text: ''
    }, SHARED_DATA),
    methods: {
      onShow: function(path) {
        onShow.call(this, path);
        this.text = '';
        return fetch(NOTES_PATH + this.path).then(rejectIfNotOk).then(getResponseText).then(function(text) {
          this.text = text;
          this.saved = true;
          tryFocus(findDescendant(this.$el, 'textarea'));
        }.bind(this));
      },
      onBeforeHide: function() {
        if (!this.saved) {
          toaster.toast('Unsaved modifications');
          return false;
        }
      },
      onChange: function() {
        this.saved = false;
      },
      onRename: onRename,
      onDelete: function () {
        return onDelete.call(this).then(function() {
          this.saved = true;
        }.bind(this));
      },
      onSave: function () {
        if (this.saved) {
          toaster.toast('Note already saved');
        } else {
          onSave.call(this, this.text).then(function() {
            this.saved = true;
          }.bind(this));
        }
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
  function getCanvasSize() {
    var draw = document.getElementById('draw');
    if (canvas && draw) {
      return {
        width: window.innerWidth,
        height: window.innerHeight - draw.children[0].offsetHeight
      };
    }
  }
  function loadImage(src) {
    return new Promise(function(resolve, reject) {
      var img = new Image();
      img.onload = function () {
        resolve(img);
      };
      img.onerror = reject;
      img.src = src;
    });
  }
  function drawImage(src) {
    var size = getCanvasSize();
    return loadImage(src).then(function(img) {
      context.drawImage(img, 0, 0, size.width, size.height);
    });
  }
  function resizeCanvas() {
    var size = getCanvasSize();
    if (canvas && size) {
      drawImage(canvas.toDataURL());
      canvas.width = size.width;
      canvas.height = size.height;
    }
  }

  var drawVue = new Vue({
    template: drawTemplate,
    data: Object.assign({}, SHARED_DATA),
    methods: {
      onShow: function(path) {
        onShow.call(this, path);
        canvas = document.getElementById('draw-canvas');
        context = canvas && canvas.getContext && canvas.getContext('2d');
        var size = getCanvasSize();
        if (canvas && context && size) {
          canvas.addEventListener('touchstart', onTouchStart, false);
          canvas.addEventListener('touchmove', onTouchMove, false);
          canvas.addEventListener('mousemove', onMouseMove, false);
          canvas.addEventListener('mousedown', onMouseDown, false);
          window.addEventListener('mouseup', onMouseUp, false);
          window.addEventListener('resize', resizeCanvas, false);
          canvas.width = size.width;
          canvas.height = size.height;
          drawImage(NOTES_PATH + this.path);
        }
      },
      onHide: function() {
        if (canvas) {
          canvas.removeEventListener('touchstart', onTouchStart);
          canvas.removeEventListener('touchmove', onTouchMove);
          canvas.removeEventListener('mousemove', onMouseMove);
          canvas.removeEventListener('mousedown', onMouseDown);
          window.removeEventListener('mouseup', onMouseUp);
          window.removeEventListener('resize', resizeCanvas);
        }
      },
      clear: function() {
        context.clearRect(0, 0, canvas.width, canvas.height);
      },
      onRename: onRename,
      onDelete: onDelete,
      onSave: function () {
        var img = canvas.toDataURL('image/png');
        var mark = 'base64,'
        var index = img.indexOf(mark);
        if (index > 0) {
          var content = img.substring(index + mark.length);
          content = window.atob(content);
          content = Uint8Array.from(content, (m) => m.codePointAt(0));
          onSave.call(this, content);
        }
      }
    }
  });

  addPageComponent(notesVue, 'sticky-note', true, true);
  addPageComponent(noteVue);
  addPageComponent(drawVue);

});
