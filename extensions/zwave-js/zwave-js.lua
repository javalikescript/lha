local extension = ...

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local protectedCall = require('jls.lang.protectedCall')
local mqtt = require('jls.net.mqtt')
local WebSocket = require('jls.net.http.ws').WebSocket
local Url = require('jls.net.Url')
local strings = require('jls.util.strings')
local json = require('jls.util.json')
local Map = require('jls.util.Map')

local Thing = require('lha.Thing')

--logger = logger:getClass():new(); logger:setLevel(logger.FINE)

-- command classes
-- 0x20..0xEE Application Command Classes
local CC = {
  MULTILEVEL = 49,
  ALARM = 113,
  BATTERY = 128,
}

local function getNodeName(node, default)
  if node.name and node.name ~= '' then
    return node.name
  elseif node.productDescription and node.productDescription ~= '' then
    return node.productDescription
  end
  return node.productLabel or node.label or default or 'Unknown'
end

local function getNodeDeviceId(node)
  if node.deviceId then
    return node.deviceId
  end
  if node.manufacturerId and node.productId and node.productType then
    return tostring(node.manufacturerId)..'-'..tostring(node.productId)..'-'..tostring(node.productType)
  end
end

local function getNodeDiscoveryId(node)
  -- TODO use node id
  local nodeId = node.nodeId or node.id
  local deviceId = getNodeDeviceId(node)
  if nodeId and deviceId then
    return nodeId..'-'..deviceId
  end
end

local function createThingFromNode(node)
  local productLabel = node.productLabel or node.label
  if productLabel == 'FGSD002' then
    return Thing:new(getNodeName(node, 'Smoke Detector'), 'Smoke Sensor', {
      Thing.CAPABILITIES.SmokeSensor,
      Thing.CAPABILITIES.TemperatureSensor,
    }):addPropertiesFromNames('smoke', 'temperature')
  end
end

local function updateThingFromNodeInfo(thing, info)
  local cc = info.commandClass
  local property = info.property
  local value = info.value or info.newValue
  if cc == CC.MULTILEVEL then
    if property == 'Air temperature' then
      thing:updatePropertyValue('temperature', value)
    end
  elseif cc == CC.ALARM then
    if property == 'Smoke Alarm' then
      thing:updatePropertyValue('smoke', value ~= 0)
    end
  end
end

local function updateThingFromNode(thing, node)
  if node.values then
    -- key is cc-?endpoint-property: '49-0-Air temperature'
    for _, value in pairs(node.values) do
      updateThingFromNodeInfo(thing, value)
    end
  end
end


local mqttClient
local webSocket
local thingsMap = {}

local function onZWaveNode(node)
  local did = getNodeDiscoveryId(node)
  if did then
    local thing = thingsMap[did]
    if thing == nil then
      thing = createThingFromNode(node)
      if thing then
        logger:info('Z-Wave node '..did..' found '..thing:getTitle()..' "'..thing:getDescription()..'"')
        extension:discoverThing(did, thing)
      else
        thing = false
      end
      thingsMap[did] = thing
    end
    if thing then
      updateThingFromNode(thing, node)
    end
  end
end

local function onZWaveNodeEvent(event)
  -- see https://zwave-js.github.io/node-zwave-js/#/api/node?id=zwavenode-events
  if event.source == 'node' and event.event == 'value updated' then
    local nodeId = event.nodeId
    local thing = thingsMap[nodeId]
    if thing then
      updateThingFromNodeInfo(thing, event.args)
    end
  end
end

local function cleanup()
  if mqttClient then
    mqttClient:close(false)
    mqttClient = nil
  end
  if webSocket then
    webSocket:close(false)
    webSocket = nil
  end
end


------------------------------------------------------------
-- MQTT
------------------------------------------------------------

local function startMqtt(mqttConfig)
  local tUrl = Url.parse(mqttConfig.url)
  if tUrl.scheme ~= 'tcp' then
    logger:warn('Invalid scheme')
    return
  end
  local apiTopic = mqttConfig.prefix..'/_CLIENTS/ZWAVE_GATEWAY-'..mqttConfig.name..'/api/'
  local eventTopic = mqttConfig.prefix..'/_EVENTS_/ZWAVE_GATEWAY-'..mqttConfig.name..'/'
  local apiPattern = '^'..strings.escape(apiTopic)..'([^/]+)$'
  local nodeStatusPattern = '^'..strings.escape(mqttConfig.prefix)..'/([^/]+)/([^/]+)/status$'
  logger:info('Z-Wave JS API pattern "'..apiPattern..'"')
  mqttClient = mqtt.MqttClient:new()
  function mqttClient:onMessage(topicName, payload)
    if logger:isLoggable(logger.FINER) then
      logger:finer('Received on topic "'..topicName..'": '..payload)
    end
    local nodeLocation, nodeName = string.match(topicName, nodeStatusPattern)
    if nodeLocation then
      local t = json.decode(payload)
      if t then
        logger:info('Z-Wave JS node status "'..nodeLocation..'" "'..nodeName..'": '..json.stringify(t, 2))
      end
    end
    local apiName = string.match(topicName, apiPattern)
    if apiName then
      if logger:isLoggable(logger.FINE) then
        logger:fine('Z-Wave JS API "'..apiName..'": '..payload)
      end
      local t = json.decode(payload)
      if t and t.success then
        logger:fine('Z-Wave JS API "'..apiName..'": '..json.stringify(t, 2))
        if apiName == 'getNodes' then
          for _, node in ipairs(t.result) do
            onZWaveNode(node)
          end
        end
      end
    end
  end
  mqttClient:connect(tUrl.host, tUrl.port):next(function()
    logger:info('Z-Wave JS connected to Broker "'..mqttConfig.url..'"')
    local statusTopic = mqttConfig.prefix..'/+/+/status'
    local topicNames = {
      apiTopic..'+',
      statusTopic,
      eventTopic..'#', -- To remove
    }
    mqttClient:subscribe(topicNames, mqttConfig.qos):next(function()
      logger:info('Z-Wave JS subscribed to topics "'..table.concat(topicNames, '", "')..'"')
      mqttClient:publish(apiTopic..'getNodes/set', '{}'):next(function()
        logger:info('Z-Wave JS getNodes published')
      end)
    end)
  end)
end


------------------------------------------------------------
-- WebSocket
------------------------------------------------------------

local function sendWebSocket(command, options)
  if webSocket then
    webSocket.zwMsgId = webSocket.zwMsgId + 1
    local messageId = 'lha-zwave-js-'..tostring(webSocket.zwMsgId)
    logger:finest('sendWebSocket('..tostring(command)..') '..messageId)
    local message = {
      command = command,
      messageId = messageId
    }
    if options then
      Map.assign(message, options)
    end
    local textMsg = json.encode(message)
    logger:finer('message: '..textMsg)
    return webSocket:sendTextMessage(textMsg):next(function()
      local promise, cb = Promise.createWithCallback()
      webSocket.zwMsgCb[messageId] = cb
      return promise
    end)
  end
  return Promise.reject()
end

local function startWebSocket(wsConfig)
  webSocket = WebSocket:new(wsConfig.url)
  webSocket.zwMsgId = 0
  webSocket.zwMsgCb = {}
  webSocket:open():next(function()
    webSocket:readStart()
    logger:info('Z-Wave JS WebSocket connected on '..tostring(wsConfig.url))
    --sendWebSocket('set_api_schema', {schemaVersion = 15})
  end, function(reason)
    logger:warn('Cannot open Z-Wave JS WebSocket on '..tostring(wsConfig.url)..' due to '..tostring(reason))
  end)
  webSocket.onClose = function()
    logger:warn('Z-Wave JS WebSocket closed')
    webSocket = nil
  end
  webSocket.onTextMessage = function(_, payload)
    if logger:isLoggable(logger.FINEST) then
      logger:finest('Z-Wave WebSocket received '..tostring(payload))
    end
    local status, message = protectedCall(json.decode, payload)
    if status and message and message.type then
      if message.type == 'event' and message.event then
        if logger:isLoggable(logger.FINER) then
          logger:finer('Z-Wave JS event: '..json.stringify(message.event, 2))
        end
        onZWaveNodeEvent(message.event)
      elseif message.type == 'result' then
        local cb = webSocket.zwMsgCb[message.messageId]
        if cb then
          logger:finer('Z-Wave JS WebSocket result '..message.messageId)
          webSocket.zwMsgCb[message.messageId] = nil
          if message.success and message.result then
            cb(nil, message.result)
          else
            local reason = tostring(message.errorCode)
            if message.errorCode == 'zwave_error' then
              reason = tostring(message.zwaveErrorCode)..': '..tostring(message.zwaveErrorMessage)
            end
            cb(reason)
          end
        end
      elseif message.type == 'version' then
        sendWebSocket('start_listening'):next(function(result)
          for _, node in ipairs(result.state.nodes) do
            onZWaveNode(node)
          end
        end)
      else
        logger:warn('Z-Wave JS WebSocket unsupported message type '..tostring(message.type))
      end
    else
      logger:warn('Z-Wave WebSocket received invalid JSON payload '..tostring(payload))
    end
  end
end


------------------------------------------------------------
-- Extension events
------------------------------------------------------------

extension:subscribeEvent('things', function()
  thingsMap = extension:getThingsByDiscoveryKey()
end)

extension:subscribeEvent('poll', function()
  local configuration = extension:getConfiguration()
  if webSocket then
    -- TODO poll nodes
    --onZWaveNode(node)
  elseif configuration.websocket and configuration.websocket.enable then
    startWebSocket(configuration.websocket)
  end
end)

extension:subscribeEvent('startup', function()
  local configuration = extension:getConfiguration()
  cleanup()
  if configuration.mqtt and configuration.mqtt.enable then
    startMqtt(configuration.mqtt)
  end
  if configuration.websocket and configuration.websocket.enable then
    startWebSocket(configuration.websocket)
  end
end)

extension:subscribeEvent('shutdown', function()
  logger:info('shutdown Z-Wave JS extension')
  cleanup()
end)
