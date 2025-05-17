local extension = ...

local logger = extension:getLogger()
local system = require('jls.lang.system')
local hasBt = pcall(require, 'bt')
local Thing = require('lha.Thing')

local function createThing(name)
  return Thing:new(name or 'Host', 'Host Reachability', {'BinarySensor'}):addProperty('reachable', {
    ['@type'] = 'BooleanProperty',
    title = 'Host Reachability',
    type = 'boolean',
    description = 'Test the reachability of a host on the network',
    readOnly = true
  }, false)
end


local isWindows = system.isWindows()
local PING_COUNT = 1
local thingsByTarget = {}

extension:subscribeEvent('things', function()
  logger:info('looking for ping things')
  local configuration = extension:getConfiguration()
  extension:cleanDiscoveredThings()
  thingsByTarget = {}
  local things = extension:getThingsByDiscoveryKey()
  local targets = configuration.targets or {}
  for _, target in ipairs(targets) do
    local key
    local address = target.address
    if type(address) == 'string' and #address > 0 then
      if target.bluetooth then
        if hasBt then
          key = 'BT-'..address
        end
      else
        key = 'IP-'..address
      end
    end
    if key and target.name then
      local thing = things[key]
      if thing then
        thingsByTarget[key] = thing
      else
        extension:discoverThing(key, createThing(target.name))
      end
    end
  end
end)

-- arp -a
local function getPingCommand(targetName)
  if isWindows then
    return 'ping -n '..PING_COUNT..' '..targetName..' >nul 2>nul'
  end
  return 'ping -c '..PING_COUNT..' '..targetName..' 2>&1 >/dev/null'
end

local function pingBluetooth(macAddress)
  local bt = require('bt')
  local info, err = bt.getDeviceInfo(macAddress)
  return info ~= nil and info ~= false
end

extension:subscribeEvent('poll', function()
  logger:info('polling ping extension')
  local engine = extension:getEngine()
  local executor = engine:getExtensionById('execute')
  if not executor then
    logger:info('execute extension not available')
    return
  end
  for key, thing in pairs(thingsByTarget) do
    local kind, address = string.match(key, '^(%w+)%-(.+)$')
    if kind == 'IP' then
      local command = getPingCommand(address)
      executor:execute(command, true):next(function(code)
        thing:updatePropertyValue('reachable', code == 0)
        logger:info('executed "%s" => %s', command, code)
      end, function(reason)
        logger:info('execution failed %s', reason)
      end)
    elseif kind == 'BT' and hasBt then
      executor:call(pingBluetooth, address):next(function(status)
        thing:updatePropertyValue('reachable', status)
      end, function(reason)
        logger:info('execution failed %s', reason)
      end)
    end
  end
end)
