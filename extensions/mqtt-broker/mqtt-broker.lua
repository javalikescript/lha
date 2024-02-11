local extension = ...

local logger = extension:getLogger()
local mqtt = require('jls.net.mqtt')

local mqttServer

local function closeServer()
  if mqttServer then
    mqttServer:close(false)
    mqttServer = nil
  end
end

extension:subscribeEvent('startup', function()
  local configuration = extension:getConfiguration()
  closeServer()
  mqttServer = mqtt.MqttServer:new()
  mqttServer:bind(configuration.address, configuration.port):next(function()
    logger:info('MQTT Broker bound on "'..configuration.port..'"')
  end)
end)

extension:subscribeEvent('shutdown', function()
  logger:info('shutdown MQTT Broker extension')
  closeServer()
end)
