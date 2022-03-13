local extension = ...

local logger = require('jls.lang.logger')
local mqtt = require('jls.net.mqtt')
local Url = require('jls.net.Url')
local strings = require('jls.util.strings')
local json = require('jls.util.json')

local mqttClient

local function closeClient()
  if mqttClient then
    mqttClient:close(false)
    mqttClient = nil
  end
end

--[[
  <mqtt_prefix>/_EVENTS_/ZWAVE_GATEWAY-<mqtt_name>/<driver|node|controller>/<event_name>
  <mqtt_prefix>/_CLIENTS/ZWAVE_GATEWAY-<mqtt_name>/api/<api_name>/set
]]

extension:subscribeEvent('startup', function()
  local configuration = extension:getConfiguration()
  closeClient()
  local tUrl = Url.parse(configuration.url)
  if tUrl.scheme ~= 'tcp' then
    logger:info('Invalid scheme')
    return
  end
  local topicPattern = '^'..strings.escape(configuration.prefix..'/')..'([^/]+)'..strings.escape('/ZWAVE_GATEWAY-'..configuration.name..'/')..'(.+)$'
  logger:info('Z-Wave JS topicPattern "'..topicPattern..'"')
  mqttClient = mqtt.MqttClient:new()
  function mqttClient:onMessage(topicName, payload)
    if logger:isLoggable(logger.FINER) then
      logger:finer('Received on topic "'..topicName..'": '..payload)
    end
    local channel, path = string.match(topicName, topicPattern)
    logger:info('Z-Wave JS message "'..topicName..'": "'..tostring(channel)..'", "'..tostring(path)..'"')
    if channel == '_EVENTS_' then
      if logger:isLoggable(logger.FINE) then
        logger:fine('Z-Wave JS Event "'..path..'": '..payload)
      end
      local t = json.decode(payload)
      if t and t.success then
        logger:info('Z-Wave JS Event "'..path..'": '..json.stringify(t, 2))
      end
    elseif channel == '_CLIENTS' then
      local apiName = string.match(path, 'api/([^/]+)')
      if apiName then
        if logger:isLoggable(logger.FINE) then
          logger:fine('Z-Wave JS API "'..apiName..'": '..payload)
        end
        local t = json.decode(payload)
        if t and t.success then
          logger:fine('Z-Wave JS API "'..apiName..'": '..json.stringify(t, 2))
        end
      end
    end
  end
  mqttClient:connect(tUrl.host, tUrl.port):next(function()
    logger:info('Z-Wave JS connected to Broker "'..configuration.url..'"')
    local topicName = configuration.prefix..'/+/ZWAVE_GATEWAY-'..configuration.name..'/#'
    mqttClient:subscribe(topicName, configuration.qos):next(function()
      logger:info('Z-Wave JS subscribed to topic "'..topicName..'"')
    end)
  end)
end)

extension:subscribeEvent('shutdown', function()
  logger:info('shutdown Z-Wave JS extension')
  closeClient()
end)
