local extension = ...

local Extension = require('lha.Extension')
local Thing = require('lha.Thing')
--local ThingProperty = require('lha.ThingProperty')
local logger = require('jls.lang.logger')
local loader = require('jls.lang.loader')
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

local function round(value, decimals)
  decimals = decimals or 10
  return mathRound(value * decimals) / decimals
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
  if t > 0 then
    return 100 - math.floor(1000 * s.idle / t) / 10
  end
  return 0
end

local function createLuaThing()
  local thing = Thing:new('Lua', 'Lua host engine', {'MultiLevelSensor'})
  thing:addProperty('memory', {
    ['@type'] = 'LevelProperty',
    title = 'Lua Memory',
    type = 'integer',
    description = 'The total memory in use by Lua in bytes',
    minimum = 0,
    readOnly = true,
    unit = 'byte'
  }, 0)
  thing:addProperty('user', {
    ['@type'] = 'LevelProperty',
    title = 'Lua User Time',
    type = 'number',
    description = 'The amount in seconds of CPU time used by the process',
    minimum = 0,
    readOnly = true,
    unit = 'second'
  }, 0)
  thing:addProperty('process_resident_memory', {
    ['@type'] = 'LevelProperty',
    title = 'Resident Set Size',
    type = 'integer',
    description = 'The resident set size (RSS) for the process.',
    minimum = 0,
    readOnly = true,
    unit = 'byte'
  }, 0)
  thing:addProperty('total_memory', {
    ['@type'] = 'LevelProperty',
    title = 'Total Memory',
    type = 'integer',
    description = 'The memory available for the host',
    minimum = 0,
    readOnly = true,
    unit = 'byte'
  }, 0)
  thing:addProperty('used_memory', {
    ['@type'] = 'LevelProperty',
    title = 'Used Memory',
    type = 'number',
    description = 'The memory used by the process',
    minimum = 0,
    maximum = 100,
    readOnly = true,
    unit = 'percent'
  }, 0)
  thing:addProperty('host_cpu_usage', {
    ['@type'] = 'LevelProperty',
    title = 'Host CPU Usage',
    type = 'number',
    description = 'The CPU usage for the host',
    minimum = 0,
    maximum = 100,
    readOnly = true,
    unit = 'percent'
  }, 0)
  thing:addProperty('process_cpu_usage', {
    ['@type'] = 'LevelProperty',
    title = 'Process CPU Usage',
    type = 'number',
    description = 'The CPU usage for the process',
    minimum = 0,
    maximum = 100,
    readOnly = true,
    unit = 'percent'
  }, 0)
  return thing
end

local function createThingsThing()
  local thing = Thing:new('Things', 'Things', {'MultiLevelSensor'})
  thing:addProperty('battery', {
    ['@type'] = 'LevelProperty',
    type = 'number',
    title = 'Min Battery Level',
    description = 'The minimum battery level in percent',
    readOnly = true,
    unit = 'percent'
  }, 0)
  thing:addProperty('lastseen', {
    ['@type'] = 'LevelProperty',
    type = 'number',
    title = 'Max Last Seen',
    description = 'The last seen max time in minutes',
    readOnly = true,
    unit = 'minute'
  }, 0)
  thing:addProperty('count', {
    ['@type'] = 'LevelProperty',
    type = 'number',
    title = 'Number of Things',
    description = 'The number of enabled things',
    readOnly = true
  }, 0)
  return thing
end

logger:info('self extension under '..extension:getDir():getPath())

local luaThing, thingsThing

--[[
curl http://localhost:8080/engine/admin/stop
curl http://localhost:8080/things
]]

local function refreshThings()
  local time = Date.now()
  local engine = extension:getEngine()
  local minBattery = 100
  local minLastseen = time
  local count = 0
  local value
  for thingId, thing in pairs(engine.things) do
    local extensionId, discoveryKey = engine:getThingDiscoveryKey(thingId)
    if extensionId ~= extension:getId() then
      local properties = thing:getProperties()
      for propertyName, property in pairs(properties) do
        count = count + 1
        if propertyName == 'battery' then
          value = property:getValue()
          if type(value) == 'number' and value < minBattery then
            minBattery = value
          end
        elseif propertyName == 'lastseen' then
          value = property:getValue()
          if type(value) == 'string' then
            value = Date.fromISOString(value)
            --logger:info('Thing '..thingId..' lastseen: '..tostring(value)..'/'..tostring(time))
            if value and value < minLastseen then
              minLastseen = value
            end
          end
        end
      end
    end
  end
  thingsThing:updatePropertyValue('battery', minBattery)
  value = 0
  if minLastseen < time then
    value = (time - minLastseen) // 60000
  end
  thingsThing:updatePropertyValue('lastseen', value)
  thingsThing:updatePropertyValue('count', count)
end

local lastClock = os.clock()
local lastTime = os.time()
local lastInfo = sumCpuInfo(luv.cpu_info())

local function refreshLua()
  luaThing:updatePropertyValue('memory', math.floor(collectgarbage('count') * 1024))
  local time = os.time()
  local clock = os.clock()
  if clock >= 0 then
    -- Win32: Given enough time, the value returned by clock can exceed the maximum positive value of clock_t.
    -- When the process has run longer, the value returned by clock is always (clock_t)(-1), about 24.8 days.
    local deltaClock = clock - lastClock
    if deltaClock >= 0 then
      luaThing:updatePropertyValue('user', round(deltaClock, 1000))
      local deltaTime = time - lastTime
      if deltaTime > 0 then
        luaThing:updatePropertyValue('process_cpu_usage', round(deltaClock * 100 / deltaTime))
      end
    end
  end
  if luv then
    luaThing:updatePropertyValue('process_resident_memory', luv.resident_set_memory())
    local total_memory = luv.get_total_memory()
    if total_memory > 0 then
      luaThing:updatePropertyValue('total_memory', math.floor(total_memory))
      luaThing:updatePropertyValue('used_memory', 100 - round(luv.get_free_memory() * 100 / total_memory))
    end
    local info = sumCpuInfo(luv.cpu_info())
    luaThing:updatePropertyValue('host_cpu_usage', computeCpuUsage(lastInfo, info))
    lastInfo = info
    --local rusage = getRUsage(luv.getrusage())
  end
  lastClock = clock
end

extension:subscribeEvent('things', function()
  logger:fine('Looking for self things')
  luaThing = extension:syncDiscoveredThingByKey('lua', createLuaThing)
  thingsThing = extension:syncDiscoveredThingByKey('things', createThingsThing)
  --logger:info('luaThing '..require('jls.util.json').encode(luaThing:asThingDescription()))
  refreshThings()
end)

extension:subscribeEvent('poll', function()
  logger:fine('Polling '..extension:getPrettyName()..' extension')
  refreshLua()
  refreshThings()
end)
