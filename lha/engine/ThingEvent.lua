
local tables = require('jls.util.tables')
--local logger = require('jls.lang.logger')

--- The ThingEvent class represents a thing event.
-- @type ThingEvent
return require('jls.lang.class').create(function(thingEvent)

	--- Creates a new ThingEvent.
	-- A event object describes an attribute of a Thing and is indexed by a event id.
	-- A event description may include:
	--   - A primitive type (one of null, boolean, object, array, number, integer or string as per [json-schema])
	--   - A semantic @type (a string identifying a type from the linked @context)
	--   - A unit ([SI] unit)
	--   - A title (A string providing a human friendly name)
	--   - A description (A string providing a human friendly description)
	--   - enum (an enumeration of possible values for the event)
	--   - readOnly (A boolean indicating whether or not the event is read-only, defaulting to false)
	--   - A minimum and maximum (numeric values)
	-- @function ThingEvent:new
	-- @param metadata the event metadata, i.e. type, description, unit, etc., as a table
	-- @return a new ThingEvent
	-- @usage
	--local event = ThingEvent:new()
	function thingEvent:initialize(metadata)
		self.metadata = metadata or {}
	end

	--- Returns the metadata of this event.
	-- @return the metadata of this event.
	function thingEvent:getMetadata()
		return self.metadata
	end

	--- Returns a description of this event.
	-- @return this event as a description.
	function thingEvent:asEventDescription()
		--return tables.deepCopy(self.metadata)
		return tables.shallowCopy(self.metadata)
	end

end)