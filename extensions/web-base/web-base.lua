local extension = ...

-- -config.extensions.web-base.assets ../../assets/www_static/

local logger = require('jls.lang.logger')
local event = require('jls.lang.event')
local File = require('jls.io.File')
local HttpExchange = require('jls.net.http.HttpExchange')
local HttpHandler = require('jls.net.http.HttpHandler')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local ZipFileHttpHandler = require('jls.net.http.handler.ZipFileHttpHandler')
local HttpContext = require('jls.net.http.HttpContext')
local WebSocketUpgradeHandler = require('jls.net.http.ws').WebSocketUpgradeHandler
local json = require("jls.util.json")
local Map = require("jls.util.Map")
local List = require("jls.util.List")
local tables = require("jls.util.tables")

local utils = require('lha.utils')

local AddonFileHttpHandler = require('jls.lang.class').create(FileHttpHandler, function(fileHttpHandler)

  function fileHttpHandler:getPath(httpExchange)
    return select(2, httpExchange:getRequestArguments())
  end

end)

local addons = {}
local contexts = {}
local websockets = {}

local function cleanup(server)
  for _, context in ipairs(contexts) do
    server:removeContext(context)
  end
  addons = {}
  contexts = {}
  websockets = {}
end

local function addContext(server, ...)
  local context = server:createContext(...)
  table.insert(contexts, context)
end

local function onWebSocketClose(webSocket)
  logger:fine('WebSocket closed '..tostring(webSocket))
  List.removeFirst(websockets, webSocket)
end

local batchDataChange = true
local dataChangeEvent = nil

local function onDataChange(value, previousValue, path)
  if logger:isLoggable(logger.FINE) then
    logger:fine('onDataChange() "'..tostring(path)..'": "'..tostring(value)..'" '..tostring(#websockets))
  end
  if #websockets == 0 then
    return
  end
  if batchDataChange then
    if not dataChangeEvent then
      event:setTimeout(function()
        local message = json.encode(dataChangeEvent)
        dataChangeEvent = nil
        for _, websocket in ipairs(websockets) do
          websocket:sendTextMessage(message)
        end
      end)
      dataChangeEvent = {event = 'data-change'}
    end
    tables.setPath(dataChangeEvent, path, value)
  else
    local thingId, propertyName = string.match(path, '^data/([^/]+)/([^/]+)$')
    if thingId then
      local message = json.encode({
        event = 'data-change',
        data = {
          [thingId] = {
            [propertyName] = {
              value = value,
              previousValue = previousValue
            }
          }
        }
      })
      for _, websocket in ipairs(websockets) do
        websocket:sendTextMessage(message)
      end
    end
  end
end

function extension:registerAddon(id, addon)
  addons[id] = addon
  logger:info('Web base add-on "'..id..'" registered')
end

function extension:unregisterAddon(name)
  addons[name] = nil
  logger:info('Web base add-on "'..name..'" unregistered')
end

function extension:registerAddonExtension(ext, script)
  local configuration = extension:getConfiguration()
  if script == true then
    script = ext:getId()..'.js'
  end
  self:registerAddon(ext:getId(), {
    handler = AddonFileHttpHandler:new(ext:getDir()):setCacheControl(configuration.cache),
    script = script or 'main.js' -- TODO change to init
  })
end

function extension:unregisterAddonExtension(ext)
  self:unregisterAddon(ext:getId())
end

extension:watchPattern('^data/.*', onDataChange)

extension:subscribeEvent('startup', function()
  local engine = extension:getEngine()
  local configuration = extension:getConfiguration()
  local server = engine:getHTTPServer()

  local assets = utils.getAbsoluteFile(configuration.assets or 'assets', extension:getDir())
  local assetsHandler
  if assets:isDirectory() then
    logger:info('Using assets directory "'..assets:getPath()..'"')
    assetsHandler = FileHttpHandler:new(assets)
  elseif assets:isFile() and string.find(assets:getPathName(), '%.zip$') then
    logger:info('Using assets file "'..assets:getPath()..'"')
    assetsHandler = ZipFileHttpHandler:new(assets)
  else
    assetsHandler = HttpContext.notFoundHandler
    logger:warn('Invalid assets directory "'..assets:getPath()..'"')
  end
  local wwwDir = File:new(extension:getDir(), 'www')

  cleanup(server)
  addContext(server, '/(.*)', FileHttpHandler:new(wwwDir, 'r', 'app.html'):setCacheControl(configuration.cache))
  addContext(server, '/static/(.*)', assetsHandler)
  addContext(server, '/addon/([^/]*)/?(.*)', HttpHandler:new(function(self, exchange)
    local name, path = exchange:getRequestArguments()
    if logger:isLoggable(logger.FINE) then
      logger:fine('add-on handler "'..tostring(name)..'" / "'..tostring(path)..'"')
    end
    if name == '' then
      local list = {}
      for id, addon in pairs(addons) do
        table.insert(list, {
          id = id,
          script = addon.script
        })
      end
      HttpExchange.ok(exchange, json.encode(list), 'application/json')
    else
      local addon = addons[name]
      if addon and addon.handler then
        if logger:isLoggable(logger.FINE) then
          logger:fine('calling add-on "'..tostring(name)..'" handler')
        end
        return addon.handler:handle(exchange)
      end
      HttpExchange.notFound(exchange)
    end
  end))
  addContext(server, '/ws/', Map.assign(WebSocketUpgradeHandler:new(), {
    onOpen = function(_, webSocket, exchange)
      if logger:isLoggable(logger.FINE) then
        logger:fine('WebSocket openned '..tostring(webSocket))
      end
      table.insert(websockets, webSocket)
      webSocket.onClose = onWebSocketClose
    end
  }))
  logger:info('WebSocket available on /ws/')

end)

extension:subscribeEvent('shutdown', function()
  local server = extension:getEngine():getHTTPServer()
  cleanup(server)
end)
