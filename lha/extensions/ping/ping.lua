local extension = ...

local system = require('jls.lang.system')
local tables = require('jls.util.tables')
local Thing = require('lha.engine.Thing')
local logger = require('jls.lang.logger')

logger:info('ping extension under '..extension:getDir():getPath())

local configuration = extension:getConfiguration()

local PING_COUNT = 1

local thingsByTarget = {}

local function createThing(targetName)
  return Thing:new('Host '..targetName, 'Host Reachability', {'BinarySensor'}):addProperty('reachable', {
    ['@type'] = 'BooleanProperty',
    title = 'Host Reachability',
    type = 'boolean',
    description = 'Test the reachability of a host on the network',
    readOnly = true
  }, false)
end

extension:cleanDiscoveredThings()
for _, targetName in ipairs(configuration.target_names) do
  extension:discoverThing(targetName, createThing(targetName))
end

extension:subscribeEvent('things', function()
  logger:info('looking for ping things')
  extension:cleanDiscoveredThings()
  thingsByTarget = {}
  local things = extension:getThings()
  for _, targetName in ipairs(configuration.target_names) do
    local thing = things[targetName]
    if thing then
      thingsByTarget[targetName] = thing
    else
      extension:discoverThing(targetName, createThing(targetName))
    end
  end
end)

local function getPingCommand(targetName)
  if system.isWindows() then
    return 'ping -n '..tostring(PING_COUNT)..' '..targetName..' >nul 2>nul'
  end
  return 'ping -c '..tostring(PING_COUNT)..' '..targetName..' 2>&1 >/dev/null'
end

extension:subscribeEvent('poll', function()
  logger:info('polling ping extension')
  local engine = extension:getEngine()
  local executor = engine:getExtensionById('execute')
  for targetName, thing in pairs(thingsByTarget) do
    local command = getPingCommand(targetName)
    executor:execute(command, true):next(function(code)
      thing:updatePropertyValue('reachable', code == 0)
      logger:info('executed "'..command..'" => '..tostring(code))
    end)
  end
end)
