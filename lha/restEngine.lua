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
  ['(engine)'] = function(_, engine)
    local list = {}
    for _, extension in ipairs(engine.extensions) do
      if extension:isLoaded() and extension:getType() ~= 'script' then
        table.insert(list, extension:toJSON())
      end
    end
    return list
  end,
  ['{+extension}(engine)'] = function(exchange, extensionId, engine)
    return engine:getExtensionById(extensionId)
  end,
  ['{extensionId}'] = {
    ['(extension)'] = function(_, extension)
      return {
        config = extension:getConfiguration(),
        info = extension:toJSON(),
        manifest = extension:getManifest()
      }
    end,
    ['config(extension)'] = function(_, extension)
      return extension:getConfiguration()
    end,
    ['info(extension)'] = function(_, extension)
      return extension:toJSON()
    end,
    ['manifest(extension)'] = function(_, extension)
      return extension:getManifest()
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
    ['poll(extension)?method=POST'] = function(_, extension)
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
    ['test(extension)?method=POST'] = function(_, extension)
      extension:publishEvent('test')
    end,
    ['refreshThingsDescription(extension, engine)?method=POST'] = function(_, extension, engine)
      if extension:isActive() then
        return refreshThingsDescription(engine, extension)
      end
    end,
    -- curl -X POST http://localhost:8080/engine/extensions/web-base/reload
    ['reload(extension)?method=POST'] = function(_, extension)
      extension:restartExtension()
    end,
    ['enable(extension)?method=POST'] = function(_, extension)
      if not extension:isActive() then
        extension:setActive(true)
        if extension:isActive() then
          extension:publishEvent('startup')
          extension:publishEvent('things')
        end
      end
    end,
    ['disable(extension)?method=POST'] = function(_, extension)
      if extension:isActive() then
        extension:publishEvent('shutdown')
        extension:setActive(false)
      end
    end
  },
}

local REST_ADMIN = {
  configuration = {
    ['save(engine)?method=POST'] = function(_, engine)
      engine.configHistory:saveJson()
      return 'Done'
    end
  },
  data = {
    ['save(engine)?method=POST'] = function(_, engine)
      engine.dataHistory:saveJson()
      return 'Done'
    end
  },
  ['reloadExtensions(engine, path)?method=POST'] = function(_, engine, path)
    local mode = RestHttpHandler.shiftPath(path)
    engine:reloadExtensions(mode == 'full', true)
    return 'Done'
  end,
  ['reloadScripts(engine)?method=POST'] = function(_, engine, path)
    local mode = RestHttpHandler.shiftPath(path)
    engine:reloadScripts(mode == 'full')
    return 'Done'
  end,
  ['reboot(engine)?method=POST'] = function(_, engine)
    event:setTimeout(function()
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
  ['restart(engine)?method=POST'] = function(_, engine)
    event:setTimeout(function()
      engine:stop()
      system.gc()
      engine:start()
    end, 100)
    return 'In progress'
  end,
  -- curl -X POST http://localhost:8080/engine/stop
  ['stop(engine)?method=POST'] = function(_, engine)
    event:setTimeout(function()
      engine:stop()
      event:stop()
    end, 100)
    return 'In progress'
  end,
  ['gc?method=POST'] = function()
    system.gc()
    return 'Done'
  end,
  ['info(engine)'] = function(_, engine)
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
    ['create(engine)?method=POST'] = function(_, engine)
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
    ['deploy(engine)?method=POST'] = function(exchange, engine)
      local backupName = exchange:getRequest():getBody() or 'lha_backup.zip'
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
  getLogLevel = function()
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
  ['(engine)?method=GET'] = function(_, engine)
    local list = {}
    for _, thing in pairs(engine.things) do
      table.insert(list, thing:asEngineThingDescription())
    end
    return list
  end,
  ['(engine, requestJson)?method=PUT'] = function(_, engine, discoveredThings)
    -- curl -X PUT --data-binary "@work\tmp\discoveredThings2.json" http://localhost:8080/engine/things
    for _, discoveredThing in ipairs(discoveredThings) do
      if discoveredThing.extensionId and discoveredThing.discoveryKey then
        engine:addDiscoveredThing(discoveredThing.extensionId, discoveredThing.discoveryKey)
      end
    end
    engine:publishEvent('things')
  end,
  ['{+thing}(engine)'] = function(_, thingId, engine)
    return engine.things[thingId]
  end,
  ['{thingId}'] = {
    ['(thing)?method=GET'] = function(_, thing)
      return thing:asEngineThingDescription()
    end,
    ['(engine, thingId, thing, requestJson)?method=POST'] = function(exchange, engine, thingId, thing, thingDesc)
      local thingConfiguration = engine:getThingConfigurationById(thingId)
      local thingDescription = thingConfiguration and thingConfiguration.description
      if not thingDescription then
        HttpExchange.notFound(exchange)
        return false
      end
      -- TODO Allow properties modifications?
      for _, key in pairs({'title', 'description'}) do
        local value = thingDesc[key]
        if value then
          thing[key] = value
          thingDescription[key] = value
        end
      end
    end,
    ['(engine, thingId)?method=DELETE'] = function(_, engine, thingId)
      engine:disableThing(thingId)
      engine:publishEvent('things')
    end,
  },
}

return {
  ['discoveredThings(engine)'] = function(_, engine)
    -- curl http://localhost:8080/engine/discoveredThings
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
  ['refreshThingsDescription(engine)?method=POST'] = function(_, engine)
    return refreshThingsDescription(engine)
  end,
  ['cleanupDisabledThings(engine)?method=POST'] = function(_, engine)
    engine:cleanThings(true)
    return 'Removed'
  end,
  ['poll(engine)?method=POST'] = function(_, engine)
    engine:publishEvent('poll')
    return 'Polled'
  end,
  ['publishEvent(engine)?method=POST'] = function(exchange, engine)
    local eventName = exchange:getRequest():getBody()
    engine:publishEvent(eventName)
    return 'Published'
  end,
  ['saveData(engine)?method=POST'] = function(_, engine)
    engine.dataHistory:save(false)
    return 'Saved'
  end,
  ['saveHistory(engine)?method=POST'] = function(_, engine)
    engine.configHistory:save(false)
    return 'Saved'
  end,
  ['properties(engine)'] = function(_, engine)
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
