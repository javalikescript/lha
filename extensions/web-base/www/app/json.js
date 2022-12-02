
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
        value = 0;
      }
    } else if (valueType === 'boolean') {
      value = value ? 1 : 0;
    }
    break;
  case 'boolean':
    if (valueType === 'string') {
      value = value.trim().toLowerCase() === 'true';
    } else if (valueType === 'number') {
      value = value !== 0;
    }
    break;
  default:
    throw new Error('Invalid type ' + type);
  }
  return value;
}

function populateJsonSchema(rootSchema, enumsById) {
  function browseJsonSchema(schema, fn) {
    if (isObject(schema)) {
      fn(schema);
      if ((schema.type === 'array') && isObject(schema.items)) {
        browseJsonSchema(schema.items, fn);
      } else if ((schema.type === 'object') && isObject(schema.properties)) {
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
  }
  function browseJsonRootSchema(schema, fn) {
    if (isObject(schema['$defs'])) {
      var defs = schema['$defs'];
      for (var k in defs) {
        browseJsonSchema(defs[k], fn);
      }
    }
    browseJsonSchema(schema, fn);
  }
  var ps = false;
  if (isObject(rootSchema) && isObject(rootSchema.properties) && (Object.keys(rootSchema.properties).length > 0)) {
    ps = deepCopy(rootSchema);
    browseJsonRootSchema(ps, function(schema) {
      if ('enumVar' in schema) {
        var enumValues = enumsById[schema.enumVar];
        if (enumValues) {
          schema.enumValues = enumValues;
        }
        delete schema.enumVar;
      }
    });
  }
  //console.info('populateJsonSchema(' + (typeof schema) + ', ' + (typeof enumsById) + ') => ' + (typeof ps));
  return ps;
}

function unrefSchema(rootSchema, schema) {
  var us = schema;
  if (isObject(schema)) {
    var ref = schema['$ref'];
    if ((typeof ref === 'string') && startsWith(ref, '#/$defs/') && isObject(rootSchema)) {
      var defs = rootSchema['$defs'];
      if (isObject(defs)) {
        var name = ref.substring(8);
        var def = defs[name];
        if (typeof def === 'object') {
          us = def;
        }
      }
    }
  }
  //console.info('unrefSchema(' + (typeof rootSchema) + ', ' + (typeof schema) + ') => ' + (typeof us));
  return us;
}

(function() {

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

function getJsonType(obj) {
  var type = typeof obj;
  switch(type) {
    case 'object':
      if (obj === null) {
        break;
      }
      if (Array.isArray(obj)) {
        return 'array';
      }
    case 'string':
    case 'number': // integer
    case 'boolean':
      return type;
  }
  return 'undefined';
}

function isJsonType(obj, type) {
  var t = type === 'integer' ? 'number' : type;
  return getJsonType(obj) === t;
}

function matchSchema(rootSchema, schema, obj) {
  var sch = unrefSchema(rootSchema, schema);
  if ((typeof sch.type === 'string') && isJsonType(obj, sch.type)) {
    if ((sch.type === 'object') && isObject(sch.properties)) {
      for (var name in sch.properties) {
        var property = sch.properties[name];
        var value = obj[name];
        if ((value === undefined) || ((property.const !== undefined) && (property.const !== value))) {
          return false;
        }
      }
    }
    return true;
  }
  return false;
}

function guessOfSchemaIndex(rootSchema, ofSchemas, obj) {
  var index = -1;
  if (Array.isArray(ofSchemas) && (ofSchemas.length > 0)) {
    if (getJsonType(obj) === 'undefined') {
      index = 0;
    } else {
      index = ofSchemas.length;
      while (--index > 0) {
        if (matchSchema(rootSchema, ofSchemas[index], obj)) {
          break;
        }
      }
    }
  }
  //console.info('guessOfSchemaIndex(' + (typeof rootSchema) + ', ' + (typeof schemas) + ', ' + (typeof obj) + ') => ' + index);
  return index;
}

// populate the object with the least possible change
function populateJson(rootSchema, schema, obj) {
  var po = obj;
  if (isObject(schema)) {
    schema = unrefSchema(rootSchema, schema);
    if (schema.const !== undefined) {
      po = schema.const;
    } else if (typeof schema.type === 'string') {
      if (!isJsonType(po, schema.type)) {
        if (isJsonType(schema.default, schema.type)) {
          po = deepCopy(schema.default);
        } else {
          po = newJsonItem(schema.type);
        }
      }
      if ((schema.type === 'object') && isObject(schema.properties)) {
        for (var k in schema.properties) {
          po[k] = populateJson(rootSchema, schema.properties[k], po[k]);
        }
        // keep additional properties (!schema.additionalProperties)
      } else if ((schema.type === 'array') && isObject(schema.items)) {
        var l = po.length;
        if ((typeof schema.minItems === 'number') && (schema.minItems > l)) {
          l = schema.minItems;
        }
        for (var i = 0; i < l; i++) {
          po[i] = populateJson(rootSchema, schema.items, po[i]);
        }
      }
    } else {
      var ofSchemas = schema.anyOf || schema.oneOf;
      var index = guessOfSchemaIndex(rootSchema, ofSchemas, po);
      if (index >= 0) {
        po = populateJson(rootSchema, ofSchemas[index], po);
      }
    }
  }
  //console.info('populateJson(' + (typeof rootSchema) + ', ' + (typeof schema) + ', ' + (typeof obj) + ') => ' + (typeof po));
  return po;
}

function guessSchemaType(rootSchema, schema) {
  var t = false;
  if (isObject(schema)) {
    schema = unrefSchema(rootSchema, schema);
    if (typeof schema.type === 'string') {
      t = schema.type;
    } else {
      //schema.const schema.default
      var ofSchemas = schema.anyOf || schema.oneOf;
      if (Array.isArray(ofSchemas)) {
        for (var i = 0; i < ofSchemas.length; i++) {
          var ot = guessSchemaType(rootSchema, ofSchemas[i]);
          if (t) {
            if (t !== ot) {
              t = false;
              break;
            }
          } else {
            t = ot;
          }
        }
      }
    }
  }
  //console.info('guessSchemaType(' + (typeof rootSchema) + ', ' + (typeof schema) + ') => ' + t);
  return t || 'undefined';
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
  props: ['name', 'obj', 'pobj', 'schema', 'rootSchema'],
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
      if (!isObject(this.schema.properties)) {
        return [];
      }
      var names = [];
      var objectNames = [];
      var arrayNames = [];
      for (var name in this.schema.properties) {
        var propertySchema = unrefSchema(this.rootSchema, this.schema.properties[name]);
        if (propertySchema.format === 'hidden') {
          continue;
        }
        var type = guessSchemaType(this.rootSchema, propertySchema);
        switch(type) {
          case 'array':
            arrayNames.push(name);
            break;
          case 'object':
            objectNames.push(name);
            break;
          case 'undefined':
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
        var index = guessOfSchemaIndex(this.rootSchema, this.schema.anyOf || this.schema.oneOf, this.obj);
        //console.info('ofIndex get => ' + index, 'obj:', deepCopy(this.obj));
        return index;
      },
      set: function(index) {
        var ofSchemas = this.schema.anyOf || this.schema.oneOf;
        if (Array.isArray(ofSchemas) && (typeof index === 'number') && (index >= 0) && (index < ofSchemas.length)) {
          // create a new object respecting the schema
          var obj = populateJson(this.rootSchema, ofSchemas[index]);
          this.obj = obj;
          this.pobj[this.$vnode.key] = obj;
          //console.info('ofIndex set(' + index + ') pobj[' + this.$vnode.key + '] = ' + JSON.stringify(obj) + ', pobj:', deepCopy(this.pobj));
          this.$forceUpdate();
        }
      }
    },
    ofSchemaLabels: function() {
      var ofSchemas = this.schema.anyOf || this.schema.oneOf;
      if (Array.isArray(ofSchemas)) {
        var rootSchema = this.rootSchema;
        return ofSchemas.map(function(ofSchema, index) {
          var schema = unrefSchema(rootSchema, ofSchema);
          return schema.title || String(index + 1);
        });
      }
      return [];
    },
    ofKey: function() {
      return this.$vnode.key || '';
    },
    ofSchemas: function() {
      var ofSchemas = this.schema.anyOf || this.schema.oneOf;
      return Array.isArray(ofSchemas) ? ofSchemas : [];
    },
    hasOfSchema: function() {
      return (this.schema.type === undefined) && Array.isArray(this.schema.anyOf || this.schema.oneOf);
    },
    ofSchema: function() {
      var ofSchemas = this.schema.anyOf || this.schema.oneOf;
      var index = guessOfSchemaIndex(this.rootSchema, ofSchemas, this.obj);
      //console.info('ofSchema => index: ' + index);
      if (index >= 0) {
        return unrefSchema(this.rootSchema, ofSchemas[index]);
      }
      console.error('Cannot get of schema', this.obj, this.schema);
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
      return (schema.type === 'object') && isObject(schema.properties);
    },
    hasList: function() {
      return (this.schema.type === 'array') && isObject(this.schema.items) && Array.isArray(this.obj);
    },
    isList: function() {
      return (this.schema.type === 'array') && isObject(this.schema.items);
    },
    isListItem: function() {
      return Array.isArray(this.pobj);
    },
    hasContent: function() {
      var type = guessSchemaType(this.rootSchema, this.schema);
      return (type === 'array') || (type === 'object');
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
      if ((this.schema.type === 'array') && isObject(this.schema.items) && Array.isArray(this.obj)) {
        var item = populateJson(this.rootSchema, this.schema.items);
        this.obj.push(item);
        this.$forceUpdate();
      } else {
        console.error('Cannot add item', this.obj, this.schema);
      }
    },
    getItemIndex: function() {
      if (Array.isArray(this.pobj)) {
        var index = this.$vnode.key;
        if (typeof index === 'number') {
          return index;
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
    insertItem: function() {
      var index = this.getItemIndex();
      if (index !== -1) {
        var item = populateJson(this.rootSchema, this.schema);
        this.pobj.splice(index, 0, item);
        this.updateParent();
        // TODO shift open values
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
      //console.log('refresh(), schema:', JSON.stringify(this.schema, undefined, 2), 'obj:', JSON.stringify(this.obj, undefined, 2));
      if (isObject(this.schema) && isObject(this.obj)) {
        // The root object shall be available and of type object
        populateJson(this.schema, this.schema, this.obj);
        //console.info('refresh(), schema:', deepCopy(this.schema), 'obj:', deepCopy(this.obj));
      }
    }
  },
  watch: { 
    obj: {
      immediate: true,
      handler: function() {
        this.refresh(); // the schema shall be set prior the object
      }
    }
  }
});

})();
