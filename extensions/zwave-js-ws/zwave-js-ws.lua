local extension = ...

local logger = extension:getLogger()
local File = require('jls.io.File')
local json = require('jls.util.json')

local Thing = require('lha.Thing')
local utils = require('lha.utils')

local ZWaveJs = extension:require('ZWaveJs')

local thingsMap = {}
local deviceMap = {}
local zWaveJs

local function onNode(node)
  local device = zWaveJs:findDeviceFromNode(node)
  if device then
    local id = node.nodeId
    local thing = thingsMap[id]
    if thing == nil then
      thing = zWaveJs:createThingFromNode(node, device)
      if thing then
        logger:info('New thing found with title %s id %s', thing, id)
        extension:discoverThing(id, thing)
      else
        thing = false
      end
      thingsMap[id] = thing
    end
    if thing then
      deviceMap[id] = device
      for _, value in ipairs(node.values) do
        zWaveJs:updateThing(thing, device, value)
      end
    end
  end
end

local function onNodes(nodes)
  for _, node in pairs(nodes) do
    onNode(node)
  end
end

local function onNodeEvent(event)
  -- see https://zwave-js.github.io/node-zwave-js/#/api/node?id=zwavenode-events
  if event.source == 'node' then
    if event.event == 'value updated' and event.nodeId and event.args then
      local id = event.nodeId
      local thing = thingsMap[id]
      local device = deviceMap[id]
      if thing and device then
        zWaveJs:updateThing(thing, device, event.args, true)
      end
    end
  end
end

local function setThingPropertyValue(thing, name, value)
  local id = utils.findKey(thingsMap, thing)
  local function logFailure(reason)
    logger:warn('Fail to set thing %s (id: %s) property "%s" to value "%s" due to "%s"', thing, id, name, value, reason)
  end
  if id then
    local device = deviceMap[id]
    if device then
      zWaveJs:setNodeValue(id, device, name, value):next(function()
        thing:updatePropertyValue(name, value)
      end, logFailure)
      return
    end
  end
  logFailure('thing or device not available')
end

extension:subscribeEvent('things', function()
  logger:info('Looking for things')
  thingsMap = extension:getThingsByDiscoveryKey()
  for _, thing in pairs(thingsMap) do
    thing.setPropertyValue = setThingPropertyValue
  end
end)

extension:subscribeEvent('poll', function()
  logger:info('Polling')
  for nodeId, thing in pairs(thingsMap) do
    logger:fine('Z-Wave polling nodeId %s', nodeId)
    -- get state will dump node, getValue for each getDefinedValueIDs
    zWaveJs:sendWebSocket({
      command = 'node.get_state',
      nodeId = nodeId
    }):next(function(result)
      logger:finer('Z-Wave nodeId %s state: %t', nodeId, result)
      onNode(result.state)
    end)
  end
end)

extension:subscribeEvent('heartbeat', function()
  if zWaveJs then
    -- TODO check web socket
  end
end)

extension:subscribeEvent('startup', function()
  logger:info('Starting')
  if zWaveJs then
    zWaveJs:close()
  end
  local config = extension:getConfiguration()
  local mappingFile = File:new(extension.dir, 'mapping.json')
  local mapping = json.decode(mappingFile:readAll())
  zWaveJs = ZWaveJs:new(config.url, mapping)
  zWaveJs:setEventHandler(onNodeEvent)
  zWaveJs:startWebSocket():next(function()
    return zWaveJs:startListeningWebSocket()
  end):next(function(state)
    onNodes(state.nodes)
  end)
end)

extension:subscribeEvent('shutdown', function()
  logger:info('shutdown')
  if zWaveJs then
    zWaveJs:close()
  end
end)
