
local tables = require('jls.util.tables')
--local logger = require('jls.lang.logger')

--- The ThingProperty class represents a thing property.
-- @type ThingProperty
return require('jls.lang.class').create(function(thingProperty)

  --- Creates a new ThingProperty.
  -- A property object describes an attribute of a Thing and is indexed by a property id.
  -- A property description may include:
  --   - A primitive `type` (one of null, boolean, object, array, number, integer or string as per [json-schema])
  --   - A semantic `@type` (a string identifying a type from the linked @context)
  --   - A `unit` ([SI] unit)
  --   - A `title` (A string providing a human friendly name)
  --   - A `description` (A string providing a human friendly description)
  --   - `enum` (an enumeration, list, of possible values for the property)
  --   - A `minimum` and `maximum` (numeric values)
  --   - `readOnly` (A boolean indicating whether or not the property is read-only, defaulting to false)
  --   - `writeOnly` (A boolean indicating whether or not the property is write-only, defaulting to false)
  --   - `configuration` (A boolean indicating whether or not the property is a configuration, defaulting to false)
  -- @function ThingProperty:new
  -- @param metadata the property metadata, i.e. type, description, unit, etc., as a table
  -- @param[opt] initialValue the property value
  -- @return a new ThingProperty
  -- @usage
  --local property = ThingProperty:new()
  function thingProperty:initialize(metadata, initialValue)
    self.metadata = metadata or {}
    self.value = initialValue
  end

  function thingProperty:isReadOnly()
    return self.metadata.readOnly == true
  end

  function thingProperty:isWriteOnly()
    return self.metadata.writeOnly == true
  end

  function thingProperty:isReadable()
    return self.metadata.writeOnly ~= true
  end

  function thingProperty:isWritable()
    return self.metadata.readOnly ~= true
  end

  function thingProperty:isConfiguration()
    return self.metadata.configuration == true
  end

  function thingProperty:getType()
    return self.metadata.type
  end

  local function checkEnum(metadata, value)
    if metadata.enum then
      for _, v in ipairs(metadata.enum) do
        if v == value then
          return true
        end
      end
      return false
    end
    return true
  end

  local function checkInterval(metadata, value)
    if metadata.minimum and value < metadata.minimum then
      return false
    end
    if metadata.maximum and value > metadata.maximum then
      return false
    end
    return checkEnum(metadata, value)
  end

  function thingProperty:isValidValue(value)
    local pt = self.metadata.type
    if pt == 'boolean' then
      return pt == type(value)
    elseif pt == 'number' then
      if pt == type(value) then
        return checkInterval(self.metadata, value)
      end
    elseif pt == 'integer' then
      if math.type(value) == 'integer' then
        return checkInterval(self.metadata, value)
      end
    elseif pt == 'string' then
      if pt == type(value) then
        return checkEnum(self.metadata, value)
      end
    elseif pt == 'object' or pt == 'array' then
      return type(value) == 'table'
    elseif pt == nil then
      return true
    end
    return false
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
