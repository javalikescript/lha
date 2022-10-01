local extension = ...

local logger = require('jls.lang.logger')
local Date = require('jls.util.Date')

local Thing = require('lha.Thing')

local HueBridge = extension:require('hue.HueBridge', true)

local configuration = extension:getConfiguration()

local hueBridge, bridgeThing
local thingsMap = {}
local lastSensorPollTime, lastLightPollTime

local function setThingPropertyValue(thing, name, value)
  if hueBridge and thing.hueId then
    hueBridge:setThingPropertyValue(thing, thing.hueId, name, value):next(function()
      thing:updatePropertyValue(name, value)
    end)
  else
    thing:updatePropertyValue(name, value)
  end
end

local function setupBridgeThing()
  bridgeThing = extension:syncDiscoveredThingByKey('bridge', function()
    return Thing:new('Bridge', 'The Hue bridge', {'MultiLevelSensor'}):addPropertiesFromNames('connected', 'reachable')
  end)
end

extension:subscribeEvent('things', function()
  logger:info('Looking for '..extension:getPrettyName()..' things')
  setupBridgeThing()
  thingsMap = extension:getThingsByDiscoveryKey()
  for _, thing in pairs(thingsMap) do
    thing.setPropertyValue = setThingPropertyValue
  end
end)

local function onHueThing(id, info, time, lastTime)
  if info and info.state and info.uniqueid then
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
      thing.hueId = id
      hueBridge:updateThing(thing, info)
    end
  end
end

local function onHueEvent(info)
  -- see https://dresden-elektronik.github.io/deconz-rest-doc/endpoints/websocket/
  if info.e == 'changed' then
    if info.r == 'lights' or info.r == 'sensors' then
      local thing = thingsMap[info.uniqueid]
      if info.state and logger:isLoggable(logger.FINE) then
        local json = require('jls.util.json')
        logger:fine('Hue event received on "'..(thing and thing:getTitle() or 'n/a')..'" '..json.stringify(info, 2))
      end
      if thing then
        hueBridge:updateThing(thing, info, true)
      end
    elseif info.r == 'websocket' then
      bridgeThing:updatePropertyValue('connected', (info.state and info.state.connected) == true)
    end
  --elseif info.e == 'added' then
  --elseif info.e == 'deleted' then
  --elseif info.e == 'scene-called' then
  end
end

extension:subscribeEvent('poll', function()
  if not hueBridge then
    return
  end
  logger:info('Polling '..extension:getPrettyName()..' extension')
  -- TODO expose a bridge thing
  hueBridge:get(HueBridge.CONST.sensors):next(function(allSensors)
    local time = Date.now()
    if allSensors then
      for sensorId, sensor in pairs(allSensors) do
        -- see https://www.developers.meethue.com/documentation/supported-sensors
        onHueThing(sensorId, sensor, time, lastSensorPollTime)
      end
    end
    lastSensorPollTime = time
    return hueBridge:get(HueBridge.CONST.lights)
  end):next(function(allLights)
    local time = Date.now()
    if allLights then
      for lightId, light in pairs(allLights) do
        onHueThing(lightId, light, time, lastLightPollTime)
      end
      lastLightPollTime = time
    end
    bridgeThing:updatePropertyValue('reachable', true)
  end):catch(function(err)
    logger:warn('fail to get '..extension:getPrettyName()..' things, due to "'..tostring(err)..'"')
    bridgeThing:updatePropertyValue('reachable', false)
  end)
end)

extension:subscribeEvent('refresh', function()
  logger:info('Refresh '..extension:getPrettyName()..' extension')
  hueBridge:updateConfiguration()
end)

extension:subscribeEvent('heartbeat', function()
  hueBridge:checkWebSocket()
end)

extension:subscribeEvent('startup', function()
  logger:info('startup '..extension:getPrettyName()..' extension')
  setupBridgeThing()
  if hueBridge then
    hueBridge:close()
  end
  hueBridge = HueBridge:new(configuration.url, configuration.user)
  if configuration.useWebSocket then
    hueBridge:setOnWebSocket(onHueEvent)
  end
  logger:info('Bridge '..extension:getPrettyName()..': "'..configuration.url..'"')
  hueBridge:updateConfiguration()
end)

extension:subscribeEvent('shutdown', function()
  if hueBridge then
    hueBridge:close()
  end
end)
