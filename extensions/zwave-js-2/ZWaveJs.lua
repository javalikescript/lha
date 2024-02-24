local logger = require('jls.lang.logger'):get(...)
local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')
local Exception = require('jls.lang.Exception')
local File = require('jls.io.File')
local json = require('jls.util.json')
local Map = require('jls.util.Map')
local WebSocket = require('jls.net.http.ws').WebSocket

local Thing = require('lha.Thing')
local utils = require('lha.utils')

return require('jls.lang.class').create(function(zWaveJs)

  function zWaveJs:initialize(url, mapping)
    self.url = url
    self.mapping = utils.replaceRefs(mapping or {}, {
      Thing = Thing,
      color = utils,
      math = math,
    })
  end

  function zWaveJs:updateConnectedState(value)
    logger:fine('updateConnectedState(%s)', value)
  end

  function zWaveJs:publishEvent(e)
    logger:finest('publishEvent()')
    if self.onZWaveEvent then
      self.onZWaveEvent(e)
    end
  end

  function zWaveJs:setEventHandler(onZWaveEvent)
    self.onZWaveEvent = onZWaveEvent
  end

  function zWaveJs:sendWebSocket(message, options)
    self.zwMsgId = self.zwMsgId + 1
    local messageId = 'lha-zwave-js-'..tostring(self.zwMsgId)
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
    return self.webSocket:sendTextMessage(textMsg):next(function()
      local promise, cb = Promise.createWithCallback()
      self.zwMsgMap[messageId] = {cb = cb, time = utils.time()}
      return promise
    end)
  end

  function zWaveJs:startListeningWebSocket()
    -- start receive the state and get events
    return self:sendWebSocket('start_listening'):next(function(result)
      logger:info('Z-Wave start_listening found %d nodes', #result.state.nodes)
      if logger:isLoggable(logger.FINEST) then
        logger:finest('Z-Wave start_listening result: '..json.stringify(result, 2))
      end
      if self.dumpNodes then
        logger:info('Z-Wave dumping nodes')
        File:new('zwave-js.json'):write(json.stringify(result.state, 2))
      end
      return result.state
    end)
  end

  function zWaveJs:startWebSocket()
    self:close()
    local webSocket = WebSocket:new(self.url)
    local promise, cb = Promise.createWithCallback()
    local timer = event:setTimeout(function()
      cb('timeout')
    end, 3000)
    webSocket.onError = function(_, reason)
      logger:warn('Z-Wave JS WebSocket error "%s"', reason)
    end
    webSocket.onClose = function()
      self:updateConnectedState(false)
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
          self:publishEvent(message.event)
        elseif message.type == 'result' then
          local zwMsg = self.zwMsgMap[message.messageId]
          if zwMsg then
            logger:finer('Z-Wave JS WebSocket result %s', message.messageId)
            self.zwMsgMap[message.messageId] = nil
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
          cb()
        else
          logger:warn('Z-Wave JS WebSocket unsupported message type %s', message.type)
        end
      else
        logger:warn('Z-Wave WebSocket received invalid JSON payload %s', payload)
      end
    end
    self.webSocket = webSocket
    webSocket:open():next(function()
      webSocket:readStart()
      logger:info('Z-Wave JS WebSocket connected on %s', self.url)
      self:updateConnectedState(true)
      --sendWebSocket('set_api_schema', {schemaVersion = 15})
    end, function(reason)
      self:updateConnectedState(false)
      logger:warn('Cannot open Z-Wave JS WebSocket on %s due to %s', self.url, reason)
    end)
    return promise:catch(function(reason)
      logger:warn('Z-Wave JS WebSocket start_listening failed "%s"', reason)
      webSocket:close(false)
      self.webSocket = nil
      return Promise.reject(reason)
    end)
  end

  function zWaveJs:close()
    if self.webSocket then
      self.webSocket:close()
      self.webSocket = nil
    end
    if self.zwMsgMap then
      for _, zwMsg in pairs(self.zwMsgMap) do
        zwMsg.cb('timeout')
      end
    end
    self.zwMsgId = 0
    self.zwMsgMap = {}
  end

  function zWaveJs:refresh()
    if self.webSocket and not self.webSocket:isClosed() then
      local checkTime = utils.time()
      local minMsgTime = checkTime - 30
      for id, zwMsg in pairs(self.zwMsgMap) do
        if zwMsg.time < minMsgTime then
          self.zwMsgMap[id] = nil
          zwMsg.cb('timeout')
        end
      end
    else
      self:startWebSocket()
    end
  end

  function zWaveJs:findDeviceFromNode(node)
    for _, device in ipairs(self.mapping.devices) do
      if node.manufacturerId == device.manufacturerId and node.productId == device.productId then
        return device
      end
    end
  end

  --[[
    To uniquely identify a node value:
      commandClass - The numeric identifier of the command class.
      endpoint - (optional) The index of the node's endpoint (sub-device).
      property - The name (or a numeric identifier) of the property, for example targetValue
      propertyKey - (optional) Allows sub-addressing properties that contain multiple values (like combined sensors).
  ]]

  -- https://github.com/OpenZWave/open-zwave/blob/master/config/manufacturer_specific.xml
  function zWaveJs:createThingFromNode(node, device)
    local title = utils.expand(self.mapping.title, node)
    local description = utils.expand(self.mapping.description, node)
    local thing = Thing:new(title, description)
    for _, info in ipairs(device.properties) do
      utils.addThingPropertyFromInfo(thing, info.name, info, node)
    end
    if next(thing:getProperties()) then
      return thing
    end
  end

  -- an event only references the node id
  function zWaveJs:updateThing(thing, device, nodeValue, isEvent)
    for _, info in ipairs(device.properties) do
      if nodeValue.commandClass == info.commandClass and nodeValue.property == info.property
          and (not info.propertyKey or nodeValue.propertyKey == info.propertyKey)
          and (not info.endpoint or nodeValue.endpoint == info.endpoint)
      then
        local value = isEvent and nodeValue.newValue or nodeValue.value
        local isValue = utils.isValue(value)
        if isValue then
          if info.adapter then
            value = info.adapter(value)
            isValue = utils.isValue(value)
          end
          if isValue then
            thing:updatePropertyValue(info.name, value)
          end
        end
        break
      end
    end
  end

  function zWaveJs:setNodeValue(nodeId, device, name, value)
    for _, info in ipairs(device.properties) do
      if name == info.name then
        return self:sendWebSocket({
          command = 'node.set_value',
          nodeId = nodeId,
          valueId = {
            commandClass = info.commandClass,
            property = info.setProperty or 'targetValue'
          },
          value = value
        })
      end
    end
    return Promise.reject(string.format('No property for name "%s"', name))
  end

end)
