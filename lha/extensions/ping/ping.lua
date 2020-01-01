local extension = ...

local system = require('jls.lang.system')
local tables = require('jls.util.tables')
local Thing = require('lha.engine.Thing')
local logger = require('jls.lang.logger')
local sysexec = require('lha.engine.sysexec')

logger:info('ping extension under '..extension:getDir():getPath())

local configuration = extension:getConfiguration()
tables.merge(configuration, {
  target_names = {'127.0.0.1'}
}, true)

local thingsByTarget = {}

local function createThing(targetName)
  return Thing:new('Host', 'Host Reachability', {'BinarySensor'}):addProperty('reachable', {
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

extension:subscribeEvent('poll', function()
  logger:info('polling ping extension')
  local count = 1
  for targetName, thing in pairs(thingsByTarget) do
    local command
    if system.isWindows() then
      command = 'ping -n '..tostring(count)..' '..targetName..' >nul 2>nul'
    else
      command = 'ping -c '..tostring(count)..' '..targetName..' 2>&1 >/dev/null'
    end
    sysexec.execute(command, function(err, code)
      thing:updatePropertyValue('reachable', code == true)
    end)
    
  end
end)
