local extension = ...

local logger = extension:getLogger()
local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')
local Exception = require('jls.lang.Exception')
local File = require('jls.io.File')
local mqtt = require('jls.net.mqtt')
local WebSocket = require('jls.net.http.ws').WebSocket
local Url = require('jls.net.Url')
local strings = require('jls.util.strings')
local json = require('jls.util.json')
local Map = require('jls.util.Map')

local Thing = require('lha.Thing')
local utils = require('lha.utils')

--logger = logger:getClass():new(); logger:setLevel(logger.FINE)

-- command classes
-- 0x20..0xEE Application Command Classes
local CC = {
  SWITCH_MULTILEVEL = 38,
  SENSOR_MULTILEVEL = 49,
  ALARM = 113,
  BATTERY = 128,
}

local SIGNAL_ORDER_PROPERTY = {
  ['@type'] = 'LevelProperty',
  title = 'Signal Order',
  type = 'integer',
  -- stop, hg, eco, -2, -1, comfort
  description = 'The signal order as a level, 0, 20, 30, 40, 50, 99 from stop to comfort',
  --enum = {0, 20, 30, 40, 50, 99},
  minimum = 0,
  maximum = 99
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
  local nodeId = node.nodeId or node.id
  local deviceId = getNodeDeviceId(node)
  if nodeId and deviceId then
    return tostring(nodeId)..'-'..deviceId
  end
end

local function parseNodeDiscoveryId(discoveryId)
  -- 8-345-82-4
  local nodeId, deviceId = string.match(discoveryId, '^(%d+)%-(.+)$')
  return nodeId, deviceId
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
    thing = Thing:new(getNodeName(node, 'Pilot Wire'), 'Pilot Wire Switch (DIN version)', {
      Thing.CAPABILITIES.MultiLevelSwitch,
    }):addProperty('value', SIGNAL_ORDER_PROPERTY, 0)
  elseif productLabel == 'ZMNHJD' then
    thing = Thing:new(getNodeName(node, 'Pilot Wire'), 'Pilot Wire Switch', {
      Thing.CAPABILITIES.MultiLevelSwitch,
    }):addProperty('value', SIGNAL_ORDER_PROPERTY, 0):addPropertiesFromNames('temperature')
  end
  if thing then
    return thing:addPropertiesFromNames('lastseen', 'lastupdated')
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


local controllerThing
local thingsMap = {}
local thingsByNodeId = {}
local lastNodesTime = utils.time()
local refreshNodesPeriod = 0 -- 86400

local function setupControllerThing()
  controllerThing = extension:syncDiscoveredThingByKey('controller', function()
    return Thing:new('Controller', 'The Z-Wave controller', {'MultiLevelSensor'}):addPropertiesFromNames('connected')
  end, controllerThing)
end

local function onZWaveNode(node)
  local did = getNodeDiscoveryId(node)
  if did then
    local thing = thingsMap[did]
    if thing == nil then
      thing = createThingFromNode(node)
      if thing then
        if logger:isLoggable(logger.INFO) then
          logger:info('Z-Wave node %s found %s "%s"', did, thing:getTitle(), thing:getDescription())
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

local function onZWaveNodes(nodes)
  thingsByNodeId = {}
  for _, node in ipairs(nodes) do
    onZWaveNode(node)
  end
  lastNodesTime = utils.time()
end

local function onZWaveEvent(event)
  logger:fine('Z-Wave %s event "%s"', event.source, event.event)
  -- see https://zwave-js.github.io/node-zwave-js/#/api/node?id=zwavenode-events
  if event.source == 'node' then
    if event.event == 'value updated' and event.nodeId then
      local thing = thingsByNodeId[event.nodeId]
      if thing then
        --logger:info('Z-Wave JS event on thing: '..json.stringify(event, 2))
        updateThingFromNodeInfo(thing, event.args)
        local time = utils.timeToString()
        if thing:hasProperty('lastseen') then
          thing:updatePropertyValue('lastseen', time)
        end
        if thing:hasProperty('lastupdated') then
          thing:updatePropertyValue('lastupdated', time)
        end
      else
        if logger:isLoggable(logger.FINE) then
          logger:fine('Z-Wave JS event without thing: '..json.stringify(event, 2))
        end
      end
    elseif event.event == 'statistics updated' and event.nodeId and event.statistics then
      if logger:isLoggable(logger.FINE) then
        logger:fine('Z-Wave JS node %s statistics updated: %s', event.nodeId, json.stringify(event.statistics))
      end
    elseif event.event == 'ready' and event.node then
      onZWaveNode(event.node)
    else
      logger:info('Z-Wave node event "%s"', event.event)
      if logger:isLoggable(logger.FINE) then
        logger:fine('Z-Wave JS event: '..json.stringify(event, 2))
      end
      -- 'wake up' / sleep, dead / alive, 'statistics updated'
    end
  elseif event.source == 'controller' and event.event == 'statistics updated' and event.statistics then
    if logger:isLoggable(logger.FINE) then
      logger:fine('Z-Wave JS controller statistics updated: '..json.stringify(event.statistics))
    end
  else
    logger:info('Z-Wave %s event "%s"', event.source, event.event)
    -- controller: node added, node removed
    -- driver: error, driver ready, all nodes ready
  end
end

------------------------------------------------------------
-- MQTT
------------------------------------------------------------

local function startMqtt(config)
  local tUrl = Url.parse(config.mqttUrl)
  if tUrl.scheme ~= 'tcp' then
    logger:warn('Invalid scheme')
    return
  end
  local apiTopic = config.prefix..'/_CLIENTS/ZWAVE_GATEWAY-'..config.name..'/api/'
  local eventTopic = config.prefix..'/_EVENTS_/ZWAVE_GATEWAY-'..config.name..'/'
  local apiPattern = '^'..strings.escape(apiTopic)..'([^/]+)$'
  local nodeStatusPattern = '^'..strings.escape(config.prefix)..'/([^/]+)/([^/]+)/status$'
  logger:info('Z-Wave JS API pattern "%s"', apiPattern)
  local mqttClient = mqtt.MqttClient:new()
  function mqttClient:onMessage(topicName, payload)
    logger:finer('Received on topic "%s": %s', topicName, payload)
    local nodeLocation, nodeName = string.match(topicName, nodeStatusPattern)
    if nodeLocation then
      local t = json.decode(payload)
      if t then
        logger:info('Z-Wave JS node status "%s" "%s": %s', nodeLocation, nodeName, json.stringify(t, 2))
      end
    end
    local apiName = string.match(topicName, apiPattern)
    if apiName then
      logger:fine('Z-Wave JS API "%s": %s', apiName, payload)
      local t = json.decode(payload)
      if t and t.success then
        logger:fine('Z-Wave JS API "%s": %s', apiName, json.stringify(t, 2))
        if apiName == 'getNodes' then
          onZWaveNodes(t.result)
        end
      end
    end
  end
  mqttClient:connect(tUrl.host, tUrl.port):next(function()
    logger:info('Z-Wave JS connected to Broker "%s"', config.mqttUrl)
    local statusTopic = config.prefix..'/+/+/status'
    local topicNames = {
      apiTopic..'+',
      statusTopic,
      eventTopic..'#', -- To remove
    }
    mqttClient:subscribe(topicNames, config.qos):next(function()
      logger:info('Z-Wave JS subscribed to topics "%s"', table.concat(topicNames, '", "'))
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
  logger:finest('sendWebSocket(%s) %s', message.command, messageId)
  if options then
    Map.assign(message, options)
  end
  local textMsg = json.encode(message)
  logger:finer('message: %s', textMsg)
  return webSocket:sendTextMessage(textMsg):next(function()
    local promise, cb = Promise.createWithCallback()
    webSocket.zwMsgMap[messageId] = {cb = cb, time = utils.time()}
    return promise
  end)
end

local function startListeningWebSocket(webSocket)
  return sendWebSocket(webSocket, 'start_listening'):next(function(result)
    logger:info('Z-Wave start_listening found %d nodes', #result.state.nodes)
    --logger:info('Z-Wave start_listening result: '..json.stringify(result, 2))
    if extension:getConfiguration().dumpNodes then
      logger:info('Z-Wave dumping nodes')
      File:new('zwave-js.json'):write(json.stringify(result, 2))
    end
    onZWaveNodes(result.state.nodes)
  end)
end

local function startWebSocket(config)
  local webSocket = WebSocket:new(config.webSocketUrl)
  webSocket.zwMsgId = 0
  webSocket.zwMsgMap = {}
  local timer = event:setTimeout(function()
    logger:warn('Z-Wave JS WebSocket start timeout')
    webSocket:close(false)
  end, 3000)
  webSocket:open():next(function()
    webSocket:readStart()
    logger:info('Z-Wave JS WebSocket connected on %s', config.webSocketUrl)
    controllerThing:updatePropertyValue('connected', true)
    --sendWebSocket('set_api_schema', {schemaVersion = 15})
  end, function(reason)
    controllerThing:updatePropertyValue('connected', false)
    logger:warn('Cannot open Z-Wave JS WebSocket on %s due to %s', config.webSocketUrl, reason)
  end)
  webSocket.onError = function(reason)
    logger:warn('Z-Wave JS WebSocket error "%s"', reason)
  end
  webSocket.onClose = function()
    controllerThing:updatePropertyValue('connected', false)
    logger:warn('Z-Wave JS WebSocket closed')
  end
  webSocket.onTextMessage = function(_, payload)
    logger:finest('Z-Wave WebSocket received %s', payload)
    local status, message = Exception.pcall(json.decode, payload)
    if status and message and message.type then
      if message.type == 'event' and message.event then
        if logger:isLoggable(logger.FINER) then
          logger:finer('Z-Wave JS event: %s', json.stringify(message.event, 2))
        end
        onZWaveEvent(message.event)
      elseif message.type == 'result' then
        local zwMsg = webSocket.zwMsgMap[message.messageId]
        if zwMsg then
          logger:finer('Z-Wave JS WebSocket result %s', message.messageId)
          webSocket.zwMsgMap[message.messageId] = nil
          if message.success and message.result then
            zwMsg.cb(nil, message.result)
          else
            local reason = tostring(message.errorCode)
            if message.errorCode == 'zwave_error' then
              reason = tostring(message.zwaveErrorCode)..': '..tostring(message.zwaveErrorMessage)
            end
            zwMsg.cb(reason)
          end
        end
      elseif message.type == 'version' then
        -- command = 'driver.set_preferred_scale', scales = {temperature = 'Celsius'}
        event:clearTimeout(timer)
        startListeningWebSocket(webSocket):catch(function(reason)
          logger:warn('Z-Wave JS WebSocket start_listening failed "%s"', reason)
          webSocket:close(false)
        end)
      else
        logger:warn('Z-Wave JS WebSocket unsupported message type %s', message.type)
      end
    else
      logger:warn('Z-Wave WebSocket received invalid JSON payload %s', payload)
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
  local property = thing:getProperty(name)
  if not (property and property:isWritable()) then
    return
  end
  if webSocket and not webSocket:isClosed() then
    local nodeId
    for id, th in pairs(thingsByNodeId) do
      if th == thing then
        nodeId = id
      end
    end
    if nodeId then
      if thing:hasType(Thing.CAPABILITIES.MultiLevelSwitch) then
        sendWebSocket(webSocket, {
          command = 'node.set_value',
          nodeId = nodeId,
          valueId = {
            commandClass = CC.SWITCH_MULTILEVEL,
            property = 'targetValue'
          },
          value = value
        }):next(function()
          logger:fine('Z-Wave nodeId %s set value "%s" done', nodeId, name)
          thing:updatePropertyValue(name, value)
        end, function(reason)
          logger:warn('Z-Wave nodeId %s set value failed due to %s', nodeId, reason)
          thing:updatePropertyValue(name, value)
        end)
        return
      end
    else
      logger:warn('Z-Wave unable to set value "%s", nodeId not found for thing id %s "%s", %d node ids', name, thing:getId(), thing:getTitle(), Map.size(thingsByNodeId))
      if logger:isLoggable(logger.INFO) then
        for id, th in pairs(thingsByNodeId) do
          logger:info('node id "%s" mapped to thing id %s "%s"', id, th:getId(), th:getTitle())
        end
      end
    end
  end
  thing:updatePropertyValue(name, value)
end

extension:subscribeEvent('things', function()
  setupControllerThing()
  thingsMap = extension:getThingsByDiscoveryKey()
  for _, thing in pairs(thingsMap) do
    thing.setPropertyValue = setThingPropertyValue
  end
end)
extension:subscribeEvent('poll', function()
  if logger:isLoggable(logger.INFO) then
    logger:info('Polling %s extension, %d node ids', extension:getPrettyName(), Map.size(thingsByNodeId))
  end
  local pollTime = utils.time()
  local minPingTime = pollTime - 6 * 3600
  if webSocket and not webSocket:isClosed() then
    if refreshNodesPeriod > 0 and pollTime - lastNodesTime > refreshNodesPeriod then
      startListeningWebSocket(webSocket)
      return
    end
    for nodeId, thing in pairs(thingsByNodeId) do
      logger:fine('Z-Wave polling nodeId %s', nodeId)
      -- get state will dump node, getValue for each getDefinedValueIDs
      sendWebSocket(webSocket, {
        command = 'node.get_state',
        nodeId = nodeId
      }):next(function(result)
        if logger:isLoggable(logger.FINE) then
          if logger:isLoggable(logger.FINEST) then
            logger:finest('Z-Wave nodeId %s state: %s', nodeId, json.stringify(result))
          else
            logger:fine('Z-Wave nodeId %s state polled', nodeId)
          end
        end
        onZWaveNode(result.state)
        local lastseen = thing:getProperty('lastseen')
        if lastseen and (not lastseen:getValue() or utils.timeFromString(lastseen:getValue()) < minPingTime) then
          logger:fine('Z-Wave pinging nodeId %s', nodeId)
          -- TODO find a better way to update lastseen, ping polling is thing dependent
          return sendWebSocket(webSocket, {
            command = 'node.ping',
            nodeId = nodeId
          }):next(function(pingResult)
            --logger:info('Z-Wave nodeId %s ping: %s', nodeId, json.stringify(result))
            if pingResult.responded then
              thing:updatePropertyValue('lastseen', utils.timeToString(pollTime))
            else
              logger:fine('Z-Wave nodeId %s did not respond to ping', nodeId)
            end
          end)
        end
      end):catch(function(reason)
        logger:fine('Z-Wave unable to poll/ping nodeId %s due to %s', nodeId, reason)
      end)
    end
  else
    logger:warn('Z-Wave no websocket available')
  end
end)

local function checkWebSocket()
  local config = extension:getConfiguration()
  if config.connection and config.connection.webSocketUrl then
    if webSocket and not webSocket:isClosed() then
      local checkTime = utils.time()
      local minMsgTime = checkTime - 30
      for id, zwMsg in pairs(webSocket.zwMsgMap) do
        if zwMsg.time < minMsgTime then
          webSocket.zwMsgMap[id] = nil
          zwMsg.cb('timeout')
        end
      end
    else
      webSocket = startWebSocket(config.connection)
    end
  end
end

extension:subscribeEvent('heartbeat', function()
  checkWebSocket()
end)

extension:subscribeEvent('startup', function()
  logger:info('Starting %s extension', extension:getPrettyName())
  cleanup()
  setupControllerThing()
  local config = extension:getConfiguration()
  if config.connection and config.connection.mqttUrl then
    mqttClient = startMqtt(config.connection)
  end
  checkWebSocket()
end)

extension:subscribeEvent('shutdown', function()
  logger:info('shutdown Z-Wave JS extension')
  cleanup()
end)
