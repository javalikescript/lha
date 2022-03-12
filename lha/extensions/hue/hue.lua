local extension = ...

local logger = require('jls.lang.logger')
local tables = require('jls.util.tables')
local Date = require('jls.util.Date')

local HueBridge = require('lha.extensions.hue.HueBridge')


local configuration = extension:getConfiguration()

local hueBridge
local thingsMap = {}
local lastSensorPollTime
local lastLightPollTime

extension:subscribeEvent('things', function()
  logger:info('Looking for '..extension:getPrettyName()..' things')
  thingsMap = extension:getThingsByDiscoveryKey()
end)

local function onHueThing(id, info, time, lastTime)
  if info.state and info.uniqueid then
    local thing = thingsMap[info.uniqueid]
    if thing == nil then
      thing = HueBridge.createThingForType(info)
      if thing then
        logger:info('New '..extension:getPrettyName()..' thing found with type "'..tostring(info.type)..'" id "'..tostring(id)..'" and uniqueid "'..tostring(info.uniqueid)..'"')
        extension:discoverThing(info.uniqueid, thing)
      else
        thing = false
      end
      thingsMap[info.uniqueid] = thing
    end
    if thing then
      if not thing.connected and thing.connect then
        hueBridge:connectThing(thing, id)
      end
      hueBridge:updateThing(thing, info, time, lastTime)
    end
  end
end

local json = require('jls.util.json')
local function onHueEvent(info)
  -- see https://dresden-elektronik.github.io/deconz-rest-doc/endpoints/websocket/

  logger:info('Hue event received '..json.stringify(info, 2))

  if info.e == 'changed' and (info.r == 'lights' or info.r == 'sensors') then
    -- info.type is missing
    local thing = thingsMap[info.uniqueid]
    if thing then
      --hueBridge:lazyUpdateThing(thing, info)
    end
  --elseif info.e == 'added' then
  --elseif info.e == 'deleted' then
  --elseif info.e == 'scene-called' then
  end
end

extension:subscribeEvent('poll', function()
  logger:info('Polling '..extension:getPrettyName()..' extension')
  hueBridge:get(HueBridge.CONST.SENSORS):next(function(allSensors)
    local time = Date.now()
    if allSensors then
      for sensorId, sensor in pairs(allSensors) do
        -- see https://www.developers.meethue.com/documentation/supported-sensors
        onHueThing(sensorId, sensor, time, lastSensorPollTime)
      end
    end
    lastSensorPollTime = time
    return hueBridge:get(HueBridge.CONST.LIGHTS)
  end):next(function(allLights)
    local time = Date.now()
    if allLights then
      for lightId, light in pairs(allLights) do
        onHueThing(lightId, light, time, lastLightPollTime)
      end
      lastLightPollTime = time
    end
    --[[for discoveryKey, thing in pairs(thingsMap) do
      if not thing:isConnected() then
        thing:setReachable(false)
      end
    end]]
  end):catch(function(err)
    logger:warn('fail to get '..extension:getPrettyName()..' things, due to "'..tostring(err)..'"')
  end)
end)

extension:subscribeEvent('refresh', function()
  logger:info('Refresh '..extension:getPrettyName()..' extension')
  hueBridge:updateConfiguration()
end)

extension:subscribeEvent('startup', function()
  logger:info('startup '..extension:getPrettyName()..' extension')
  if hueBridge then
    hueBridge:close()
  end
  hueBridge = HueBridge:new(configuration.url, configuration.user, configuration.useWebSocket and onHueEvent)
  logger:info('Bridge '..extension:getPrettyName()..': "'..configuration.url..'"')
  hueBridge:updateConfiguration()
end)

extension:subscribeEvent('shutdown', function()
  if hueBridge then
    hueBridge:close()
  end
end)
