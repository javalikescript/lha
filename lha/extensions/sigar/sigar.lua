local extension = ...

local logger = require('jls.lang.logger')
local Sigar = require('jls.util.Sigar')
local Thing = require('lha.engine.Thing')

logger:info('sigar extension under '..extension:getDir():getPath())

--local configuration = extension:getConfiguration()

-- always register the single thing
local sigarThing = Thing:new('Sigar', 'Sigar Monitoring', {'MultiLevelSensor'}):addProperty('total_memory', {
  ['@type'] = 'LevelProperty',
  title = 'Total Memory',
  type = 'integer',
  description = 'The total memory available',
  minimum = 0,
  readOnly = true,
  unit = 'byte'
}, 0):addProperty('used_memory', {
  ['@type'] = 'LevelProperty',
  title = 'Used Memory',
  type = 'number',
  description = 'The memory used',
  minimum = 0,
  maximum = 100,
  readOnly = true,
  unit = 'percent'
}, 0):addProperty('host_cpu_usage', {
  ['@type'] = 'LevelProperty',
  title = 'CPU Usage',
  type = 'number',
  description = 'The CPU usage',
  minimum = 0,
  maximum = 100,
  readOnly = true,
  unit = 'percent'
}, 0):addProperty('process_resident_memory', {
  ['@type'] = 'LevelProperty',
  title = 'Resident Memory',
  type = 'integer',
  description = 'The process resident memory',
  minimum = 0,
  readOnly = true,
  unit = 'byte'
}, 0):addProperty('process_cpu_usage', {
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
extension:discoverThing('sigar', sigarThing)

extension:subscribeEvent('things', function()
  logger:info('looking for sigar things')
  local things = extension:getThings()
  if things['sigar'] then
    sigarThing = things['sigar']
    logger:info('sigar thing found')
    extension:cleanDiscoveredThings()
  end
end)

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

local previousProcessInfo
local previousProcessorInfo

extension:subscribeEvent('poll', function()
  logger:info('polling sigar extension')
  local sigar = Sigar:new()
  local processorInfo = sigar:getProcessorInfo()
  local memInfo = sigar:getMemoryInfo()
  local processInfo = sigar:getProcessInfo(pid)
  sigarThing:updatePropertyValue('total_memory', memInfo:getTotalSize())
  sigarThing:updatePropertyValue('used_memory', toPercent(memInfo:getUsedPercent()))
  sigarThing:updatePropertyValue('process_resident_memory', processInfo:getMemoryResident())
  if processorInfo and previousProcessorInfo then
    local deltaProcessorInfo = processorInfo:newDelta(previousProcessorInfo)
    sigarThing:updatePropertyValue('host_cpu_usage', toPercent(deltaProcessorInfo:getUsagePercent()))
  end
  previousProcessorInfo = processorInfo
  if processInfo and previousProcessInfo then
    local deltaProcessInfo = processInfo:newDelta(previousProcessInfo)
    sigarThing:updatePropertyValue('process_cpu_usage', toPercent(deltaProcessInfo:getUsagePercent()))
  end
  previousProcessInfo = processInfo
end)

extension:subscribeEvent('refresh', function()
  logger:info('refresh sigar extension')
end)
