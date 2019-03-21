local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local File = require('jls.io.File')
local json = require('jls.util.json')
local http = require('jls.net.http')
local httpHandler = require('jls.net.http.handler')
local Scheduler = require('jls.util.Scheduler')
local runtime = require('jls.lang.runtime')
local event = require('jls.lang.event')
local tables = require('jls.util.tables')
local Date = require('jls.util.Date')
local HistoricalTable = require('lha.engine.HistoricalTable')
local Device = require('lha.engine.Device')
local Plugin = require('lha.engine.Plugin')
local Script = require('lha.engine.Script')
local ZipFile = require('jls.util.zip.ZipFile')


local function createDirectoryOrExit(dir)
  if not dir:isDirectory() then
    if dir:mkdir() then
      logger:info('created directory '..dir:getPath())
    else
      logger:warn('unable to create directory '..dir:getPath())
      runtime.exit(1)
    end
  end
end

local function cleanDirectory(dir)
  if dir:isDirectory() then
    return dir:deleteAll()
  end
  return dir:mkdir()
end

local function writeCertificateAndPrivateKey(certFile, pkeyFile, commonName)
  local secure = require('jls.net.secure')
  local cacert, pkey = secure.createCertificate({
    commonName = commonName or 'localhost'
  })
  local cacertPem  = cacert:export('pem')
  -- pkey:export('pem', true, 'secret') -- format='pem' raw=true,  passphrase='secret'
  local pkeyPem  = pkey:export('pem')
  certFile:write(cacertPem)
  pkeyFile:write(pkeyPem)
end

local function historicalDataHandler(exchange)
  if httpHandler.methodAllowed(exchange, 'GET') then
    local context = exchange:getContext()
    local engine = context:getAttribute('engine')
    local path = exchange:getRequestArguments()
    local request = exchange:getRequest()
    local toTime = tonumber(request:getHeader("X-TO-TIME"))
    if toTime then
      toTime = toTime * 1000
    end
    local period = tonumber(request:getHeader("X-PERIOD"))
    if not period then
      local t
      local tp = string.gsub(path, '/$', '')
      if toTime then
        t = engine.dataHistory:getTableAt(toTime) or {}
      else
        t = engine.root.historicalData
      end
      httpHandler.replyJson(exchange:getResponse(), {
        value = tables.getPath(t, '/'..tp)
      })
      return
    end
    local fromTime = tonumber(request:getHeader("X-FROM-TIME"))
    local subPaths = request:getHeader("X-PATHS")
    if logger:isLoggable(logger.FINE) then
      logger:fine('process historicalData request '..tostring(fromTime)..' - '..tostring(toTime)..' / '..tostring(period)..' on "'..tostring(path)..'"')
    end
    period = period * 1000
    if not toTime then
      toTime = Date.now()
    end
    if fromTime then
      fromTime = fromTime * 1000
    else
      -- use 100 data points by default
      fromTime = toTime - period * 100
    end
    if fromTime < toTime and ((toTime - fromTime) / period) < 10000 then
      local result
      if subPaths then
        local paths = tables.split(subPaths, ',')
        for i = 1, #paths do
          paths[i] = path..paths[i]
        end
        result = engine.dataHistory:loadMultiValues(fromTime, toTime, period, paths)
      else
        result = engine.dataHistory:loadValues(fromTime, toTime, period, path)
      end
      httpHandler.replyJson(exchange:getResponse(), result)
    else
      httpHandler.badRequest(exchange)
    end
  end
end

local function tableHandler(httpExchange)
  local request = httpExchange:getRequest()
  local context = httpExchange:getContext()
  local engine = context:getAttribute('engine')
  local publish = context:getAttribute('publish') == true
  local basePath = context:getAttribute('path') or ''
  local method = string.upper(request:getMethod())
  local path = httpExchange:getRequestArguments()
  local tp = basePath..string.gsub(path, '/$', '')
  if logger:isLoggable(logger.FINE) then
    logger:fine('tableHandler(), method: "'..method..'", path: "'..tp..'"')
  end
  if method == http.CONST.METHOD_GET then
    local value = tables.getPath(engine.root, tp)
    httpHandler.ok(httpExchange, json.encode({
      value = value
    }), 'application/json')
  elseif not context:getAttribute('editable') then
    httpHandler.methodNotAllowed(httpExchange)
  elseif method == http.CONST.METHOD_PUT or method == http.CONST.METHOD_POST then
    if logger:isLoggable(logger.FINEST) then
      logger:finest('tableHandler(), request body: "'..request:getBody()..'"')
    end
    if request:getBody() then
      local rt = json.decode(request:getBody())
      if type(rt) == 'table' and rt.value then
        if method == http.CONST.METHOD_PUT then
          engine:setRootValue(engine, tp, rt.value, publish)
        elseif method == http.CONST.METHOD_POST then
          engine:setRootValues(engine, tp, rt.value, publish)
        end
      end
    end
    httpHandler.ok(httpExchange)
  else
    httpHandler.methodNotAllowed(httpExchange)
  end
  if logger:isLoggable(logger.FINE) then
    logger:fine('tableHandler(), status: '..tostring(httpExchange:getResponse():getStatusCode()))
  end
end

local function getItemById(items, id)
  for _, item in ipairs(items) do
    if item.id == id then
      return item
    end
  end
  return nil
end

local function listItems(items, list)
  if not list then
    list = {}
  end
  for _, item in ipairs(items) do
    table.insert(list, item:toJSON())
  end
  return list
end

local function listDevices(plugin, list)
  return listItems(plugin:getDevices(), list)
end


local REST_ITEM_HANDLERS = {
  poll = function(exchange)
    exchange.attributes.item:publishItemEvent(exchange.attributes.engine, 'poll')
    return 'Done'
  end,
  reload = function(exchange)
    exchange.attributes.item:reloadItem()
    return 'Done'
  end
}

local REST_PLUGIN_HANDLERS = tables.merge({
  listDevices = function(exchange)
    return listDevices(exchange.attributes.item)
  end
}, REST_ITEM_HANDLERS)

local REST_DEVICE_HANDLERS = tables.merge({}, REST_ITEM_HANDLERS)

local REST_SCRIPT_HANDLERS = tables.merge({}, REST_ITEM_HANDLERS)

local function handleItem(exchange, getItemFn)
  local path = exchange:getAttribute('path')
  local name, remainingPath = httpHandler.shiftPath(path)
  local engine = exchange:getAttribute('engine')
  local item = getItemFn(engine, name)
  if item then
    exchange:setAttribute('item', item)
    return httpHandler.restPart(REST_SCRIPT_HANDLERS, exchange, remainingPath)
  end
  httpHandler.notFound(exchange)
  return false
end

local REST_ADMIN_HANDLERS = {
  list = function(exchange)
    local list = {}
    local engine = exchange:getAttribute('engine')
    listItems(engine.plugins, list)
    for _, plugin in ipairs(engine.plugins) do
      listDevices(plugin, list)
    end
    listItems(engine.scripts, list)
    return list
  end,
  listDevices = function(exchange)
    local list = {}
    local engine = exchange:getAttribute('engine')
    for _, plugin in ipairs(engine.plugins) do
      listDevices(plugin, list)
    end
    return list
  end,
  pollDevices = function(exchange)
    exchange.attributes.engine:publishEvent('poll')
    return 'Done'
  end,
  listScripts = function(exchange)
    return listItems(exchange.attributes.engine.scripts)
  end,
  reloadScripts = function(exchange)
    exchange.attributes.engine:reloadScripts()
    return 'Done'
  end,
  listPlugins = function(exchange)
    return listItems(exchange.attributes.engine.plugins)
  end,
  plugin = function(exchange)
    return handleItem(exchange, function(engine, name)
      return engine:getPlugin(name)
    end)
  end,
  device = function(exchange)
    return handleItem(exchange, function(engine, name)
      return engine:getDevice(name)
    end)
  end,
  script = function(exchange)
    return handleItem(exchange, function(engine, name)
      return engine:getScript(name)
    end)
  end,
  reloadPlugins = function(exchange)
    exchange.attributes.engine:reloadPlugins()
    return 'Done'
  end,
  deploy = function(exchange)
    if not httpHandler.methodAllowed(exchange, 'POST') then
      return false
    end
    local engine = exchange:getAttribute('engine')
    local path = exchange:getAttribute('path')
    local deployFile = File:new(engine.tmpDir, path)
    local deployDir = File:new(engine.tmpDir, 'deploy')
    local backupDir = File:new(engine.tmpDir, 'backup')
    local lhaDir = engine.dir:getParentFile()
    local topDir = lhaDir:getParentFile()
    if not cleanDirectory(deployDir) then
      return 'Ooops'
    end
    if not deployFile:isFile() or not ZipFile.unzipTo(deployFile, deployDir) then
      return 'Deploy file invalid or not found'
    end
    if not cleanDirectory(backupDir) then
      return 'Ooops'
    end
    for _, file in ipairs(deployDir:listFiles()) do
      local name = file:getName()
      local bFile = File:new(backupDir, name)
      local dFile = File:new(topDir, name)
      if dFile:exists() then
        if not dFile:renameTo(bFile) then
          return 'Ooops'
        end
      end
      if not file:renameTo(dFile) then
        return 'Ooops'
      end
    end
    return 'Done'
  end,
  restart = function(exchange)
    local engine = exchange:getAttribute('engine')
    event:setTimeout(function()
      engine.restart = true
      engine:stop()
    end, 100)
    return 'See you later'
  end,
  configuration = {
    save = function(exchange)
      local engine = exchange:getAttribute('engine')
      engine.configHistory:saveJson()
      return 'Done'
    end
  },
  stop = function(exchange)
    event:setTimeout(function()
      exchange.attributes.engine:stop()
    end, 100)
    return 'Bye'
  end,
  gc = function(exchange)
    if not httpHandler.methodAllowed(exchange, 'POST') then
      return false
    end
    runtime.gc()
    return 'Done'
  end,
  info = function()
    return {
      clock = os.clock(),
      memory = math.floor(collectgarbage('count') * 1024),
      time = Date.now() // 1000
    }
  end
}

--- An Engine class.
-- @type Engine
return class.create(function(engine)

  --- Creates an Engine.
  -- @function Engine:new
  -- @param dir the engine base directory
  -- @param workDir the engine working directory
  function engine:initialize(dir, workDir, options)
    self.dir = dir
    self.workDir = workDir
    self.options = options
    self.plugins = {}
    self.scripts = {}
    -- setup
    local configurationDir = File:new(workDir, 'configuration')
    logger:debug('configurationDir is '..configurationDir:getPath())
    createDirectoryOrExit(configurationDir)
    self.configHistory = HistoricalTable:new(configurationDir, 'config')

    local dataDir = File:new(workDir, 'data')
    logger:debug('dataDir is '..dataDir:getPath())
    createDirectoryOrExit(dataDir)
    self.dataHistory = HistoricalTable:new(dataDir, 'data')

    self.pluginsDir = File:new(workDir, 'plugin')
    logger:debug('pluginsDir is '..self.pluginsDir:getPath())
    createDirectoryOrExit(self.pluginsDir)

    self.lhaPluginsDir = nil
    local lhaDir = dir:getParentFile()
    if lhaDir and lhaDir:getPath() ~= workDir:getPath() then
      self.lhaPluginsDir = File:new(lhaDir, 'plugin')
    end

    self.scriptsDir = File:new(workDir, 'scripts')
    logger:debug('scriptsDir is '..self.scriptsDir:getPath())
    createDirectoryOrExit(self.scriptsDir)

    self.tmpDir = File:new(workDir, 'tmp')
    logger:debug('tmpDir is '..self.tmpDir:getPath())
    createDirectoryOrExit(self.tmpDir)
  end

  function engine:load()
    self.configHistory:loadLatest()
    self.dataHistory:loadLatest()
    self.root = {
      configuration = self.configHistory:getLiveTable(),
      data = tables.deepCopy(self.dataHistory:getLiveTable()),
      historicalData = self.dataHistory:getLiveTable()
    }
    --[[
      Default schedules are:
      poll every quarter of an hour then archive data 5 minutes after,
      configuration and refresh every day at midnight,
      clean the first day of every month.
    ]]
    tables.merge(self.root.configuration, {
      schedule = {
        clean = '0 0 1 * *',
        configuration = '0 0 * * *',
        data = '5-55/15 * * * *',
        poll = '*/15 * * * *'
      }
    }, true)
  end

  function engine:publishRootChange(source, path, value, previousValue)
    -- tables.mergeValuesByPath
    if type(previousValue) == 'table' then
      local previousValuesByPath = tables.mapValuesByPath(previousValue, path)
      for p, v in pairs(previousValuesByPath) do
        self:publishItemsEvent(source, 'change', p, nil, v)
      end
    end
    if type(value) == 'table' then
      local valuesByPath = tables.mapValuesByPath(value, path)
      for p, v in pairs(valuesByPath) do
        self:publishItemsEvent(source, 'change', p, v, nil)
      end
    else
      self:publishItemsEvent(source, 'change', path, value, previousValue)
    end
  end

  function engine:setRootValue(source, path, value, publish)
    --logger:info('engine:setRootValue('..path..', '..tostring(value)..')')
    local previousValue = tables.setPath(self.root, path, value)
    if publish and previousValue ~= value then
      logger:info('engine:setRootValue() change('..path..', '..tostring(value)..', '..tostring(previousValue)..')')
      self:publishRootChange(source, path, value, previousValue)
    end
  end

  function engine:setRootValues(source, path, value, publish)
    if type(value) == 'table' then
      local valuesByPath = tables.mapValuesByPath(value, path)
      for p, v in pairs(valuesByPath) do
        self:setRootValue(source, p, v, publish)
      end
    else
      self:setRootValue(source, path, value, publish)
    end
  end

  function engine:setConfigurationValue(source, path, value)
    self:setRootValue(source, 'configuration/'..path, value, true)
  end

  function engine:setConfigurationValues(source, path, value)
    self:setRootValues(source, 'configuration/'..path, value, true)
  end

  function engine:setDataValue(source, path, value, archive)
    self:setRootValue(source, 'data/'..path, value, true)
    if archive then
      self:setRootValue(source, 'historicalData/'..path, value, false)
    end
  end

  function engine:setDataValues(source, path, value, archive)
    self:setRootValues(source, 'data/'..path, value, true)
    if archive then
      self:setRootValues(source, 'historicalData/'..path, value, false)
    end
  end

  function engine:createScheduler()
    local engine = self
    local scheduler = Scheduler:new()
    -- poll devices schedule
    scheduler:schedule(engine.root.configuration.schedule.poll, function(t)
      logger:info('Polling devices')
      -- TODO Clean data
      engine:publishEvent('poll')
    end)
    -- data schedule
    scheduler:schedule(engine.root.configuration.schedule.data, function(t)
      logger:info('Archiving data')
      -- archive data
      engine.dataHistory:save()
      -- clean live data
      -- TODO
    end)
    -- configuration schedule
    scheduler:schedule(engine.root.configuration.schedule.configuration, function(t)
      logger:info('Archiving configuration')
      engine.configHistory:save(false, true)
      engine.dataHistory:save(true)
      engine:publishEvent('refresh')
    end)
    -- clean schedule
    scheduler:schedule(engine.root.configuration.schedule.clean, function(t)
      logger:info('Cleaning')
      engine.configHistory:save(true, true)
      engine:publishEvent('clean')
    end)
    self.scheduler = scheduler
  end

  function engine:startHTTPServer()
    local engine = self
    local httpServer = http.Server:new()
    httpServer:bind(self.options.address or '::', self.options.port or 8080):next(function()
      logger:info('Server bound to "'..tostring(self.options.address)..'" on port '..tostring(self.options.port))
    end, function(err) -- could failed if address is in use or hostname cannot be resolved
      logger:warn('Cannot bind HTTP server to "'..tostring(self.options.address)..'" on port '..tostring(self.options.port)..' due to '..tostring(err))
    end)
    -- optional secure server
    if type(self.options.secure) == 'table' then
      local certFile = File:new(self.workDir, certificate or 'cert.pem')
      local pkeyFile = File:new(self.workDir, self.options.secure.key or 'pkey.pem')
      if not certFile:exists() or not pkeyFile:exists() then
        writeCertificateAndPrivateKey(certFile, pkeyFile, self.options.secure.commonName or self.options.hostname)
        logger:info('Generate certificate '..certFile:getPath()..' and associated private key '..pkeyFile:getPath())
      end
      local httpSecureServer = http.Server.createSecure({
        certificate = certFile:getPath(),
        key = pkeyFile:getPath()
      })
      if httpSecureServer then
        httpSecureServer:bind(self.options.address or '::', self.options.secure.port or 8443):next(function()
          logger:info('Server secure bound to "'..tostring(self.options.address)..'" on port '..tostring(self.options.secure.port))
        end, function(err) -- could failed if address is in use or hostname cannot be resolved
          logger:warn('Cannot bind HTTP secure server to "'..tostring(self.options.address)..'" on port '..tostring(self.options.secure.port)..' due to '..tostring(err))
        end)
        -- share contexts
        if type(self.options.secure.credentials) == 'table' then
          local contextHolder = http.ContextHolder:new()
          contextHolder.contexts = httpServer.contexts
          httpSecureServer:createContext('.*', httpHandler.chain(httpHandler.basicAuthentication, contextHolder:toHandler()), {
            credentials = self.options.secure.credentials
          })
        else
          httpSecureServer.contexts = httpServer.contexts
        end
        self.secureServer = httpSecureServer
      else
        logger:warn('Unable to create secure HTTP server, make sure that openssl is available')
      end
    end
    -- register rest engine handler
    httpServer:createContext('/engine/admin/(.*)', httpHandler.rest, {
      attributes = {
        engine = self
      },
      handlers = REST_ADMIN_HANDLERS
    })
    httpServer:createContext('/engine/configuration/(.*)', tableHandler, {
      path = 'configuration/',
      editable = true,
      engine = self,
      publish = true
    })
    httpServer:createContext('/engine/data/(.*)', tableHandler, {
      path = 'data/',
      editable = true,
      engine = self,
      publish = true
    })
    httpServer:createContext('/engine/historicalData/(.*)', historicalDataHandler, {engine = self})
    -- register rest engine configuration handler
    -- register files plugins handler
    --httpServer:createContext('/engine/plugins/(.*)', httpHandler.files, {rootFile = self.pluginsDir})
    httpServer:createContext('/engine/scripts/(.*)', httpHandler.files, {rootFile = self.scriptsDir})
    httpServer:createContext('/engine/tmp/(.*)', httpHandler.files, {rootFile = self.tmpDir})
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
    end, self.options.heartbeat or 15000)
  end

  function engine:stopHeartbeat()
    if self.eventId then
      event:clearInterval(self.eventId)
      self.eventId = nil
    end
  end

  function engine:publishPluginsEvent(...)
    for _, plugin in ipairs(self.plugins) do
      plugin:publishItemEvent(...)
      --plugin:publishDevicesEvent(...)
    end
  end

  function engine:publishScriptsEvent(...)
    for _, script in ipairs(self.scripts) do
      script:publishItemEvent(...)
    end
  end

  function engine:publishItemsEvent(...)
    self:publishPluginsEvent(...)
    self:publishScriptsEvent(...)
  end

  function engine:publishEvent(...)
    self:publishPluginsEvent(self, ...)
    self:publishScriptsEvent(self, ...)
  end

  function engine:getPlugin(id)
    return getItemById(self.plugins, id)
  end

  function engine:getScript(id)
    return getItemById(self.scripts, id)
  end

  function engine:getDevice(id)
    for _, plugin in ipairs(self.plugins) do
      for _, item in ipairs(plugin:getDevices()) do
        if item.id == id then
          return item
        end
      end
    end
    return nil
  end

  function engine:loadPlugin(pluginDir)
    local plugin = Plugin.read(self, pluginDir)
    if plugin then
      if self:getPlugin(plugin:getId()) then
        logger:info('The plugin '..plugin:getId()..' already exists')
        return nil
      end
      plugin:loadItem()
      table.insert(self.plugins, plugin)
      logger:info('Plugin '..plugin:getId()..' loaded')
      return plugin
    end
  end

  function engine:loadPlugins(pluginsDir)
    if pluginsDir then
      for _, pluginDir in ipairs(pluginsDir:listFiles()) do
        if pluginDir:isDirectory() then
          self:loadPlugin(pluginDir)
        end
      end
    else
      self.plugins = {}
      if self.lhaPluginsDir:isDirectory() then
        self:loadPlugins(self.lhaPluginsDir)
      end
      self:loadPlugins(self.pluginsDir)
    end
  end

  function engine:reloadPlugins()
    logger:info('engine:reloadPlugins()')
    self:publishPluginsEvent(self, 'shutdown')
    for _, plugin in ipairs(self.plugins) do
      plugin:cleanItem()
    end
    self:loadPlugins()
    self:publishPluginsEvent(self, 'startup')
  end

  function engine:loadScript(id)
    local script = Script:new(self, self.scriptsDir, id)
    script:loadItem()
    table.insert(self.scripts, script)
    logger:info('Script '..script:getId()..' loaded')
    return script
  end

  function engine:loadScripts()
    self.scripts = {}
    for _, file in ipairs(self.scriptsDir:listFiles()) do
      if file:isFile() then
        local id, ext = string.match(file:getName(), '^(.*)%.([^%.]+)$')
        if id and ext == 'lua' then
          self:loadScript(id)
        end
      end
    end
  end

  function engine:reloadScripts()
    logger:info('engine:reloadScripts()')
    self:publishScriptsEvent(self, 'shutdown')
    for _, script in ipairs(self.scripts) do
      script:cleanItem()
    end
    self:loadScripts()
    self:publishScriptsEvent(self, 'startup')
  end

  function engine:start()
    self:load()
    self:createScheduler()
    self:startHTTPServer()
    self:startHeartbeat()
    self:loadPlugins()
    self:loadScripts()
    self:publishEvent('startup')
  end

  function engine:stop()
    self:stopHeartbeat()
    self:stopHTTPServer()
    self:publishEvent('shutdown')
    -- save configuration if necessary
    self.configHistory:save(false, true)
    event:stop()
    -- event:setTimeout(function()
    --   logger:info('exit')
    --   runtime.exit(0)
    -- end, 5000)
  end

end)