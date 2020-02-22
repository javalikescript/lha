local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local File = require('jls.io.File')
local json = require('jls.util.json')
local http = require('jls.net.http')
local httpHandler = require('jls.net.http.handler')
local Scheduler = require('jls.util.Scheduler')
local runtime = require('jls.lang.runtime')
local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')
local strings = require('jls.util.strings')
local tables = require('jls.util.tables')
local Date = require('jls.util.Date')
local HistoricalTable = require('lha.engine.HistoricalTable')
local IdGenerator = require('lha.engine.IdGenerator')
local Extension = require('lha.engine.Extension')
local Thing = require('lha.engine.Thing')

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

local function writeCertificateAndPrivateKey(certFile, pkeyFile, commonName)
  local secure = require('jls.net.secure')
  local cacert, pkey = secure.createCertificate({
    commonName = commonName or 'localhost'
  })
  local cacertPem  = cacert:export('pem')
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
        t = engine.dataHistory:getLiveTable()
      end
      httpHandler.replyJson(exchange:getResponse(), {
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
      httpHandler.replyJson(exchange:getResponse(), result)
    else
      httpHandler.badRequest(exchange)
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
      httpHandler.ok(exchange, json.encode({
        value = value
      }), 'application/json')
    else
      httpHandler.notFound(exchange)
    end
  elseif not context:getAttribute('editable') then
    httpHandler.methodNotAllowed(exchange)
  elseif method == http.CONST.METHOD_PUT or method == http.CONST.METHOD_POST then
    if logger:isLoggable(logger.FINEST) then
      logger:finest('tableHandler(), request body: "'..request:getBody()..'"')
    end
    if request:getBody() then
      local rt = json.decode(request:getBody())
      if type(rt) == 'table' and rt.value then
        if method == http.CONST.METHOD_PUT then
          engine:setRootValue(tp, rt.value, publish)
        elseif method == http.CONST.METHOD_POST then
          engine:setRootValues(tp, rt.value, publish)
        end
      end
    end
    httpHandler.ok(exchange)
  else
    httpHandler.methodNotAllowed(exchange)
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
  end

  function engineThing:setArchiveData(archiveData)
    self.engine:setRootValues('configuration/things/'..self.thingId..'/archiveData', self.archiveData, true)
  end

  function engineThing:getArchiveData()
    return tables.getPath(self.engine.root, 'configuration/things/'..self.thingId..'/archiveData', false)
  end

  function engineThing:setPropertyValue(name, value)
		local property = self:findProperty(name)
    if property and property:isReadOnly() then
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
    self.lastupdated = getUpdateTime()
    if self:getArchiveData() then
      self.engine:setRootValues('data/'..self.thingId..'/'..name, value, true)
    end
    return super.updatePropertyValue(self, name, value)
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
    description.archiveData = self:getArchiveData()
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
          return exchange.attributes.thing:getProperties()
        elseif method == http.CONST.METHOD_PUT then
          local rt = json.decode(request:getBody())
          for name, value in pairs(rt) do
            exchange.attributes.thing:setPropertyValue(name, value)
          end
        else
          httpHandler.methodNotAllowed(exchange)
          return false
        end
      end,
      ['/any'] = function(exchange)
          local request = exchange:getRequest()
          local method = string.upper(request:getMethod())
          local propertyName = exchange.attributes.propertyName
          local property = exchange.attributes.thing:findProperty(propertyName)
          if property then
              if method == http.CONST.METHOD_GET then
                  return {[propertyName] = property:getValue()}
              elseif method == http.CONST.METHOD_PUT then
                  local rt = json.decode(request:getBody())
                  local value = rt[propertyName]
                  exchange.attributes.thing:setPropertyValue(propertyName, value)
              else
                  httpHandler.methodNotAllowed(exchange)
                  return false
              end
          else
              httpHandler.notFound(exchange)
              return false
          end
      end,
      name = 'propertyName'
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
  ['/any'] = REST_THING,
  name = 'thing',
  value = function(exchange, name)
    local engine = exchange:getAttribute('engine')
    return engine.things[name]
  end
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
  ['/any'] = {
    [''] = function(exchange)
      local engine = exchange:getAttribute('engine')
      local extension = exchange.attributes.extension
      return {
        config = engine.root.configuration.extensions[extension.id] or {},
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
    poll = function(exchange)
      if exchange.attributes.extension:isActive() then
        exchange.attributes.extension:publishEvent('poll')
      end
    end,
    reload = function(exchange)
      reloadExtension(exchange.attributes.extension)
    end
  },
  name = 'extension',
  value = function(exchange, name)
    local engine = exchange:getAttribute('engine')
    return engine:getExtensionById(name)
  end
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
        -- TODO Load new script?
        return scriptId
      end
    else
      httpHandler.methodNotAllowed(exchange)
      return false
    end
  end,
  ['/any'] = {
    reload = function(exchange)
      reloadExtension(exchange.attributes.extension)
    end
  },
  name = 'extension',
  value = function(exchange, name)
    local engine = exchange:getAttribute('engine')
    return engine:getExtensionById(name)
  end
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
    local mode = httpHandler.shiftPath(exchange:getAttribute('path'))
    exchange.attributes.engine:reloadExtensions(mode == 'full', true)
    return 'Done'
  end,
  reloadScripts = function(exchange)
    local mode = httpHandler.shiftPath(exchange:getAttribute('path'))
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
    if not httpHandler.methodAllowed(exchange, 'POST') then
      return false
    end
    local engine = exchange:getAttribute('engine')
    engine:publishEvent('poll')
    return 'Polled'
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
        if request:getBody() then
          local discoveredThings = json.decode(request:getBody())
          for _, discoveredThing in ipairs(discoveredThings) do
            if discoveredThing.extensionId and discoveredThing.discoveryKey then
              engine:addDiscoveredThing(discoveredThing.extensionId, discoveredThing.discoveryKey)
            end
          end
          engine:publishEvent('things')
        end
      else
        httpHandler.methodNotAllowed(exchange)
        return false
      end
    end,
    ['/any'] = {
      [''] = function(exchange)
        local thingId = exchange:getAttribute('thingId')
        local engine = exchange:getAttribute('engine')
        local thing = engine.things[thingId]
        if not thing then
          httpHandler.notFound(exchange)
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
          httpHandler.methodNotAllowed(exchange)
          return false
        end
      end
    },
    name = 'thingId'
  },
  schema = function(exchange)
    return {
      type = "object",
      properties = {
        schedule = {
          title = "Group for scheduling using cron like syntax",
          type = "object",
          properties = {
            clean = {
              title = "Schedule for cleaning",
              type = "string"
            },
            configuration = {
              title = "Schedule for archiving configuration",
              type = "string"
            },
            data = {
              title = "Schedule for archiving data",
              type = "string"
            },
            poll = {
              title = "Schedule for polling extension things",
              type = "string"
            }
          }
        }
      }
    }
  end,
  admin = REST_ADMIN
}

--- An Engine class.
-- @type Engine
return class.create(function(engine)

  --- Creates an Engine.
  -- @function Engine:new
  -- @param dir the engine base directory
  -- @param rootDir the root directory, used to resolve relative paths
  function engine:initialize(dir, rootDir, options)
    self.dir = dir
    self.rootDir = rootDir
    self.options = options or {}
    self.things = {}
    self.extensions = {}
    self.idGenerator = IdGenerator:new()

    -- setup
    local workDir = self:getAbsoluteFile(self.options.work or 'work')
    checkDirectoryOrExit(workDir)
    logger:debug('workDir is '..workDir:getPath())

    local configurationDir = File:new(workDir, 'configuration')
    logger:debug('configurationDir is '..configurationDir:getPath())
    createDirectoryOrExit(configurationDir)
    self.configHistory = HistoricalTable:new(configurationDir, 'config')

    local dataDir = File:new(workDir, 'data')
    logger:debug('dataDir is '..dataDir:getPath())
    createDirectoryOrExit(dataDir)
    self.dataHistory = HistoricalTable:new(dataDir, 'data')

    self.extensionsDir = File:new(workDir, 'extensions')
    logger:debug('extensionsDir is '..self.extensionsDir:getPath())
    createDirectoryOrExit(self.extensionsDir)

    self.lhaExtensionsDir = nil
    local lhaDir = dir:getParentFile()
    if lhaDir and lhaDir:getPath() ~= workDir:getPath() then
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

  function engine:getAbsoluteFile(path)
    local file = File:new(path)
    if file:isAbsolute() then
      return file
    end
    return File:new(self.rootDir, path)
  end
  
  function engine:load()
    self.configHistory:loadLatest()
    self.dataHistory:loadLatest()
    self.root = {
      configuration = self.configHistory:getLiveTable(),
      data = self.dataHistory:getLiveTable()
    }
    --[[
      Default schedules are:
      poll every quarter of an hour then archive data 5 minutes after,
      configuration and refresh every day at midnight,
      clean the first day of every month.
    ]]
    tables.merge(self.root.configuration, {
      engine = {
        schedule = {
          clean = '0 0 1 * *',
          configuration = '0 0 * * *',
          data = '5-55/15 * * * *',
          poll = '*/15 * * * *'
        }
      },
      extensions = {},
      things = {}
    }, true)
    -- save configuration if missing
    if not self.configHistory:hasJsonFile() then
      logger:info('Saving configuration')
      self.configHistory:saveJson()
    end
  end

  function engine:createScheduler()
    local engine = self
    local scheduler = Scheduler:new()
    local schedules = self.root.configuration.engine.schedule
    -- poll things schedule
    scheduler:schedule(schedules.poll, function(t)
      logger:info('Polling things')
      -- TODO Clean data
      engine:publishEvent('poll')
    end)
    -- data schedule
    scheduler:schedule(schedules.data, function(t)
      logger:info('Archiving data')
      -- archive data
      engine.dataHistory:save()
      -- clean live data
      -- TODO
    end)
    -- configuration schedule
    scheduler:schedule(schedules.configuration, function(t)
      logger:info('Archiving configuration')
      engine.configHistory:save(false, true)
      engine.dataHistory:save(true)
      engine:publishEvent('refresh')
    end)
    -- clean schedule
    scheduler:schedule(schedules.clean, function(t)
      logger:info('Cleaning')
      engine.configHistory:save(true, true)
      engine:publishEvent('clean')
    end)
    self.scheduler = scheduler
  end

  function engine:startHTTPServer()
    local httpServer = http.Server:new()
    httpServer:bind(self.options.address or '::', self.options.port or 8080):next(function()
      logger:info('Server bound to "'..tostring(self.options.address)..'" on port '..tostring(self.options.port))
    end, function(err) -- could failed if address is in use or hostname cannot be resolved
      logger:warn('Cannot bind HTTP server to "'..tostring(self.options.address)..'" on port '..tostring(self.options.port)..' due to '..tostring(err))
      runtime.exit(98)
    end)
    -- optional secure server
    if type(self.options.secure) == 'table' then
      local certFile = self:getAbsoluteFile(certificate or 'cert.pem')
      local pkeyFile = self:getAbsoluteFile(self.options.secure.key or 'pkey.pem')
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
        end, function(err) -- could fail if address is in use or hostname cannot be resolved
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
    httpServer:createContext('/engine/(.*)', httpHandler.rest, {
      attributes = {
        engine = self
      },
      handlers = REST_ENGINE_HANDLERS
    })
    httpServer:createContext('/things/?(.*)', httpHandler.rest, {
      attributes = {
        engine = self
      },
      handlers = REST_THINGS
    })
    httpServer:createContext('/engine/configuration/(.*)', tableHandler, {
      path = 'configuration/',
      editable = true,
      engine = self,
      publish = true
    })
    httpServer:createContext('/engine/data/(.*)', tableHandler, {
      path = 'data/',
      editable = false,
      engine = self,
      publish = true
    })
    httpServer:createContext('/engine/historicalData/(.*)', historicalDataHandler, {
      engine = self
    })
    httpServer:createContext('/engine/scriptFiles/(.*)', httpHandler.files, {
      rootFile = self.scriptsDir,
      allowCreate = true,
      allowDelete = true
    })
    httpServer:createContext('/engine/tmp/(.*)', httpHandler.files, {
      rootFile = self.tmpDir,
      allowCreate = true,
      allowDelete = true
    })
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
    local previousValue = tables.setPath(self.root, path, value)
    if publish and previousValue ~= value then
      logger:info('engine:setRootValue() change('..path..', '..tostring(value)..', '..tostring(previousValue)..')')
      self:publishRootChange(path, value, previousValue)
    end
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
    logger:fine('Publishing Extensions Event '..tostring(name))
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
  end

  function engine:loadThings()
    -- Load the things available in the configuration
    self.things = {}
    for thingId, thingConfiguration in pairs(self.root.configuration.things) do
      if thingConfiguration.active then
        self:loadThing(thingId, thingConfiguration)
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
  end

  function engine:start()
    self:load()
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
    -- save configuration if necessary
    self.configHistory:save(false, true)
    event:stop()
  end

end)