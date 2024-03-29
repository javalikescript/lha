local extension = ...

local logger = extension:getLogger()
local system = require('jls.lang.system')
local Thing = require('lha.Thing')

local function createThing(targetName)
  return Thing:new('Host '..targetName, 'Host Reachability', {'BinarySensor'}):addProperty('reachable', {
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
  local targetNames = configuration.targetNames or {}
  for _, targetName in ipairs(targetNames) do
    local thing = things[targetName]
    if thing then
      thingsByTarget[targetName] = thing
    else
      extension:discoverThing(targetName, createThing(targetName))
    end
  end
end)

local function getPingCommand(targetName)
  if isWindows then
    return 'ping -n '..tostring(PING_COUNT)..' '..targetName..' >nul 2>nul'
  end
  return 'ping -c '..tostring(PING_COUNT)..' '..targetName..' 2>&1 >/dev/null'
end

extension:subscribeEvent('poll', function()
  logger:info('polling ping extension')
  local engine = extension:getEngine()
  local executor = engine:getExtensionById('execute')
  if not executor then
    logger:info('execute extension not available')
    return
  end
  for targetName, thing in pairs(thingsByTarget) do
    local command = getPingCommand(targetName)
    executor:execute(command, true):next(function(code)
      thing:updatePropertyValue('reachable', code == 0)
      logger:info('executed "%s" => %s', command, code)
    end, function(reason)
      logger:info('execution failed %s', reason)
    end)
  end
end)
