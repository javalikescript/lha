var strcasecmp = function(a, b) {
  var al = ('' + a).toLowerCase();
  var bl = ('' + b).toLowerCase();
  return al === bl ? 0 : (al > bl ? 1 : -1);
};

var compareByName = function(a, b) {
  return strcasecmp(a.name, b.name);
};

var compareByTitle = function(a, b) {
  return strcasecmp(a.title, b.title);
};

var setTheme = function(name) {
  var body = document.getElementsByTagName('body')[0];
  body.setAttribute('class', 'theme_' + name);
};

var formatNavigationPath = function(pageId, path) {
  return '/' + pageId + '/' + (path ? path : '');
};

var hsvToRgb = function(h, s, v) {
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
};

var hashString = function(value) {
  var hash = 0;
  if (typeof value === 'string') {
    for (var i = 0; i < value.length; i++) {
      hash = ((hash << 5) - hash) + value.charCodeAt(i);
      hash = hash & hash; // Convert to 32bit integer
    }
  }
  return hash;
};

var SEC_IN_HOUR = 60 * 60;
var SEC_IN_DAY = SEC_IN_HOUR * 24;

var dateToSec = function(date) {
  return Math.floor(date.getTime() / 1000);
};

var parseBoolean = function(value) {
  switch (typeof value) {
  case 'boolean':
    return value;
  case 'string':
    return value.toLowerCase() === 'true';
  }
  return false;
};

var hasSchema = function(schema) {
  return schema && (Object.keys(schema.properties).length > 0)
};

var newJsonItem = function(type) {
  switch(type) {
    case 'string':
      return '';
    case 'integer':
    case 'number':
      return 0;
    case 'boolean':
      return false;
    case 'array':
      return [];
    case 'object':
      return {};
    }
    return undefined;
};

var parseJsonItemValue = function(type, value) {
  if ((value === null) || (value === undefined)) {
    return value;
  }
  var valueType = typeof value;
  if ((valueType !== 'string') && (valueType !== 'number') && (valueType !== 'boolean')) {
    throw new Error('Invalid value type ' + valueType);
  }
  switch(type) {
  case 'string':
    if (valueType !== 'string') {
      value = '' + value;
    }
    break;
  case 'integer':
  case 'number':
    if (valueType === 'string') {
      value = parseFloat(value);
      if (isNaN(value)) {
        return 0;
      }
    } else if (valueType === 'boolean') {
      value = value ? 1 : 0;
    }
    break;
  case 'boolean':
    if (valueType === 'string') {
      value = value.trim().toLowerCase();
      value = value === 'true';
    } else if (valueType === 'number') {
      value = value !== 0;
    }
    break;
  default:
    throw new Error('Invalid type ' + type);
  }
  return value;
};
