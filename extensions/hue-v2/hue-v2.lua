local extension = ...

local logger = extension:getLogger()
local Promise = require('jls.lang.Promise')
local File = require('jls.io.File')
local dns = require('jls.net.dns')
local UdpSocket = require('jls.net.UdpSocket')
local json = require('jls.util.json')
local Map = require('jls.util.Map')
local List = require('jls.util.List')

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
    logger:warn('Fail to set thing %s (id: %s) property "%s" to value "%s" due to "%s"', thing, id, name, value, reason)
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
  local mappingFile = File:new(extension:getDir(), 'mapping-v2.json')
  local mapping = json.decode(mappingFile:readAll())
  local hueBridgePem = File:new(extension:getDir(), 'hue-bridge.pem'):getPath()
  hueBridge = HueBridgeV2:new(configuration.url, configuration.user, mapping, hueBridgePem)
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

local function discover(name, dnsType)
  local mdnsAddress, mdnsPort = '224.0.0.251', 5353
  local id = math.random(0xfff)
  local messages = {}
  local onMessage
  local function onReceived(err, data, addr)
    if data then
      logger:finer('received data: (%l) %x %t', #data, data, addr)
      local _, message = pcall(dns.decodeMessage, data)
      logger:finer('message: %t', message)
      if message.id == id then
        message.addr = addr
        table.insert(messages, message)
        if type(onMessage) == 'function' then
          local status, e = pcall(onMessage, message)
          if not status then
            logger:warn('error on message %s', e)
          end
        end
      end
    elseif err then
      logger:warn('receive error %s', err)
    else
      logger:fine('receive no data')
    end
  end
  local data = dns.encodeMessage({
    id = id,
    questions = {{
      name = name or '_services._dns-sd._udp.local',
      type = dnsType or dns.TYPES.PTR,
      class = dns.CLASSES.IN,
      unicastResponse = true,
    }}
  })
  local senders = {}
  return {
    messages = messages,
    onMessage = function(fn)
      onMessage = fn
    end,
    start = function()
      local addresses = dns.getInterfaceAddresses()
      logger:fine('Interface addresses: %t', addresses)
      for _, address in ipairs(addresses) do
        local sender = UdpSocket:new()
        sender:bind(address, 0)
        logger:fine('sender bound to %s', address)
        sender:receiveStart(onReceived)
        table.insert(senders, sender)
      end
    end,
    send = function()
      for _, sender in ipairs(senders) do
        sender:send(data, mdnsAddress, mdnsPort):catch(function(reason)
          logger:warn('Error while sending UDP, %s', reason)
          sender:close()
          List.removeAll(senders, sender)
        end)
      end
    end,
    close = function()
      local sendersToClose = senders
      senders = {}
      for _, sender in ipairs(sendersToClose) do
        sender:close()
      end
    end
  }
end

function extension:discoverBridge()
  logger:info('Looking for Hue Bridge...')
  return Promise:new(function(resolve, reject)
    local discovery = discover('_hue._tcp.local')
    discovery.onMessage(function(message)
      local ip = message.addr and message.addr.ip
      logger:fine('on message %s', ip)
      if ip then
        resolve('Found '..ip)
        configuration.url = 'https://'..ip..'/'
        discovery.close()
        extension:clearTimer('discovery')
      end
    end)
    discovery.start()
    discovery.send()
    extension:setTimer(function()
      reject('Discovery timeout')
      discovery.close()
    end, 5000, 'discovery')
  end)
end

function extension:generateKey()
  if not configuration.url then
    return Promise.reject('Bridge URL not available')
  end
  local hueBridgePem = File:new(extension:getDir(), 'hue-bridge.pem'):getPath()
  local client = HueBridgeV2.createHttpClient(configuration.url, hueBridgePem)
  return client:fetch('/api', {
    method = 'POST',
    headers = {
      ['Content-Type'] = 'application/json'
    },
    body = json.encode({
      devicetype = 'lha#default', -- existing key will be replaced
      generateclientkey = true
    })
  }):next(HueBridgeV2.processResponseV1):next(function(response)
    configuration.user = response.username
    --configuration.clientkey = response.clientkey
    return 'OK'
  end):finally(function()
    client:close()
  end)
end

function extension:touchlink()
  return hueBridge:putConfig({touchlink = true}):next(function(response)
    return 'OK'
  end)
end

local function getLastScan(path, callback)
  logger:fine('Looking for last scan...')
  hueBridge:httpRequestV1('GET', path):next(function(response)
    if response.lastscan == 'active' then
      callback(nil, 'Scan in progress...')
      extension:setTimer(function()
        getLastScan(path, callback)
      end, 5000, 'scan')
    else
      logger:fine('Last scan: %T', response)
      local count = Map.size(response) - 1
      if count > 0 then
        callback(nil, string.format('Found %s things (%s)', count, response.lastscan))
      else
        callback(nil, string.format('Nothing found (%s)', response.lastscan))
      end
    end
  end):catch(function(reason)
    callback('Cannot get last scan due to '..tostring(reason))
  end)
end

function extension:searchNewDevices(exchange, path)
  local session = exchange:getSession()
  local sessionId = session and session:getId()
  return hueBridge:httpRequestV1('POST', path):next(function(response)
    getLastScan(path..'/new', function(err, message)
      extension:notify(err or message, sessionId)
    end)
    return 'OK'
  end)
end

function extension:searchNewLights(exchange)
  return self:searchNewDevices(exchange, '/lights')
end

function extension:searchNewSensors(exchange)
  return self:searchNewDevices(exchange, '/sensors')
end
