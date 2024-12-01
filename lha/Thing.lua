local tables = require('jls.util.tables')
local List = require('jls.util.List')

local ThingProperty = require('lha.ThingProperty')
local utils = require('lha.utils')

local PROPERTY_METADATA_BY_NAME = utils.requireJson('lha.properties')

-- Standard properties, see https://webthings.io/schemas/

-- See also https://www.w3.org/TR/wot-thing-description/

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
  --ConcentrationProperty = 'ConcentrationProperty',
  ColorModeProperty = 'ColorModeProperty',
  ColorTemperatureProperty = 'ColorTemperatureProperty',
  --DensityProperty = 'DensityProperty',
  HumidityProperty = 'HumidityProperty',
  IlluminanceProperty = 'LevelProperty',
  --LeakProperty = 'LeakProperty',
  LevelProperty = 'LevelProperty',
  LightLevelProperty = 'LevelProperty',
  --LockedProperty = 'LockedProperty',
  MotionProperty = 'MotionProperty',
  OnOffProperty = 'OnOffProperty',
  --OpenProperty = 'OpenProperty',
  PushedProperty = 'PushedProperty',
  SmokeProperty = 'SmokeProperty',
  TemperatureProperty = 'TemperatureProperty',
  TargetTemperatureProperty = 'TargetTemperatureProperty',
  ApparentPowerProperty = 'ApparentPowerProperty',
  --InstantaneousPowerProperty = 'InstantaneousPowerProperty',
  --VoltageProperty = 'VoltageProperty',
  CurrentProperty = 'CurrentProperty',
  --FrequencyProperty	 = 'FrequencyProperty',
}


--- The Thing class represents a device.
-- See https://webthings.io/api/ https://webthings.io/schemas/
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
    self.links = {}
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

  function thing:toString()
    return string.format('"%s"-"%s"', self.title, self.description)
  end

  function thing:addType(sType)
    if not self:hasType(sType) then
      table.insert(self.type, sType)
    end
    return self
  end

  function thing:hasType(sType)
    return List.indexOf(self.type, sType) ~= 0
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

  function thing:getLinks()
    return self.links
  end

  --- Adds a link.
  -- @tparam table link The link as a table
  -- @tparam string link.href a string representation of a URL
  -- @tparam string link.rel a string describing a relationship
  -- @tparam string link.mediaType a string identifying a media type
  function thing:addLink(link, rel, mediaType)
    local href
    if type(link) == 'table' then
      href = link.href
      rel = link.rel
      mediaType = link.mediaType
    elseif type(link) == 'string' then
      href = link
    end
    table.insert(self.links, {
      href = href,
      rel = rel,
      mediaType = mediaType
    })
  end

  function thing:getLinkDescriptions()
    if #self.links > 0 then
      return List.map(self.links, tables.shallowCopy)
    end
    return nil
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
      --events = {},
      --actions = {},
      links = self:getLinkDescriptions(),
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

end)