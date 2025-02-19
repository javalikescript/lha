local rootLogger = require('jls.lang.logger')
local Logger = rootLogger:getClass()
local logger = rootLogger:get(...)
local system = require('jls.lang.system')
local event = require('jls.lang.event')
local loader = require('jls.lang.loader')
local File = require('jls.io.File')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
local HttpExchange = require('jls.net.http.HttpExchange')
local json = require('jls.util.json')
local Date = require('jls.util.Date')
local Map = require('jls.util.Map')
local ZipFile = require('jls.util.zip.ZipFile')
local Promise = require('jls.lang.Promise')

local md = loader.tryRequire('md')

local utils = require('lha.utils')

local engineSchema = utils.requireJson('lha.schema').properties.config.properties.engine

local function refreshThingsDescription(engine, extension)
  local publisher
  local things
  if extension then
    publisher = extension
    things = extension:getThings()
  else
    publisher = engine
    things = engine.things
  end
  local thingIds = Map.skeys(things)
  if #thingIds == 0 then
    return
  end
  logger:info('Disabling %d things', #thingIds)
  things = {}
  for _, thingId in ipairs(thingIds) do
    local thing = engine:getThingById(thingId)
    local extensionId, discoveryKey = engine:getThingDiscoveryKey(thingId)
    if thing and extensionId and discoveryKey then
      things[thingId] = thing
      engine:disableThing(thingId)
      logger:info('Thing %s (%s %s/%s) disabled', thing, thingId, extensionId, discoveryKey)
    end
  end
  publisher:publishEvent('things')
  publisher:publishEvent('poll') -- poll is used for discovery
  thingIds = Map.skeys(things)
  return Promise:new(function(resolve, reject)
    local count, maxCount = 0, 5
    local timer
    timer = event:setInterval(function()
      count = count + 1
      logger:info('Discovering %d things %d/%d', #thingIds, count, maxCount)
      for _, thingId in ipairs(thingIds) do
        local extensionId, discoveryKey = engine:getThingDiscoveryKey(thingId)
        if engine:getDiscoveredThing(extensionId, discoveryKey) then
          local discoveredThing = engine:addDiscoveredThing(extensionId, discoveryKey)
          local thing = things[thingId]
          things[thingId] = nil
          -- keep title and description
          local thingConfiguration = engine:getThingConfigurationById(thingId)
          local thingDescription = thingConfiguration and thingConfiguration.description
          discoveredThing:setTitle(thing:getTitle())
          discoveredThing:setDescription(thing:getDescription())
          thingDescription.title = thing:getTitle()
          thingDescription.description = thing:getDescription()
          -- restore values
          local values = thing:getPropertyValues()
          for name, value in pairs(values) do
            if discoveredThing:getPropertyValue(name) == nil then
              logger:fine('Restoring thing %s value %s %s', thing, name, value)
              discoveredThing:updatePropertyValue(name, value)
            end
          end
          logger:fine('Thing %s (%s) discovered', thing, thingId)
        end
      end
      thingIds = Map.skeys(things)
      if #thingIds == 0 or count >= maxCount then
        event:clearInterval(timer)
        logger:info('Discovered ended, missing %d things', #thingIds)
        for thingId, thing in pairs(things) do
          engine.things[thingId] = thing
          logger:warn('Thing %s (%s) restored', thing, thingId)
          local thingConfiguration = engine:getThingConfigurationById(thingId)
          if thingConfiguration then
            thingConfiguration.active = true
          end
        end
        publisher:publishEvent('things')
        resolve()
      end
    end, 1000)
  end)
end

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
    config = function(exchange)
      return exchange.attributes.extension:getConfiguration()
    end,
    info = function(exchange)
      return exchange.attributes.extension:toJSON()
    end,
    manifest = function(exchange)
      return exchange.attributes.extension:getManifest()
    end,
    ['readme(extension)'] = function(exchange, extension)
      local readme = File:new(extension:getDir(), extension:readme())
      if not readme:isFile() then
        HttpExchange.notFound(exchange)
        return false
      end
      local readmeExt = string.lower(readme:getExtension())
      local content = readme:readAll()
      if readmeExt == 'md' then
        if md then
          content = md.render(content)
        else
          content = '<pre>'..content..'</pre>'
        end
      elseif readmeExt == 'txt' then
        content = '<pre>'..content..'</pre>'
      elseif not (readmeExt == 'html' or readmeExt == 'htm') then
        HttpExchange.notFound(exchange)
        return false
      end
      local response = exchange:getResponse()
      response:setStatusCode(HTTP_CONST.HTTP_OK, 'OK')
      response:setContentType('text/html')
      response:setContentLength(#content)
      response:setBody(content)
      return false
    end,
    ['poll(extension)?method=POST'] = function(exchange, extension)
      if extension:isActive() then
        extension:publishEvent('poll')
      end
    end,
    action = {
      ['{index}(extension, index, requestJson)?method=POST'] = function(exchange, extension, index, arguments)
        local actions = extension:getManifest('actions')
        index = math.tointeger(index)
        local action = index and actions and actions[index]
        if action and action.method then
          local method = extension[action.method]
          if type(method) ~= 'function' then
            HttpExchange.internalServerError(exchange, 'The action method is not available')
          elseif action.active ~= nil and action.active ~= extension:isActive() then
            HttpExchange.badRequest(exchange, 'The extension active state does not match')
          elseif (action.arguments and #action.arguments or 0) ~= (arguments and #arguments or 0) then
            HttpExchange.badRequest(exchange, 'The action arguments are invalid')
          else
            return utils.toResponse(method, extension, exchange, table.unpack(arguments))
          end
        else
          HttpExchange.notFound(exchange)
        end
        return false
      end
    },
    ['test(extension)?method=POST'] = function(exchange, extension)
      extension:publishEvent('test')
    end,
    ['refreshThingsDescription(extension)?method=POST'] = function(exchange, extension)
      local engine = exchange:getAttribute('engine')
      if extension:isActive() then
        return refreshThingsDescription(engine, extension)
      end
    end,
    -- curl -X POST http://localhost:8080/engine/extensions/web-base/reload
    ['reload(extension)?method=POST'] = function(exchange, extension)
      extension:restartExtension()
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

local REST_ADMIN = {
  configuration = {
    ['save?method=POST'] = function(exchange)
      exchange.attributes.engine.configHistory:saveJson()
      return 'Done'
    end
  },
  data = {
    ['save?method=POST'] = function(exchange)
      exchange.attributes.engine.dataHistory:saveJson()
      return 'Done'
    end
  },
  ['reloadExtensions?method=POST'] = function(exchange)
    local mode = RestHttpHandler.shiftPath(exchange:getAttribute('path'))
    exchange.attributes.engine:reloadExtensions(mode == 'full', true)
    return 'Done'
  end,
  ['reloadScripts?method=POST'] = function(exchange)
    local mode = RestHttpHandler.shiftPath(exchange:getAttribute('path'))
    exchange.attributes.engine:reloadScripts(mode == 'full')
    return 'Done'
  end,
  ['reboot?method=POST'] = function(exchange)
    event:setTimeout(function()
      local engine = exchange:getAttribute('engine')
      engine:stop()
      --local installName = 'lha_reboot_install.zip'
      --local installFile = File:new(engine.rootDir, installName)
      --if installFile:isFile() then
      --  logger:info('Installing "%s"', installName)
      --  ZipFile.unzipTo(installFile, engine.rootDir)
      --end
      system.halt(11)
    end, 100)
    return 'In progress'
  end,
  ['restart?method=POST'] = function(exchange)
    event:setTimeout(function()
      exchange.attributes.engine:stop()
      system.gc()
      exchange.attributes.engine:start()
    end, 100)
    return 'In progress'
  end,
  -- curl -X POST http://localhost:8080/engine/stop
  ['stop?method=POST'] = function(exchange)
    event:setTimeout(function()
      exchange.attributes.engine:stop()
      event:stop()
    end, 100)
    return 'In progress'
  end,
  ['gc?method=POST'] = function(exchange)
    system.gc()
    return 'Done'
  end,
  info = function(exchange)
    local engine = exchange:getAttribute('engine')
    local httpServer = engine:getHTTPServer()
    --local ip, port = httpServer:getAddress()
    local httpsExt = engine:getExtensionById('https')
    local httpsServer = httpsExt and httpsExt:getHTTPServer()
    local webBaseExt = engine:getExtensionById('web-base')
    local webBaseInfo = webBaseExt and webBaseExt:getWebBaseInfo()
    return {
      ['CPU Time'] = os.clock(),
      ['Server Time'] = os.time(),
      ['Server Date'] = os.date(),
      ['Lua Memory Size'] = math.floor(collectgarbage('count') * 1024),
      ['Lua Registry Entries'] = Map.size(debug.getregistry()),
      ['Loaded Packages'] = Map.size(package.loaded),
      ['HTTP Clients'] = Map.size(httpServer.pendings),
      ['HTTPS Clients'] = httpsServer and Map.size(httpsServer.pendings) or 0,
      ['Web Base Addons'] = webBaseInfo and webBaseInfo.addons or 0,
      ['Web Base WebSockets'] = webBaseInfo and webBaseInfo.websockets or 0,
    }
  end,
  backup = {
    ['create?method=POST'] = function(exchange)
      local engine = exchange:getAttribute('engine')
      local ts = Date.timestamp()
      -- TODO add host name in file name
      local backup = File:new(engine:getTemporaryDirectory(), 'lha_backup.'..ts..'.zip')
      engine:saveThingValues()
      engine.configHistory:saveJson()
      engine.dataHistory:saveJson()
      return ZipFile.zipToAsync(backup, engine:getWorkDirectory():listFiles(function(file)
        return file:getName() ~= 'tmp'
      end)):finally(function()
        engine.configHistory:removeJson()
        engine.dataHistory:removeJson()
        engine:getThingValuesFile():delete()
      end):next(function()
        return backup:getName()
      end)
    end,
    ['deploy?method=POST'] = function(exchange)
      local backupName = exchange:getRequest():getBody() or 'lha_backup.zip'
      local engine = exchange:getAttribute('engine')
      local backup = File:new(engine:getTemporaryDirectory(), backupName)
      if not backup:isFile() then
        HttpExchange.notFound(exchange)
        return false
      end
      local workDir = engine:getWorkDirectory()
      local workNew = File:new(workDir:getParentFile(), 'work_new')
      local workOld = File:new(workDir:getParentFile(), 'work_old')
      if not (workNew:deleteRecursive() and workNew:mkdir() and workOld:deleteRecursive()) then
        HttpExchange.internalServerError(exchange)
        return false
      end
      if not ZipFile.unzipTo(backup, workNew) then
        HttpExchange.badRequest(exchange)
        return false
      end
      local tmpDir = File:new(workDir, 'tmp')
      local tmpNew = File:new(workNew, 'tmp')
      event:setTimeout(function()
        engine:stop() -- stops the HTTP server
        if tmpDir:isDirectory() then
          tmpDir:renameTo(tmpNew)
        else
          tmpNew:mkdir()
        end
        if workDir:renameTo(workOld) and workNew:renameTo(workDir) then
          engine:start()
          workOld:deleteRecursive()
        else
          logger:warn('Fail to deploy, please check and re start manually')
        end
      end, 100)
      return 'In progress'
    end
  },
  getLogLevel = function(exchange)
    return Logger.levelToString(rootLogger:getLevel())
  end,
  ['setLogLevel?method=POST'] = function(exchange)
    local request = exchange:getRequest()
    rootLogger:setLevel(request:getBody())
  end,
  ['setLogConfig?method=POST'] = function(exchange)
    local request = exchange:getRequest()
    rootLogger:setConfig(request:getBody())
  end
}

local REST_THINGS = {
  [''] = function(exchange)
    local engine = exchange:getAttribute('engine')
    local request = exchange:getRequest()
    local method = string.upper(request:getMethod())
    if method == HTTP_CONST.METHOD_GET then
      local list = {}
      for thingId, thing in pairs(engine.things) do
        table.insert(list, thing:asEngineThingDescription())
      end
      return list
    elseif method == HTTP_CONST.METHOD_PUT then
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
  ['{thingId}'] = { -- TODO review routing
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
      if method == HTTP_CONST.METHOD_GET then
        return thing:asEngineThingDescription()
      elseif method == HTTP_CONST.METHOD_DELETE then
        engine:disableThing(thingId)
        engine:publishEvent('things')
      elseif method == HTTP_CONST.METHOD_POST then
        local thingConfiguration = engine:getThingConfigurationById(thingId)
        local thingDescription = thingConfiguration and thingConfiguration.description
        if thingDescription then
          local thingDesc = json.decode(request:getBody())
          -- TODO Allow properties modifications?
          for _, key in pairs({'title', 'description'}) do
            local value = thingDesc[key]
            if value then
              thing[key] = value
              thingDescription[key] = value
            end
          end
        end
      else
        HttpExchange.methodNotAllowed(exchange)
        return false
      end
    end,
  },
}

return {
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
  ['refreshThingsDescription?method=POST'] = function(exchange)
    local engine = exchange:getAttribute('engine')
    return refreshThingsDescription(engine)
  end,
  ['poll?method=POST'] = function(exchange)
    exchange.attributes.engine:publishEvent('poll')
    return 'Polled'
  end,
  ['publishEvent?method=POST'] = function(exchange)
    local eventName = exchange:getRequest():getBody()
    exchange.attributes.engine:publishEvent(eventName)
    return 'Published'
  end,
  ['saveData?method=POST'] = function(exchange)
    exchange.attributes.engine.dataHistory:save(false)
    return 'Saved'
  end,
  ['saveHistory?method=POST'] = function(exchange)
    exchange.attributes.engine.configHistory:save(false)
    return 'Saved'
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
  things = REST_THINGS,
  schema = function(exchange)
    return engineSchema
  end,
  user = function(exchange)
    local session = exchange:getSession()
    if session then
      local user = session.attributes.user
      return {
        name = user and user.name,
        logged = user ~= nil,
        permission = session.attributes.permission
      }
    end
    return {
      permission = 'rwca'
    }
  end,
  admin = REST_ADMIN
}
