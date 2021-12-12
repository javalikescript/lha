local extension = ...

local Thing = require('lha.engine.Thing')
--local ThingProperty = require('lha.engine.ThingProperty')
local logger = require('jls.lang.logger')
local loader = require('jls.lang.loader')
local memprof = require('jls.util.memprof')
local File = require('jls.io.File')
local Date = require('jls.util.Date')
local luv = loader.tryRequire('luv')

local function mathRound(value)
  -- Rounds value towards zero
  if value >= 0 then
    return math.floor(value + 0.5)
  else
    return math.ceil(value - 0.5)
  end
end

local function toPercent(value)
  return mathRound(value * 10) / 10
end

local function timevalToMilis(tv)
  return tv.sec * 1000 + (tv.usec // 1000)
end
local function getRUsage(rusage)
  return {
    sys = timevalToMilis(rusage.stime),
    usage = timevalToMilis(rusage.utime),
  }
end

local timeKeys = {'idle', 'user', 'sys', 'irq', 'nice'}
local function sumCpuInfo(infos)
  local s = {}
  for _, k in ipairs(timeKeys) do
    s[k] = 0
  end
  for _, info in ipairs(infos) do
    local times = info.times
    for _, k in ipairs(timeKeys) do
      s[k] = s[k] + math.floor(times[k])
    end
  end
  return s
end
local function computeCpuUsage(lastInfo, info)
  local s = {}
  local t = 0
  for _, k in ipairs(timeKeys) do
    local d = info[k] - lastInfo[k]
    s[k] = d
    t = t + d
  end
  return 100 - math.floor(1000 * s.idle / t) / 10
end

logger:info('self extension under '..extension:getDir():getPath())

local configuration = extension:getConfiguration()

-- activate the extension by default
if type(configuration.active) ~= 'boolean' then
  configuration.active = true
end


-- always register the single thing
local luaThing = Thing:new('Lua', 'Lua host engine', {'MultiLevelSensor'})
luaThing:addProperty('memory', {
  ['@type'] = 'LevelProperty',
  title = 'Lua Memory',
  type = 'integer',
  description = 'The total memory in use by Lua in bytes',
  minimum = 0,
  readOnly = true,
  unit = 'byte'
}, 0)
luaThing:addProperty('user', {
  ['@type'] = 'LevelProperty',
  title = 'Lua User Time',
  type = 'number',
  description = 'The amount in seconds of CPU time used by the program',
  minimum = 0,
  readOnly = true,
  unit = 'second'
}, 0)
luaThing:addProperty('process_resident_memory', {
  ['@type'] = 'LevelProperty',
  title = 'Resident Set Size',
  type = 'integer',
  description = 'The resident set size (RSS) for the current process.',
  minimum = 0,
  readOnly = true,
  unit = 'byte'
}, 0)
luaThing:addProperty('total_memory', {
  ['@type'] = 'LevelProperty',
  title = 'Total Memory',
  type = 'integer',
  description = 'The total memory available',
  minimum = 0,
  readOnly = true,
  unit = 'byte'
}, 0)
luaThing:addProperty('used_memory', {
  ['@type'] = 'LevelProperty',
  title = 'Used Memory',
  type = 'number',
  description = 'The memory used',
  minimum = 0,
  maximum = 100,
  readOnly = true,
  unit = 'percent'
}, 0)
luaThing:addProperty('host_cpu_usage', {
  ['@type'] = 'LevelProperty',
  title = 'CPU Usage',
  type = 'number',
  description = 'The CPU usage',
  minimum = 0,
  maximum = 100,
  readOnly = true,
  unit = 'percent'
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
  local thing = things['lua']
  if thing then
    luaThing = thing
    logger:info('lua self thing found')
    extension:cleanDiscoveredThings()
  end
end)

local lastClock = os.clock()
local lastInfo

extension:subscribeEvent('poll', function()
  logger:info('polling self extension')
  local clock = os.clock()
  luaThing:updatePropertyValue('memory', math.floor(collectgarbage('count') * 1024))
  luaThing:updatePropertyValue('user', math.floor((clock - lastClock) * 1000) / 1000)
  if luv then
    luaThing:updatePropertyValue('process_resident_memory', luv.resident_set_memory())
    local total_memory = luv.get_total_memory()
    luaThing:updatePropertyValue('total_memory', math.floor(total_memory))
    luaThing:updatePropertyValue('used_memory', math.floor(1000 - luv.get_free_memory() * 1000 / total_memory) / 10)
    local info = sumCpuInfo(luv.cpu_info())
    if lastInfo then
      luaThing:updatePropertyValue('host_cpu_usage', computeCpuUsage(lastInfo, info))
    end
    lastInfo = info
    --local rusage = getRUsage(luv.getrusage())
  end
  lastClock = clock
end)

local engine = extension:getEngine()
local reportFile = File:new(engine:getTemporaryDirectory(), 'memprof.csv')
if reportFile:exists() then
  local ts = Date.timestamp(Date.now(), true)
  local backupReportFile = File:new(engine:getTemporaryDirectory(), 'memprof.'..ts..'.csv')
  logger:info('Renaming memory report file "'..reportFile:getPath()..'" to "'..backupReportFile:getPath()..'"')
  reportFile:renameTo(backupReportFile)
end

extension:subscribeEvent('refresh', function()
  logger:info('refresh self extension')
  if configuration.memory.enabled then
    memprof.printReport(function(data)
      reportFile:write(data, true)
    end, false, false, configuration.memory.format)
  end
end)
