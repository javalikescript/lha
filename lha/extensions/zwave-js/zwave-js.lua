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
  local apiTopic = configuration.prefix..'/_CLIENTS/ZWAVE_GATEWAY-'..configuration.name..'/api/'
  local eventTopic = configuration.prefix..'/_EVENTS_/ZWAVE_GATEWAY-'..configuration.name..'/'
  -- '^'..strings.escape(configuration.prefix..'/')..'([^/]+)'..strings.escape('/ZWAVE_GATEWAY-'..configuration.name..'/')..'(.+)$'
  local apiPattern = '^'..strings.escape(apiTopic)..'([^/]+)$'
  local nodeStatusPattern = '^'..strings.escape(configuration.prefix)..'/([^/]+)/([^/]+)/status$'
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
            logger:info('Z-Wave node '..tostring(node.id)..' found '..tostring(node.productLabel)..' "'..tostring(node.productDescription)..'"')
          end
        end
      end
    end
  end
  mqttClient:connect(tUrl.host, tUrl.port):next(function()
    logger:info('Z-Wave JS connected to Broker "'..configuration.url..'"')
    local topicNames = {
      apiTopic..'+',
      configuration.prefix..'/+/+/status',
      eventTopic..'#', -- To remove
    }
    mqttClient:subscribe(topicNames, configuration.qos):next(function()
      logger:info('Z-Wave JS subscribed to topics "'..table.concat(topicNames, '", "')..'"')
      mqttClient:publish(apiTopic..'getNodes/set', '{}'):next(function()
        logger:info('Z-Wave JS getNodes published')
      end)
    end)
  end)
end)

extension:subscribeEvent('shutdown', function()
  logger:info('shutdown Z-Wave JS extension')
  closeClient()
end)
