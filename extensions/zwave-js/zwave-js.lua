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
local Date = require('jls.util.Date')

local Thing = require('lha.Thing')

--logger = logger:getClass():new(); logger:setLevel(logger.FINE)

-- command classes
-- 0x20..0xEE Application Command Classes
local CC = {
  SWITCH_MULTILEVEL = 38,
  SENSOR_MULTILEVEL = 49,
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
    return tostring(nodeId)..'-'..deviceId
  end
end

local function findNodeValue(node, commandClass, property)
  if node.values then
    for _, info in pairs(node.values) do
      if info.commandClass == commandClass and info.property == property then
        return info
      end
    end
  end
end

local function createThingFromNode(node)
  local productLabel = node.productLabel or node.label
  local thing
  -- we may add properties based on the CC
  if productLabel == 'FGSD002' then
    thing = Thing:new(getNodeName(node, 'Smoke Detector'), 'Smoke Sensor', {
      Thing.CAPABILITIES.SmokeSensor,
      Thing.CAPABILITIES.TemperatureSensor,
    }):addPropertiesFromNames('smoke', 'temperature', 'battery')
  elseif productLabel == 'ZSE44' then
    thing = Thing:new(getNodeName(node, 'Temperature Sensor'), 'Temperature Sensor', {
      Thing.CAPABILITIES.HumiditySensor,
      Thing.CAPABILITIES.TemperatureSensor,
    }):addPropertiesFromNames('humidity', 'temperature', 'battery')
  elseif productLabel == 'ZMNHUD' then
    thing = Thing:new(getNodeName(node, 'Pilot Wire'), 'Pilot Wire Switch', {
      Thing.CAPABILITIES.MultiLevelSwitch,
    }):addProperty('value', {
      ['@type'] = 'LevelProperty',
      title = 'Signal Order',
      type = 'integer',
      -- stop, hg, eco, -2, -1, comfort
      description = 'The signal order as a level, 0, 20, 30, 40, 50, 99 from stop to comfort',
      minimum = 0,
      maximum = 99
    }, 0)
  end
  if thing then
    return thing:addPropertiesFromNames('lastseen')
  end
end

local function updateThingFromNodeInfo(thing, info)
  local cc = info.commandClass
  local property = info.property
  local value = info.value or info.newValue
  if cc == CC.SENSOR_MULTILEVEL then
    --logger:info('Z-Wave update thing "'..thing:getTitle()..'" node info: '..json.stringify(info, 2))
    if property == 'Air temperature' and type(value) == 'number' then
      thing:updatePropertyValue('temperature', value)
    elseif property == 'Humidity' and type(value) == 'number' then
      thing:updatePropertyValue('humidity', value)
    end
  elseif cc == CC.SWITCH_MULTILEVEL then
    if property == 'currentValue' and type(value) == 'number' then
      thing:updatePropertyValue('value', value)
    end
  elseif cc == CC.ALARM then
    if property == 'Smoke Alarm' and type(value) == 'number' then
      thing:updatePropertyValue('smoke', value ~= 0)
    end
  elseif cc == CC.BATTERY then
    if property == 'level' and type(value) == 'number' then
      thing:updatePropertyValue('battery', value)
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


local thingsMap = {}
local thingsByNodeId = {}

local function onZWaveNode(node)
  local did = getNodeDiscoveryId(node)
  if did then
    local thing = thingsMap[did]
    if thing == nil then
      thing = createThingFromNode(node)
      if thing then
        if logger:isLoggable(logger.INFO) then
          logger:info('Z-Wave node '..did..' found '..thing:getTitle()..' "'..thing:getDescription()..'"')
        end
        extension:discoverThing(did, thing)
      else
        thing = false
      end
      thingsMap[did] = thing
    end
    if thing then
      if node.nodeId then
        thingsByNodeId[node.nodeId] = thing
      end
      updateThingFromNode(thing, node)
    end
  end
end

local function onZWaveNodeEvent(event)
  -- see https://zwave-js.github.io/node-zwave-js/#/api/node?id=zwavenode-events
  if event.source == 'node' and event.event == 'value updated' and event.nodeId then
    local thing = thingsByNodeId[event.nodeId]
    if thing then
      --logger:info('Z-Wave JS event on thing: '..json.stringify(event, 2))
      updateThingFromNodeInfo(thing, event.args)
      if thing:hasProperty('lastseen') then
        local lastseen = string.sub(Date:new():toISOString(true), 1, 16)..'Z'
        thing:updatePropertyValue('lastseen', lastseen)
      end
    else
      if logger:isLoggable(logger.FINE) then
        logger:fine('Z-Wave JS event without thing: '..json.stringify(event, 2))
      end
    end
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
  local mqttClient = mqtt.MqttClient:new()
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
  return mqttClient
end


------------------------------------------------------------
-- WebSocket
------------------------------------------------------------

local function sendWebSocket(webSocket, message, options)
  webSocket.zwMsgId = webSocket.zwMsgId + 1
  local messageId = 'lha-zwave-js-'..tostring(webSocket.zwMsgId)
  if type(message) == 'string' then
    message = {
      command = message
    }
  elseif type(message) ~= 'table' then
    error('Invalid message type '..type(message))
  end
  message.messageId = messageId
  logger:finest('sendWebSocket('..tostring(message.command)..') '..messageId)
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

local function startListeningWebSocket(webSocket)
  sendWebSocket(webSocket, 'start_listening'):next(function(result)
    --logger:info('Z-Wave start_listening result: '..json.stringify(result, 2))
    if extension:getConfiguration().dumpNodes then
      logger:info('Z-Wave dumping nodes')
      local File = require('jls.io.File')
      File:new('zwave-js.json'):write(json.stringify(result, 2))
    end
    for _, node in ipairs(result.state.nodes) do
      onZWaveNode(node)
    end
  end)
end

local function startWebSocket(wsConfig)
  local webSocket = WebSocket:new(wsConfig.url)
  webSocket.zwMsgId = 0
  webSocket.zwMsgCb = {}
  webSocket:open():next(function()
    webSocket:readStart()
    logger:info('Z-Wave JS WebSocket connected on '..tostring(wsConfig.url))
    extension:setStatus('WebSocket')
    --sendWebSocket('set_api_schema', {schemaVersion = 15})
  end, function(reason)
    extension:setStatus('WebSocket', 'error', 'Cannot open Z-Wave JS WebSocket')
    logger:warn('Cannot open Z-Wave JS WebSocket on '..tostring(wsConfig.url)..' due to '..tostring(reason))
  end)
  webSocket.onClose = function()
    extension:setStatus('WebSocket', 'error', 'Z-Wave JS WebSocket closed')
    logger:warn('Z-Wave JS WebSocket closed')
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
        startListeningWebSocket(webSocket)
      else
        logger:warn('Z-Wave JS WebSocket unsupported message type '..tostring(message.type))
      end
    else
      logger:warn('Z-Wave WebSocket received invalid JSON payload '..tostring(payload))
    end
  end
  return webSocket
end


------------------------------------------------------------
-- Extension events
------------------------------------------------------------

local mqttClient
local webSocket

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

local function setThingPropertyValue(thing, name, value)
  if webSocket and not webSocket:isClosed() then
    local nodeId
    for id, th in pairs(thingsByNodeId) do
      if th == thing then
        nodeId = id
      end
    end
    if nodeId and thing:hasType(Thing.CAPABILITIES.MultiLevelSwitch) and thing:hasProperty(name) then
      sendWebSocket(webSocket, {
        command = 'node.set_value',
        nodeId = nodeId,
        valueId = {
          commandClass = CC.SWITCH_MULTILEVEL,
          property = 'targetValue'
        },
        value = value
      }):next(function()
        logger:info('Z-Wave nodeId '..tostring(nodeId)..' state set done')
        thing:updatePropertyValue(name, value)
      end, function(reason)
        logger:info('Z-Wave nodeId '..tostring(nodeId)..' state set failed '..tostring(reason))
        thing:updatePropertyValue(name, value)
      end)
      return
    end
  end
  thing:updatePropertyValue(name, value)
end

extension:subscribeEvent('things', function()
  thingsByNodeId = {}
  thingsMap = extension:getThingsByDiscoveryKey()
  for _, thing in pairs(thingsMap) do
    thing.setPropertyValue = setThingPropertyValue
  end
end)

extension:subscribeEvent('poll', function()
  logger:info('Polling '..extension:getPrettyName()..' extension')
  if webSocket and not webSocket:isClosed() then
    -- starting again to receive the nodes state, not really part of the API
    -- necessary to discover new nodes
    startListeningWebSocket(webSocket)
    --[[
    for nodeId in pairs(thingsByNodeId) do
      logger:fine('Z-Wave polling nodeId '..tostring(nodeId))
      sendWebSocket(webSocket, {
        command = 'node.get_state',
        nodeId = nodeId
      }):next(function(results)
        logger:info('Z-Wave nodeId '..tostring(nodeId)..' state polled')
        --logger:info('Z-Wave nodeId '..tostring(nodeId)..' state: '..json.stringify(results))
        onZWaveNode(results.state)
      end)
    end
    ]]
  else
    logger:warn('Z-Wave no websocket available')
  end
end)

local function checkWebSocket()
  local wsConfig = extension:getConfiguration().websocket
  if wsConfig and wsConfig.enable and (not webSocket or webSocket:isClosed()) then
    logger:info('Z-Wave JS WebSocket connecting to '..tostring(wsConfig.url))
    webSocket = startWebSocket(wsConfig)
  end
end

extension:subscribeEvent('heartbeat', function()
  checkWebSocket()
end)

extension:subscribeEvent('startup', function()
  logger:info('Starting '..extension:getPrettyName()..' extension')
  cleanup()
  local mqttConfig = extension:getConfiguration().mqtt
  if mqttConfig and mqttConfig.enable then
    mqttClient = startMqtt(mqttConfig)
  end
  checkWebSocket()
end)

extension:subscribeEvent('shutdown', function()
  logger:info('shutdown Z-Wave JS extension')
  cleanup()
end)
