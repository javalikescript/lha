local extension = ...

local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local File = require('jls.io.File')
local json = require('jls.util.json')

local Thing = require('lha.Thing')
local utils = require('lha.utils')

local HueBridgeV1 = extension:require('HueBridgeV1')

local configuration = extension:getConfiguration()

local hueBridge, bridgeThing
local thingsMap = {}
local lastResourceMap = {}

local function setThingPropertyValue(thing, name, value)
  if hueBridge then
    local id = utils.findKey(thingsMap, thing)
    if id then
      local resource = lastResourceMap[id]
      if resource.primaryid then
        -- setting value is restricted to sub primary resources!
        resource = lastResourceMap[resource.primaryid]
      end
      hueBridge:setResourceValue(resource, name, value):next(function()
        thing:updatePropertyValue(name, value)
      end)
    end
  else
    thing:updatePropertyValue(name, value)
  end
end

local function updateReachability(value)
  if bridgeThing then
    bridgeThing:updatePropertyValue('reachable', value)
  end
end

extension:subscribeEvent('things', function()
  logger:info('Looking for %s things', extension:getPrettyName())
  bridgeThing = extension:syncDiscoveredThingByKey('bridge', function()
    return Thing:new('Bridge', 'The Hue bridge', {'MultiLevelSensor'}):addPropertiesFromNames('connected', 'reachable')
  end, bridgeThing)
  thingsMap = extension:getThingsByDiscoveryKey()
  for _, thing in pairs(thingsMap) do
    thing.setPropertyValue = setThingPropertyValue
  end
end)

local function processRessources(resources)
  lastResourceMap = resources
  for id in pairs(resources) do
    local thing = thingsMap[id]
    if thing == nil then
      thing = hueBridge:createThingFromDeviceId(resources, id)
      if thing then
        logger:info('New %s thing found with id "%s"', extension:getPrettyName(), id)
        extension:discoverThing(id, thing)
      else
        thing = false
      end
      thingsMap[id] = thing
    end
  end
  for id, resource in pairs(resources) do
    local thing
    if resource.primaryid then
      thing = thingsMap[resource.primaryid]
      thingsMap[id] = thing
    else
      thing = thingsMap[id]
    end
    if thing then
      hueBridge:updateThingResource(thing, resource, resource)
    end
  end
end

local function onHueEvent(info)
  -- see https://dresden-elektronik.github.io/deconz-rest-doc/endpoints/websocket/
  if info.state and info.e == 'changed' then
    if info.r == 'sensors' or info.r == 'lights' then
      local thing = thingsMap[info.uniqueid]
      local resource = lastResourceMap[info.uniqueid]
      if thing and resource then
        if logger:isLoggable(logger.FINE) then
          logger:fine('Hue event received on "%s" %s', thing and thing:getTitle(), json.stringify(info))
        end
        hueBridge:updateThingResource(thing, resource, info, true)
      end
    elseif info.r == 'websocket' and bridgeThing then
      bridgeThing:updatePropertyValue('connected', info.state.connected == true)
    end
  end
end

extension:subscribeEvent('poll', function()
  logger:info('Polling %s extension', extension:getPrettyName())
  if hueBridge then
    hueBridge:getResourceMapById():next(function(resources)
      updateReachability(true)
      processRessources(resources)
    end, function(reason)
      updateReachability(false)
      return Promise.reject(reason)
    end):catch(function(reason)
      logger:warn('Polling %s extension error: %s', extension:getPrettyName(), reason)
    end)
  end
end)

extension:subscribeEvent('refresh', function()
  logger:info('Refresh %s extension', extension:getPrettyName())
  if hueBridge then
    hueBridge:updateConfiguration()
  end
end)

extension:subscribeEvent('heartbeat', function()
  if hueBridge then
    hueBridge:checkWebSocket()
  end
end)

extension:subscribeEvent('startup', function()
  logger:info('startup %s extension', extension:getPrettyName())
  if hueBridge then
    hueBridge:close()
  end
  local mappingFile = File:new(extension.dir, 'mapping-v1.json')
  local mapping
  if mappingFile:isFile() then
    mapping = json.decode(mappingFile:readAll())
  end
  hueBridge = HueBridgeV1:new(configuration.url, configuration.user, mapping)
  if configuration.useWebSocket then
    hueBridge:setOnWebSocket(onHueEvent)
  end
  logger:info('Bridge '..extension:getPrettyName()..': "'..configuration.url..'"')
  hueBridge:updateConfiguration()
end)

extension:subscribeEvent('shutdown', function()
  if hueBridge then
    hueBridge:close()
    hueBridge = nil
  end
end)
