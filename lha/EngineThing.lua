local logger = require('jls.lang.logger'):get(...)
local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')
local tables = require('jls.util.tables')
local Date = require('jls.util.Date')

local Thing = require('lha.Thing')

local function getUpdateTime()
  return Date.now()
end

local function isValidValue(value)
  if value == nil then
    return false
  end
  -- valid number is not nan nor +/-inf
  if type(value) == 'number' and (value ~= value or value == math.huge or value == -math.huge) then
    return false
  end
  return true
end

return class.create(Thing, function(engineThing, super)

  function engineThing:initialize(engine, extensionId, thingId, td)
    super.initialize(self, td.title, td.description, td['@type'], td['@context'])
    self:addProperties(td.properties)
    self:setHref('/things/'..thingId)
    self.engine = engine
    self.extensionId = extensionId
    self.thingId = thingId
    self:refreshConfiguration()
  end

  function engineThing:refreshConfiguration()
    self.configuration = tables.getPath(self.engine.root, 'configuration/things/'..self.thingId) or {}
  end

  function engineThing:setArchiveData(archiveData)
    self.configuration.archiveData = archiveData
  end

  function engineThing:isArchiveData()
    return self.configuration.archiveData
  end

  function engineThing:getThingId()
    return self.thingId
  end

  function engineThing:setPropertyValue(name, value)
    local property = self:getProperty(name)
    if property then
      if property:isWritable() then
        self:updatePropertyValue(name, value)
      else
        logger:warn('Cannot set property "%s" for thing %s', name, self)
      end
    else
      logger:warn('Cannot set unknown property "%s" for thing %s', name, self)
    end
  end

  function engineThing:updatePropertyValue(name, value, publish)
    local property = self:getProperty(name)
    if property then
      if isValidValue(value) and property:isValidValue(value) then
        local path = self.thingId..'/'..name
        local prev
        if property:isReadable() then
          if self:isArchiveData() and not property:isConfiguration() then
            self.engine.dataHistory:aggregateValue(path, value)
          end
          prev = property:getValue()
        end
        property:setValue(value)
        if publish or prev ~= value then
          self.engine:publishRootChange('data/'..path, value, prev)
        end
      else
        logger:warn('Invalid value "%s" on update property "%s" for thing %s', value, name, self)
      end
    else
      logger:warn('Cannot update unknown property "%s" for thing %s', name, self)
    end
  end

  function engineThing:asEngineThingDescription()
    local description = self:asThingDescription()
    description.archiveData = self:isArchiveData()
    description.extensionId = self.extensionId
    description.thingId = self.thingId
    return description
  end

end)
