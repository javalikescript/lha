define(['./web-notes.xml', './web-note.xml', './web-draw.xml'], function(notesTemplate, noteTemplate, drawTemplate) {

  var NOTES_PATH = '/user-notes/';

  function getNoteExtension(type) {
    switch (type) {
      case 'note':
        return '.txt';
      case 'draw':
        return '.png';
      case 'link':
        return '.lnk';
      case 'dir':
        return '/';
    }
    return '';
  }

  function getNoteType(name) {
    if (endsWith(name, '.txt')) {
      return 'note';
    } else if (endsWith(name, '.png')) {
      return 'draw';
    } else if (endsWith(name, '.lnk')) {
      return 'link';
    } else if (endsWith(name, '/')) {
      return 'dir';
    }
    return '';
  }

  function checkPath(path) {
    return fetch(NOTES_PATH + path, {method: 'HEAD'}).then(function(response) {
      if (response.status !== 404) {
        return Promise.reject('Already exists');
      }
    });
  }

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
        return fetch(NOTES_PATH + path, {
          headers: {
            "Accept": 'application/json'
          }
        }).then(rejectIfNotOk).then(getResponseJson).then(function(response) {
          if (isArrayWithItems(response)) {
            var notes = response.map(function(note) {
              if (note.isDir) {
                note.type = 'dir';
              } else {
                note.type = getNoteType(note.name);
              }
              return note;
            });
            this.notes = this.notes.concat(notes);
          }
        }.bind(this));
      },
      onRefresh: function() {
        return this.onShow(this.path);
      },
      createNote: function() {
        promptDialog.ask({
          type: 'array',
          minItems: 2,
          prefixItems: [
            {
              title: 'Name',
              type: 'string',
              pattern: '[^/\\]+'
            },
            {
              title: 'Type',
              type: 'string',
              default: 'note',
              enumValues: [
                {const: 'note', title: 'Note'},
                {const: 'dir', title: 'Folder'},
                {const: 'draw', title: 'Drawing'},
                {const: 'link', title: 'Link'}
              ]
            }
          ]
        }, 'New note').then(function(args) {
          var name = args[0];
          var type = args[1];
          if (!name || name.indexOf('/') !== -1 || name.indexOf('\\') !== -1 || name.indexOf('..') !== -1) {
            return Promise.reject('Invalid name');
          }
          if (type === 'dir') {
            var path = this.path + name + '/';
            return checkPath(path).then(function() {
              return fetch(NOTES_PATH + path, {method: 'PUT'})
            }).then(assertIsOk).then(function() {
              toaster.toast('Folder created');
              this.onRefresh();
            }.bind(this));
          }
          var path = this.path + name + getNoteExtension(type);
          return checkPath(path).then(function() {
            app.toPage(type, path);
          });
        }.bind(this)).catch(function(reason) {
          toaster.toast('Fail to create note, ' + reason);
        });
      },
      onDelete: function() {
        return confirmation.ask('Delete the folder?').then(function() {
          return fetch(NOTES_PATH + this.path, {method: 'DELETE'});
        }.bind(this)).then(assertIsOk).then(function() {
          toaster.toast('Folder deleted');
        });
      },
      openNote: function(note) {
        var path = this.path + note.name;
        switch (note.type) {
          case 'note':
          case 'draw':
            app.toPage(note.type, path);
            break;
          case 'link':
            fetch(NOTES_PATH + path).then(getResponseText).then(function(content) {
              open(content, '_blank');
            });
            break;
          case 'dir':
            app.toPage('notes', path + '/');
            break;
        }
      },
      dirname: function() {
        var path = basename(this.path.substring(0, this.path.length - 2), true);
        return path ? path + '/' : '';
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

  function dirname() {
    var path = basename(this.path, true);
    return path ? path + '/' : '';
  }

  function onShow(path) {
    this.path = path;
    this.name = basename(path);
    this.extension = extname(path);
    this.newName = false;
  }

  function onDelete() {
    return confirmation.ask('Delete the note?').then(function() {
      return fetch(NOTES_PATH + this.path, {method: 'DELETE'});
    }.bind(this)).then(assertIsOk).then(function() {
      toaster.toast('Note deleted');
    });
  }

  function onRename() {
    var newName = this.newName + (this.extension ? '.' + this.extension : '');
    var dir = basename(this.path, true);
    var path = dir ? dir + '/' + newName : newName;
    return fetch(NOTES_PATH + this.path, {
      method: 'MOVE',
      headers: {
        destination: NOTES_PATH + path
      }
    }).then(function(response) {
      if (response.ok || response.status === 404) {
        return response;
      }
      return Promise.reject(response.statusText);
    }).then((function() {
      this.name = newName;
      this.newName = false;
      this.path = path;
      app.replacePage(app.page, this.path);
    }).bind(this));
  }

  function onMove() {
    var newPath;
    var path = this.dirname();
    return fetch(NOTES_PATH + path, {
      headers: {
        "Accept": 'application/json'
      }
    }).then(rejectIfNotOk).then(getResponseJson).then(function(response) {
      if (isArrayWithItems(response)) {
        return response.filter(function(note) {
          return note.isDir;
        }).map(function(note) {
          return note.name;
        });
      }
      return Promise.reject();
    }).then(function(dirs) {
      if (path) {
        dirs.splice(0, 0, '..');
      }
      return promptDialog.ask({
        title: 'Folder Name',
        type: 'string',
        enumValues: dirs.map(function(name) {
          return {const: name, title: name};
        })
      }, 'Destination');
    }).then(function(dir) {
      if (dir === '..') {
        newPath = basename(basename(this.path, true), true);
      } else {
        newPath = path + dir;
      }
      if (newPath) {
        newPath += '/';
      }
      newPath += this.name;
      return fetch(NOTES_PATH + this.path, {
        method: 'MOVE',
        headers: {
          destination: NOTES_PATH + newPath
        }
      });
    }.bind(this)).then(rejectIfNotOk).then((function() {
      this.path = newPath;
      app.replacePage(app.page, this.path);
    }).bind(this));
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
      onMove: onMove,
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
      },
      dirname: dirname
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
