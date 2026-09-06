local logger = require('jls.lang.logger'):get(...)
local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')
local Exception = require('jls.lang.Exception')
local File = require('jls.io.File')
local json = require('jls.util.json')
local WebSocket = require('jls.net.http.WebSocket')

local Thing = require('lha.Thing')
local utils = require('lha.utils')

return require('jls.lang.class').create(function(matterJs)

  function matterJs:initialize(url, mapping)
    self.url = url
    self.mapping = utils.replaceRefs(mapping or {}, {
      utils = utils,
      math = math,
    })
  end

  function matterJs:updateConnectedState(value)
    logger:fine('updateConnectedState(%s)', value)
  end

  function matterJs:publishEvent(name, data)
    logger:finest('publishEvent(%s, %T)', name, data)
    -- node_added node_updated node_removed attribute_updated endpoint_added endpoint_removed node_event server_info_updated server_shutdown
    if self.eventHandler then
      self.eventHandler(name, data)
    end
  end

  function matterJs:setEventHandler(eventHandler)
    self.eventHandler = eventHandler
  end

  -- https://github.com/matter-js/matterjs-server/blob/main/docs/websockets_api.md
  function matterJs:sendWebSocket(command, args)
    logger:finest('sendWebSocket(%s, %t)', command, args)
    if not self.webSocket then
      return Promise.reject('not connected')
    end
    self.msgId = self.msgId + 1
    local messageId = 'lha-'..tostring(self.msgId)
    local message = {
      message_id = messageId,
      command = command,
      args = args
    }
    local textMsg = json.encode(message)
    logger:finer('message: %s', textMsg)
    return self.webSocket:sendTextMessage(textMsg):next(function()
      local promise, cb = Promise.createWithCallback()
      self.msgMap[messageId] = {cb = cb, time = utils.time()}
      return promise
    end)
  end

  function matterJs:startListeningWebSocket()
    return self:sendWebSocket('start_listening'):next(function(result)
      logger:info('start_listening found %l nodes', result)
      if self.dumpNodes then
        local filename = 'matterjs-nodes.json'
        logger:info('dumping nodes in file %s', filename)
        File:new(filename):write(json.stringify(result, 2))
      end
      return result
    end)
  end

  function matterJs:startWebSocket()
    self:close()
    local webSocket = WebSocket:new(self.url)
    local promise, cb = Promise.createWithCallback()
    local timer = event:setTimeout(function()
      cb('timeout')
    end, 15000)
    webSocket.onError = function(_, reason)
      logger:warn('WebSocket error "%s"', reason)
    end
    webSocket.onClose = function()
      self:updateConnectedState(false)
      logger:warn('WebSocket closed')
    end
    webSocket.onTextMessage = function(_, payload)
      logger:finest('WebSocket received %s', payload)
      local status, message = Exception.pcall(json.decode, payload)
      if status and message then
        if type(message.event) == 'string' then
          self:publishEvent(message.event, message.data)
        elseif message.message_id then
          local msg = self.msgMap[message.message_id]
          if msg then
            logger:finer('WebSocket result %s', message.message_id)
            self.msgMap[message.message_id] = nil
            if message.result then
              msg.cb(nil, message.result)
            else
              -- see packages\ws-controller\src\types\WebSocketMessageTypes.ts
              local reason = tostring(message.error_code or '0')
              if message.details then
                reason = reason..': '..tostring(message.details)
              end
              msg.cb(reason)
            end
          end
        elseif message.schema_version then
          event:clearTimeout(timer)
          cb()
        else
          logger:warn('WebSocket received unsupported message %T', message)
        end
      else
        logger:warn('WebSocket received invalid JSON payload %s', payload)
      end
    end
    self.webSocket = webSocket
    webSocket:open():next(function()
      webSocket:readStart()
      logger:info('WebSocket connected on %s', self.url)
      self:updateConnectedState(true)
    end, function(reason)
      self:updateConnectedState(false)
      logger:warn('Cannot open WebSocket on %s due to %s', self.url, reason)
    end)
    return promise:catch(function(reason)
      logger:warn('WebSocket connection failed "%s"', reason)
      webSocket:close(false)
      self.webSocket = nil
      return Promise.reject(reason)
    end)
  end

  function matterJs:close()
    if self.webSocket then
      self.webSocket:close()
      self.webSocket = nil
    end
    if self.msgMap then
      for _, msg in pairs(self.msgMap) do
        msg.cb('timeout')
      end
    end
    self.msgId = 0
    self.msgMap = {}
  end

  function matterJs:refresh()
    if self.webSocket and not self.webSocket:isClosed() then
      local checkTime = utils.time()
      local minMsgTime = checkTime - 30
      for id, msg in pairs(self.msgMap) do
        if msg.time < minMsgTime then
          self.msgMap[id] = nil
          msg.cb('timeout')
        end
      end
    else
      self:startWebSocket()
    end
  end

  function matterJs:findDeviceFromNode(node)
    local vendorId = node.attributes['0/40/2']
    local productId = node.attributes['0/40/4']
    for _, device in ipairs(self.mapping.devices) do
      if vendorId == device.vendorId and productId == device.productId then
        return device
      end
    end
  end

  function matterJs:createThingFromNode(node, device)
    local title = utils.expand(self.mapping.title, node)
    local description = utils.expand(self.mapping.description, node)
    local thing = Thing:new(title, description)
    if device.capabilities then
      for _, capability in ipairs(device.capabilities) do
        thing:addType(capability)
      end
    end
    for _, info in ipairs(device.properties) do
      utils.addThingPropertyFromInfo(thing, info.name, info, node)
    end
    if next(thing:getProperties()) then
      return thing
    end
  end

  function matterJs:updateThing(thing, device, node)
    logger:finest('updateThing(%s, %t, %t)', thing, device, node)
    for _, info in ipairs(device.properties) do
      local value = utils.expand(info.value, node)
      if utils.isValue(value) then
        if info.adapter then
          value = info.adapter(value)
          if utils.isValue(value) then
            thing:updatePropertyValue(info.name, value)
          end
        else
          thing:updatePropertyValue(info.name, value)
        end
      end
    end
  end

end)
