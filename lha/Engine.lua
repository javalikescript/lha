local logger = require('jls.lang.logger'):get(...)
local class = require('jls.lang.class')
local system = require('jls.lang.system')
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
local TableHandler = require('lha.TableHandler')
local utils = require('lha.utils')

return class.create(function(engine)

  function engine:initialize(options)
    self.options = options or {}
    self.things = {}
    self.extensions = {}
    self.idGenerator = IdGenerator:new()

    local rootDir = File:new(options.engine):getAbsoluteFile():getParentFile()
    utils.checkDirectoryOrExit(rootDir)
    logger:fine('rootDir is %s', rootDir)
    self.rootDir = rootDir

    -- setup
    local workDir = utils.getAbsoluteFile(options.work or 'work', rootDir)
    utils.checkDirectoryOrExit(workDir)
    logger:fine('workDir is %s', workDir)
    self.workDir = workDir

    local configurationDir = File:new(workDir, 'configuration')
    logger:fine('configurationDir is %s', configurationDir)
    utils.createDirectoryOrExit(configurationDir)
    self.configHistory = HistoricalTable:new(configurationDir, 'config', {fileMin = 43200})

    local dataDir = File:new(workDir, 'data')
    logger:fine('dataDir is %s', dataDir)
    utils.createDirectoryOrExit(dataDir)
    self.dataHistory = HistoricalTable:new(dataDir, 'data')

    self.extensionsDir = File:new(workDir, 'extensions')
    logger:fine('extensionsDir is %s', self.extensionsDir)
    utils.createDirectoryOrExit(self.extensionsDir)

    self.lhaExtensionsDir = nil
    if rootDir:getPath() ~= workDir:getPath() then
      self.lhaExtensionsDir = File:new(rootDir, 'extensions')
      logger:fine('lhaExtensionsDir is %s', self.lhaExtensionsDir)
    end

    self.scriptsDir = File:new(workDir, 'scripts')
    logger:fine('scriptsDir is %s', self.scriptsDir)
    utils.createDirectoryOrExit(self.scriptsDir)

    self.tmpDir = File:new(workDir, 'tmp')
    logger:fine('tmpDir is %s', self.tmpDir)
    utils.createDirectoryOrExit(self.tmpDir)
  end

  function engine:generateId()
    return self.idGenerator:generate()
  end

  function engine:getExtensionsDirectory()
    return self.extensionsDir
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
      self:publishEvent('refresh')
      self.dataHistory:save(true)
      self.configHistory:save(false)
    end)
    -- clean schedule
    scheduler:schedule(schedules.clean, function()
      logger:info('Cleaning')
      self:publishEvent('clean')
      self.configHistory:save(true)
    end)
    -- We could expose default scheduler based events such as hourly, daily
    self.scheduler = scheduler
  end

  function engine:startHTTPServer()
    local server = HttpServer:new()
    server:bind(self.options.address, self.options.port):next(function()
      logger:info('Server bound to "%s" on port %s', self.options.address, self.options.port)
    end, function(err) -- could failed if address is in use or hostname cannot be resolved
      logger:warn('Cannot bind HTTP server to "%s" on port %s due to %s', self.options.address, self.options.port, err)
      system.exit(98)
    end)
    server:createContext('/engine/(.*)', RestHttpHandler:new(restEngine, {engine = self}))
    server:createContext('/things/?(.*)', RestHttpHandler:new(restThings, {engine = self}))
    server:createContext('/engine/configuration/(.*)', TableHandler:new(self, 'configuration/', true, true))
    server:createContext('/engine/tmp/(.*)', FileHttpHandler:new(self.tmpDir, 'rw'))
    self.server = server
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

  function engine:getHeartbeatDelay()
    return math.floor(self.options.heartbeat * 1000 + 0.5)
  end

  function engine:startHeartbeat()
    self.eventId = event:setInterval(function()
      self.scheduler:runTo()
      self:publishEvent('heartbeat')
    end, self:getHeartbeatDelay())
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
      logger:fine('engine:setRootValue() change(%s, %s, %s)', path, value, previousValue)
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

  function engine:publishExtensionsEvent(source, ...)
    local name = ...
    logger:finest('Publishing Extensions Event %s', name)
    for _, extension in ipairs(self.extensions) do
      if extension ~= source and extension:isActive() then
        logger:finer('Publishing event %s on extension %s', name, extension)
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

  function engine:loadExtensionFromDirectory(dir, typ, deactivate)
    logger:fine('Loading extension from directory "%s"', dir)
    local extension = Extension.read(self, dir, typ)
    if extension then
      if self:getExtensionById(extension:getId()) then
        logger:warn('The extension %s already exists', extension)
        return nil
      end
      if deactivate == true then
        local configuration = extension:getConfiguration()
        configuration.active = false
      end
      if extension:loadExtension() then
        self:addExtension(extension)
        logger:info('Extension %s loaded', extension)
      else
        logger:warn('The extension %s cannot be loaded', dir)
      end
    else
      logger:info('The extension %s is ignored', dir)
    end
  end

  function engine:loadExtensionsFromDirectory(dir, typ, deactivate)
    logger:info('Loading extensions from directory "%s"', dir)
    for _, extensionDir in ipairs(dir:listFiles()) do
      if extensionDir:isDirectory() then
        self:loadExtensionFromDirectory(extensionDir, typ, deactivate)
      end
    end
  end

  function engine:loadScriptExtensions(deactivate)
    if self.scriptsDir:isDirectory() then
      self:loadExtensionsFromDirectory(self.scriptsDir, 'script', deactivate)
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

  function engine:reloadExtensions(full)
    if full then
      self.extensions = List.filter(self.extensions, function(extension)
        return extension:getType() == 'script'
      end)
      self:loadOtherExtensions()
    else
      for _, extension in ipairs(self.extensions) do
        if extension:getType() ~= 'script' then
          extension:restartExtension()
        end
      end
    end
  end

  function engine:reloadScripts(full)
    if full then
      self.extensions = List.filter(self.extensions, function(extension)
        return extension:getType() ~= 'script'
      end)
      self:loadScriptExtensions()
    else
      for _, extension in ipairs(self.extensions) do
        if extension:getType() == 'script' then
          extension:restartExtension()
        end
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
    logger:fine('addDiscoveredThing("%s", "%s")', extensionId, discoveryKey)
    local discoveredThing = self:getDiscoveredThing(extensionId, discoveryKey)
    if not discoveredThing then
      logger:info('The thing "%s", "%s" has not been discovered', extensionId, discoveryKey)
      return
    end
    local thing, thingId, thingConfiguration = self:getThingByDiscoveryKey(extensionId, discoveryKey)
    if thing then
      logger:info('The thing "%s" is already available', thingId)
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
    logger:info('The thing "%s" has been added', thingId)
    --self:publishEvent('things')
    return thing
  end

  function engine:refreshThingDescription(thingId)
    local thing = self.things[thingId]
    local thingConfiguration = self:getThingConfigurationById(thingId)
    if thing and thingConfiguration then
      logger:info('refreshThingDescription("%s") not implemented', thingId)
    end
  end

  function engine:getThingConfigurationById(thingId)
    return self.root.configuration.things[thingId]
  end

  function engine:disableThing(thingId)
    local thingConfiguration = self:getThingConfigurationById(thingId)
    if thingConfiguration then
      logger:info('Disabling thing %s', thingId)
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
            if tId ~= thingId and tConf.active and tConf.extensionId == extensionId and tConf.discoveryKey == discoveryKey then
              toRemove = true -- the inactive thing uses the same discovery key than an active thing
              break
            end
          end
        end
        if toRemove then
          logger:info('thing "%s" (%s/%s) removed', thingId, extensionId, discoveryKey)
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
            local property = thing:getProperty(name)
            if property then
              property:setValue(value)
            end
          end
        end
      end
      file:delete()
    else
      -- if the engine stopped unexpectedly then the values with no history are not available
      -- the main issue is about generic things not archived
      -- the values are not all in the historical data
      -- we could 1) regularly save the values as for the configuration
      -- we could 2) save values in the generic extension
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
            else
              logger:warn('missing discoveryKey for thing %s on extension %s', thing, extensionId)
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
      logger:fine('customConfig: %T', customConfig)
      tables.merge(self.root.configuration, customConfig)
    end
    if defaultConfig then
      tables.merge(self.root.configuration, defaultConfig, true)
    end
    logger:finer('config: %T', self.root.configuration)
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
    self.extensions = {}
    self:loadOtherExtensions()
    self:loadScriptExtensions(self.options.disableScripts)
    self.things = {}
    self:loadThings()
    self:loadThingValues()
    logger:info('Engine started')
    self.startTime = os.time()
    self:publishEvent('startup')
    self:publishEvent('configuration')
    self:publishEvent('extensions')
    self:publishEvent('things')
    self:startHeartbeat()
    logger:info('Engine heartbeat started')
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
    for _, extension in ipairs(self.extensions) do
      extension:cleanExtension()
    end
    self.extensions = {}
    self.things = {}
  end

end, function(Engine)

  function Engine.launch(arguments)
    local options, customOptions = tables.createArgumentTable(arguments, {
      configPath = 'engine',
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
    local customConfig = customOptions.config
    options.config = nil
    local rootLogger = require('jls.lang.logger')
    rootLogger:setConfig(options.loglevel)
    local engine = Engine:new(options)
    engine:start(defaultConfig, customConfig)
    -- Poll before first heartbeat
    event:setTimeout(function()
      logger:info('Start polling')
      engine:publishEvent('poll')
    end, engine:getHeartbeatDelay() // 3)
    return engine
  end

end)