local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local runtime = require('jls.lang.runtime')
local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')
local File = require('jls.io.File')
local http = require('jls.net.http')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
local HttpExchange = require('jls.net.http.HttpExchange')
local json = require('jls.util.json')
local Scheduler = require('jls.util.Scheduler')
local strings = require('jls.util.strings')
local tables = require('jls.util.tables')
local TableList = require('jls.util.TableList')
local Date = require('jls.util.Date')

local HistoricalTable = require('lha.engine.HistoricalTable')
local IdGenerator = require('lha.engine.IdGenerator')
local Extension = require('lha.engine.Extension')
local Thing = require('lha.engine.Thing')
local utils = require('lha.engine.utils')

local schema = utils.requireJson('lha.engine.schema')

local function createDirectoryOrExit(dir)
  if not dir:isDirectory() then
    if dir:mkdir() then
      logger:info('Created directory "'..dir:getPath()..'"')
    else
      logger:warn('Unable to create the directory "'..dir:getPath()..'"')
      runtime.exit(1)
    end
  end
end

local function checkDirectoryOrExit(dir)
  if not dir:isDirectory() then
    logger:warn('The directory "'..dir:getPath()..'" does not exist')
    runtime.exit(1)
  end
end

local function historicalDataHandler(exchange)
  if HttpExchange.methodAllowed(exchange, 'GET') then
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
        t = engine.dataHistory:getLiveTable()
      end
      RestHttpHandler.replyJson(exchange, {
        value = tables.getPath(t, '/'..tp)
      })
      return
    end
    local fromTime = tonumber(request:getHeader("X-FROM-TIME"))
    local subPaths = request:getHeader("X-PATHS")
    if logger:isLoggable(logger.FINE) then
      logger:fine('process data request '..tostring(fromTime)..' - '..tostring(toTime)..' / '..tostring(period)..' on "'..tostring(path)..'"')
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
        local paths = strings.split(subPaths, ',')
        for i = 1, #paths do
          paths[i] = path..paths[i]
        end
        result = engine.dataHistory:loadMultiValues(fromTime, toTime, period, paths)
      else
        result = engine.dataHistory:loadValues(fromTime, toTime, period, path)
      end
      RestHttpHandler.replyJson(exchange, result)
    else
      HttpExchange.badRequest(exchange)
    end
  end
end

local function tableHandler(exchange)
  local request = exchange:getRequest()
  local context = exchange:getContext()
  local engine = context:getAttribute('engine')
  local publish = context:getAttribute('publish') == true
  local basePath = context:getAttribute('path') or ''
  local method = string.upper(request:getMethod())
  local path = exchange:getRequestArguments()
  local tp = basePath..string.gsub(path, '/$', '')
  if logger:isLoggable(logger.FINE) then
    logger:fine('tableHandler(), method: "'..method..'", path: "'..tp..'"')
  end
  if method == http.CONST.METHOD_GET then
    local value = tables.getPath(engine.root, tp)
    if value then
      HttpExchange.ok(exchange, json.encode({
        value = value
      }), 'application/json')
    else
      HttpExchange.notFound(exchange)
    end
  elseif not context:getAttribute('editable') then
    HttpExchange.methodNotAllowed(exchange)
  elseif method == http.CONST.METHOD_PUT or method == http.CONST.METHOD_POST then
    if logger:isLoggable(logger.FINEST) then
      logger:finest('tableHandler(), request body: "'..request:getBody()..'"')
    end
    local rt = json.decode(request:getBody())
    if type(rt) == 'table' and rt.value then
      if method == http.CONST.METHOD_PUT then
        engine:setRootValue(tp, rt.value, publish)
      elseif method == http.CONST.METHOD_POST then
        engine:setRootValues(tp, rt.value, publish)
      end
    end
    HttpExchange.ok(exchange)
  else
    HttpExchange.methodNotAllowed(exchange)
  end
  if logger:isLoggable(logger.FINE) then
    logger:fine('tableHandler(), status: '..tostring(exchange:getResponse():getStatusCode()))
  end
end

local function getUpdateTime()
  return Date.now()
end


local EngineThing = class.create(Thing, function(engineThing, super)

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

  function engineThing:setPropertyValue(name, value)
    local property = self:getProperty(name)
    if not property or property:isReadOnly() then
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

  local function computeChanges(t, key)
    local fullKey = key..HistoricalTable.CHANGES_SUFFIX
    local previousValue = t[fullKey]
    if previousValue then
      t[fullKey] = previousValue + 1
    else
      t[fullKey] = 2
    end
  end
  local function computeMin(t, key, value)
    local fullKey = key..HistoricalTable.MIN_SUFFIX
    local previousValue = t[fullKey]
    if not previousValue or value < previousValue then
      t[fullKey] = value
    end
  end
  local function computeMax(t, key, value)
    local fullKey = key..HistoricalTable.MAX_SUFFIX
    local previousValue = t[fullKey]
    if not previousValue or value > previousValue then
      t[fullKey] = value
    end
  end

  function engineThing:updatePropertyValue(name, value)
    local property = self.properties[name]
    if property then
      -- check numbers are valid, not nan nor +/-inf
      if type(value) == 'number' and (value ~= value or value == math.huge or value == -math.huge) then
        logger:warn('Invalid number value on update property "'..name..'"')
        return
      end
      self.lastupdated = getUpdateTime()
      if self:isArchiveData() then
        local path = 'data/'..self.thingId..'/'..name
        local previousValue, t, key = self.engine:setRootValue(path, value, true)
        if previousValue ~= nil and previousValue ~= value then
          local mt = property:getMetadata('type') -- type(value)
          if mt == 'number' or mt == 'integer' then
            computeMin(t, key, math.min(value, previousValue))
            computeMax(t, key, math.max(value, previousValue))
          elseif mt == 'boolean' or mt == 'string' then
            computeChanges(t, key)
          end
        end
      end
      super.updatePropertyValue(self, name, value)
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

local function reloadExtension(extension)
  if extension:isActive() then
    extension:publishEvent('shutdown')
  end
  extension:reloadExtension()
  if extension:isActive() then
    extension:publishEvent('startup')
    extension:publishEvent('things')
  end
end

local REST_THING = {
  [''] = function(exchange)
    return exchange.attributes.thing:asThingDescription()
  end,
  properties = {
    [''] = function(exchange)
      local request = exchange:getRequest()
      local method = string.upper(request:getMethod())
      if method == http.CONST.METHOD_GET then
        return exchange.attributes.thing:getPropertyValues()
      elseif method == http.CONST.METHOD_PUT then
        local rt = json.decode(request:getBody())
        for name, value in pairs(rt) do
          exchange.attributes.thing:setPropertyValue(name, value)
        end
      else
        HttpExchange.methodNotAllowed(exchange)
        return false
      end
    end,
    ['{propertyName}(propertyName)'] = function(exchange, propertyName)
        local request = exchange:getRequest()
        local method = string.upper(request:getMethod())
        local property = exchange.attributes.thing:getProperty(propertyName)
        if property then
            if method == http.CONST.METHOD_GET then
                return {[propertyName] = property:getValue()}
            elseif method == http.CONST.METHOD_PUT then
                local rt = json.decode(request:getBody())
                local value = rt[propertyName]
                exchange.attributes.thing:setPropertyValue(propertyName, value)
            else
                HttpExchange.methodNotAllowed(exchange)
                return false
            end
        else
            HttpExchange.notFound(exchange)
            return false
        end
    end,
  }
}

local REST_THINGS = {
  [''] = function(exchange)
    local engine = exchange:getAttribute('engine')
    local descriptions = {}
    local thingIds = tables.keys(engine.things)
    table.sort(thingIds)
    for _, thingId in ipairs(thingIds) do
      local thing = engine.things[thingId]
      if thing then
        local description = thing:asThingDescription()
        table.insert(descriptions, description)
      end
    end
    --[[
    for _, thing in pairs(engine.things) do
      local description = thing:asThingDescription()
      table.insert(descriptions, description)
    end
    ]]
    return descriptions
  end,
  ['{+}'] = function(exchange, name)
    local engine = exchange:getAttribute('engine')
    exchange:setAttribute('thing', engine.things[name])
  end,
  ['{thingId}'] = REST_THING,
}

local REST_EXTENSIONS = {
  [''] = function(exchange)
    local engine = exchange:getAttribute('engine')
    local list = {}
    for _, extension in ipairs(engine.extensions) do
      if extension:isLoaded() and extension:getType() ~= 'script' then
        table.insert(list, extension:toJSON())
      end
    end
    return list
  end,
  ['{+}'] = function(exchange, name)
    local engine = exchange:getAttribute('engine')
    exchange:setAttribute('extension', engine:getExtensionById(name))
  end,
  ['{extensionId}'] = {
    [''] = function(exchange)
      local extension = exchange.attributes.extension
      return {
        config = extension:getConfiguration(),
        info = extension:toJSON(),
        manifest = extension:getManifest()
      }
    end,
    info = function(exchange)
      return exchange.attributes.extension:toJSON()
    end,
    manifest = function(exchange)
      return exchange.attributes.extension:getManifest()
    end,
    ['poll(extension)?method=POST'] = function(exchange, extension)
      if extension:isActive() then
        extension:publishEvent('poll')
      end
    end,
    ['reload(extension)?method=POST'] = function(exchange, extension)
      reloadExtension(extension)
    end,
    ['enable(extension)?method=POST'] = function(exchange, extension)
      if not extension:isActive() then
        extension:setActive(true)
        if extension:isActive() then
          extension:publishEvent('startup')
          extension:publishEvent('things')
        end
      end
    end,
    ['disable(extension)?method=POST'] = function(exchange, extension)
      if extension:isActive() then
        extension:publishEvent('shutdown')
        extension:setActive(false)
      end
    end
  },
}

local REST_SCRIPTS = {
  [''] = function(exchange)
    local request = exchange:getRequest()
    local method = string.upper(request:getMethod())
    local engine = exchange:getAttribute('engine')
    if method == http.CONST.METHOD_GET then
      local list = {}
      for _, extension in ipairs(engine.extensions) do
        if extension:getType() == 'script' then
          table.insert(list, extension:toJSON())
        end
      end
      return list
    elseif method == http.CONST.METHOD_PUT then
      if engine.scriptsDir:isDirectory() then
        local scriptId = engine:generateId()
        local scriptDir = File:new(engine.scriptsDir, scriptId)
        scriptDir:mkdir()
        local blocksFile = File:new(scriptDir, 'blocks.xml')
        local scriptFile = File:new(scriptDir, 'script.lua')
        local manifestFile = File:new(scriptDir, 'manifest.json')
        local manifest = {
          name = "New script",
          version = "1.0",
          blocks = blocksFile:getName(),
          script = scriptFile:getName()
        }
        blocksFile:write('<xml xmlns="http://www.w3.org/1999/xhtml"></xml>')
        scriptFile:write("local script = ...\nlocal logger = require('jls.lang.logger')\n\n")
        manifestFile:write(json.encode(manifest))
        logger:fine('Created script "'..scriptId..'"')
        engine:loadExtensionFromDirectory(scriptDir, 'script')
        return scriptId
      else
        logger:warn('Cannot create script')
      end
    else
      HttpExchange.methodNotAllowed(exchange)
      return false
    end
  end,
  ['{+}'] = function(exchange, name)
    local engine = exchange:getAttribute('engine')
    exchange:setAttribute('extension', engine:getExtensionById(name))
  end,
  ['{extensionId}'] = {
    [''] = function(exchange)
      local request = exchange:getRequest()
      local method = string.upper(request:getMethod())
      local engine = exchange:getAttribute('engine')
      local extension = exchange:getAttribute('extension')
      if method == http.CONST.METHOD_DELETE then
        local extensionDir = extension:getDir()
        if extension:isActive() then
          extension:publishEvent('shutdown')
        end
        engine:removeExtension(extension)
        extensionDir:deleteRecursive()
      else
        HttpExchange.methodNotAllowed(exchange)
        return false
      end
    end,
    reload = function(exchange)
      reloadExtension(exchange.attributes.extension)
    end
  },
}

local REST_ADMIN = {
  configuration = {
    save = function(exchange)
      -- curl http://localhost:8080/engine/admin/configuration/save
      local engine = exchange:getAttribute('engine')
      engine.configHistory:saveJson()
      return 'Done'
    end
  },
  reloadExtensions = function(exchange)
    local mode = RestHttpHandler.shiftPath(exchange:getAttribute('path'))
    exchange.attributes.engine:reloadExtensions(mode == 'full', true)
    return 'Done'
  end,
  reloadScripts = function(exchange)
    local mode = RestHttpHandler.shiftPath(exchange:getAttribute('path'))
    exchange.attributes.engine:reloadScripts(mode == 'full')
    return 'Done'
  end,
  stop = function(exchange)
    -- curl http://localhost:8080/engine/admin/configuration/stop
    event:setTimeout(function()
      exchange.attributes.engine:stop()
    end, 100)
    return 'Bye'
  end,
  gc = function(exchange)
    if not HttpExchange.methodAllowed(exchange, 'POST') then
      return false
    end
    runtime.gc()
    return 'Done'
  end,
  info = function(exchange)
    --local engine = exchange:getAttribute('engine')
    --local ip, port = engine:getHTTPServer():getAddress()
    return {
      clock = os.clock(),
      memory = math.floor(collectgarbage('count') * 1024),
      time = Date.now() // 1000
    }
  end,
  mem = function(exchange)
    local report = ''
    require('jls.util.memprof').printReport(function(data)
      report = data
    end, false, false, 'csv')
    return report
  end
}

local REST_ENGINE_HANDLERS = {
  discoveredThings = function(exchange)
    -- curl http://localhost:8080/engine/discoveredThings
    local engine = exchange:getAttribute('engine')
    local descriptions = {}
    for _, extension in ipairs(engine.extensions) do
      if extension:isLoaded() then
        local discoveredThings = extension:getDiscoveredThings()
        for discoveryKey, thing in pairs(discoveredThings) do
          local description = thing:asThingDescription()
          description.discoveryKey = discoveryKey
          description.extensionId = extension:getId()
          table.insert(descriptions, description)
        end
      end
    end
    return descriptions
  end,
  poll = function(exchange)
    if not HttpExchange.methodAllowed(exchange, 'POST') then
      return false
    end
    local engine = exchange:getAttribute('engine')
    engine:publishEvent('poll')
    return 'Polled'
  end,
  properties = function(exchange)
    local engine = exchange:getAttribute('engine')
    local t = {}
    for thingId, thing in pairs(engine.things) do
      t[thingId] = thing:getPropertyValues()
    end
    return t
  end,
  extensions = REST_EXTENSIONS,
  scripts = REST_SCRIPTS,
  things = {
    [''] = function(exchange)
      local engine = exchange:getAttribute('engine')
      local request = exchange:getRequest()
      local method = string.upper(request:getMethod())
      if method == http.CONST.METHOD_GET then
        local list = {}
        for thingId, thing in pairs(engine.things) do
          table.insert(list, thing:asEngineThingDescription())
        end
        return list
      elseif method == http.CONST.METHOD_PUT then
        -- curl -X PUT --data-binary "@work\tmp\discoveredThings2.json" http://localhost:8080/engine/things
        local discoveredThings = json.decode(request:getBody())
        for _, discoveredThing in ipairs(discoveredThings) do
          if discoveredThing.extensionId and discoveredThing.discoveryKey then
            engine:addDiscoveredThing(discoveredThing.extensionId, discoveredThing.discoveryKey)
          end
        end
        engine:publishEvent('things')
      else
        HttpExchange.methodNotAllowed(exchange)
        return false
      end
    end,
    ['{thingId}'] = {
      [''] = function(exchange)
        local engine = exchange:getAttribute('engine')
        local thingId = exchange:getAttribute('thingId')
        local thing = engine.things[thingId]
        if not thing then
          HttpExchange.notFound(exchange)
          return false
        end
        local request = exchange:getRequest()
        local method = string.upper(request:getMethod())
        if method == http.CONST.METHOD_GET then
          return thing:asEngineThingDescription()
        elseif method == http.CONST.METHOD_DELETE then
          engine:disableThing(thingId)
          engine:publishEvent('things')
        else
          HttpExchange.methodNotAllowed(exchange)
          return false
        end
      end,
      refreshDescription = function(exchange)
        local engine = exchange:getAttribute('engine')
        local thingId = exchange:getAttribute('thingId')
        local thing = engine.things[thingId]
        if not thing then
          HttpExchange.notFound(exchange)
          return false
        end
        engine:refreshThingDescription(thingId)
        return 'done'
      end,
    },
  },
  schema = function(exchange)
    return schema.properties.config.properties.engine
  end,
  admin = REST_ADMIN
}

return class.create(function(engine)

  function engine:initialize(options)
    self.options = options or {}
    self.things = {}
    self.extensions = {}
    self.idGenerator = IdGenerator:new()

    local optionsDir = File:new(options.engine):getAbsoluteFile():getParentFile()
    checkDirectoryOrExit(optionsDir)
    logger:debug('optionsDir is '..optionsDir:getPath())

    local enginePath = assert(package.searchpath('lha.engine.Engine', package.path))
    local engineFile = File:new(enginePath):getAbsoluteFile()
    local lhaDir = engineFile:getParentFile():getParentFile()
    local rootDir = lhaDir:getParentFile()
    checkDirectoryOrExit(rootDir)
    logger:debug('rootDir is '..rootDir:getPath())
    self.rootDir = rootDir

    -- setup
    local workDir = utils.getAbsoluteFile(options.work or 'work', optionsDir)
    checkDirectoryOrExit(workDir)
    logger:debug('workDir is '..workDir:getPath())
    self.workDir = workDir

    local configurationDir = File:new(workDir, 'configuration')
    logger:debug('configurationDir is '..configurationDir:getPath())
    createDirectoryOrExit(configurationDir)
    self.configHistory = HistoricalTable:new(configurationDir, 'config', {keepTable = true})

    local dataDir = File:new(workDir, 'data')
    logger:debug('dataDir is '..dataDir:getPath())
    createDirectoryOrExit(dataDir)
    self.dataHistory = HistoricalTable:new(dataDir, 'data')

    self.extensionsDir = File:new(workDir, 'extensions')
    logger:debug('extensionsDir is '..self.extensionsDir:getPath())
    createDirectoryOrExit(self.extensionsDir)

    self.lhaExtensionsDir = nil
    if lhaDir:getPath() ~= workDir:getPath() then
      self.lhaExtensionsDir = File:new(lhaDir, 'extensions')
      logger:debug('lhaExtensionsDir is '..self.lhaExtensionsDir:getPath())
    end

    self.scriptsDir = File:new(workDir, 'scripts')
    logger:debug('scriptsDir is '..self.scriptsDir:getPath())
    createDirectoryOrExit(self.scriptsDir)

    self.tmpDir = File:new(workDir, 'tmp')
    logger:debug('tmpDir is '..self.tmpDir:getPath())
    createDirectoryOrExit(self.tmpDir)
  end

  function engine:generateId()
    return self.idGenerator:generate()
  end

  function engine:getWorkDirectory()
    return self.workDir
  end

  function engine:getTemporaryDirectory()
    return self.tmpDir
  end

  function engine:archiveData(isFull)
    self.dataHistory:save(isFull)
    self.root.data = self.dataHistory:getLiveTable()
  end

  function engine:createScheduler()
    local scheduler = Scheduler:new()
    local schedules = self.root.configuration.engine.schedule
    -- poll things schedule
    scheduler:schedule(schedules.poll, function()
      logger:info('Polling things')
      -- TODO Clean data
      self:publishEvent('poll')
    end)
    -- data schedule
    scheduler:schedule(schedules.data, function()
      logger:info('Archiving data')
      self:archiveData(false)
    end)
    -- configuration schedule
    scheduler:schedule(schedules.configuration, function()
      logger:info('Archiving configuration')
      self.configHistory:save(false, true)
      self:archiveData(true)
      self:publishEvent('refresh')
    end)
    -- clean schedule
    scheduler:schedule(schedules.clean, function()
      logger:info('Cleaning')
      self.configHistory:save(true, true)
      self:publishEvent('clean')
    end)
    self.scheduler = scheduler
  end

  function engine:startHTTPServer()
    local httpServer = http.Server:new()
    httpServer:bind(self.options.address, self.options.port):next(function()
      logger:info('Server bound to "'..tostring(self.options.address)..'" on port '..tostring(self.options.port))
    end, function(err) -- could failed if address is in use or hostname cannot be resolved
      logger:warn('Cannot bind HTTP server to "'..tostring(self.options.address)..'" on port '..tostring(self.options.port)..' due to '..tostring(err))
      runtime.exit(98)
    end)
    -- register rest engine handler
    httpServer:createContext('/engine/(.*)', RestHttpHandler:new(REST_ENGINE_HANDLERS, {
      engine = self
    }))
    httpServer:createContext('/things/?(.*)', RestHttpHandler:new(REST_THINGS, {
      engine = self
    }))
    httpServer:createContext('/engine/configuration/(.*)', tableHandler, {
      path = 'configuration/',
      editable = true,
      engine = self,
      publish = true
    })
    -- TODO Remove as things have the data
    httpServer:createContext('/engine/data/(.*)', tableHandler, {
      path = 'data/',
      editable = false,
      engine = self,
      publish = true
    })
    httpServer:createContext('/engine/historicalData/(.*)', historicalDataHandler, {
      engine = self
    })
    httpServer:createContext('/engine/scriptFiles/(.*)', FileHttpHandler:new(self.scriptsDir, 'rcd'))
    httpServer:createContext('/engine/tmp/(.*)', FileHttpHandler:new(self.tmpDir, 'rcd'))
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
    --logger:info('engine:setRootValue('..path..', '..tostring(value)..')')
    local previousValue, t, key = tables.setPath(self.root, path, value)
    if publish and previousValue ~= value then
      logger:info('engine:setRootValue() change('..path..', '..tostring(value)..', '..tostring(previousValue)..')')
      self:publishRootChange(path, value, previousValue)
    end
    return previousValue, t, key
  end

  function engine:setRootValues(path, value, publish)
    if type(value) == 'table' then
      local valuesByPath = tables.mapValuesByPath(value, path)
      for p, v in pairs(valuesByPath) do
        self:setRootValue(p, v, publish)
      end
    else
      self:setRootValue(path, value, publish)
    end
  end

  function engine:publishEvent(...)
    self:publishExtensionsEvent(nil, ...)
  end

  function engine:publishExtensionsEvent(source, ...)
    local name = ...
    logger:finer('Publishing Extensions Event '..tostring(name))
    for _, extension in ipairs(self.extensions) do
      if extension ~= source and extension:isActive() then
        extension:publishEvent(...)
      end
    end
  end

  function engine:addExtension(extension)
    table.insert(self.extensions, extension)
    return extension
  end

  function engine:removeExtension(extension)
    TableList.removeFirst(self.extensions, extension)
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
      if extension:isLoaded() then
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
          reloadExtension(extension)
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
          reloadExtension(extension)
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
        reloadExtension(extension)
      end
    end
  end

  -- Adds a thing to this engine.
  function engine:addDiscoveredThing(extensionId, discoveryKey)
    logger:info('addDiscoveredThing("'..tostring(extensionId)..'", "'..tostring(discoveryKey)..'")')
    local extension = self:getExtensionById(extensionId)
    local thing = extension and extension:getDiscoveredThingByKey(discoveryKey)
    if thing then
      local thingConfiguration, thingId = self:getThingByDiscoveryKey(extensionId, discoveryKey)
      if thingConfiguration and thingId then
        thingConfiguration.description = thing:asThingDescription()
        if not thingConfiguration.active then
          thingConfiguration.active = true
          thingConfiguration.archiveData = false
        end
      else
        thingId = self:generateId()
        thingConfiguration = {
          extensionId = extensionId,
          discoveryKey = discoveryKey,
          description = thing:asThingDescription(),
          active = true,
          archiveData = false
        }
      end
      self.root.configuration.things[thingId] = thingConfiguration
      self:loadThing(thingId, thingConfiguration)
      --self:publishEvent('things')
    end
  end

  function engine:refreshThingDescription(thingId)
    local thing = self.things[thingId]
    local thingConfiguration = self.root.configuration.things[thingId]
    if thing and thingConfiguration then
      logger:info('refreshThingDescription("'..tostring(thingId)..'") not implemented')
    end
  end

  function engine:disableThing(thingId)
    local thingConfiguration = self.root.configuration.things[thingId]
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

  function engine:loadThings()
    -- Load the things available in the configuration
    self.things = {}
    for thingId, thingConfiguration in pairs(self.root.configuration.things) do
      local extension = self:getExtensionById(thingConfiguration.extensionId)
      local discoveredThing = extension and extension:getDiscoveredThingByKey(thingConfiguration.discoveryKey)
      if thingConfiguration.active then
        local thing = self:loadThing(thingId, thingConfiguration)
        if discoveredThing then
          -- TODO provide a full update and check if the thing is still compatible
          local updated = false
          for name, property in pairs(discoveredThing:getProperties()) do
            if not thing:getProperty(name) then
              thing:addProperty(name, property)
              updated = true
            end
          end
          if updated then
            thingConfiguration.description = thing:asThingDescription()
            logger:info('thing "'..tostring(thingId)..'" ('..tostring(thingConfiguration.extensionId)..'/'..tostring(thingConfiguration.discoveryKey)..') updated')
          end
        end
      end
    end
  end

  function engine:getThingsByExtensionId(extensionId)
    local things = {}
    for thingId, thingConfiguration in pairs(self.root.configuration.things) do
      if thingConfiguration.active and thingConfiguration.extensionId == extensionId then
        local thing = self.things[thingId]
        if thing then
          things[thingConfiguration.discoveryKey] = thing
        end
      end
    end
    return things
  end

  function engine:getThingByDiscoveryKey(extensionId, discoveryKey)
    for thingId, thingConfiguration in pairs(self.root.configuration.things) do
      if thingConfiguration.extensionId == extensionId and thingConfiguration.discoveryKey == discoveryKey then
        return self.things[thingId], thingId
      end
    end
    return nil
  end

  function engine:getThingById(thingId)
    return self.things[thingId]
  end

  function engine:start(defaultConfig, customConfig)
    self.configHistory:loadLatest()
    self.dataHistory:loadLatest()
    self.root = {
      configuration = self.configHistory:getLiveTable(),
      data = self.dataHistory:getLiveTable()
    }
    if customConfig then
      tables.merge(self.root.configuration, customConfig)
    end
    if defaultConfig then
      tables.merge(self.root.configuration, defaultConfig, true)
    end
    if logger:isLoggable(logger.FINER) then
      logger:finer('config: '..json.stringify(self.root.configuration, 2))
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
    self:publishEvent('startup')
    self:publishEvent('things')
  end

  function engine:stop()
    self:stopHeartbeat()
    self:stopHTTPServer()
    self:publishEvent('shutdown')
    self.configHistory:saveJson()
    self.dataHistory:saveJson()
    event:stop()
  end

end, function(Engine)

  function Engine.launch(arguments)
    local options, customOptions = tables.createArgumentTable(arguments, {
      configPath = 'file',
      emptyPath = 'work',
      helpPath = 'help',
      disableSchemaDefaults = true,
      schema = schema
    })
    local defaultConfig = options.config
    options.config = nil
    logger:setLevel(options.loglevel)
    local engine = Engine:new(options)
    engine:start(defaultConfig, customOptions.config)
    engine:publishEvent('poll')
    return engine
  end

end)