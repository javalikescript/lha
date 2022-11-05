
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

function normalizeJsonType(type) {
  return type === 'integer' ? 'number' : type;
}

function areJsonTypeCompatible(a, b) {
  return (a === b) || ((a === 'number') && (b === 'integer')) || ((a === 'integer') && (b === 'number'));
}

function getJsonType(obj) {
  if (obj === null) {
    return 'undefined';
  }
  if (Array.isArray(obj)) {
    return 'array';
  }
  var type = typeof obj;
  switch(type) {
    case 'string':
    case 'number': // integer
    case 'boolean':
    case 'object':
      return type;
  }
  return 'undefined';
}

function isJsonType(obj, type) {
  return getJsonType(obj) === normalizeJsonType(type);
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
    browseJsonSchema(schema.items, fn);
  } else if ((schema.type === 'object') && schema.properties) {
    for (var name in schema.properties) {
      browseJsonSchema(schema.properties[name], fn);
    }
  }
  if (Array.isArray(schema.anyOf)) {
    schema.anyOf.forEach(function(ofSchema) {
      browseJsonSchema(ofSchema, fn);
    });
  }
  if (Array.isArray(schema.oneOf)) {
    schema.oneOf.forEach(function(ofSchema) {
      browseJsonSchema(ofSchema, fn);
    });
  }
}

function copyObject(obj) {
  return JSON.parse(JSON.stringify(obj));
}

function populateJsonSchema(schema, enumsById) {
  if (hasSchema(schema)) {
    schema = copyObject(schema);
    browseJsonSchema(schema, function(s) {
      if ('enumVar' in s) {
        var enumValues = enumsById[s.enumVar];
        if (enumValues) {
          s.enumValues = enumValues;
        }
        delete s.enumVar;
      }
    });
    return schema;
  }
  return false;
}

function guessOfSchemaIndex(schemas, obj) {
  if (Array.isArray(schemas)) {
    for (var index = 0; index < schemas.length; index++) {
      var schema = schemas[index];
      if (isJsonType(obj, schema.type)) {
        if ((schema.type === 'object') && (typeof schema.properties === 'object')) {
          var match = true;
          for (var name in schema.properties) {
            if (!(name in obj)) {
              match = false;
              break;
            }
          }
          if (match) {
            return index;
          }
        } else {
          return index;
        }
      }
    }
    if (getJsonType(obj) === 'object') {
      var index = obj['#schema'];
      if ((typeof index === 'number') && (index >= 0) && (index < of.length)) {
        return index;
      }
    }
    return 0;
  }
  return -1;
}

function populateJson(schema, obj) {
  if (schema) {
    if (schema.type) {
      if (!isJsonType(obj, schema.type)) {
        if (isJsonType(schema.default, schema.type)) {
          obj = schema.default;
        } else {
          obj = newJsonItem(schema.type);
        }
      }
      if ((schema.type === 'object') && schema.properties) {
        for (var k in schema.properties) {
          obj[k] = populateJson(schema.properties[k], obj[k]);
        }
      } else if ((schema.type === 'array') && schema.items) {
        var l = obj.length;
        if ((typeof schema.minItems === 'number') && (schema.minItems > l)) {
          l = schema.minItems;
        }
        for (var i = 0; i < l; i++) {
          obj[i] = populateJson(schema.items, obj[i]);
        }
      }
    } else {
      var of = schema.anyOf || schema.oneOf;
      if (Array.isArray(of)) {
        var index = guessOfSchemaIndex(of, obj);
        if (index >= 0) {
          obj = populateJson(of[index], obj);
        }
      }
    }
  }
  return obj;
}

function isJsonItem(comp) {
  return comp.$options.name === 'json-item';
}

function forEachJsonItem(comp, fn) {
  comp.$children.forEach(function(child) {
    if (isJsonItem(child)) {
      fn(child);
      forEachJsonItem(child, fn);
    }
  });
}

function findJsonItem(comp, fn) {
  var children = comp.$children;
  for (var i = 0; i < children.length; i++) {
    var child = children[i];
    if (isJsonItem(child)) {
      if (typeof fn === 'function') {
        return fn(child, comp);
      }
      return child;
    }
  }
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
      var title = this.schema.title;
      if (title) {
        if (this.name && (strcasecmp(title, this.name) !== 0)) {
          return title + ' (' + this.name + ')';
        }
        return title;
      }
      return this.name || 'Value';
    },
    propertyNames: function() {
      var names = [];
      var objectNames = [];
      var arrayNames = [];
      for (var name in this.schema.properties) {
        var propertySchema = this.schema.properties[name];
        if (propertySchema.format === 'hidden') {
          continue;
        }
        switch(propertySchema.type) {
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
        var v = parseJsonItemValue(this.schema.type, val, true);
        if ((v !== null) && (v !== undefined)) {
          this.pobj[this.$vnode.key] = v;
        }
      }
    },
    ofIndex: {
      get: function() {
        var schemas = this.schema.anyOf || this.schema.oneOf;
        var index = -1;
        if (Array.isArray(schemas)) {
          index = guessOfSchemaIndex(schemas, this.obj);
        }
        return index;
      },
      set: function(val) {
        var schemas = this.schema.anyOf || this.schema.oneOf;
        var index = parseInt(val, 10);
        if (!isNaN(index) && (index >= 0) && (index < schemas.length)) {
          var obj = populateJson(schemas[index]);
          this.obj = obj;
          this.pobj[this.$vnode.key] = obj;
          this.updateParent();
        }
      }
    },
    ofSchemaLabels: function() {
      var schemas = this.schema.anyOf || this.schema.oneOf;
      if (Array.isArray(schemas)) {
        return schemas.map(function(ofSchema, index) {
          return ofSchema.title || String(index + 1);
        });
      }
      return [];
    },
    ofKey: function() {
      return this.$vnode.key || '';
    },
    ofSchemas: function() {
      return this.schema.anyOf || this.schema.oneOf;
    },
    hasOfSchema: function() {
      return (this.schema.type === undefined) && Array.isArray(this.schema.anyOf || this.schema.oneOf);
    },
    isOfSchema: function() {
      return this.$parent && this.$parent.hasOfSchema;
    },
    hasEnumValues: function() {
      var schema = this.schema;
      return (Array.isArray(schema.enum) || Array.isArray(schema.enumValues)) &&
        ((schema.type === 'string') || (schema.type === 'number') || (schema.type === 'integer'));
    },
    isProperties: function() {
      var schema = this.schema;
      return (schema.type === 'object') && (typeof schema.properties === 'object');
    },
    hasList: function() {
      return (this.schema.type === 'array') && (typeof this.schema.items === 'object') && Array.isArray(this.obj);
    },
    isList: function() {
      return (this.schema.type === 'array') && (typeof this.schema.items === 'object');
    },
    isRemovable: function() {
      return Array.isArray(this.pobj);
    },
    hasContent: function() {
      if ((this.schema.type === 'array') || (this.schema.type === 'object')) {
        return true;
      }
      if (this.schema.type === undefined) {
        var schemas = this.schema.anyOf || this.schema.oneOf;
        if (Array.isArray(schemas)) {
          var schema = schemas[this.ofIndex];
          if (schema && ((schema.type === 'array') || (schema.type === 'object'))) {
            return true;
          }
        }
      }
      return false;
    }
  },
  methods: {
    updateParent: function() {
      var parent = this;
      while ((parent.pobj === this.pobj) && parent.$parent) {
        parent = parent.$parent;
      }
      parent.$forceUpdate();
    },
    addItem: function() {
      if ((this.schema.type === 'array') && (typeof this.schema.items === 'object') && Array.isArray(this.obj)) {
        var item = populateJson(this.schema.items);
        this.obj.push(item);
        this.$forceUpdate();
      } else {
        console.error('Cannot add item', this.obj, this.schema);
      }
    },
    getItemIndex: function() {
      if (Array.isArray(this.pobj)) {
        var index = parseInt(this.name, 10);
        if (index && (index >= 1) && (index <= this.pobj.length)) {
          return index - 1;
        }
      }
      return -1;
    },
    removeItem: function() {
      var index = this.getItemIndex();
      if (index !== -1) {
        this.pobj.splice(index, 1);
        this.updateParent();
      }
    },
    canMove: function(delta) {
      var index = this.getItemIndex();
      if (index !== -1) {
        var newIndex = index + delta;
        return (newIndex >= 0) && (newIndex < this.pobj.length);
      }
      return false;
    },
    moveItem: function(delta) {
      var index = this.getItemIndex();
      if (index !== -1) {
        var newIndex = index + delta;
        var items = this.pobj.splice(index, 1);
        this.pobj.splice(newIndex, 0, items[0]);
        this.updateParent();
      }
    },
    toggle: function(value) {
      if (typeof value !== 'boolean') {
        value = !this.open;
      }
      this.open = value;
      if (this.hasOfSchema) {
        var child = findJsonItem(this);
        if (child) {
          child.open = value;
        }
      }
    },
    toggleAll: function() {
      this.toggle();
      var open = this.open;
      forEachJsonItem(this, function(comp) {
        comp.toggle(open);
      });
    }
  }
});

Vue.component('json', {
  props: ['name', 'obj', 'schema'],
  template: '#json-template',
  methods: {
    refresh: function() {
      //console.log('refresh()', this.schema, this.obj);
      if ((typeof this.schema === 'object') && (typeof this.obj === 'object')) {
        populateJson(this.schema, this.obj);
        //console.log('populateJson() ' + JSON.stringify(this.obj, undefined, 2));
      }
    }
  },
  watch: { 
    obj: {
      handler: function(newValue) {
        this.refresh();
      },
      immediate: true
    }
  }
});
