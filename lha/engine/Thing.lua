local tables = require('jls.util.tables')
local ThingProperty = require('lha.engine.ThingProperty')
local ThingEvent = require('lha.engine.ThingEvent')

-- Standard properties

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
		['@type'] = 'LevelProperty',
		type = 'number',
		title = 'Relative Humidity',
		description = 'The relative humidity in percent',
		readOnly = true,
		unit = 'percent'
	},
	ATMOSPHERIC_PRESSURE = {
		['@type'] = 'LevelProperty',
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
		description = 'The light level in Lux',
		minimum = 0,
		readOnly = true
	},
	PUSHED = {
		['@type'] = 'PushedProperty',
		type = 'boolean',
		title = 'Push Button',
		description = 'Whether the button is pushed',
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

	function thing:setDescription(description)
		self.description = description
		return self
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

	function thing:addProperties(properties)
		if type(properties) == 'table' then
			for name, property in pairs(properties) do
				self:addProperty(name, property)
			end
		end
		return self
	end

	function thing:findProperty(name)
		return self.properties[name]
	end

	function thing:getProperty(name)
		local property = self:findProperty(name)
		if property then
			return property:getValue()
		end
	end

	function thing:getPropertyValue(name)
		local property = self:findProperty(name)
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
		local property = self:findProperty(name)
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

	function thing:getProperties()
		local props = {}
		for name, property in pairs(self.properties) do
			props[name] = property:getValue()
		end
		return props
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
			events = {},
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

  function thing:addPushedProperty(title, description, initialValue)
		return self:addPropertyFrom('pushed', PROPERTIES.PUSHED, title, description, initialValue)
  end

end, function(Thing)

	function Thing.hsvToRgb(h, s, v)
		if s <= 0 then
			return v, v, v
		end
		local c = v * s
		local x = (1 - math.abs((h % 2) - 1)) * c
		local m = v - c
		local r, g, b = 0, 0, 0
		if h < 1 then
			r, g, b = c, x, 0
		elseif h < 2 then
			r, g, b = x, c, 0
		elseif h < 3 then
			r, g, b = 0, c, x
		elseif h < 4 then
			r, g, b = 0, x, c
		elseif h < 5 then
			r, g, b = x, 0, c
		else
			r, g, b = c, 0, x
		end
		return r + m, g + m, b + m
	end
	
	function Thing.hsvToRgbHex(h, s, v)
		local r, g, b = Thing.hsvToRgb(h, s, v)
		return string.format('%02X%02X%02X', math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
	end

	function Thing.getDefaultValueForType(type)
		if type == 'boolean' then
			return (type(value) == 'boolean') and value or false
		elseif type == 'integer' then
			return (type(value) == 'number') and math.floor(value) or 0
		elseif type == 'number' then
			return (type(value) == 'number') and value or 0
		elseif type == 'string' then
			return (type(value) == 'string') and value or ''
		end
	end

	Thing.PROPERTIES = PROPERTIES
	
end)