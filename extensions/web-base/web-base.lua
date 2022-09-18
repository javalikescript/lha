local extension = ...

-- -config.extensions.web-base.assets ../../assets/www_static/

local class = require('jls.lang.class')
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

local Logger = logger:getClass()
local recordLog = Logger.getLogRecorder()

local AddonFileHttpHandler = class.create(FileHttpHandler, function(fileHttpHandler)
  function fileHttpHandler:getPath(httpExchange)
    return select(2, httpExchange:getRequestArguments())
  end
end)

local RollingList = class.create(List, function(rollingList)
  function rollingList:initialize(size)
    self.index = size
    self.size = size
  end
  function rollingList:add(value)
    if value == nil then
      error('Cannot add nil value')
    end
    local i = self.index % self.size + 1
    local dropped = self[i]
    self[i] = value
    self.index = i
    if dropped then
      self:onDropped(dropped)
    end
    return self
  end
  function rollingList:onDropped(value)
  end
  function rollingList:values()
    if #self ~= self.size or self.index == self.size then
      return self
    end
    local l = {}
    table.move(self, self.index + 1, self.size, 1, l)
    table.move(self, 1, self.index, 1, l)
    return l
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
  Logger.setLogRecorder(recordLog)
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
  if script == true then
    script = ext:getId()..'.js'
  end
  self:registerAddon(ext:getId(), {
    handler = AddonFileHttpHandler:new(ext:getDir()),
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

  cleanup(server)

  local maxMessageSize = 1024
  local maxMessageCount = 60
  local warnMessages = RollingList:new(maxMessageCount // 3)
  local logMessages = RollingList:new(maxMessageCount - maxMessageCount // 3)
  function logMessages:onDropped(value)
    if value.level >= logger.WARN then
      warnMessages:add(value)
    end
  end
  local bufferMessages
  Logger.setLogRecorder(function(lgr, time, level, message)
    recordLog(lgr, time, level, message)
    if #message > maxMessageSize then
      message = string.sub(message, 1, maxMessageSize - 3)..'...'
    end
    local value = {
      time = time, level = level, message = message
    }
    logMessages:add(value)
    if #websockets == 0 then
      bufferMessages = nil
    else
      if not bufferMessages then
        event:setTimeout(function()
          local content = json.encode(bufferMessages)
          bufferMessages = nil
          for _, websocket in ipairs(websockets) do
            websocket:sendTextMessage(content)
          end
        end)
        bufferMessages = {event = 'logs', logs = {}}
      end
      table.insert(bufferMessages.logs, value)
    end
  end)

  local assets = utils.getAbsoluteFile(configuration.assets or 'assets', extension:getDir())
  local assetsHandler
  if assets:isFile() then
    if string.find(assets:getPathName(), '%.zip$') then
      logger:info('Using assets file "'..assets:getPath()..'"')
      assetsHandler = ZipFileHttpHandler:new(assets)
    else
      logger:warn('Invalid assets file "'..assets:getPath()..'"')
      assetsHandler = HttpContext.notFoundHandler
    end
  else
    if assets:isDirectory() then
      logger:info('Using assets directory "'..assets:getPath()..'"')
    else
      logger:warn('Missing assets directory "'..assets:getPath()..'"')
    end
    assetsHandler = FileHttpHandler:new(assets):setCacheControl(configuration.cache)
  end
  local wwwDir = File:new(extension:getDir(), 'www')

  addContext(server, '/(.*)', FileHttpHandler:new(wwwDir, 'r', 'app.html'))
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
  addContext(server, '/logs/', HttpHandler:new(function(self, exchange)
    local l = List.concat({}, logMessages:values(), warnMessages:values())
    HttpExchange.ok(exchange, json.stringify(l), 'application/json')
  end))
  logger:info('WebSocket available on /ws/')

end)

extension:subscribeEvent('shutdown', function()
  local server = extension:getEngine():getHTTPServer()
  cleanup(server)
end)
