local extension = ...

local logger = require('jls.lang.logger')
local tables = require('jls.util.tables')
local Date = require('jls.util.Date')

local HueBridge = require('lha.extensions.hue.HueBridge')


local configuration = extension:getConfiguration()
tables.merge(configuration, {
  url = 'http://localhost/api/',
  user = 'unknown'
}, true)

local hueBridge
local thingsMap = {}
local lastSensorPollTime
local lastLightPollTime

extension:subscribeEvent('things', function()
  logger:info('Looking for '..extension:getPrettyName()..' things')
  local things = extension:getThings()
  thingsMap = {}
  for discoveryKey, thing in pairs(things) do
    thingsMap[discoveryKey] = thing
  end
end)

local function onHueThing(info, time, lastTime)
  if info.state and info.uniqueid then
    local thing = thingsMap[info.uniqueid]
    if not thing then
      thing = HueBridge.createThingForType(info)
      if thing then
        logger:info('New '..extension:getPrettyName()..' thing found with type "'..tostring(info.type)..'" and id "'..tostring(info.uniqueid)..'"')
        extension:discoverThing(info.uniqueid, thing)
      end
    end
    if thing then
      hueBridge:updateThing(thing, info, time, lastTime)
    end
  end
end

extension:subscribeEvent('poll', function()
  logger:info('Polling '..extension:getPrettyName()..' extension')
  extension:cleanDiscoveredThings()
  hueBridge:get(HueBridge.CONST.SENSORS):next(function(allSensors)
    local time = Date.now()
    if allSensors then
      for _, sensor in pairs(allSensors) do
        -- see https://www.developers.meethue.com/documentation/supported-sensors
        onHueThing(sensor, time, lastSensorPollTime)
      end
    end
    lastSensorPollTime = time
  end):catch(function(err)
    logger:warn('Fail to get '..extension:getPrettyName()..' sensors, due to "'..tostring(err)..'"')
  end)
  hueBridge:get(HueBridge.CONST.LIGHTS):next(function(allLights)
    local time = Date.now()
    if allLights then
      for lightId, light in pairs(allLights) do
        onHueThing(light, time, lastLightPollTime)
      end
      lastLightPollTime = time
    end
  end):catch(function(err)
    logger:warn('fail to get '..extension:getPrettyName()..' lights, due to "'..tostring(err)..'"')
  end)
end)

extension:subscribeEvent('refresh', function()
  logger:info('Refresh '..extension:getPrettyName()..' extension')
  hueBridge:updateConfiguration()
end)

extension:subscribeEvent('startup', function()
  logger:info('startup '..extension:getPrettyName()..' extension')
  hueBridge = HueBridge:new(configuration.url, configuration.user)
  logger:info('Bridge '..extension:getPrettyName()..': "'..configuration.url..'"')
  hueBridge:updateConfiguration()
  --[[
  extension:getEngine():onExtension('web_base', function(webSamplePlugin)
    webSamplePlugin:registerAddonExtension(extension)
  end)
  ]]
end)
