
local ThingProperty = require('lha.engine.ThingProperty')
local ThingEvent = require('lha.engine.ThingEvent')

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

end)