local tables = require('jls.util.tables')
local List = require('jls.util.List')
local color = require('jls.util.color')
local hex = require('jls.util.hex')

local ThingProperty = require('lha.ThingProperty')

-- Standard properties, see https://webthings.io/schemas/

local CAPABILITIES = {
  Alarm = 'Alarm',
  AirQualitySensor = 'AirQualitySensor',
  BarometricPressureSensor = 'BarometricPressureSensor',
  BinarySensor = 'BinarySensor',
  Camera = 'Camera',
  ColorControl = 'ColorControl',
  ColorSensor = 'ColorSensor',
  DoorSensor = 'DoorSensor',
  EnergyMonitor = 'EnergyMonitor',
  HumiditySensor = 'HumiditySensor',
  IlluminanceSensor = 'MultiLevelSensor',
  LeakSensor = 'LeakSensor',
  Light = 'Light',
  LightLevelSensor = 'MultiLevelSensor',
  Lock = 'Lock',
  MotionSensor = 'MotionSensor',
  MultiLevelSensor = 'MultiLevelSensor',
  MultiLevelSwitch = 'MultiLevelSwitch',
  OnOffSwitch = 'OnOffSwitch',
  PushButton = 'PushButton',
  SmartPlug = 'SmartPlug',
  SmokeSensor = 'SmokeSensor',
  TemperatureSensor = 'TemperatureSensor',
  Thermostat = 'Thermostat',
  VideoCamera = 'VideoCamera',
}

local PROPERTY_TYPES = {
  AlarmProperty = 'AlarmProperty',
  BarometricPressureProperty = 'BarometricPressureProperty',
  BooleanProperty = 'BooleanProperty',
  DateTimeProperty = 'DateTimeProperty',
  BrightnessProperty = 'BrightnessProperty',
  ColorProperty = 'ColorProperty',
  ColorTemperatureProperty = 'ColorTemperatureProperty',
  HumidityProperty = 'HumidityProperty',
  IlluminanceProperty = 'LevelProperty',
  LevelProperty = 'LevelProperty',
  LightLevelProperty = 'LevelProperty',
  MotionProperty = 'MotionProperty',
  OnOffProperty = 'OnOffProperty',
  PushedProperty = 'PushedProperty',
  SmokeProperty = 'SmokeProperty',
  TemperatureProperty = 'TemperatureProperty',
  ApparentPowerProperty = 'ApparentPowerProperty',
  --InstantaneousPowerProperty = 'InstantaneousPowerProperty',
  --VoltageProperty = 'VoltageProperty',
  CurrentProperty = 'CurrentProperty',
  --FrequencyProperty	 = 'FrequencyProperty',
}

local UNIT_BY_PROPERTY_TYPE = {
  BarometricPressureProperty = 'hectopascal',
  DateTimeProperty = 'date time', -- string ISO 8601
  BrightnessProperty = 'percent',
  ColorTemperatureProperty = 'kelvin',
  HumidityProperty = 'percent',
  IlluminanceProperty = 'lux',
  TemperatureProperty = 'degree celsius',
  ApparentPowerProperty = 'voltampere',
  --InstantaneousPowerProperty = 'watt',
  --VoltageProperty = 'volt',
  CurrentProperty = 'ampere',
  --FrequencyProperty = 'hertz',
}

local AT_TYPE = '@type'

local PROPERTY_METADATA_BY_NAME = {
  on = {
    [AT_TYPE] = PROPERTY_TYPES.OnOffProperty,
    type = 'boolean',
    title = 'On/Off',
    description = 'Whether the thing is turned on'
  },
  brightness = {
    [AT_TYPE] = PROPERTY_TYPES.BrightnessProperty,
    type = 'integer',
    title = 'Brightness',
    description = 'The level of light from 0-100',
    minimum = 0,
    maximum = 100,
    unit = 'percent'
  },
  colorTemperature = {
    [AT_TYPE] = PROPERTY_TYPES.ColorTemperatureProperty,
    type = 'integer',
    title = 'Color temperature',
    description = 'The color temperature in Kelvin',
    unit = 'kelvin',
    minimum = 2000,
    maximum = 6600
  },
  color = {
    [AT_TYPE] = PROPERTY_TYPES.ColorProperty,
    type = 'string',
    title = 'Color',
    description = 'The color as hexadecimal RGB color code'
  },
  temperature = {
    [AT_TYPE] = PROPERTY_TYPES.TemperatureProperty,
    type = 'number',
    title = 'Temperature',
    description = 'The temperature',
    readOnly = true,
    unit = 'degree celsius'
  },
  presence = {
    [AT_TYPE] = PROPERTY_TYPES.MotionProperty,
    type = 'boolean',
    title = 'Motion',
    description = 'Whether a presence is detected',
    readOnly = true
  },
  humidity = {
    [AT_TYPE] = PROPERTY_TYPES.HumidityProperty,
    type = 'number',
    title = 'Relative Humidity',
    description = 'The relative humidity in percent',
    readOnly = true,
    unit = 'percent'
  },
  pressure = {
    [AT_TYPE] = PROPERTY_TYPES.BarometricPressureProperty,
    type = 'number',
    title = 'Atmospheric Pressure',
    description = 'The atmospheric pressure in hectopascal',
    readOnly = true,
    minimum = 800,
    maximum = 1100,
    unit = 'hectopascal'
  },
  lightlevel = {
    [AT_TYPE] = PROPERTY_TYPES.LightLevelProperty,
    type = 'integer',
    title = 'Light Level',
    description = 'The light level in 10000 x log10(Illuminance)',
    minimum = 0,
    readOnly = true
  },
  illuminance = {
    [AT_TYPE] = PROPERTY_TYPES.IlluminanceProperty,
    type = 'integer',
    title = 'Illuminance',
    description = 'The illuminance in lux',
    minimum = 0,
    readOnly = true,
    unit = 'lux'
  },
  pushed = {
    [AT_TYPE] = PROPERTY_TYPES.PushedProperty,
    type = 'boolean',
    title = 'Push Button',
    description = 'Whether the button is pushed',
    readOnly = true
  },
  smoke = {
    [AT_TYPE] = PROPERTY_TYPES.SmokeProperty,
    type = 'boolean',
    title = 'Smoke',
    description = 'Whether smoke is detected',
    readOnly = true
  },
  battery = {
    [AT_TYPE] = PROPERTY_TYPES.LevelProperty,
    type = 'number',
    title = 'Battery Level',
    description = 'The battery level in percent',
    configuration = true,
    readOnly = true,
    unit = 'percent'
  },
  lastseen = {
    [AT_TYPE] = PROPERTY_TYPES.DateTimeProperty,
    type = 'string',
    title = 'Last Seen',
    description = 'The date where the thing was last seen',
    configuration = true,
    readOnly = true,
    unit = 'date time'
  },
  reachable = {
    [AT_TYPE] = PROPERTY_TYPES.BooleanProperty,
    type = 'boolean',
    title = 'Reachable',
    description = 'Whether the thing is reachable',
    configuration = true,
    readOnly = true
  },
  enabled = {
    [AT_TYPE] = PROPERTY_TYPES.OnOffProperty,
    type = 'boolean',
    title = 'Enabled',
    description = 'Whether the thing is enabled',
    configuration = true
  },
  alarm = {
    [AT_TYPE] = PROPERTY_TYPES.AlarmProperty,
    type = 'boolean',
    title = 'Alarm',
    description = 'Whether the alarm is active',
    readOnly = true
  },
  current = {
    [AT_TYPE] = PROPERTY_TYPES.CurrentProperty,
    type = 'number',
    title = 'Current',
    description = 'The current',
    readOnly = true,
    unit = 'ampere'
  },
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
    return List.indexOf(self.type, type) ~= nil
  end

  --- Adds a property to this thing.
  -- Sensor values, configuration parameters, statuses, computation results
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

  --- Returns a description of this thing.
  -- @return this thing as a description.
  function thing:asThingDescription()
    return {
      id = self.id,
      title = self.title,
      description = self.description,
      ['@context'] = self.context,
      [AT_TYPE] = self.type,
      properties = self:getPropertyDescriptions(),
      --events = {},
      --actions = {},
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
    return self:addProperty(name, copyPropertyMetadata(fromMetadata, title, description), initialValue)
  end

  -- Standard properties with default names

  function thing:addPropertyFromName(name, title, description, initialValue)
    local md = PROPERTY_METADATA_BY_NAME[name]
    if md then
      return self:addProperty(name, copyPropertyMetadata(md, title, description), initialValue)
    end
    error('No metadata for property "'..tostring(name)..'"')
  end

  function thing:addPropertiesFromNames(...)
    local names = {...}
    for _, name in ipairs(names) do
      self:addPropertyFromName(name)
    end
    return self
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

  Thing.CAPABILITIES = CAPABILITIES
  Thing.PROPERTY_TYPES = PROPERTY_TYPES
  Thing.PROPERTY_METADATA_BY_NAME = PROPERTY_METADATA_BY_NAME
  Thing.UNIT_BY_PROPERTY_TYPE = UNIT_BY_PROPERTY_TYPE

end)