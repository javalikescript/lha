local extension = ...

local Thing = require('lha.engine.Thing')
--local ThingProperty = require('lha.engine.ThingProperty')

local logger = require('jls.lang.logger')
logger:info('self extension under '..extension:getDir():getPath())


local configuration = extension:getConfiguration()

-- activate the extension by default
if type(configuration.active) ~= 'boolean' then
  configuration.active = true
end

-- always register the single thing
local luaThing = Thing:new('Lua', 'Lua host engine', {'MultiLevelSensor'}):addProperty('memory', {
  ['@type'] = 'LevelProperty',
  title = 'Lua Memory',
  type = 'integer',
  description = 'The total memory in use by Lua in bytes',
  minimum = 0,
  readOnly = true,
  unit = 'byte'
}, 0):addProperty('user', {
  ['@type'] = 'LevelProperty',
  title = 'Lua User Time',
  type = 'number',
  description = 'The amount in seconds of CPU time used by the program',
  minimum = 0,
  readOnly = true,
  unit = 'second'
}, 0)

extension:cleanDiscoveredThings()
extension:discoverThing('lua', luaThing)

--logger:info('luaThing '..require('jls.util.json').encode(luaThing:asThingDescription()))
--[[
curl http://localhost:8080/engine/admin/stop
curl http://localhost:8080/things

]]

extension:subscribeEvent('things', function()
  logger:info('looking for self things')
  local things = extension:getThings()
  if things['lua'] then
    luaThing = things['lua']
    logger:info('lua self thing found')
    extension:cleanDiscoveredThings()
  end
end)

local lastClock = os.clock()

extension:subscribeEvent('poll', function()
  logger:info('polling self extension')
  local clock = os.clock()
  luaThing:updatePropertyValue('memory', math.floor(collectgarbage('count') * 1024))
  luaThing:updatePropertyValue('user', math.floor((clock - lastClock) * 1000) / 1000)
  lastClock = clock
end)
