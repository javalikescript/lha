
function newJsonItem(type) {
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
}

function parseJsonItemValue(type, value, optional) {
  if ((value === null) || (value === undefined)) {
    return value;
  }
  if ((value === '') && optional) {
    return undefined;
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
}

function hasSchema(schema) {
  return schema && (Object.keys(schema.properties).length > 0)
}

function browseJsonSchema(schema, fn) {
  fn(schema);
  if ((schema.type === 'array') && schema.items) {
    browseJsonSchema(schema.items, fn)
  } else if ((schema.type === 'object') && schema.properties) {
    for (var name in schema.properties) {
      browseJsonSchema(schema.properties[name], fn)
    }
  }
}

function computeJsonSchema(schema, things) {
  if (hasSchema(schema)) {
    schema = JSON.parse(JSON.stringify(schema));
    browseJsonSchema(schema, function(s) {
      if ('enumVar' in s) {
        if (s.enumVar === 'thingIds') {
          s.enumValues = things.map(function(thing) {
            return {
              const: thing.thingId,
              title: thing.title + ' - ' + thing.description
            };
          });
          s.enumValues.sort(compareByTitle);
        }
        delete s.enumVar;
      }
    });
    return schema;
  }
  return false;
}

Vue.component('json-item', {
  props: ['name', 'obj', 'pobj', 'schema', 'root'],
  data: function() {
    return {
      open: true
    };
  },
  template: '#json-item-template',
  computed: {
    label: function() {
      var title = this.schema && this.schema.title;
      if (title) {
        if (this.name) {
          return title + ' (' + this.name + ')';
        }
        return title;
      }
      return this.name || 'Value';
    },
    hasStringValue: function() {
      return this.schema && (this.schema.type === 'string');
    },
    hasEnumValues: function() {
      return this.schema && (Array.isArray(this.schema.enum) || Array.isArray(this.schema.enumValues));
    },
    hasNumberValue: function() {
      return this.schema && ((this.schema.type === 'number') || (this.schema.type === 'integer'));
    },
    hasBooleanValue: function() {
      return this.schema && (this.schema.type === 'boolean');
    },
    propertyNames: function() {
      var names = [];
      var objectNames = [];
      var arrayNames = [];
      for (var name in this.schema.properties) {
        var propertyType = this.schema.properties[name].type;
        switch(propertyType) {
          case 'array':
            arrayNames.push(name);
            break;
          case 'object':
            objectNames.push(name);
            break;
          default:
            names.push(name);
            break;
        }
      }
      arrayNames.sort(strcasecmp);
      objectNames.sort(strcasecmp);
      names.sort(strcasecmp);
      return names.concat(objectNames).concat(arrayNames);
    },
    enumValues: function() {
      if (Array.isArray(this.schema.enumValues)) {
        return this.schema.enumValues;
      } else if (Array.isArray(this.schema.enum)) {
        return this.schema.enum.map(function(key) {
          return {
            "const": key,
            "title": key
          };
        });
      }
      return [];
    },
    value: {
      get: function() {
        return this.obj;
      },
      set: function(val) {
        //console.log('value()', val, this.$vnode.key);
        var v = parseJsonItemValue(this.schema.type, val, true);
        if ((v !== null) && (v !== undefined)) {
          this.pobj[this.$vnode.key] = v;
        }
      }
    },
    isList: function() {
      return this.schema && (this.schema.type === 'array') && (typeof this.schema.items === 'object') && Array.isArray(this.obj);
    },
    isRemovable: function() {
      return Array.isArray(this.pobj);
    },
    hasProperties: function() {
      if (this.schema && (this.schema.type === 'object') && (typeof this.schema.properties === 'object')) {
        for (var name in this.schema.properties) {
          var ss = this.schema.properties[name];
          if (!(name in this.obj)) {
            this.obj[name] = newJsonItem(ss.type);
          }
        }
        return true;
      }
      return false;
    }
  },
  methods: {
    getProperty: function(name) { 
      if (!(name in this.obj)) {
        if (name in this.schema.properties) {
          this.obj[name] = newJsonItem(this.schema.properties[name].type);
        } else {
          this.obj[name] = '';
        }
      }
      return this.obj[name];
    },
    addItem: function() {
      if (this.schema && (this.schema.type === 'array') && (typeof this.schema.items === 'object') && Array.isArray(this.obj)) {
        console.log('addItem()', this.obj, this.schema);
        var item = newJsonItem(this.schema.items.type);
        this.obj.push(item);
        this.$forceUpdate();
      } else {
        console.error('Cannot add item', this.obj, this.schema);
      }
    },
    removeItem: function() {
      if (Array.isArray(this.pobj)) {
        var index = parseInt(this.name, 10);
        if (index && (index >= 1) && (index <= this.pobj.length)) {
          this.pobj.splice(index - 1, 1);
          this.$forceUpdate();
        }
      }
    },
    toggle: function() {
      if (this.schema && ((this.schema.type === 'array') || (this.schema.type === 'object'))) {
        this.open = !this.open
      }
    }
  }
});

Vue.component('json', {
  props: ['name', 'obj', 'schema'],
  template: '#json-template'
});
