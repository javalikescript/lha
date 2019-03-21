local plugin = ...

local logger = require('jls.lang.logger')
local Sigar = require('jls.util.Sigar')
local tables = require('jls.util.tables')

logger:info('sigar plugin under '..plugin:getDir():getPath())

local configuration = plugin:getConfiguration()

tables.merge(configuration, {
  report_file_systems = false
}, true)

local hostDevice = plugin:registerDevice('host')
local processDevice = plugin:registerDevice('process')

local previousProcessInfo
local previousProcessorInfo

local function formatPath(path)
  path = string.gsub(path, '^[/\\]+', '')
  path = string.gsub(path, '[/\\:]+$', '')
  path = string.gsub(path, '[/\\]+', '-')
  path = string.gsub(path, '[^%w]+', '_')
  if path == '' then
    return 'root'
  end
  return path
end

hostDevice:subscribeEvent('poll', function()
  logger:info('poll sigar host device')
  local sigar = Sigar:new()
  local processorInfo = sigar:getProcessorInfo()
  local memInfo = sigar:getMemoryInfo()
  local data = {
    memory = {
      total = memInfo:getTotalSize(),
      used_percent = memInfo:getUsedPercent()
    }
  }
  if configuration.report_file_systems then
    local fsInfos = sigar:getFileSystemInfos()
    local fileSystem = {}
    for _, fsInfo in ipairs(fsInfos) do
      local path = formatPath(fsInfo:getName())
      fileSystem[path] = {
        usage = fsInfo:getUsagePercent()
      }
    end
    data.file_system = fileSystem
  end
  if processorInfo and previousProcessorInfo then
    local deltaProcessorInfo = processorInfo:newDelta(previousProcessorInfo)
    data.cpu_usage = deltaProcessorInfo:getUsagePercent()
  end
  hostDevice:setDeviceData(data)
  previousProcessorInfo = processorInfo
end)

processDevice:subscribeEvent('poll', function()
  logger:info('poll sigar process device')
  local sigar = Sigar:new()
  local processInfo = sigar:getProcessInfo(pid)
  local data = {
    memory = {
      --lua = math.floor(collectgarbage('count') * 1024)
      resident = processInfo:getMemoryResident()
    }
  }
  if processInfo and previousProcessInfo then
    local deltaProcessInfo = processInfo:newDelta(previousProcessInfo)
    data.cpu_usage = deltaProcessInfo:getUsagePercent()
  end
  processDevice:setDeviceData(data)
  previousProcessInfo = processInfo
end)

plugin:subscribeEvent('refresh', function()
  logger:info('refresh sigar plugin')
end)

