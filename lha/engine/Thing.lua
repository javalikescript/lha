local tables = require('jls.util.tables')
local TableList = require('jls.util.TableList')
local color = require('jls.util.color')
local hex = require('jls.util.hex')
local ThingProperty = require('lha.engine.ThingProperty')
local ThingEvent = require('lha.engine.ThingEvent')

-- Standard properties, see https://webthings.io/schemas/

local PROPERTIES = {
  ON_OFF = {
    ['@type'] = 'OnOffProperty',
    type = 'boolean',
    title = 'On/Off',
    description = 'Whether the thing is turned on'
  },
  BRIGHTNESS = {
    ['@type'] = 'BrightnessProperty',
    type = 'integer',
    title = 'Brightness',
    description = 'The level of light from 0-100',
    minimum = 0,
    maximum = 100,
    unit = 'percent'
  },
  COLOR_TEMPERATURE = {
    ['@type'] = 'ColorTemperatureProperty',
    type = 'integer',
    title = 'Color temperature',
    description = 'The color temperature in Kelvin',
    unit = 'kelvin',
    minimum = 2000,
    maximum = 6600
  },
  COLOR = {
    ['@type'] = 'ColorProperty',
    type = 'string',
    title = 'Color',
    description = 'The color as hexadecimal RGB color code'
  },
  TEMPERATURE = {
    ['@type'] = 'TemperatureProperty',
    type = 'number',
    title = 'Temperature',
    description = 'The temperature',
    readOnly = true,
    unit = 'degree celsius'
  },
  MOTION = {
    ['@type'] = 'MotionProperty',
    type = 'boolean',
    title = 'Motion',
    description = 'Whether a presence is detected',
    readOnly = true
  },
  RELATIVE_HUMIDITY = {
    ['@type'] = 'HumidityProperty',
    type = 'number',
    title = 'Relative Humidity',
    description = 'The relative humidity in percent',
    readOnly = true,
    unit = 'percent'
  },
  ATMOSPHERIC_PRESSURE = {
    ['@type'] = 'BarometricPressureProperty',
    type = 'number',
    title = 'Atmospheric Pressure',
    description = 'The atmospheric pressure in hectopascal',
    readOnly = true,
    minimum = 800,
    maximum = 1100,
    unit = 'hPa'
  },
  LIGHT_LEVEL = {
    ['@type'] = 'LevelProperty',
    type = 'integer',
    title = 'Light Level',
    description = 'The light level in 10000 x log10(Illuminance)',
    minimum = 0,
    readOnly = true
  },
  ILLUMINANCE = {
    ['@type'] = 'LevelProperty',
    type = 'integer',
    title = 'Illuminance',
    description = 'The illuminance in lux',
    minimum = 0,
    readOnly = true,
    unit = 'lux'
  },
  PUSHED = {
    ['@type'] = 'PushedProperty',
    type = 'boolean',
    title = 'Push Button',
    description = 'Whether the button is pushed',
    readOnly = true
  },
  SMOKE = {
    ['@type'] = 'SmokeProperty',
    type = 'boolean',
    title = 'Smoke',
    description = 'Whether smoke is detected',
    readOnly = true
  }
}


--- The Thing class represents a device.
-- See https://iot.mozilla.org/wot/
-- @type Thing
return require('jls.lang.class').create(function(thing)

  --- Creates a new Thing.
  -- @function Thing:new
  -- @param[opt] title The thing's title
  -- @param[opt] description Description of the thing
  -- @param[opt] tType The thing's type(s)
  -- @return a new Thing
  -- @usage
  --local thing = Thing:new()
  function thing:initialize(title, description, tType, context)
    self.title = title or 'Unnamed'
    self.description = description or ''
    if type(tType) == 'string' then
      tType = {tType}
    end
    self.type = tType or {}
    self.context = context or 'https://iot.mozilla.org/schemas'
    self.properties = {}
    self.events = {}
  end

  --- Returns the id of this thing.
  -- An identifier of the device in the form of a URI.
  -- @return the id of this thing.
  function thing:getId()
    return self.id
  end

  function thing:setId(id)
    self.id = id
    return self
  end

  --- Returns the hyperlink reference of this thing.
  -- @return the hyperlink reference of this thing.
  function thing:getHref()
    return self.href
  end

  function thing:setHref(href)
    self.href = href
    return self
  end

  --- Returns the title of this thing.
  -- @return the title of this thing.
  function thing:getTitle()
    return self.title
  end

  function thing:setTitle(title)
    self.title = title
    return self
  end

  --- Returns the description of this thing.
  -- @return the description of this thing.
  function thing:getDescription()
    return self.description
  end

  function thing:setDescription(description)
    self.description = description
    return self
  end

  function thing:addType(type)
    if not self:hasType(type) then
      table.insert(self.type, type)
    end
    return self
  end

  function thing:hasType(type)
    return TableList.indexOf(self.type, type) ~= nil
  end

  --- Adds a property to this thing.
  -- @param name The property's name
  -- @param property The property to add
  -- @return this thing
  function thing:addProperty(name, property, value)
    if type(property) == 'table' then
      if not ThingProperty:isInstance(property) then
        property = ThingProperty:new(property, value)
      end
      self.properties[name] = property
    end
    return self
  end

  function thing:hasProperty(name)
    return self.properties[name] ~= nil
  end

  function thing:addProperties(properties)
    if type(properties) == 'table' then
      for name, property in pairs(properties) do
        self:addProperty(name, property)
      end
    end
    return self
  end

  function thing:getProperties()
    return self.properties
  end

  function thing:getProperty(name)
    return self.properties[name]
  end

  function thing:getPropertyValue(name)
    local property = self.properties[name]
    if property then
      return property:getValue()
    end
  end

  --- Sets a property value.
  -- This method shall be used to modify a property value.
  -- This method allows an extension to request the thing modification.
  -- @param name The property's name
  -- @param value The property value to set
  function thing:setPropertyValue(name, value)
    self:updatePropertyValue(name, value)
  end

  --- Updates a property value.
  -- This method shall be used to update the real property value.
  -- This method allows to record historical values.
  -- @param name The property's name
  -- @param value The property value to update
  function thing:updatePropertyValue(name, value)
    -- should we accept nil value
    local property = self.properties[name]
    if property then
      property:setValue(value)
    end
  end

  function thing:getPropertyDescriptions()
    local descriptions = {}
    for name, property in pairs(self.properties) do
      descriptions[name] = property:asPropertyDescription()
    end
    return descriptions
  end

  function thing:getPropertyValues()
    local props = {}
    for name, property in pairs(self.properties) do
      props[name] = property:getValue()
    end
    return props
  end

  function thing:getPropertyNames()
    local names = {}
    for name in pairs(self.properties) do
      table.insert(names, name)
    end
    return names
  end

  function thing:addEvent(name, event)
    if type(event) == 'table' then
      if not ThingEvent:isInstance(event) then
        event = ThingEvent:new(event)
      end
      self.events[name] = event
    end
    return self
  end

  function thing:getEventDescriptions()
    local descriptions = {}
    for name, event in pairs(self.events) do
      descriptions[name] = event:asEventDescription()
    end
    return descriptions
  end

  --- Returns a description of this thing.
  -- @return this thing as a description.
  function thing:asThingDescription()
    return {
      id = self.id,
      title = self.title,
      description = self.description,
      ['@context'] = self.context,
      ['@type'] = self.type,
      properties = self:getPropertyDescriptions(),
      events = self:getEventDescriptions(),
      actions = {},
      links = {},
      href = self.href
    }
  end

  local function copyPropertyMetadata(fromMetadata, title, description)
    local metadata = tables.shallowCopy(fromMetadata)
    if title then
      metadata.title = title
    end
    if description then
      metadata.description = description
    end
    return metadata
  end

  function thing:addPropertyFrom(name, fromMetadata, title, description, initialValue)
    --return self:addProperty(name, ThingProperty:new(copyPropertyMetadata(fromMetadata, title, description), initialValue))
    return self:addProperty(name, copyPropertyMetadata(fromMetadata, title, description), initialValue)
  end

  -- Standard properties with default names
  -- TODO move to static functions

  function thing:addOnOffProperty(title, description, initialValue)
    return self:addPropertyFrom('on', PROPERTIES.ON_OFF, title, description, initialValue)
  end

  function thing:addBrightnessProperty(title, description, initialValue)
    return self:addPropertyFrom('brightness', PROPERTIES.BRIGHTNESS, title, description, initialValue)
  end

  function thing:addColorTemperatureProperty(title, description, initialValue)
    return self:addPropertyFrom('colorTemperature', PROPERTIES.COLOR_TEMPERATURE, title, description, initialValue)
  end

  function thing:addColorProperty(title, description, initialValue)
    return self:addPropertyFrom('color', PROPERTIES.COLOR, title, description, initialValue)
  end

  function thing:addTemperatureProperty(title, description, initialValue)
    return self:addPropertyFrom('temperature', PROPERTIES.TEMPERATURE, title, description, initialValue)
  end

  function thing:addPresenceProperty(title, description, initialValue)
    return self:addPropertyFrom('presence', PROPERTIES.MOTION, title, description, initialValue)
  end

  function thing:addRelativeHumidityProperty(title, description, initialValue)
    return self:addPropertyFrom('humidity', PROPERTIES.RELATIVE_HUMIDITY, title, description, initialValue)
  end

  function thing:addAtmosphericPressureProperty(title, description, initialValue)
    return self:addPropertyFrom('pressure', PROPERTIES.ATMOSPHERIC_PRESSURE, title, description, initialValue)
  end

  function thing:addLightLevelProperty(title, description, initialValue)
    return self:addPropertyFrom('lightlevel', PROPERTIES.LIGHT_LEVEL, title, description, initialValue)
  end

  function thing:addIlluminanceProperty(title, description, initialValue)
    return self:addPropertyFrom('illuminance', PROPERTIES.ILLUMINANCE, title, description, initialValue)
  end

  function thing:addPushedProperty(title, description, initialValue)
    return self:addPropertyFrom('pushed', PROPERTIES.PUSHED, title, description, initialValue)
  end

  function thing:addSmokeProperty(title, description, initialValue)
    return self:addPropertyFrom('smoke', PROPERTIES.SMOKE, title, description, initialValue)
  end

end, function(Thing)

  function Thing.formatRgbHex(r, g, b)
    return string.format('#%02X%02X%02X', math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
  end

  function Thing.parseRgbHex(rgbHex)
    if string.sub(rgbHex, 1, 1) == '#' then
      rgbHex = string.sub(rgbHex, 2)
    end
    if #rgbHex < 6 then
      return 0, 0, 0
    end
    local rgb = hex.decode(rgbHex)
    local r, g, b = string.byte(rgb, 1, 3)
    return r / 255, g / 255, b / 255
  end

  function Thing.hsvToRgbHex(h, s, v)
    local r, g, b = color.hsvToRgb(h, s, v)
    return Thing.formatRgbHex(r, g, b)
  end

  function Thing.rgbHexToHsv(rgbHex)
    local r, g, b = Thing.parseRgbHex(rgbHex)
    return color.rgbToHsv(r, g, b)
  end

  function Thing.getDefaultValueForType(valueType, value)
    if valueType == 'boolean' then
      return (type(value) == 'boolean') and value or false
    elseif valueType == 'integer' then
      return (type(value) == 'number') and math.floor(value) or 0
    elseif valueType == 'number' then
      return (type(value) == 'number') and value or 0
    elseif valueType == 'string' then
      return (type(value) == 'string') and value or ''
    end
  end

  Thing.PROPERTIES = PROPERTIES
  
end)