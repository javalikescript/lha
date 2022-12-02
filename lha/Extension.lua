local logger = require('jls.lang.logger')
local loader = require('jls.lang.loader')
local event = require('jls.lang.event')
local Exception = require('jls.lang.Exception')
local File = require('jls.io.File')
local json = require('jls.util.json')
local tables = require('jls.util.tables')
local List = require('jls.util.List')
local Map = require('jls.util.Map')
local Scheduler = require('jls.util.Scheduler')
local system = require('jls.lang.system')

local utils = require('lha.utils')
local schema = utils.requireJson('lha.schema-extension')

--- A Extension class.
-- @type Extension
return require('jls.lang.class').create(require('jls.util.EventPublisher'), function(extension, super)

  --- Creates a Extension.
  -- Available events are:
  --  startup: called after all the extension have been loaded
  --  shutdown: called prior to stop the engine, or when reloading an extenstion
  --  things: called when things change, added, removed, or extension loaded
  --  extensions: called when extensions change
  --  poll: called depending on the configuration schedule, to collect things data and discover things
  --  refresh: called depending on the configuration schedule
  --  clean: called depending on the configuration
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
    self.timers = {}
    self:cleanExtension()
    self:connectConfiguration()
  end

  function extension:cleanExtension()
    if logger:isLoggable(logger.FINE) then
      logger:fine('extension:cleanExtension() '..self.id)
    end
    self.scheduler:removeAllSchedules()
    self:unsubscribeAllEvents()
    self:subscribeEvent('error', function(reason, eventName)
      logger:warn('Error while handling event "%s" on extension "%s": "%s"', eventName, self.id, reason)
    end)
    self:clearTimers()
    self.watchers = {}
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

  function extension:getManifest(key)
    if key then
      return self.manifest[key]
    end
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

  function extension:isActive()
    return self.loaded and self.configuration.active
  end

  function extension:setActive(value)
    local target = value == true
    if self.loaded and self.configuration.active ~= target then
      self.configuration.active = target
      self:fireExtensionEvent('extensions')
    end
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

  function extension:connectConfiguration()
    self.configuration = tables.mergePath(self.engine.root, 'configuration/extensions/'..self.id, {})
  end

  function extension:getConfiguration()
    return self.configuration
  end

  function extension:initConfiguration()
    if logger:isLoggable(logger.FINEST) then
      logger:finest('initializing configuration for extension '..self:getPrettyName())
    end
    local configuration = self:getConfiguration()
    if self.manifest.config then
      -- we do not want to validate the config against the schema
      tables.merge(configuration, self.manifest.config, true)
    end
    if self.manifest.schema then
      local defaultValues, err = tables.getSchemaValue(self.manifest.schema, {}, true)
      if defaultValues then
        tables.merge(configuration, defaultValues, true)
      elseif logger:isLoggable(logger.WARN) then
        logger:warn('unable to get default values from schema, due to '..tostring(err))
        logger:warn('schema :'..json.stringify(self.manifest.schema, 2))
      end
    end
    if next(configuration) == nil then
      -- ensure that configuration is detected as an object by adding a property
      configuration.active = false
    end
  end

  function extension:require(name, base)
    return loader.load(name, base and self.dir:getParent() or self.dir:getPath())
  end

  function extension:subscribePollEvent(fn, minIntervalSec, lastPollSec)
    if type(minIntervalSec) ~= 'number' or minIntervalSec <= 0 then
      return self:subscribeEvent('poll', fn)
    end
    if type(lastPollSec) ~= 'number' then
      -- if the last poll instant is unknown then we must be sure to respect the interval
      lastPollSec = system.currentTime()
    end
    return self:subscribeEvent('poll', function(...)
      local pollSec = system.currentTime()
      if pollSec - lastPollSec >= minIntervalSec then
        lastPollSec = pollSec
        fn(...)
      else
        if logger:isLoggable(logger.INFO) then
          logger:info('minimum polling interval not reached ('..tostring(minIntervalSec + lastPollSec - pollSec)..'s)')
        end
      end
    end)
  end

  function extension:fireExtensionEvent(...)
    if logger:isLoggable(logger.INFO) then
      logger:info('extension:fireExtensionEvent('..List.join(table.pack(...), ', ')..')')
    end
    self.engine:publishExtensionsEvent(self, ...)
  end

  function extension:reloadExtension()
    if logger:isLoggable(logger.INFO) then
      logger:info('extension:reloadExtension() '..self.id)
    end
    self:cleanExtension()
    self:loadExtension()
  end

  function extension:restartExtension()
    if self:isActive() then
      self:publishEvent('shutdown')
    end
    self:reloadExtension()
    if self:isActive() then
      self:publishEvent('startup')
      self:publishEvent('things')
    end
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

  function extension:setTimer(fn, delay, id)
    local timerId = event:setTimeout(function()
      self.timers[id] = nil
      fn()
    end, delay)
    id = id or timerId
    self:clearTimer(id)
    self.timers[id] = timerId
    return id
  end

  function extension:clearTimer(id)
    local timerId = self.timers[id]
    if timerId then
      event:clearTimeout(timerId)
      self.timers[id] = nil
    end
  end

  function extension:clearTimers()
    local timers = self.timers
    self.timers = {}
    for _, id in pairs(timers) do
      event:clearTimeout(id)
    end
  end

  function extension:forgetValue(watcher)
    List.removeFirst(self.watchers, watcher)
    if #self.watchers == 0 then
      self:unsubscribeEvent('change', self.changeFn)
    end
  end

  function extension:addWatcher(watcher)
    table.insert(self.watchers, watcher)
    if #self.watchers == 1 then
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

  function extension:getConfigurationValue(path)
    return tables.getPath(self.engine.root, 'configuration/'..path)
  end

  function extension:setConfigurationValue(path, value)
    self.engine:setRootValues('configuration/'..path, value, true)
  end

  function extension:getDataValue(path)
    local thingId, propertyName = string.match(path, '^([^/]+)/([^/]+)$')
    if thingId then
      local thing = self.engine:getThingById(thingId)
      if thing then
        return thing:getPropertyValue(propertyName)
      else
        logger:warn('unknown thing for id "'..tostring(thingId)..'"')
      end
    else
      logger:warn('invalid path "'..tostring(path)..'"')
    end
    return nil
  end

  function extension:setDataValue(path, value)
    local thingId, propertyName = string.match(path, '^([^/]+)/([^/]+)$')
    if thingId then
      local thing = self.engine:getThingById(thingId)
      if thing then
        thing:setPropertyValue(propertyName, value)
      else
        logger:warn('unknown thing for id "'..tostring(thingId)..'"')
      end
    else
      logger:warn('invalid path "'..tostring(path)..'"')
    end
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

  --- Removes all the discovered things.
  function extension:cleanDiscoveredThings()
    self.discoveredThings = {}
  end

  --- Adds a discovered thing to this extension.
  -- @param key A uniq string identifying the thing in this extension.
  -- @param thing A thing to add.
  function extension:discoverThing(key, thing)
    if logger:isLoggable(logger.FINE) then
      logger:fine('the thing "'..key..'" on extension '..self.id..' has been discovered')
    end
    self.discoveredThings[key] = thing
  end

  --- Returns the discovered thing associated to the discovery key.
  function extension:getDiscoveredThingByKey(key)
    return self.discoveredThings[key]
  end

  --- Removes and returns the discovered thing associated to the discovery key.
  function extension:removeDiscoveredThingByKey(key)
    local discoveredThing = self.discoveredThings[key]
    if discoveredThing ~= nil then
      self.discoveredThings[key] = nil
    end
    return discoveredThing
  end

  --- Returns the list of discovered things.
  function extension:listDiscoveredThings()
    local list
    for _, thing in pairs(self.discoveredThings) do
      table.insert(list, thing)
    end
    return list
  end

  --- Returns the map of discovered things by their discovery key.
  function extension:getDiscoveredThings()
    return self.discoveredThings
  end

  --- Returns the map of things by their discovery key.
  function extension:getThingsByDiscoveryKey()
    -- We may cache this map and refresh on things event
    return self:getEngine():getThingsByExtensionId(self:getId(), true)
  end

  --- Returns the map of things by their id.
  function extension:getThings()
    return self:getEngine():getThingsByExtensionId(self:getId())
  end

  --- Returns the thing associated to the discovery key.
  function extension:getThingByDiscoveryKey(discoveryKey)
    return self:getEngine():getThingByDiscoveryKey(self:getId(), discoveryKey)
  end

  --- Returns the thing associated to the discovery key.
  -- The thing is removed from discovery, if managed by the engine.
  -- The thing is created and discovered, if necessary.
  -- @tparam string key The uniq string identifying the thing in this extension.
  -- @tparam function create The function to call in order to create the thing.
  -- @return the thing associated to the discovery key.
  function extension:syncDiscoveredThingByKey(key, create, previousThing)
    local discoveredThing = self.discoveredThings[key]
    local thing = self:getThingByDiscoveryKey(key)
    if discoveredThing then
      if thing then
        if logger:isLoggable(logger.FINE) then
          logger:fine('the thing "'..key..'" on extension '..self.id..' is now managed by the engine')
        end
        for name, value in pairs(discoveredThing:getPropertyValues()) do
          thing:updatePropertyValue(name, value)
        end
        self.discoveredThings[key] = nil
      else
        return discoveredThing
      end
    elseif not thing and create then
      local createdThing = create()
      self:discoverThing(key, createdThing)
      if previousThing then
        for name, value in pairs(previousThing:getPropertyValues()) do
          createdThing:updatePropertyValue(name, value)
        end
      end
      return createdThing
    end
    return thing
  end

  function extension:refresh()
    local lastModified = self:getLastModified()
    if lastModified > self.lastModified then
      if logger:isLoggable(logger.INFO) then
        logger:info('reloading extension '..self.id)
      end
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
    return File:new(self.dir, self.manifest and self.manifest.script or 'init.lua')
  end

  function extension:loadManifest()
    local manifestFile = self:getManifestFile()
    if manifestFile:isFile() then
      if logger:isLoggable(logger.FINEST) then
        logger:finest('reading manifest for extension '..self:getPrettyName())
      end
      local manifest = json.decode(manifestFile:readAll())
      local m, err = tables.getSchemaValue(schema, manifest, true)
      if m then
        return m
      end
      if logger:isLoggable(logger.WARN) then
        logger:warn('Invalid extension manifest, '..tostring(err))
      end
      return manifest
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
      if logger:isLoggable(logger.FINEST) then
        logger:finest('loading extension '..self:getPrettyName())
      end
      local env = setmetatable({}, { __index = _G })
      local scriptFn, err = loadfile(scriptFile:getPath(), 't', env)
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
      self:initConfiguration()
      local status, err = Exception.pcall(scriptFn, self)
      if status then
        self.lastModified = lastModified
        self.loaded = true
      else
        logger:warn('Cannot load extension "%s" due to %s', self:getPrettyName(), err)
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