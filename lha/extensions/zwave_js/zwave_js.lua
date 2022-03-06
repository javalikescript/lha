local extension = ...

local logger = require('jls.lang.logger')
local mqtt = require('jls.net.mqtt')
local Url = require('jls.net.Url')

local mqttClient

local function closeClient()
  if mqttClient then
    mqttClient:close(false)
    mqttClient = nil
  end
end

extension:subscribeEvent('startup', function()
  local configuration = extension:getConfiguration()
  closeClient()
  local tUrl = Url.parse(configuration.url)
  if tUrl.scheme ~= 'tcp' then
    logger:info('Invalid scheme')
    return
  end
  mqttClient = mqtt.MqttClient:new()
  mqttClient:connect(tUrl.host, tUrl.port):next(function()
    logger:info('Z-Wave JS connected to Broker "'..configuration.url..'"')
  end)
end)

extension:subscribeEvent('shutdown', function()
  logger:info('shutdown MQTT Broker extension')
  closeClient()
end)
