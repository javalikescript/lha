
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

function parseJsonItemValue(type, value) {
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
  template: '<li class="json"><div @click="toggle">' +
    '<span>{{ label }}:</span><br>' +
    '<input v-if="hasStringValue && !hasEnumValues" v-model="value" type="text" placeholder="String Value">' +
    '<input v-if="hasNumberValue && !hasEnumValues" v-model="value" type="number" placeholder="Number Value">' +
    '<label v-if="hasBooleanValue" class="switch big"><input type="checkbox" v-model="value" /><span class="slider"></span></label>' +
    '<select v-if="hasEnumValues && (hasStringValue || hasNumberValue)" v-model="value"><option v-for="ev in enumValues" :value="ev.const">{{ev.title}}</option></select>' +
    '</div>' +
    '<ul class="json-properties" v-show="open" v-if="hasProperties"><li is="json-item" v-for="n in propertyNames" :key="n" :name="n" :pobj="obj" :obj="getProperty(n)" :schema="schema.properties[n]" :root="root"></li></ul>' +
    '<ul class="json-items" v-show="open" v-if="isList">' +
    '<li is="json-item" v-for="(so, i) in obj" :key="i" :name="\'#\' + i" :pobj="obj" :obj="so" :schema="schema.items" :root="root"></li>' +
    '<li><button v-on:click="addItem" title="Add Item"><i class="fa fa-plus"></i></button></li>' +
    '</ul>' +
    '</li>',
  computed: {
    label: function() {
      return this.schema && this.schema.title || this.name || 'Value';
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
      for (var name in this.schema.properties) {
        names.push(name);
      }
      names.sort(strcasecmp);
      return names;
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
        this.pobj[this.$vnode.key] = parseJsonItemValue(this.schema.type, val);
      }
    },
    isList: function() {
      return this.schema && (this.schema.type === 'array') && (typeof this.schema.items === 'object') && Array.isArray(this.obj);
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
    toggle: function() {
      if (this.schema && ((this.schema.type === 'array') || (this.schema.type === 'object'))) {
        this.open = !this.open
      }
    }
  }
});

Vue.component('json', {
  props: ['name', 'obj', 'schema'],
  template: '<ul class="json-root"><json-item :name="name" :obj="obj" :schema="schema" :root="this"></json-item></ul>'
});
