local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local File = require('jls.io.File')
local FileDescriptor = require('jls.io.FileDescriptor')
local json = require('jls.util.json')
local tables = require('jls.util.tables')
local integers = require('jls.util.integers')
local Date = require('jls.util.Date')
local Deflater = require('jls.util.zip.Deflater')
local Inflater = require('jls.util.zip.Inflater')

local NO_VALUE = {}

-- The value aggregator enables to aggregate values,
-- slice aggregated values on specified time then
-- finish the aggregation by enriching the first value
local ValueAggregator = class.create(function(valueAggregator)

  function valueAggregator:initialize()
    self:clear()
    self.lastValue = NO_VALUE
  end

  function valueAggregator:clear()
    self.changes = 0
    self.count = 0
  end

  function valueAggregator:copy(va)
    self.changes = va.changes
    self.count = va.count
    return self
  end

  function valueAggregator:aggregate(value)
    if value ~= nil then
      self.count = self.count + 1
    end
    if self.lastValue ~= value then
      self.changes = self.changes + 1
    end
    self.lastValue = value
  end

  function valueAggregator:compute(t)
    t.count = self.count
  end

  -- Insert the computed aggregated value in the specified table
  function valueAggregator:slice(values, time)
    local t = {
      time = time // 1000
    }
    self:compute(t)
    table.insert(values, t)
    self:clear()
  end
  
  function valueAggregator:finish(value)
    value.type = 'none'
  end

end)

local NumberAggregator = class.create(ValueAggregator, function(numberAggregator, super)

  function numberAggregator:clear()
    super.clear(self)
    self.total = 0
    self.min = nil
    self.max = nil
  end

  function numberAggregator:aggregate(value)
    super.aggregate(self, value)
    if type(value) == 'number' then
      self.total = self.total + value
      if not self.min or value < self.min then
        self.min = value
      end
      if not self.max or value > self.max then
        self.max = value
      end
    end
  end

  function numberAggregator:compute(t)
    super.compute(self, t)
    if self.count > 0 then
      t.average = self.total / self.count
    end
    t.min = self.min
    t.max = self.max
  end

  function numberAggregator:finish(value)
    value.type = 'number'
  end

end)

local BooleanAggregator = class.create(ValueAggregator, function(booleanAggregator, super)

  local BOOLEAN_VALUE_MAP = {
    [false] = 1,
    [true] = 2
  }
  
  function booleanAggregator:compute(t)
    super.compute(self, t)
    t.changes = self.changes
    t.index = BOOLEAN_VALUE_MAP[self.lastValue]
    --t.value = self.lastValue
  end

  function booleanAggregator:finish(value)
    value.type = 'boolean'
    value.map = {false, true}
  end

end)

local StringAggregator = class.create(ValueAggregator, function(stringAggregator, super)

  function stringAggregator:initialize()
    super.initialize(self)
    self.map = {}
    self.mapCount = 0
  end
  
  function stringAggregator:aggregate(value)
    super.aggregate(self, value)
    if type(value) == 'string' then
      if not self.map[value] and self.mapCount < 100 then
        self.mapCount = self.mapCount + 1
        self.map[value] = self.mapCount
      end
    end
  end

  function stringAggregator:compute(t)
    super.compute(self, t)
    t.changes = self.changes
    t.index = self.map[self.lastValue]
    --t.value = self.lastValue
  end

  function stringAggregator:finish(value)
    value.type = 'string'
    value.map = {}
    --for i = 1, self.mapCount do
    --  value.map[i]
    --end
    for k, v in pairs(self.map) do
      value.map[v] = k
    end
  end

end)

local function guessAggregatorClass(value)
  local tv = type(value)
  if tv == 'number' then
    return NumberAggregator
  elseif tv == 'boolean' then
    return BooleanAggregator
  elseif tv == 'string' then
    return StringAggregator
  end
  return ValueAggregator
end

local AnyValueAggregator = class.create(function(anyValueAggregator)

  local copy = ValueAggregator.prototype.copy

  function anyValueAggregator:initialize()
    self.va = ValueAggregator:new()
    self.vac = nil
  end

  function anyValueAggregator:aggregate(value)
    if value ~=nil and not self.vac then
      self.vac = guessAggregatorClass(value)
      self.va = copy(self.vac:new(), self.va)
    end
    self.va:aggregate(value)
  end

  function anyValueAggregator:slice(values, time)
    self.va:slice(values, time)
  end
  
  function anyValueAggregator:finishAll(values)
    if #values > 0 then
      self.va:finish(values[1])
    end
  end

end)


return class.create(function(historicalTable, _, HistoricalTable)

  HistoricalTable.DEFAULT_FILE_MINUTES = 10080 -- one week

  function historicalTable:initialize(dir, name, fileMin, t)
    self.dir = dir
    self.name = name
    self.liveTable = t or {}
    self.previousTable = tables.deepCopy(self.liveTable)
    self.utc = true
    self:setFileMinutes(fileMin)
    --self.file = nil
    --self.time = nil
  end

  function historicalTable:getFileMinutes()
    return self.fileMin
  end

  function historicalTable:setFileMinutes(fileMin)
    self.fileMin = fileMin or HistoricalTable.DEFAULT_FILE_MINUTES
  end

  function historicalTable:getLiveTable()
    return self.liveTable
  end

  function historicalTable:setLiveTable(t)
    self.liveTable = t
    return self
  end

  function historicalTable:getJsonFile()
    return File:new(self.dir, self.name..'.json')
  end

  function historicalTable:getFileName(ts)
    return self.name..'_'..ts..'.log'
  end

  function historicalTable:getFilePattern()
    return '^'..self:getFileName('(%d+)')..'$'
  end

  function historicalTable:selectLatestFile()
    local filePattern = self:getFilePattern()
    local filenames = self.dir:list()
    table.sort(filenames)
    self.file = nil
    self.time = nil
    local li = #filenames
    while li > 0 do
      local filename = filenames[li]
      local ts = string.match(filename, filePattern)
      if ts then
        local time = Date.fromTimestamp(ts, self.utc)
        if time then
          self.time = time
          self.file = File:new(self.dir, filename)
          break
        end
      end
      li = li - 1
    end
  end

  function historicalTable:forEachTableInFile(file, fromTime, toTime, fn)
    if logger:isLoggable(logger.FINE) then
      logger:fine('historicalTable:forEachTableInFile('..file:getPath()..', '..tostring(fromTime)..', '..tostring(toTime)..'")')
    end
    -- file format is: kind, time, data size, data content
    local fd = FileDescriptor.openSync(file)
    local offset = 0
    local t, err
    while true do
      local header = fd:readSync(12, offset)
      if not header or #header == 0 then
        break
      end
      if #header ~= 12 then
        err = 'Invalid file at offset '..tostring(offset)..', bad header'
        break
      end
      offset = offset + 12
      local kind = string.byte(header, 4)
      local isFull = (kind & 1) == 1
      local isDeflated = (kind & 2) == 2
      local time = integers.be.toUInt32(string.sub(header, 5)) * 1000
      local size = integers.be.toUInt32(string.sub(header, 9))
      if time > toTime then
        break
      end
      if size > 0 then
        local data = fd:readSync(size, offset)
        if not data or #data ~= size then
          err = 'Invalid file at offset '..tostring(offset)..', bad data'
          break
        end
        offset = offset + size
        if isDeflated then
          local inflater = Inflater:new()
          data = inflater:inflate(data)
        end
        if isFull then
          t = json.decode(data)
        elseif t then
          local dt = json.decode(data)
          t = tables.patch(t, dt)
        end
      end
      if fn and t and time >= fromTime then
        fn(t, time, isFull)
      end
    end
    fd:closeSync()
    if err then
      logger:warn('historicalTable:forEachTableInFile('..file:getPath()..') '..err)
      return nil, err
    end
    return t
  end

  function historicalTable:loadLatest()
    local t
    self:selectLatestFile()
    local jsonFile = self:getJsonFile()
    if jsonFile:isFile() then
      t = json.decode(jsonFile:readAll())
    else
      if self.file and self.file:isFile() then
        t = self:forEachTableInFile(self.file, 0, Date.now())
      end
    end
    self.liveTable = t or {}
    self.previousTable = tables.deepCopy(self.liveTable)
  end

  function historicalTable:forEachFile(fromTime, toTime, fn)
    if logger:isLoggable(logger.FINE) then
      logger:fine('historicalTable:forEachFile('..tostring(fromTime)..', '..tostring(toTime)..'")')
    end
    local filePattern = self:getFilePattern()
    local filenames = self.dir:list()
    table.sort(filenames)
    local previousFilename
    for _, filename in ipairs(filenames) do
      local ts = string.match(filename, filePattern)
      if ts then
        local time = Date.fromTimestamp(ts, self.utc)
        if time then
          if logger:isLoggable(logger.FINEST) then
            logger:finest('historicalTable:forEachFile('..tostring(fromTime)..', '..tostring(toTime)..'") '..filename..': '..tostring(time))
          end
          if time > toTime then
            break
          end
          if time >= fromTime then
            if previousFilename and time > fromTime then
              fn(File:new(self.dir, previousFilename))
              previousFilename = nil
            end
            fn(File:new(self.dir, filename))
          else
            previousFilename = filename
          end
        end
      end
    end
    if previousFilename then
      fn(File:new(self.dir, previousFilename))
    end
  end

  function historicalTable:forEachTable(fromTime, toTime, fn)
    self:forEachFile(fromTime, toTime, function(file)
      self:forEachTableInFile(file, fromTime, toTime, fn)
    end)
  end

  function historicalTable:getTableAt(time)
    local result = nil
    self:forEachTable(time, time + 3600000, function(t, tTime)
      if result == nil then
        result = t
      end
    end)
    return result
  end

  function historicalTable:forEachPeriod(fromTime, toTime, period, periodFn, tableFn)
    if logger:isLoggable(logger.FINE) then
      logger:fine('historicalTable:forEachPeriod('..tostring(fromTime)..', '..tostring(toTime)..', '..tostring(period)..')')
    end
    if fromTime >= toTime or not period or period <= 0 then
      return
    end
    local periodEndTime = fromTime + period
    self:forEachTable(fromTime, toTime, function(t, tTime)
      -- close periods and fill blanks
      while tTime > periodEndTime do
        periodFn(periodEndTime)
        periodEndTime = periodEndTime + period
      end
      tableFn(t)
    end)
    -- close periods and fill blanks
    while periodEndTime <= toTime do
      periodFn(periodEndTime)
      periodEndTime = periodEndTime + period
    end
  end

  function historicalTable:loadValues(fromTime, toTime, period, path)
    if logger:isLoggable(logger.FINE) then
      logger:fine('historicalTable:loadValues('..tostring(fromTime)..', '..tostring(toTime)..', '..tostring(period)..', "'..tostring(path)..'")')
    end
    local values = {}
    local periodAggregator = AnyValueAggregator:new()
    self:forEachPeriod(fromTime, toTime, period, function(time)
      periodAggregator:slice(values, time)
    end, function(t)
      local value = tables.getPath(t, path)
      periodAggregator:aggregate(value)
    end)
    periodAggregator:finishAll(values)
    return values
  end

  function historicalTable:loadMultiValues(fromTime, toTime, period, paths)
    if logger:isLoggable(logger.FINE) then
      logger:fine('historicalTable:loadMultiValues('..tostring(fromTime)..', '..tostring(toTime)..', '..tostring(period)..', "'..tostring(#paths)..'")')
    end
    local count = #paths
    local pathsValues = {}
    local pathsAggregator = {}
    for i = 1, count do
      pathsValues[i] = {}
      pathsAggregator[i] = AnyValueAggregator:new()
    end
    self:forEachPeriod(fromTime, toTime, period, function(time)
      for i = 1, count do
        pathsAggregator[i]:slice(pathsValues[i], time)
      end
    end, function(t)
      for i = 1, count do
        local value = tables.getPath(t, paths[i])
        pathsAggregator[i]:aggregate(value)
      end
    end)
    for i = 1, count do
      pathsAggregator[i]:finishAll(pathsValues[i])
    end
    return pathsValues
  end

  function historicalTable:getFileAt(time)
    if self.time and time > (self.time + (self.fileMin * 60000)) then
      self.file = nil
    end
    if not self.file then
      self.time = time
      local ts = Date.timestamp(self.time, self.utc)
      self.file = File:new(self.dir, self:getFileName(ts))
      return self.file, true
    end
    return self.file, false
  end

  function historicalTable:hasJsonFile()
    return self:getJsonFile():isFile()
  end

  function historicalTable:saveJson()
    local t = tables.deepCopy(self.liveTable)
    local jsonFile = self:getJsonFile()
    jsonFile:write(json.encode(t))
  end

  function historicalTable:save(isFull, withJson, time)
    if logger:isLoggable(logger.FINE) then
      logger:fine('historicalTable:save() '..self.name)
    end
    if not time then
      time = Date.now()
    end
    local file, isNew = self:getFileAt(time)
    local tmp = tables.deepCopy(self.liveTable)
    local kind, size, data
    if isFull or isNew then
      kind = 1
      data = json.encode(tmp)
      size = #data
    else
      kind = 0
      local dt = tables.compare(self.previousTable, tmp)
      size = 0
      if dt then
        data = json.encode(dt)
        size = #data
      end
    end
    if withJson then
      -- TODO format
      local jsonFile = self:getJsonFile()
      if (kind & 1) == 1 then
        jsonFile:write(data)
      elseif size > 0 then
        jsonFile:write(json.encode(tmp))
      end
    end
    if size > 8 then
      local deflater = Deflater:new()
      data = deflater:deflate(data, 'finish')
      size = #data
      kind = kind | 2
    end
    local header = 'LHA'..string.char(kind)..integers.be.fromUInt32(time // 1000)..integers.be.fromUInt32(size)
    local fd, err = FileDescriptor.openSync(file, 'a')
    -- fd may be null
    -- 2018-10-28T09:50:11 90 Scheduled failed due to "./lha/engine/HistoricalTable.lua:282: attempt to index a nil value (local 'fd')"
    if fd then
      fd:writeSync(header)
      if data then
        fd:writeSync(data)
      end
      fd:closeSync()
      self.previousTable = tmp
    else
      logger:warn('historicalTable:save() Cannot append file '..file:getPath()..' due to '..tostring(err))
    end
  end

end)