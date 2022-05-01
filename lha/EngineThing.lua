local logger = require('jls.lang.logger')
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
    self.connected = false
    self.setterFn = false
    self.lastupdated = 0
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
    if not property or property:isReadOnly() then
      logger:warn('Cannot update property "'..name..'"')
      return
    end
    if self.setterFn then
      local r = self:setterFn(name, value)
      if r ~= nil then
        if Promise:isInstance(r) then
          r:next(function(v)
            if v ~= nil then
              super.setPropertyValue(self, name, v)
            end
          end)
        else
          super.setPropertyValue(self, name, r)
        end
      end
    else
      super.setPropertyValue(self, name, value)
    end
  end

  function engineThing:updatePropertyValue(name, value)
    if isValidValue(value) then
      self.lastupdated = getUpdateTime()
      local property = self:getProperty(name)
      if property then
        local path = self.thingId..'/'..name
        local prev
        if self:isArchiveData() and not property:isConfiguration() then
          prev = self.engine.dataHistory:aggregateValue(path, value)
        else
          prev = property:getValue()
        end
        if prev ~= value then
          self.engine:publishRootChange('data/'..path, value, prev)
        end
      end
      super.updatePropertyValue(self, name, value)
    else
      logger:warn('Invalid number value on update property "'..name..'"')
    end
  end

  function engineThing:connect(setterFn)
    self.connected = true
    self.setterFn = (type(setterFn) == 'function') and setterFn or false
    return self
  end

  function engineThing:disconnect()
    local setterFn = self.setterFn
    self.connected = false
    self.setterFn = false
    return setterFn
  end

  function engineThing:isConnected()
    return self.connected
  end

  function engineThing:isReachable(since, time)
    since = since or 3600000
    time = time or Date.now()
    return (time - self.lastupdated) < since
  end

  function engineThing:asEngineThingDescription()
    local description = self:asThingDescription()
    description.archiveData = self:isArchiveData()
    --description.connected = self:isConnected()
    --description.reachable = self:isReachable()
    description.extensionId = self.extensionId
    description.thingId = self.thingId
    return description
  end

end)
