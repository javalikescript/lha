
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
    var s = arguments[i];
    if ((s !== null) && (s !== undefined)) {
      var sl = ('' + s).toLowerCase();
      if (sl.indexOf(ql) >= 0) {
        return true;
      }
    }
  }
  return false;
}

function apply(to, fn) {
  return function(args) {
    return fn.apply(to, args);
  };
}

function call(to, fn) {
  console.warn('call is deprecated, please use bind', new Error());
  return function() {
    return fn.apply(to, arguments);
  };
}

function isEmpty(obj) {
  return (obj === null) || (obj === undefined) || (Array.isArray(obj) && (obj.length === 0)) || ((typeof obj === 'object') && (Object.keys(obj).length === 0));
}

function isArrayWithItems(obj) {
  return Array.isArray(obj) && (obj.length > 0);
}

function isObject(obj) {
  return (obj !== null) && (typeof obj === 'object');
}

function isObjectWithKeys(obj) {
  return isObject(obj) && (Object.keys(obj).length > 0);
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
    if (isObject(n)) {
      for (var k in n) {
        m[k] = n[k];
      }
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

function deepMap(value, fn) {
  if ((value === undefined) || (value === null)) {
    return value;
  }
  if (typeof value !== 'object') {
    return fn(value);
  }
  if (Array.isArray(value)) {
    var l = [];
    for (var i = 0; i < value.length; i++) {
      l.push(deepMap(value[i], fn));
    }
    return l;
  }
  var m = {};
  for (var k in value) {
    m[k] = deepMap(value[k], fn);
  }
  return m;
}

function deepCopy(value, useParse) {
  if (useParse) {
    return JSON.parse(JSON.stringify(value));
  }
  return deepMap(value, function(v) {return v;});
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

function parseRgb(v) {
  var parts = /^#?(\w\w)(\w\w)(\w\w)$/.exec(v);
  return parts ? {
    r: parseInt(parts[1], 16),
    g: parseInt(parts[2], 16),
    b: parseInt(parts[3], 16)
  } : null;
}

function toHex(v) {
  var h = (v & 0xff).toString(16);
  return h.length == 1 ? '0' + h : h;
}
function formatRgb(r, g, b) {
  if (typeof r === 'object') {
    return parseRgb(r.r, r.g, r.b);
  }
  return "#" + toHex(r) + toHex(g) + toHex(b);
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
  if ((length === undefined) || (length > value.length)) {
    length = value.length;
  }
  return value.substring(length - search.length, length) === search;
}

function startsWith(value, search, position) {
  if ((position === undefined) || (position < 0)) {
    position = 0;
  }
  return value.substring(position, position + search.length) === search;
}

function basename(path, invert) {
  var slashIndex = path.lastIndexOf('/');
  if (invert) {
    return slashIndex < 0 ? '' : path.substring(0, slashIndex);
  }
  return slashIndex < 0 ? path : path.substring(slashIndex + 1);
}

function extname(path, invert) {
  var name = basename(path);
  var dotIndex = name.lastIndexOf('.');
  if (invert) {
    return dotIndex < 0 ? name : name.substring(0, dotIndex);
  }
  return dotIndex < 0 ? '' : name.substring(dotIndex + 1);
}

function postJson(resource, obj, options, method) {
  return fetch(resource, assignMap({
    method: method || 'POST',
    headers: { "Content-Type": 'application/json' },
    body: JSON.stringify(obj)
  }, options));
}

function putJson(resource, obj, options) {
  return postJson(resource, obj, options, 'PUT');
}

function getJson(response) {
  return response.json();
}

function getResponseJson(response) {
  return response.json();
}

function getResponseText(response) {
  return response.text();
}

function rejectIfNotOk(response) {
  if (response.ok) {
    return response;
  }
  return Promise.reject(response.statusText);
}

function doNothing() {
}

function insertTab(e) {
  var t = e && e.target;
  if (t && t.setRangeText) {
    t.setRangeText('\t', t.selectionStart, t.selectionStart, 'end');
  }
}

function findAncestor(el, selector, deep) {
  if (el) {
    var d = typeof deep === 'number' ? deep : 10;
    while (--d > 0) {
      el = el.parentElement;
      if (el) {
        if (el.matches(selector)) {
          return el;
        }
      } else {
        break;
      }
    }
  }
}

function findChild(el, selector) {
  if (el) {
    for (let i = 0; i < el.children.length; i++) {
      let c = el.children[i];
      if (c.matches(selector)) {
        return c;
      }
    }
  }
}

function findDescendant(el, selector, deep) {
  if (el) {
    var m = findChild(el, selector);
    if (m) {
      return m;
    }
    var d = typeof deep === 'number' ? deep : 10;
    if (d > 0) {
      d--;
      for (let i = 0; i < el.children.length; i++) {
        let c = el.children[i];
        m = findDescendant(c, selector, d);
        if (m) {
          return m;
        }
      }
    }
  }
}

function findParent(el) {
  if (el) {
    return el.parentElement;
  }
}

function tryFocus(el) {
  if (el) {
    el.focus();
  }
}

function addElement(tagName, attributes, node) {
  return new Promise(function(resolve, reject) {
    if (node === undefined) {
      node = 'head';
    }
    if (typeof node === 'string') {
      node = document.getElementsByTagName(node)[0];
    }
    if (!node) {
      reject();
    }
    var list = node.getElementsByTagName(tagName);
    for (var i = 0; i < list.length; i++) {
      var item = list[i];
      var matches = true;
      for (var name in attributes) {
        if (item.getAttribute(name) !== attributes[name]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        resolve();
      }
    }
    var el = document.createElement(tagName);
    el.onload = resolve;
    el.onerror = reject;
    for (var name in attributes) {
      el.setAttribute(name, attributes[name])
    }
    node.appendChild(el);
  });
}

function addHeadCss(url) {
  return addElement('link', {
    type: 'text/css',
    rel: 'stylesheet',
    href: url
  });
}

function addHeadScript(url) {
  return addElement('script', {
    type: 'text/javascript',
    charset: 'utf-8',
    src: url
  });
}

function loadScripts(urls) {
  if (Array.isArray(urls)) {
    return Promise.all(urls.map(function(url) {
      return fetch(url).then(function(response) {
        if (!response.ok) {
          return Promise.reject(response.statusText);
        }
        return response.text();
      });
    })).then(function(sources) {
      for (var i = 0; i < sources.length; i++) {
        Function(sources[i])();
      }
    });
  } else if (typeof urls === 'string') {
    return loadScripts(Array.prototype.slice.call(arguments));
  } else if (urls === undefined) {
    return Promise.resolve();
  }
  return Promise.reject();
}
