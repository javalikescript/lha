local logger = require('jls.lang.logger')
local File = require('jls.io.File')
local Date = require("jls.util.Date")
local tables = require("jls.util.tables")
local HistoricalTable = require('lha.engine.HistoricalTable')

local function usage(msg)
  if msg then
    print(msg)
  end
  print('try: something else')
  runtime.exit(22)
end

-- parse arguments
local argt = tables.createArgumentTable(arg)

if tables.getArgument(argt, '-h') then
  usage()
end
local HOUR_SEC = 3600
local DAY_SEC = 24 * HOUR_SEC
local WEEK_SEC = 7 * DAY_SEC
local dirname = 'lha_work'
local period = 60 * 10
local path = 'device/self_memory/memory'
local toTime = Date.now() + HOUR_SEC * 2 * 1000
local fromTime = toTime - DAY_SEC * 2 * 1000

if period then
  period = period * 1000
else
  period = HOUR_SEC * 1000
end

local dir = File:new(dirname)
local dataDir = File:new(dir, 'data')

print('from '..Date:new(fromTime):toISOString()..' to '..Date:new(toTime):toISOString())

local dataHistory = HistoricalTable:new(dataDir, 'data')
--dataHistory:loadLatest()

print('tables:')
dataHistory:forEachTable(0, toTime, function(t, tTime)
  if tTime >= fromTime then
    local date = Date:new(tTime)
    print(date:toISOString())
  end
end)

print('values, period is '..tostring(period // 1000)..':')
local values = dataHistory:loadValues(fromTime, toTime, period, path)
for _, value in ipairs(values) do
  local time = value.time * 1000
  local date = Date:new(time)
  print(date:toISOString()..' count: '..tostring(value.count))
end
