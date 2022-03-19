
local tables = require('jls.util.tables')
--local logger = require('jls.lang.logger')

--- The ThingProperty class represents a thing property.
-- @type ThingProperty
return require('jls.lang.class').create(function(thingProperty)

  --- Creates a new ThingProperty.
  -- A property object describes an attribute of a Thing and is indexed by a property id.
  -- A property description may include:
  --   - A primitive type (one of null, boolean, object, array, number, integer or string as per [json-schema])
  --   - A semantic @type (a string identifying a type from the linked @context)
  --   - A unit ([SI] unit)
  --   - A title (A string providing a human friendly name)
  --   - A description (A string providing a human friendly description)
  --   - enum (an enumeration of possible values for the property)
  --   - readOnly (A boolean indicating whether or not the property is read-only, defaulting to false)
  --   - A minimum and maximum (numeric values)
  -- @function ThingProperty:new
  -- @param metadata the property metadata, i.e. type, description, unit, etc., as a table
  -- @param[opt] initialValue the property value
  -- @return a new ThingProperty
  -- @usage
  --local property = ThingProperty:new()
  function thingProperty:initialize(metadata, initialValue)
    self.value = initialValue
    self.metadata = metadata or {}
  end

  function thingProperty:isReadOnly()
    return self.metadata and (self.metadata.readOnly == true)
  end

  function thingProperty:getValue()
    return self.value
  end

  function thingProperty:setValue(value)
    self.value = value
    return self
  end

  --- Returns the metadata of this property.
  -- @param[opt] key the metadata key to return.
  -- @return the metadata of this property.
  function thingProperty:getMetadata(key)
    if key then
      return self.metadata[key]
    end
    return self.metadata
  end

  --- Returns a description of this property.
  -- @return this property as a description.
  function thingProperty:asPropertyDescription()
    --return tables.deepCopy(self.metadata)
    return tables.shallowCopy(self.metadata)
  end

end)