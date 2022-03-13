local extension = ...

local logger = require('jls.lang.logger')
local mqtt = require('jls.net.mqtt')
local Url = require('jls.net.Url')
local strings = require('jls.util.strings')

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
  local topicPattern = strings.escape('^'..configuration.prefix..'/')..'([^/]+)'..strings.escape('/ZWAVE_GATEWAY-'..configuration.name..'/')..'(.+)$'
  mqttClient = mqtt.MqttClient:new()
  function mqttClient:onPublish(topicName, payload)
    logger:fine('Received on topic "'..topicName..'": '..payload)
    local channel, path = string.match(topicName, topicPattern)
    if channel == '_EVENTS_' then
      logger:info('Z-Wave JS Event "'..path..'": '..payload)

    elseif channel == '_CLIENTS' then
      local apiName = string.match(path, '/api/([^/]+)/set')
      if apiName then
        logger:info('Z-Wave JS API "'..apiName..'": '..payload)
        
      end
    end
  end
  mqttClient:connect(tUrl.host, tUrl.port):next(function()
    logger:info('Z-Wave JS connected to Broker "'..configuration.url..'"')
    local topicName = configuration.prefix..'/+/ZWAVE_GATEWAY-'..configuration.name..'/#'
    logger:info('Z-Wave JS subscribe to topic "'..topicName..'"')
    mqttClient:subscribe(topicName, configuration.qos)
  end)
end)

extension:subscribeEvent('shutdown', function()
  logger:info('shutdown Z-Wave JS extension')
  closeClient()
end)
