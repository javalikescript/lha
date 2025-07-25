local rootLogger = require('jls.lang.logger')
local loader = require('jls.lang.loader')
local event = require('jls.lang.event')
local Exception = require('jls.lang.Exception')
local File = require('jls.io.File')
local json = require('jls.util.json')
local tables = require('jls.util.tables')
local List = require('jls.util.List')
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
  --  configuration: called when the configuration changes
  --  things: called when things change, added, removed, or extension loaded
  --  extensions: called when extensions change
  --  poll: called every 15 minutes(*), to collect things data and discover things
  --  refresh: called every day at midnight(*)
  --  clean: called the first day of the month(*)
  -- (*) depending on the configuration schedule
  -- @function Extension:new
  -- @param engine the engine that holds this extension.
  -- @param dir the extension directory
  -- @param typ the extension type, default to 'default'
  -- @tparam string type the extension type.
  function extension:initialize(engine, dir, typ)
    super.initialize(self)
    self.engine = engine
    self.dir = dir
    self.type = typ or 'default'
    self.id = dir:getName()
    self.loaded = false
    self.manifest = {}
    self.discoveredThings = {}
    self.lastModified = 0
    self.scheduler = Scheduler:new()
    self.watchers = {}
    self.timers = {}
    self.contexts = {}
    self.logger = rootLogger:get('lha.extension.'..self.id)
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
    self:cleanExtension()
    self:connectConfiguration()
  end

  function extension:cleanExtension()
    self.logger:fine('cleanExtension()')
    self.scheduler:removeAllSchedules()
    self:unsubscribeAllEvents()
    self:subscribeEvent('error', function(reason, eventName)
      self.logger:warn('Error while handling event "%s" on extension "%s": "%s"', eventName, self.id, reason)
    end)
    self:clearTimers()
    self:clearContexts()
    self.watchers = {}
  end

  function extension:getEngine()
    return self.engine
  end

  function extension:getLogger()
    return self.logger
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

  function extension:toString()
    return string.format('%s %s %s', self.id, self.type, self.manifest.name)
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
    return self.manifest.name or self.id
  end

  function extension:description()
    return self.manifest.description or ''
  end

  function extension:version()
    return self.manifest.version or '1.0'
  end

  function extension:readme()
    return self.manifest.readme or 'readme.md'
  end

  function extension:isActive()
    return self.loaded and self.configuration.active == true
  end

  function extension:setActive(value)
    local target = value == true
    if self.loaded and self.configuration.active ~= target then
      self.configuration.active = target
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
    self.logger:finest('initializing configuration')
    local configuration = self:getConfiguration()
    if self.manifest.config then
      -- we do not want to validate the config against the schema
      tables.merge(configuration, self.manifest.config, true)
    end
    if self.manifest.schema then
      local defaultValues, err = tables.getSchemaValue(self.manifest.schema, {}, true)
      if defaultValues then
        tables.merge(configuration, defaultValues, true)
      elseif self.logger:isLoggable(self.logger.WARN) then
        self.logger:warn('unable to get default values from schema, due to %s', err)
        self.logger:warn('schema is %T', self.manifest.schema)
      end
    end
    if next(configuration) == nil then
      -- ensure that configuration is detected as an object by adding a property
      configuration.active = false
    end
  end

  function extension:require(name, isCore)
    local dir = self.dir
    if isCore then
      dir = self.engine.lhaExtensionsDir
    end
    return loader.load(name, dir:getPath())
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
        self.logger:info('minimum polling interval not reached (%ds)', minIntervalSec + lastPollSec - pollSec)
      end
    end)
  end

  function extension:addContext(...)
    local server = self.engine:getHTTPServer()
    local context = server:createContext(...)
    table.insert(self.contexts, context)
    if #self.contexts == 1 then
      self:subscribeEventOnce('shutdown', function()
        self:clearContexts()
      end)
    end
    return context
  end

  function extension:clearContexts()
    local server = self.engine:getHTTPServer()
    for _, context in ipairs(self.contexts) do
      server:removeContext(context)
    end
    self.contexts = {}
  end

  function extension:fireExtensionEvent(...)
    if self.logger:isLoggable(self.logger.INFO) then
      self.logger:info('fireExtensionEvent(%s)', List.join(table.pack(...), ', '))
    end
    self.engine:publishExtensionsEvent(self, ...)
  end

  function extension:reloadExtension()
    self.logger:info('reloading extension')
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
      self:publishEvent('configuration')
      self:publishEvent('things')
    end
  end

  function extension:registerSchedule(schedule, fn)
    if not self.scheduler:hasSchedule() then
      self.eventId = self:subscribeEvent('heartbeat', function()
        self.scheduler:runTo()
      end)
    end
    local scheduleId = self.scheduler:schedule(schedule, fn)
    return scheduleId
  end

  function extension:unregisterSchedule(scheduleId)
    self.scheduler:removeSchedule(scheduleId)
    if not self.scheduler:hasSchedule() then
      self:unsubscribeEvent('heartbeat', self.eventId)
      self.eventId = nil
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

  function extension:putTimer(id, fn, delay)
    if self.timers[id] then
      return id
    end
    return self:setTimer(fn, delay, id)
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
        self.logger:warn('unknown thing for id "%s"', thingId)
      end
    else
      self.logger:warn('invalid path "%s"', path)
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
        self.logger:warn('unknown thing for id "%s"', thingId)
      end
    else
      self.logger:warn('invalid path "%s"', path)
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
    self.logger:fine('the thing "%s" has been discovered', key)
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
        self.logger:fine('the thing "%s" is now managed by the engine', key)
        for name, value in pairs(discoveredThing:getPropertyValues()) do
          thing:updatePropertyValue(name, value)
        end
        self.discoveredThings[key] = nil
      else
        return discoveredThing
      end
    elseif not thing and create then
      local createdThing = create()
      if createdThing then
        self:discoverThing(key, createdThing)
        if previousThing then
          for name, value in pairs(previousThing:getPropertyValues()) do
            createdThing:updatePropertyValue(name, value)
          end
        end
        return createdThing
      end
    end
    return thing
  end

  --- Notifies a message to the user.
  function extension:notify(message, sessionId)
    self:getEngine():publishEvent('notification', message, sessionId)
  end

  function extension:refresh()
    local lastModified = self:getLastModified()
    if lastModified > self.lastModified then
      self.logger:info('reloading extension')
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
    local script = self.manifest and self.manifest.script or 'init.lua'
    local path = string.match(script, '^//(.+)$')
    if path then
      return File:new(self.engine.lhaExtensionsDir, path)
    end
    return File:new(self.dir, script)
  end

  function extension:loadManifest()
    local manifestFile = self:getManifestFile()
    if manifestFile:isFile() then
      self.logger:finest('reading manifest')
      local manifest = json.decode(manifestFile:readAll())
      local m, err = tables.getSchemaValue(schema, manifest, true)
      if m then
        if not manifest.schema then
          m.schema = nil
        end
        return m
      end
      self.logger:warn('Invalid extension manifest, %s', err)
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
      self.logger:finest('loading extension')
      local env = setmetatable({}, { __index = _G })
      local scriptFn, err = loadfile(scriptFile:getPath(), 't', env)
      if not scriptFn or err then
        self.logger:warn('Cannot load extension from script "%s" due to %s', scriptFile, err)
      else
        return scriptFn
      end
    else
      self.logger:warn('Cannot load extension from invalid script file "%s"', scriptFile)
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
        self.logger:warn('Cannot load extension due to %s', err)
        self.manifest = {}
      end
    else
      self.manifest = {}
    end
    return self.loaded
  end

end, function(Extension)

  function Extension.read(engine, dir, typ)
    if Extension.isValid(engine, dir) then
      return Extension:new(engine, dir, typ)
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