local extension = ...

local logger = require('jls.lang.logger')
local mqtt = require('jls.net.mqtt')
local Url = require('jls.net.Url')
local json = require('jls.util.json')

local mqttClient

local function cleanup()
  if mqttClient then
    mqttClient:close(false)
    mqttClient = nil
  end
end

local configuration = extension:getConfiguration()

local function publisher(value, previousValue, path)
  if mqttClient then
    local topic = configuration.prefix..path
    mqttClient:publish(topic, json.encode({
      value = value,
      previousValue = previousValue
    }), configuration)
  end
end

extension:watchPattern('^data/.*', publisher)

extension:subscribeEvent('startup', function()
  cleanup()
  local tUrl = Url.parse(configuration.url)
  local engine = extension:getEngine()
  local prefix = configuration.prefix
  mqttClient = mqtt.MqttClient:new()
  function mqttClient:onMessage(topicName, payload)
    local path = string.sub(topicName, #prefix + 2)
    local value = json.decode(payload)
    engine:setRootValues(path, value, true)
  end
  mqttClient:connect(tUrl.host, tUrl.port):next(function()
    logger:info('MQTT connected on "'..configuration.url..'"')
    if configuration.subscribe then
      mqttClient:subscribe(prefix + '/#', configuration.qos)
    end
  end)
end)

extension:subscribeEvent('shutdown', function()
  cleanup()
end)
