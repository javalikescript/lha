local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local tables = require('jls.util.tables')
local EventPublisher = require('jls.util.EventPublisher')
local Scheduler = require('jls.util.Scheduler')
local system = require('jls.lang.system')

--- A EngineItem class.
-- @type EngineItem
return class.create(EventPublisher, function(engineItem, super)

  --- Creates an EngineItem.
  -- @function EngineItem:new
  -- @param engine the engine that holds this item.
  -- @tparam string type the item type.
  -- @tparam string id the item id.
  function engineItem:initialize(engine, type, id)
    super.initialize(self)
    self.engine = engine
    self.id = id
    self.type = type
    self.path = type..'/'..id
    self.started = started
    self.scheduler = Scheduler:new()
    self.scheduleFn = function()
      self.scheduler:runTo()
    end
    self.watchers = {}
    self.changeFn = function(path, value, previousValue)
      for _, watcher in ipairs(self.watchers) do
        if watcher.path and watcher.path == path then
          watcher.fn(value, previousValue, path)
        elseif watcher.pattern then
          local s, _, a, b, c, d, e = string.find(path, watcher.pattern)
          if s then
            watcher.fn(value, previousValue, path, a, b, c, d, e)
          end
        end
      end
    end
  end

  function engineItem:getEngine()
    return self.engine
  end

  function engineItem:getId()
    return self.id
  end

  function engineItem:getPath(path)
    if path then
      return self.path..'/'..path
    end
    return self.path
  end

  function engineItem:getType()
    return self.type
  end

  function engineItem:getConfiguration()
    local rootTable = self.engine.root
    local pp = 'configuration/'..self:getPath()
    local pc = tables.getPath(rootTable, pp)
    if not pc then
      pc = {}
      tables.setPath(rootTable, pp, pc)
    end
    -- TODO Cache
    return pc
  end

  function engineItem:applyItemConfiguration(value)
    self.engine:setConfigurationValues(self, self:getPath(), value)
  end

  function engineItem:setItemConfiguration(value)
    self.engine:setConfigurationValue(self, self:getPath(), value)
  end

  function engineItem:isActive()
    -- TODO Use cache
    return tables.getPath(self.engine.root, 'configuration/'..self:getPath('active'), false)
  end

  function engineItem:isStarted()
    return self.started
  end

  function engineItem:subscribePollEvent(fn, minIntervalSec)
    if minIntervalSec > 0 then
      local lastPoll = system.currentTime()
      return self:subscribeEvent('poll', function(...)
        local date = system.currentTime()
        if date - lastPoll >= minIntervalSec then
          lastPoll = date
          fn(...)
        else
          logger:info('minimum polling interval not reached ('..tostring(minIntervalSec + lastPoll - date)..'s)')
        end
      end)
    end
    return self:subscribeEvent('poll', fn)
  end

  function engineItem:publishItemEvent(source, ...)
    if self ~= source and self:isActive() then
      self:publishEvent(...)
    end
  end

  function engineItem:fireItemEvent(...)
    logger:info('engineItem:fireItemEvent('..tables.concat(table.pack(...), ', ')..')')
    self.engine:publishItemsEvent(self, ...)
  end

  function engineItem:reloadItem()
    logger:info('engineItem:reloadItem() '..self.id)
    self:publishItemEvent(nil, 'shutdown')
    self:cleanItem()
    self:loadItem()
    self:publishItemEvent(nil, 'startup')
  end

  function engineItem:loadItem()
  end

  function engineItem:cleanItem()
    if logger:isLoggable(logger.FINE) then
      logger:fine('engineItem:cleanItem() '..self.id)
    end
    self.scheduler:removeAllSchedules()
    self:unsubscribeAllEvents()
    self.watchers = {}
  end

  function engineItem:registerSchedule(schedule, fn)
    local scheduleId = self.scheduler:schedule(schedule, fn)
    if self.scheduler:hasSchedule() then
      self:subscribeEvent('heartbeat', self.scheduleFn)
    end
    return scheduleId
  end

  function engineItem:unregisterSchedule(scheduleId)
    self.scheduler:removeSchedule(scheduleId)
    if not self.scheduler:hasSchedule() then
      self:unsubscribeEvent('heartbeat', self.scheduleFn)
    end
    return scheduleId
  end

  function engineItem:forgetValue(watcher)
    tables.removeTableValue(self.watchers, watcher, true)
    if #self.watchers == 0 then
      self:unsubscribeEvent('change', self.changeFn)
    end
  end

  function engineItem:addWatcher(watcher)
    table.insert(self.watchers, watcher)
    if #self.watchers > 0 then
      self:subscribeEvent('change', self.changeFn)
    end
    return watcher
  end

  function engineItem:watchPattern(pattern, fn)
    return self:addWatcher({
      pattern = pattern,
      fn = fn
    })
  end

  function engineItem:watchConfigurationPattern(pattern, fn)
    return self:watchPattern('^configuration/'..pattern, fn)
  end

  function engineItem:watchValue(path, fn)
    return self:addWatcher({
      path = path,
      fn = fn
    })
  end

  function engineItem:watchConfigurationValue(path, fn)
    return self:watchValue('configuration/'..path, fn)
  end

  function engineItem:watchDataValue(path, fn)
    return self:watchValue('data/'..path, fn)
  end

  function engineItem:toJSON()
    return {
      id = self:getId(),
      type = self:getType(),
      active = self:isActive()
    }
  end

end)