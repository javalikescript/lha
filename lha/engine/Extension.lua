local logger = require('jls.lang.logger')
local File = require('jls.io.File')
local json = require('jls.util.json')
local tables = require('jls.util.tables')
local TableList = require('jls.util.TableList')
local Scheduler = require('jls.util.Scheduler')
local system = require('jls.lang.system')

--- A Extension class.
-- @type Extension
return require('jls.lang.class').create(require('jls.util.EventPublisher'), function(extension, super)

  --- Creates a Extension.
  -- Available events are:
  --  refresh: called depending on the configuration schedule
  --  startup: called after all the extension have been loaded
  --  shutdown: called prior to stop the engine
  --  discover: look for available things for this extension
  -- @function Extension:new
  -- @param engine the engine that holds this extension.
  -- @param dir the extension directory
  -- @tparam string type the extension type.
  function extension:initialize(engine, dir, type)
    super.initialize(self)
    self.engine = engine
    self.dir = dir
    self.type = type or 'default'
    self.id = dir:getName()
    self.loaded = false
    self.manifest = {}
    self.discoveredThings = {}
    self.lastModified = 0
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

  function extension:getEngine()
    return self.engine
  end

  function extension:getType()
    return self.type
  end

  function extension:getDir()
    return self.dir
  end

  function extension:getId()
    return self.id
  end

  function extension:getPrettyName()
    return self.id
  end

  function extension:isLoaded()
    return self.loaded
  end

  function extension:getManifest()
    return self.manifest
  end

  function extension:name()
    return self.manifest.name or self:getPrettyName()
  end

  function extension:description()
    return self.manifest.description or ''
  end

  function extension:version()
    return self.manifest.version or '1.0'
  end

  function extension:toJSON()
    return {
      id = self:getId(),
      type = self:getType(),
      active = self:isActive(),
      loaded = self:isLoaded(),
      name = self:name(),
      description = self:description(),
      version = self:version()
    }
  end

  function extension:getConfiguration()
    local rootTable = self.engine.root
    local pp = 'configuration/extensions/'..self.id
    local pc = tables.getPath(rootTable, pp)
    if not pc then
      pc = {}
      tables.setPath(rootTable, pp, pc)
    end
    -- TODO Cache
    return pc
  end

  --[[
  function extension:applyExtensionConfiguration(value)
    self.engine:setConfigurationValues(self, self:getPath(), value)
  end

  function extension:setExtensionConfiguration(value)
    self.engine:setConfigurationValue(self, self:getPath(), value)
  end
  ]]

  function extension:isActive()
    -- TODO Use cache
    return self.loaded and tables.getPath(self.engine.root, 'configuration/extensions/'..self.id..'/'..'active', false)
  end

  function extension:subscribePollEvent(fn, minIntervalSec)
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

  function extension:fireExtensionEvent(...)
    logger:info('extension:fireExtensionEvent('..TableList.concat(table.pack(...), ', ')..')')
    self.engine:publishExtensionsEvent(self, ...)
  end

  function extension:reloadExtension()
    logger:info('extension:reloadExtension() '..self.id)
    self:cleanExtension()
    self:loadExtension()
  end

  function extension:cleanExtension()
    if logger:isLoggable(logger.FINE) then
      logger:fine('extension:cleanExtension() '..self.id)
    end
    self.scheduler:removeAllSchedules()
    self:unsubscribeAllEvents()
    self.watchers = {}
  end

  function extension:registerSchedule(schedule, fn)
    local scheduleId = self.scheduler:schedule(schedule, fn)
    if self.scheduler:hasSchedule() then
      self:subscribeEvent('heartbeat', self.scheduleFn)
    end
    return scheduleId
  end

  function extension:unregisterSchedule(scheduleId)
    self.scheduler:removeSchedule(scheduleId)
    if not self.scheduler:hasSchedule() then
      self:unsubscribeEvent('heartbeat', self.scheduleFn)
    end
    return scheduleId
  end

  function extension:forgetValue(watcher)
    TableList.removeFirst(self.watchers, watcher)
    if #self.watchers == 0 then
      self:unsubscribeEvent('change', self.changeFn)
    end
  end

  function extension:addWatcher(watcher)
    table.insert(self.watchers, watcher)
    if #self.watchers > 0 then
      self:subscribeEvent('change', self.changeFn)
    end
    return watcher
  end

  function extension:watchPattern(pattern, fn)
    return self:addWatcher({
      pattern = pattern,
      fn = fn
    })
  end

  function extension:watchConfigurationPattern(pattern, fn)
    return self:watchPattern('^configuration/'..pattern, fn)
  end

  function extension:watchValue(path, fn)
    return self:addWatcher({
      path = path,
      fn = fn
    })
  end

  function extension:watchConfigurationValue(path, fn)
    return self:watchValue('configuration/'..path, fn)
  end

  function extension:watchDataValue(path, fn)
    return self:watchValue('data/'..path, fn)
  end

  function extension:cleanDiscoveredThings()
    self.discoveredThings = {}
  end

  -- Adds a discovered thing to this device.
	-- @param key A uniq string identifying the thing in this extension.
	-- @param thing A thing to add.
  function extension:discoverThing(key, thing)
    self.discoveredThings[key] = thing
  end

  function extension:getDiscoveredThingByKey(key)
    return self.discoveredThings[key]
  end

  function extension:listDiscoveredThings()
    local list
    for discoveryKey, thing in pairs(self.discoveredThings) do
      table.insert(list, thing)
    end
    return list
  end

  function extension:getDiscoveredThings()
    return self.discoveredThings
  end

  function extension:getThings()
    return self:getEngine():getThingsByExtensionId(self:getId())
  end

  function extension:refresh()
    local lastModified = self:getLastModified()
    if lastModified > self.lastModified then
      logger:info('reloading extension '..self.id)
      self:reloadExtension()
    elseif lastModified <= 0 then
      self.lastModified = 0
      self:cleanExtension()
    end
  end

  function extension:getManifestFile()
    return File:new(self.dir, 'manifest.json')
  end

  function extension:getScriptFile()
    return File:new(self.dir, self.manifest and self.manifest.script or 'main.lua')
  end

  function extension:loadManifest()
    local manifestFile = self:getManifestFile()
    if manifestFile:isFile() then
      logger:debug('reading manifest for extension '..self:getPrettyName())
      return json.decode(manifestFile:readAll())
    end
  end

  function extension:getLastModified()
    local lastModifiedManifest = self:getManifestFile():lastModified()
    local lastModifiedScript = self:getScriptFile():lastModified()
    if lastModifiedManifest > lastModifiedScript then
      return lastModifiedManifest
    end
    return lastModifiedScript
  end

  function extension:loadScript()
    -- TODO handle dependencies
    local scriptFile = self:getScriptFile()
    if scriptFile:isFile() then
      logger:debug('loading extension '..self:getPrettyName())
      local scriptFn, err = loadfile(scriptFile:getPath())
      if not scriptFn or err then
        logger:warn('Cannot load extension "'..self:getPrettyName()..'" from script "'..scriptFile:getPath()..'" due to '..tostring(err))
      else
        return scriptFn
      end
    else
      logger:warn('Cannot load extension "'..self:getPrettyName()..'" from invalid script file "'..scriptFile:getPath()..'"')
    end
  end

  function extension:loadExtension()
    self.loaded = false
    self.manifest = self:loadManifest()
    local lastModified = self:getLastModified()
    local scriptFn = self:loadScript()
    if scriptFn then
      local status, err = pcall(scriptFn, self)
      if status then
        self.lastModified = lastModified
        self.loaded = true
      else
        logger:warn('Cannot load extension "'..self:getPrettyName()..'" due to "'..tostring(err)..'"')
        self.manifest = {}
      end
    else
      self.manifest = {}
    end
    return self.loaded
  end

end, function(Extension)

  function Extension.read(engine, dir, type)
    if Extension.isValid(engine, dir) then
      return Extension:new(engine, dir, type)
    end
    return nil
  end

  function Extension.isValid(engine, dir)
    local manifestFile = File:new(dir, 'manifest.json')
    if manifestFile:isFile() then
      return true
    end
    return false
  end

end)