local logger = require('jls.lang.logger')
local runtime = require('jls.lang.runtime')
local event = require('jls.lang.event')
local File = require('jls.io.File')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
local HttpExchange = require('jls.net.http.HttpExchange')
local json = require('jls.util.json')
local Date = require('jls.util.Date')
local Map = require('jls.util.Map')
local ZipFile = require('jls.util.zip.ZipFile')

local utils = require('lha.utils')

local engineSchema = utils.requireJson('lha.schema').properties.config.properties.engine

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
    save = function(exchange)
      exchange.attributes.engine.configHistory:saveJson()
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
  ['restart?method=POST'] = function(exchange)
    event:setTimeout(function()
      exchange.attributes.engine:stop()
      runtime.gc()
      exchange.attributes.engine:start()
    end, 100)
    return 'In progress'
  end,
  ['stop?method=POST'] = function(exchange)
    event:setTimeout(function()
      exchange.attributes.engine:stop()
      event:stop()
    end, 100)
    return 'In progress'
  end,
  ['gc?method=POST'] = function(exchange)
    runtime.gc()
    return 'Done'
  end,
  info = function(exchange)
    local engine = exchange:getAttribute('engine')
    local httpServer = engine:getHTTPServer()
    --local ip, port = httpServer:getAddress()
    return {
      ['CPU Time'] = os.clock(),
      ['Server Time'] = os.time(),
      ['Server Date'] = os.date(),
      ['Lua Memory Size'] = math.floor(collectgarbage('count') * 1024),
      ['Lua Registry Entries'] = Map.size(debug.getregistry()),
      ['Loaded Packages'] = Map.size(package.loaded),
      ['HTTP Clients'] = Map.size(httpServer.pendings),
    }
  end,
  backup = {
    ['create?method=POST'] = function(exchange)
      local engine = exchange:getAttribute('engine')
      local ts = Date.timestamp()
      local backup = File:new(engine:getTemporaryDirectory(), 'lha_backup.'..ts..'.zip')
      engine:saveThingValues()
      engine.configHistory:saveJson()
      engine.dataHistory:saveJson()
      ZipFile.zipTo(backup, engine:getWorkDirectory():listFiles(function(file)
        return file:getName() ~= 'tmp'
      end))
      engine.configHistory:removeJson()
      engine.dataHistory:removeJson()
      engine:getThingValuesFile():delete()
      return backup:getName()
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
      workNew:deleteRecursive()
      workOld:deleteRecursive()
      workNew:mkdir()
      ZipFile.unzipTo(backup, workNew)
      local tmpDir = File:new(workNew, 'tmp')
      local tmpNew = File:new(workNew, 'tmp')
      engine:stop()
      if tmpDir:isDirectory() then
        tmpDir:renameTo(tmpNew)
      else
        tmpNew:mkdir()
      end
      workDir:renameTo(workOld)
      workNew:renameTo(workDir)
      engine:start()
      workOld:deleteRecursive()
    end
  },
  getLogLevel = function(exchange)
    return logger:getClass().levelToString(logger:getLevel())
  end,
  ['setLogLevel?method=POST'] = function(exchange)
    local request = exchange:getRequest()
    logger:setLevel(request:getBody())
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
      if method == HTTP_CONST.METHOD_GET then
        return thing:asEngineThingDescription()
      elseif method == HTTP_CONST.METHOD_DELETE then
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
  admin = REST_ADMIN
}
