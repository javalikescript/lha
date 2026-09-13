local extension = ...

local logger = extension:getLogger()
local File = require('jls.io.File')
local json = require('jls.util.json')

local MatterJs = extension:require('MatterJs')

local thingsMap = {}
local deviceMap = {}
local matterJs

local function onNode(node)
  local device = matterJs:findDeviceFromNode(node)
  if device then
    local id = node.node_id
    local thing = thingsMap[id]
    if thing == nil then
      thing = matterJs:createThingFromNode(node, device)
      if thing then
        logger:info('New thing found %s with id %s', thing, id)
        logger:finest('properties %T', thing, thing:getPropertyDescriptions())
        extension:discoverThing(id, thing)
      else
        thing = false
      end
      thingsMap[id] = thing
    end
    if thing then
      deviceMap[id] = device
      matterJs:updateThing(thing, device, node)
      logger:finest('properties values %T', thing:getPropertyValues())
    end
  end
end

local function onNodes(nodes)
  for _, node in pairs(nodes) do
    onNode(node)
  end
end

local function onNodeEvent(event, data)
  logger:fine('onNodeEvent(%s, %T)', event, data)
  -- https://github.com/matter-js/matterjs-server/blob/main/docs/websockets_api.md#events
  if event == 'attribute_updated' then
    local id = data[1]
    local thing = thingsMap[id]
    local device = deviceMap[id]
    if thing and device then
      matterJs:updateThing(thing, device, {attributes = {[data[2]] = data[3]}})
    end
  end
end

extension:subscribeEvent('things', function()
  logger:info('Looking for things')
  thingsMap = extension:getThingsByDiscoveryKey()
  --for _, thing in pairs(thingsMap) do; thing.setPropertyValue = setThingPropertyValue; end
end)

extension:subscribeEvent('poll', function()
  logger:info('Polling')
end)

extension:subscribeEvent('heartbeat', function()
  if matterJs then
    matterJs:refresh()
  end
end)

extension:subscribeEvent('startup', function()
  logger:info('Starting')
  if matterJs then
    matterJs:close()
  end
  local config = extension:getConfiguration()
  local mappingFile = File:new(extension.dir, 'mapping.json')
  local mapping = json.decode(mappingFile:readAll())
  matterJs = MatterJs:new(config.url, mapping)
  matterJs:setEventHandler(onNodeEvent)
  matterJs:startWebSocket():next(function()
    return matterJs:startListeningWebSocket()
  end):next(function(nodes)
    logger:info('Connected')
    onNodes(nodes)
  end)
end)

extension:subscribeEvent('shutdown', function()
  logger:info('shutdown')
  if matterJs then
    matterJs:close()
  end
end)

function extension:setThreadDataset(exchange, dataset)
  return matterJs:sendWebSocket('set_thread_dataset', {
    dataset = dataset
  }):next(function()
    return 'OK'
  end)
end

function extension:setWifiCredentials(exchange, ssid, credentials)
  return matterJs:sendWebSocket('set_wifi_credentials', {
    ssid = ssid,
    credentials = credentials
  }):next(function()
    return 'OK'
  end)
end

function extension:discover(exchange)
  return matterJs:sendWebSocket('discover'):next(function(devices)
    return 'Found '..tostring(#devices)..' devices'
  end)
end

function extension:commissionWithCode(exchange, code, networkOnly)
  return matterJs:sendWebSocket('discover', {
    code = code,
    network_only = networkOnly
  }):next(function()
    return 'OK'
  end)
end
