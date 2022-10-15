local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local runtime = require('jls.lang.runtime')
local event = require('jls.lang.event')
local File = require('jls.io.File')
local HttpServer = require('jls.net.http.HttpServer')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
local Scheduler = require('jls.util.Scheduler')
local tables = require('jls.util.tables')
local List = require('jls.util.List')
local json = require('jls.util.json')

local HistoricalTable = require('lha.HistoricalTable')
local IdGenerator = require('lha.IdGenerator')
local Extension = require('lha.Extension')
local EngineThing = require('lha.EngineThing')
local restEngine = require('lha.restEngine')
local restThings = require('lha.restThings')
local tableHandler = require('lha.tableHandler')
local utils = require('lha.utils')

return class.create(function(engine)

  function engine:initialize(options)
    self.options = options or {}
    self.things = {}
    self.extensions = {}
    self.idGenerator = IdGenerator:new()

    local rootDir = File:new(options.engine):getAbsoluteFile():getParentFile()
    utils.checkDirectoryOrExit(rootDir)
    logger:fine('rootDir is '..rootDir:getPath())
    self.rootDir = rootDir

    -- setup
    local workDir = utils.getAbsoluteFile(options.work or 'work', rootDir)
    utils.checkDirectoryOrExit(workDir)
    logger:fine('workDir is '..workDir:getPath())
    self.workDir = workDir

    local configurationDir = File:new(workDir, 'configuration')
    logger:fine('configurationDir is '..configurationDir:getPath())
    utils.createDirectoryOrExit(configurationDir)
    self.configHistory = HistoricalTable:new(configurationDir, 'config')

    local dataDir = File:new(workDir, 'data')
    logger:fine('dataDir is '..dataDir:getPath())
    utils.createDirectoryOrExit(dataDir)
    self.dataHistory = HistoricalTable:new(dataDir, 'data')

    self.extensionsDir = File:new(workDir, 'extensions')
    logger:fine('extensionsDir is '..self.extensionsDir:getPath())
    utils.createDirectoryOrExit(self.extensionsDir)

    self.lhaExtensionsDir = nil
    if rootDir:getPath() ~= workDir:getPath() then
      self.lhaExtensionsDir = File:new(rootDir, 'extensions')
      logger:fine('lhaExtensionsDir is '..self.lhaExtensionsDir:getPath())
    end

    self.scriptsDir = File:new(workDir, 'scripts')
    logger:fine('scriptsDir is '..self.scriptsDir:getPath())
    utils.createDirectoryOrExit(self.scriptsDir)

    self.tmpDir = File:new(workDir, 'tmp')
    logger:fine('tmpDir is '..self.tmpDir:getPath())
    utils.createDirectoryOrExit(self.tmpDir)
  end

  function engine:generateId()
    return self.idGenerator:generate()
  end

  function engine:getScriptsDirectory()
    return self.scriptsDir
  end

  function engine:getWorkDirectory()
    return self.workDir
  end

  function engine:getTemporaryDirectory()
    return self.tmpDir
  end

  function engine:createScheduler()
    local scheduler = Scheduler:new()
    local schedules = self.root.configuration.engine.schedule
    -- poll things schedule
    scheduler:schedule(schedules.poll, function()
      self.server:closePendings(3600)
      logger:info('Polling things')
      -- TODO Clean data
      self:publishEvent('poll')
    end)
    -- data schedule
    scheduler:schedule(schedules.data, function()
      logger:info('Archiving data')
      self.dataHistory:save(false)
      self.configHistory:save(false, true)
    end)
    -- configuration schedule
    scheduler:schedule(schedules.configuration, function()
      logger:info('Archiving configuration')
      self.dataHistory:save(true)
      self.configHistory:save(false)
      self:publishEvent('refresh')
    end)
    -- clean schedule
    scheduler:schedule(schedules.clean, function()
      logger:info('Cleaning')
      self.configHistory:save(true)
      self:publishEvent('clean')
    end)
    -- We could expose default scheduler based events such as hourly, daily
    self.scheduler = scheduler
  end

  function engine:startHTTPServer()
    local httpServer = HttpServer:new()
    httpServer:bind(self.options.address, self.options.port):next(function()
      logger:info('Server bound to "'..tostring(self.options.address)..'" on port '..tostring(self.options.port))
    end, function(err) -- could failed if address is in use or hostname cannot be resolved
      logger:warn('Cannot bind HTTP server to "'..tostring(self.options.address)..'" on port '..tostring(self.options.port)..' due to '..tostring(err))
      runtime.exit(98)
    end)
    httpServer:createContext('/engine/(.*)', RestHttpHandler:new(restEngine, {engine = self}))
    httpServer:createContext('/things/?(.*)', RestHttpHandler:new(restThings, {engine = self}))
    httpServer:createContext('/engine/configuration/(.*)', tableHandler, {
      path = 'configuration/',
      editable = true,
      engine = self,
      publish = true
    })
    httpServer:createContext('/engine/tmp/(.*)', FileHttpHandler:new(self.tmpDir, 'rw'))
    self.server = httpServer
  end

  function engine:getHTTPServer()
    return self.server
  end

  function engine:stopHTTPServer()
    self.server:close():next(function()
      logger:info('HTTP Server closed')
    end)
    if self.secureServer then
      self.secureServer:close():next(function()
        logger:info('HTTP Secure Server closed')
      end)
    end
  end

  function engine:startHeartbeat()
    self.eventId = event:setInterval(function()
      self.scheduler:runTo()
      self:publishEvent('heartbeat')
    end, math.floor(self.options.heartbeat * 1000 + 0.5))
  end

  function engine:stopHeartbeat()
    if self.eventId then
      event:clearInterval(self.eventId)
      self.eventId = nil
    end
  end

  function engine:publishRootChange(path, value, previousValue)
    -- tables.mergeValuesByPath
    if type(previousValue) == 'table' then
      local previousValuesByPath = tables.mapValuesByPath(previousValue, path)
      for p, v in pairs(previousValuesByPath) do
        self:publishEvent('change', p, nil, v)
      end
    end
    if type(value) == 'table' then
      local valuesByPath = tables.mapValuesByPath(value, path)
      for p, v in pairs(valuesByPath) do
        self:publishEvent('change', p, v, nil)
      end
    else
      self:publishEvent('change', path, value, previousValue)
    end
  end

  function engine:setRootValue(path, value, publish)
    local previousValue, t, key = tables.setPath(self.root, path, value)
    if publish and previousValue ~= value then
      logger:fine('engine:setRootValue() change('..path..', '..tostring(value)..', '..tostring(previousValue)..')')
      self:publishRootChange(path, value, previousValue)
    end
    return previousValue, t, key
  end

  function engine:setRootValues(path, value, publish, clean)
    if type(value) ~= 'table' then
      return self:setRootValue(path, value, publish)
    end
    local valuesByPath = tables.mapValuesByPath(value, path)
    local currentValue
    if clean then
      currentValue = tables.getPath(self.root, path)
      if type(currentValue) == 'table' then
        local currentValuesByPath = tables.mapValuesByPath(currentValue, path)
        for p in pairs(currentValuesByPath) do
          if not valuesByPath[p] then
            self:setRootValue(p, nil, publish)
          end
        end
      end
    end
    for p, v in pairs(valuesByPath) do
      self:setRootValue(p, v, publish)
    end
    if type(currentValue) == 'table' then
      utils.removeEmptyPaths(currentValue)
    end
  end

  function engine:publishEvent(...)
    self:publishExtensionsEvent(nil, ...)
  end

  function engine:publishEventAsync(...)
    event:setTimeout(function(...)
      self:publishExtensionsEvent(nil, ...)
    end, 0, ...)
  end

  function engine:publishExtensionsEvent(source, ...)
    local name = ...
    if logger:isLoggable(logger.FINER) then
      logger:finer('Publishing Extensions Event '..tostring(name))
    end
    for _, extension in ipairs(self.extensions) do
      if extension ~= source and extension:isActive() then
        if logger:isLoggable(logger.FINE) then
          logger:fine('Publishing event '..tostring(name)..' on extension '..tostring(extension:getId()))
        end
        extension:publishEvent(...)
      end
    end
  end

  function engine:addExtension(extension)
    table.insert(self.extensions, extension)
    return extension
  end

  function engine:removeExtension(extension)
    List.removeFirst(self.extensions, extension)
  end

  function engine:onExtension(id, fn)
    local extension = self:getExtensionById(id)
    if extension then
      fn(extension)
      return true
    end
    return false
  end

  function engine:getExtensionById(id)
    for _, extension in ipairs(self.extensions) do
      if extension:getId() == id then
        return extension
      end
    end
    return nil
  end

  function engine:getExtensions()
    local list = {}
    for _, extension in ipairs(self.extensions) do
      if extension:isActive() then
        table.insert(list, extension)
      end
    end
    return list
  end

  function engine:loadExtensionFromDirectory(dir, type)
    logger:info('Loading extension from directory "'..dir:getPath()..'"')
    local extension = Extension.read(self, dir, type)
    if extension then
      if self:getExtensionById(extension:getId()) then
        logger:info('The extension '..extension:getId()..' already exists')
        return nil
      end
      if extension:loadExtension() then
        self:addExtension(extension)
        logger:info('Extension '..extension:getId()..' loaded')
      else
        logger:info('The extension '..dir:getPath()..' cannot be loaded')
      end
    else
      logger:info('The extension '..dir:getPath()..' is ignored')
    end
  end

  function engine:loadExtensionsFromDirectory(dir, type)
    logger:info('Loading extensions from directory "'..dir:getPath()..'"')
    for _, extensionDir in ipairs(dir:listFiles()) do
      if extensionDir:isDirectory() then
        self:loadExtensionFromDirectory(extensionDir, type)
      end
    end
  end

  function engine:loadScriptExtensions()
    if self.scriptsDir:isDirectory() then
      self:loadExtensionsFromDirectory(self.scriptsDir, 'script')
    end
  end

  function engine:loadOtherExtensions()
    if self.lhaExtensionsDir:isDirectory() then
      self:loadExtensionsFromDirectory(self.lhaExtensionsDir, 'core')
    end
    if self.extensionsDir:isDirectory() then
      self:loadExtensionsFromDirectory(self.extensionsDir, 'extension')
    end
  end

  function engine:loadExtensions()
    self.extensions = {}
    self:loadOtherExtensions()
    self:loadScriptExtensions()
  end

  function engine:getScriptExtensions()
    local scripts = {}
    local others = {}
    for _, extension in ipairs(self.extensions) do
      if extension:getType() == 'script' then
        table.insert(scripts, extension)
      else
        table.insert(others, extension)
      end
    end
    return scripts, others
  end

  function engine:reloadExtensions(full, excludeScripts)
    if excludeScripts then
      local scripts, others = self:getScriptExtensions()
      if full then
        self.extensions = scripts
        self:loadOtherExtensions()
      else
        for _, extension in ipairs(others) do
          extension:restartExtension()
        end
      end
    else
      if full then
        self:publishEvent('shutdown')
        self:loadExtensions()
        self:publishEvent('startup')
        self:publishEvent('things')
      else
        for _, extension in ipairs(self.extensions) do
          extension:restartExtension()
        end
      end
    end
  end

  function engine:reloadScripts(full)
    local scripts, others = self:getScriptExtensions()
    if full then
      self.extensions = others
      self:loadScriptExtensions()
    else
      for _, extension in ipairs(scripts) do
        extension:restartExtension()
      end
    end
  end

  function engine:getDiscoveredThing(extensionId, discoveryKey)
    local extension = self:getExtensionById(extensionId)
    if extension then
      return extension:getDiscoveredThingByKey(discoveryKey)
    end
  end

  -- Adds a thing to this engine.
  function engine:addDiscoveredThing(extensionId, discoveryKey, keepDescription)
    logger:fine('addDiscoveredThing("'..tostring(extensionId)..'", "'..tostring(discoveryKey)..'")')
    local discoveredThing = self:getDiscoveredThing(extensionId, discoveryKey)
    if not discoveredThing then
      logger:info('The thing "'..tostring(extensionId)..'", "'..tostring(discoveryKey)..'" has not been discovered')
      return
    end
    local thing, thingId, thingConfiguration = self:getThingByDiscoveryKey(extensionId, discoveryKey)
    if thing then
      logger:info('The thing "'..tostring(thingId)..'" is already available')
      return thing
    end
    if thingId and thingConfiguration then
      thingConfiguration.active = true
      if not keepDescription then
        thingConfiguration.description = discoveredThing:asThingDescription()
      end
    else
      thingId = self:generateId()
      thingConfiguration = {
        extensionId = extensionId,
        discoveryKey = discoveryKey,
        description = discoveredThing:asThingDescription(),
        active = true,
        archiveData = false
      }
      self.root.configuration.things[thingId] = thingConfiguration
    end
    thing = self:loadThing(thingId, thingConfiguration)
    for name, value in pairs(discoveredThing:getPropertyValues()) do
      thing:updatePropertyValue(name, value)
    end
    logger:info('The thing "'..tostring(thingId)..'" has been added')
    --self:publishEvent('things')
    return thing
  end

  function engine:refreshThingDescription(thingId)
    local thing = self.things[thingId]
    local thingConfiguration = self:getThingConfigurationById(thingId)
    if thing and thingConfiguration then
      logger:info('refreshThingDescription("'..tostring(thingId)..'") not implemented')
    end
  end

  function engine:getThingConfigurationById(thingId)
    return self.root.configuration.things[thingId]
  end

  function engine:disableThing(thingId)
    local thingConfiguration = self:getThingConfigurationById(thingId)
    if thingConfiguration then
      thingConfiguration.active = false
      self.things[thingId] = nil
      --self:publishEvent('things')
    end
  end

  function engine:loadThing(thingId, thingConfiguration)
    local thing = EngineThing:new(self, thingConfiguration.extensionId, thingId, thingConfiguration.description)
    self.things[thingId] = thing
    return thing
  end

  function engine:cleanThings(allInactive)
    local things = self.root.configuration.things
    for thingId, thingConfiguration in pairs(things) do
      local extensionId = thingConfiguration.extensionId
      local discoveryKey = thingConfiguration.discoveryKey
      if not thingConfiguration.active then
        local toRemove = false
        if allInactive then
          toRemove = true
        else
          for tId, tConf in pairs(things) do
            if tId ~= thingId and tConf.extensionId == extensionId and tConf.discoveryKey == discoveryKey then
              toRemove = true
              break
            end
          end
        end
        if toRemove then
          logger:info('thing "'..tostring(thingId)..'" ('..tostring(extensionId)..'/'..tostring(discoveryKey)..') removed')
          things[thingId] = nil
        end
      end
    end
  end

  function engine:getThingValuesFile()
    return File:new(self.workDir, 'things.json')
  end

  function engine:loadThingValues()
    local file = self:getThingValuesFile()
    if file:isFile() then
      local t = json.decode(file:readAll())
      for thingId, values in pairs(t) do
        local thing = self.things[thingId]
        if thing then
          for name, value in pairs(values) do
            thing:updatePropertyValue(name, value)
          end
        end
      end
      file:delete()
    end
  end

  function engine:saveThingValues()
    local t = {}
    for thingId, thing in pairs(self.things) do
      t[thingId] = thing:getPropertyValues()
    end
    local file = self:getThingValuesFile()
    file:write(json.stringify(t, 2))
  end

  function engine:loadThings()
    -- Load the things available in the configuration
    self.things = {}
    self:cleanThings(false)
    for thingId, thingConfiguration in pairs(self.root.configuration.things) do
      if thingConfiguration.active then
        self:loadThing(thingId, thingConfiguration)
      end
    end
  end

  function engine:getThingsByExtensionId(extensionId, useDiscoveryKey)
    local things = {}
    for thingId, thingConfiguration in pairs(self.root.configuration.things) do
      if thingConfiguration.active and thingConfiguration.extensionId == extensionId then
        local thing = self.things[thingId]
        if thing then
          if useDiscoveryKey then
            if thingConfiguration.discoveryKey then
              things[thingConfiguration.discoveryKey] = thing
            end
          else
            things[thingId] = thing
          end
        end
      end
    end
    return things
  end

  function engine:getThingByDiscoveryKey(extensionId, discoveryKey)
    for thingId, thingConfiguration in pairs(self.root.configuration.things) do
      if thingConfiguration.extensionId == extensionId and thingConfiguration.discoveryKey == discoveryKey then
        return self.things[thingId], thingId, thingConfiguration
      end
    end
    return nil
  end

  function engine:getThingDiscoveryKey(thingId)
    local thingConfiguration = self:getThingConfigurationById(thingId)
    if thingConfiguration then
      return thingConfiguration.extensionId, thingConfiguration.discoveryKey
    end
  end

  function engine:getThingById(thingId)
    return self.things[thingId]
  end

  function engine:start(defaultConfig, customConfig)
    logger:info('Starting engine')
    self.configHistory:loadLatest()
    self.dataHistory:loadLatest()
    self.root = {
      configuration = self.configHistory:getLiveTable(),
      data = self.dataHistory:getLiveTable()
    }
    if customConfig then
      if logger:isLoggable(logger.FINE) then
        logger:fine('customConfig: '..require('jls.util.json').stringify(customConfig, 2))
      end
      tables.merge(self.root.configuration, customConfig)
    end
    if defaultConfig then
      tables.merge(self.root.configuration, defaultConfig, true)
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('config: '..require('jls.util.json').stringify(self.root.configuration, 2))
    end
    tables.merge(self.root.configuration, {
      engine = {},
      extensions = {},
      things = {}
    }, true)
    -- save configuration if missing
    if not self.configHistory:hasJsonFile() then
      logger:info('Saving configuration')
      self.configHistory:saveJson()
    end
    self:createScheduler()
    self:startHTTPServer()
    self:startHeartbeat()
    self:loadExtensions()
    self:loadThings()
    self:loadThingValues()
    self.startTime = os.time()
    self:publishEvent('startup')
    self:publishEvent('extensions')
    self:publishEvent('things')
  end

  function engine:stop()
    logger:info('Stopping engine')
    self:stopHeartbeat()
    self.scheduler:removeAllSchedules()
    self:stopHTTPServer()
    self:publishEvent('shutdown')
    self.configHistory:saveJson()
    self.dataHistory:saveJson()
    self:saveThingValues()
  end

end, function(Engine)

  function Engine.launch(arguments)
    local options, customOptions = tables.createArgumentTable(arguments, {
      configPath = 'file',
      emptyPath = 'work',
      helpPath = 'help',
      disableSchemaDefaults = true,
      aliases = {
        h = 'help',
        w = 'work',
        p = 'port',
        ll = 'loglevel',
      },
      schema = utils.requireJson('lha.schema')
    })
    local defaultConfig = options.config
    options.config = nil
    logger:setLevel(options.loglevel)
    local engine = Engine:new(options)
    engine:start(defaultConfig, customOptions.config)
    -- Do we need to poll at startup?
    engine:publishEventAsync('poll')
    return engine
  end

end)