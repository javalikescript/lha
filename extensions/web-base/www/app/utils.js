
function strcasecmp(a, b) {
  var al = ('' + a).toLowerCase();
  var bl = ('' + b).toLowerCase();
  return al === bl ? 0 : (al > bl ? 1 : -1);
}

function compareByName(a, b) {
  return strcasecmp(a.name, b.name);
}

function compareByTitle(a, b) {
  return strcasecmp(a.title, b.title);
}

function contains(q) {
  var ql = q.toLowerCase();
  for (var i = 1; i < arguments.length; i++) {
    var sl = ('' + arguments[i]).toLowerCase();
    if (sl.indexOf(ql) >= 0) {
      return true;
    }
  }
  return false;
}

function apply(to, fn) {
  return function(args) {
    return fn.apply(to, args);
  };
}

function isEmpty(obj) {
  return ((obj === null) || (obj === undefined)) || (Array.isArray(obj) && (obj.length === 0)) || (Object.keys(obj).length === 0);
}

function swapMap(m) {
  var r = {};
  for (var k in m) {
    r[m[k]] = k;
  }
  return r;
}

function assignMap(m) {
  for (var i = 1; i < arguments.length; i++) {
    var n = arguments[i];
    for (var k in n) {
      m[k] = n[k];
    }
  }
  return m;
}

function toMap(l, k) {
  if (Array.isArray(l)) {
    var m = {};
    for (var i = 0; i < l.length; i++) {
      var e = l[i];
      m[e[k]] = e;
    }
    return m;
  }
  return l;
}

function hsvToRgb(h, s, v) {
  var r, g, b;
  var i = Math.floor(h * 6);
  var f = h * 6 - i;
  var p = v * (1 - s);
  var q = v * (1 - f * s);
  var t = v * (1 - (1 - f) * s);
  switch (i % 6) {
  case 0: r = v, g = t, b = p; break;
  case 1: r = q, g = v, b = p; break;
  case 2: r = p, g = v, b = t; break;
  case 3: r = p, g = q, b = v; break;
  case 4: r = t, g = p, b = v; break;
  case 5: r = v, g = p, b = q; break;
  }
  return 'rgb(' + Math.floor(r * 255) + ',' + Math.floor(g * 255) + ',' + Math.floor(b * 255) + ')';
}

function hashString(value) {
  var hash = 0;
  if (typeof value === 'string') {
    for (var i = 0; i < value.length; i++) {
      hash = ((hash << 5) - hash) + value.charCodeAt(i);
      hash = hash & hash; // Convert to 32bit integer
    }
  }
  return hash;
}

var SEC_IN_HOUR = 60 * 60;
var SEC_IN_DAY = SEC_IN_HOUR * 24;

function dateToSec(date) {
  return Math.floor(date.getTime() / 1000);
}

function parseBoolean(value) {
  switch (typeof value) {
  case 'boolean':
    return value;
  case 'string':
    return value.toLowerCase() === 'true';
  }
  return false;
}

function toggleFullScreen() {
  if (document.fullscreenElement) {
    document.exitFullscreen();
  } else {
    document.body.requestFullscreen();
  }
}

function endsWith(value, search, length) {
  if ((length === undefined) || (length > this.length)) {
    length = value.length;
  }
  return value.substring(length - search.length, length) === search;
}

function extname(path, invert) {
  var slashIndex = path.lastIndexOf('/');
  var dotIndex = path.lastIndexOf('.');
  if (invert) {
    return dotIndex <= slashIndex ? path : path.substring(0, dotIndex);
  }
  return dotIndex <= slashIndex ? '' : path.substring(dotIndex + 1);
}

function rejectIfNotOk(response) {
  if (response.ok) {
    return response;
  }
  return Promise.reject(response.statusText);
}
