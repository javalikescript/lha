local lu = require('luaunit')

local File = require('jls.io.File')
local Date = require('jls.util.Date')
local tables = require('jls.util.tables')

local HistoricalTable = require('lha.HistoricalTable')

local TEST_PATH = 'tools'
local TMP_PATH = TEST_PATH..'/tmp'

local PERIOD = 15
local REF_TIME = Date.fromISOString('2022-04-01T10:00:00') // 1000

local function getTmpDir()
  local tmpDir = File:new(TMP_PATH)
  if tmpDir:isDirectory() then
    if not tmpDir:deleteRecursive() then
      error('Cannot delete tmp dir')
    end
  end
  return tmpDir
end

local function getEmptyTmpDir()
  local tmpDir = File:new(TMP_PATH)
  if tmpDir:isDirectory() then
    if not tmpDir:deleteAll() then
      error('Cannot delete tmp dir')
    end
  else
    if not tmpDir:mkdir() then
      error('Cannot create tmp dir')
    end
  end
  return tmpDir
end

local function applySamples(ht, samples, debug)
  local t = ht:getLiveTable()
  for _, sample in ipairs(samples) do
    if type(sample) == 'table' then
      for k, v in pairs(sample) do
        ht:aggregateValue(k, v)
      end
    elseif type(sample) == 'number' then
      if debug then
        print(tables.stringify(t, 2))
      end
      ht:save(false, nil, sample * 1000)
    end
  end
end

local function getValues(values, key)
  local l = {}
  for i, t in ipairs(values) do
    l[i] = t[key]
  end
  return l
end

local function loadValues(ht, startTime, endTime, period, path, debug)
  local values = ht:loadValues((startTime - 1) * 1000, (endTime + 1) * 1000, period * 1000, path)
  --print(tables.stringify(values, 2))
  if debug then
    print('values', startTime, endTime, period, table.concat(getValues(values, 'time'), ','))
  end
  --table.remove(values, 1)
  return values
end

function Test_aggregate_min_max()
  local period = PERIOD
  local time = REF_TIME
  local startTime = time
  local function nextTime()
    local t = time
    time = time + period
    return t
  end
  local samples = {
    {temperature = 19},
    nextTime(),
    {temperature = 19},
    nextTime(),
    {temperature = 19},
    {temperature = 19},
    nextTime(),
    {temperature = 19},
    {temperature = 20},
    nextTime(),
    {temperature = 20},
    {temperature = 18},
    nextTime(),
    {temperature = 18},
    {temperature = 21},
    {temperature = 18},
    nextTime(),
    {temperature = 18},
    nextTime(),
  }
  local endTime = time

  local values, value
  local tmpDir = getEmptyTmpDir()
  local ht = HistoricalTable:new(tmpDir, 'test')
  applySamples(ht, samples)
  values = loadValues(ht, startTime, endTime, period, 'temperature')
  lu.assertEquals(getValues(values, 'count'), {1, 1, 1, 1, 1, 1, 1})
  lu.assertEquals(getValues(values, 'min'), {19, 19, 19, 19, 18, 18, 18})
  lu.assertEquals(getValues(values, 'max'), {19, 19, 19, 20, 20, 21, 18})
  lu.assertEquals(getValues(values, 'average'), {19, 19, 19, 20, 18, 18, 18}) -- average is computed with the last period value
  values = loadValues(ht, startTime, endTime, endTime - startTime, 'temperature')
  lu.assertEquals(getValues(values, 'count'), {7})
  value = values[1]
  lu.assertAlmostEquals(value.average, 18.7, 0.1)
  lu.assertEquals(value.min, 18)
  lu.assertEquals(value.max, 21)
end

function Test_aggregate_changes()
  local period = PERIOD
  local time = REF_TIME
  local startTime = time
  local function nextTime()
    local t = time
    time = time + period
    return t
  end
  local samples = {
    {presence = false},
    nextTime(),
    {presence = false},
    nextTime(),
    {presence = false},
    {presence = false},
    nextTime(),
    {presence = false},
    {presence = true},
    nextTime(),
    {presence = true},
    {presence = false},
    nextTime(),
    {presence = false},
    {presence = true},
    {presence = false},
    nextTime(),
    {presence = false},
    nextTime(),
  }
  local endTime = time

  local values
  local tmpDir = getEmptyTmpDir()
  local ht = HistoricalTable:new(tmpDir, 'test')
  applySamples(ht, samples)
  values = loadValues(ht, startTime, endTime, period, 'presence')
  lu.assertEquals(getValues(values, 'changes'), {1, 0, 0, 1, 1, 2, 0})
  lu.assertEquals(getValues(values, 'count'), {1, 1, 1, 1, 1, 1, 1})
  values = loadValues(ht, startTime, endTime, endTime - startTime, 'presence')
  lu.assertEquals(getValues(values, 'changes'), {5})
  lu.assertEquals(getValues(values, 'count'), {7})
end

function Test_aggregate_clear()
  local samples = {
    {temperature = 19},
    {presence = false},
    {presence = true},
    {presence = false, temperature = 18},
    {temperature = 21},
    {temperature = 18},
  }
  local tmpDir = getEmptyTmpDir()
  local ht = HistoricalTable:new(tmpDir, 'test')
  applySamples(ht, samples)
  --print(tables.stringify(ht.liveTable, 2))
  lu.assertEquals(ht.liveTable, {
    presence = false,
    ["presence&changes"] = 3,
    temperature = 18,
    ["temperature&max"] = 21,
    ["temperature&min"] = 18,
  })
  ht:clearAggregation()
  --print(tables.stringify(ht.liveTable, 2))
  lu.assertEquals(ht.liveTable, {
    presence = false,
    temperature = 18,
  })

end

-- last test will cleanup the tmp dir
function Test_z_cleanup()
  local f = getTmpDir()
  lu.assertEquals(f:isDirectory(), false)
end

os.exit(lu.LuaUnit.run())
