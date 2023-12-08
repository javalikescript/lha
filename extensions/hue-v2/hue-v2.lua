local extension = ...

local logger = require('jls.lang.logger')
local File = require('jls.io.File')
local Date = require('jls.util.Date')
local json = require('jls.util.json')
local tables = require('jls.util.tables')
local ProxyHttpHandler = require('jls.net.http.handler.ProxyHttpHandler')

local Thing = require('lha.Thing')

local HueBridge = extension:require('HueBridgeV2')

local configuration = extension:getConfiguration()

local contexts = {}

local hueBridge
local thingsMap = {}
local lastResourceMap = {}

local function cleanup(server)
  for _, context in ipairs(contexts) do
    server:removeContext(context)
  end
  contexts = {}
end

local function addContext(server, ...)
  local context = server:createContext(...)
  table.insert(contexts, context)
end

local function findKey(map, value)
  for k, v in pairs(map) do
    if v == value then
      return k
    end
  end
end

local function setThingPropertyValue(thing, name, value)
  if hueBridge then
    local id = findKey(thingsMap, thing)
    if id and lastResourceMap then
      hueBridge:setThingPropertyValue(lastResourceMap, id, name, value):next(function()
        thing:updatePropertyValue(name, value)
      end)
    end
  else
    thing:updatePropertyValue(name, value)
  end
end

extension:subscribeEvent('things', function()
  logger:info('Looking for %s things', extension:getPrettyName())
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
          logger:info('New %s thing found with name "%s" id "%s"', extension:getPrettyName(), device.metadata.name, id)
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
end

local function processEvents(events)
  for _, event in ipairs(events) do
    if event and event.type == 'update' and event.data then
      for _, data in ipairs(event.data) do
        local owner = data.owner
        if owner and owner.rtype == 'device' then
          local thing = thingsMap[owner.rid]
          if thing then
            local resource = lastResourceMap and lastResourceMap[data.id] or data
            hueBridge:updateThingResource(thing, resource, data)
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
  logger:info('Polling %s extension', extension:getPrettyName())
  hueBridge:getResourceMapById():next(processRessources):catch(function(reason)
    logger:warn('Polling %s extension error: %s', extension:getPrettyName(), reason)
  end)
end)

extension:subscribeEvent('refresh', function()
  logger:info('Refresh %s extension', extension:getPrettyName())
end)

extension:subscribeEvent('startup', function()
  logger:info('startup %s extension', extension:getPrettyName())
  if hueBridge then
    hueBridge:close()
  end
  local mappingFile = File:new(extension.dir, 'mapping.json')
  local mapping = json.decode(mappingFile:readAll())
  hueBridge = HueBridge:new(configuration.url, configuration.user, mapping)

  if configuration.streamEnabled then
    logger:info('start event stream')
    hueBridge:startEventStream(processEvents)
  end

  extension:getEngine():onExtension('web-base', function(webBaseExtension)
    --webBaseExtension:registerAddonExtension(extension, true)
  end)
  local server = extension:getEngine():getHTTPServer()
  cleanup(server)
  --addContext(server, '/hue-api/(.*)', ProxyHttpHandler:new():configureReverse(configuration.url..configuration.user..'/'))
end)

extension:subscribeEvent('shutdown', function()
  if hueBridge then
    hueBridge:close()
  end
  extension:getEngine():onExtension('web-base', function(webBaseExtension)
    webBaseExtension:unregisterAddonExtension(extension)
  end)
  cleanup(extension:getEngine():getHTTPServer())
end)
