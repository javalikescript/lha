local extension = ...

local logger = extension:getLogger()
local Promise = require('jls.lang.Promise')
local File = require('jls.io.File')
local json = require('jls.util.json')
local Map = require('jls.util.Map')

local HueBridgeV2 = extension:require('HueBridgeV2')

local configuration = extension:getConfiguration()

local hueBridge, bridgeId
local thingsMap = {}
local lastResourceMap = {}

local function getThingId(thing)
  for id, t in pairs(thingsMap) do
    if t == thing then
      local resource = lastResourceMap[id]
      if resource and resource.type == 'device' then
        return id
      end
    end
  end
end

local function setThingPropertyValue(thing, name, value)
  local id = getThingId(thing)
  local function logFailure(reason)
    logger:warn('Fail to set thing "%s" (id: %s) property "%s" to value "%s" due to "%s"', thing:getTitle(), id, name, value, reason)
  end
  if hueBridge and id then
    hueBridge:setResourceValue(lastResourceMap, id, name, value):next(function()
      thing:updatePropertyValue(name, value)
    end, logFailure)
  else
    logFailure('thing or bridge not available')
    thing:updatePropertyValue(name, value)
  end
end

extension:subscribeEvent('things', function()
  logger:info('Looking for things')
  thingsMap = extension:getThingsByDiscoveryKey()
  for _, thing in pairs(thingsMap) do
    thing.setPropertyValue = setThingPropertyValue
  end
end)

local function processRessources(resources)
  lastResourceMap = resources
  for id, device in pairs(resources) do
    if device.type == 'device' then
      local thing = thingsMap[id]
      if thing == nil then
        thing = hueBridge:createThingFromDeviceId(resources, id)
        if thing then
          logger:info('New thing found with name "%s" id "%s"', device.metadata.name, id)
          extension:discoverThing(id, thing)
        else
          thing = false
        end
        thingsMap[id] = thing
      end
      if thing then
        hueBridge:updateThing(thing, resources, id)
      end
    end
  end
  if not bridgeId then
    for _, device in pairs(resources) do
      if device.type == 'bridge' then
        bridgeId = device.owner.rid
        break
      end
    end
  end
end

local function updateReachability(value)
  if bridgeId then
    local thing = thingsMap[bridgeId]
    if thing then
      thing:updatePropertyValue('reachable', value)
    end
  end
end

local function processEvents(events)
  for _, event in ipairs(events) do
    if event and event.type == 'update' and event.data then
      for _, data in ipairs(event.data) do
        local owner = data.owner
        if owner and owner.rtype == 'device' then
          local thing = thingsMap[owner.rid]
          if thing then
            local resource = lastResourceMap[data.id] or data
            hueBridge:updateThingResource(thing, resource, data, true)
          else
            logger:info('Hue event received on unmapped thing %s', owner.rid)
          end
        end
      end
    end
  end
end

extension:subscribeEvent('poll', function()
  if not hueBridge then
    return
  end
  logger:info('Polling')
  hueBridge:getResourceMapById():next(function(resources)
    if logger:isLoggable(logger.FINE) then
      logger:info('%d resources found', Map.size(resources))
    end
    updateReachability(true)
    processRessources(resources)
  end, function(reason)
    updateReachability(false)
    return Promise.reject(reason)
  end):catch(function(reason)
    logger:warn('Polling error: %s', reason)
  end)
end)

extension:subscribeEvent('refresh', function()
  logger:info('Refresh')
end)

extension:subscribeEvent('heartbeat', function()
  if hueBridge then
    hueBridge:checkEventStream()
  end
end)

extension:subscribeEvent('startup', function()
  logger:info('Starting')
  if hueBridge then
    hueBridge:close()
  end
  local mappingFile = File:new(extension.dir, 'mapping-v2.json')
  local mapping = json.decode(mappingFile:readAll())
  hueBridge = HueBridgeV2:new(configuration.url, configuration.user, mapping)

  if configuration.streamEnabled then
    logger:info('start event stream')
    hueBridge:startEventStream(processEvents)
  end
end)

extension:subscribeEvent('shutdown', function()
  if hueBridge then
    hueBridge:close()
  end
end)
