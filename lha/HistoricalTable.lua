local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local File = require('jls.io.File')
local FileDescriptor = require('jls.io.FileDescriptor')
local json = require('jls.util.json')
local tables = require('jls.util.tables')
local Date = require('jls.util.Date')
local Deflater = require('jls.util.zip.Deflater')
local Inflater = require('jls.util.zip.Inflater')

local SUFFIX_SEPARATOR = '&'
local CHANGES_SUFFIX = SUFFIX_SEPARATOR..'changes'
local MIN_SUFFIX = SUFFIX_SEPARATOR..'min'
local MAX_SUFFIX = SUFFIX_SEPARATOR..'max'

local function computeChanges(t, key)
  local fullKey = key..CHANGES_SUFFIX
  local previousValue = t[fullKey]
  if previousValue then
    t[fullKey] = previousValue + 1
  else
    t[fullKey] = 1
  end
end

local function computeMin(t, key, value)
  local fullKey = key..MIN_SUFFIX
  local previousValue = t[fullKey]
  if not previousValue or value < previousValue then
    t[fullKey] = value
  end
end

local function computeMax(t, key, value)
  local fullKey = key..MAX_SUFFIX
  local previousValue = t[fullKey]
  if not previousValue or value > previousValue then
    t[fullKey] = value
  end
end

local function hasSuffix(key)
  return (string.find(key, SUFFIX_SEPARATOR, 2, true))
end

local function removeTableKeys(t, fn)
  for key, value in pairs(t) do
    if type(value) == 'table' then
      removeTableKeys(value, fn)
    elseif fn(key) then
      t[key] = nil
    end
  end
  return t
end

-- The value aggregator enables to aggregate values,
-- slice aggregated values on specified time then
-- finish the aggregation by enriching the first value
local ValueAggregator = class.create(function(valueAggregator)

  local NO_VALUE = {}

  function valueAggregator:initialize()
    self.lastValue = NO_VALUE
    self:clear()
  end

  function valueAggregator:clear()
    self.changes = 0
    self.count = 0
  end

  -- Copies the specified aggregation into this aggregation
  function valueAggregator:copy(va)
    self.changes = va.changes
    self.count = va.count
    self.lastValue = va.lastValue
    return self
  end

  -- Aggregates the value
  function valueAggregator:aggregate(value, t, k)
    if value ~= nil then
      self.count = self.count + 1
    end
    local changes = t[k..CHANGES_SUFFIX]
    if changes then
      self.changes = self.changes + changes
    elseif self.lastValue ~= value then
      self.changes = self.changes + 1
    end
    self.lastValue = value
  end

  -- Computes the aggregated value into the specified map
  function valueAggregator:compute(t)
    t.count = self.count
  end

  -- Inserts the computed aggregated value at the specified time as a map in the specified list
  function valueAggregator:slice(values, time)
    local t = {
      time = time // 1000
    }
    self:compute(t)
    table.insert(values, t)
    self:clear()
  end

  -- Ends the aggregation and enriches the specified value
  function valueAggregator:finish(value)
    value.type = 'none'
  end

  -- Ends the aggregation and enriches the specified values
  function valueAggregator:finishAll(values)
    if #values > 0 then
      self:finish(values[1])
    end
  end

end)

local NumberAggregator = class.create(ValueAggregator, function(numberAggregator, super)

  function numberAggregator:clear()
    super.clear(self)
    self.total = 0
    self.totalCount = 0
    self.min = nil
    self.max = nil
  end

  function numberAggregator:aggregate(value, t, k)
    super.aggregate(self, value, t, k)
    if type(value) == 'number' then
      local min = t[k..MIN_SUFFIX] or value
      local max = t[k..MAX_SUFFIX] or value
      self.total = self.total + value
      self.totalCount = self.totalCount + 1
      if not self.min or min < self.min then
        self.min = min
      end
      if not self.max or max > self.max then
        self.max = max
      end
    end
  end

  function numberAggregator:compute(t)
    super.compute(self, t)
    if self.totalCount > 0 then
      t.average = self.total / self.totalCount
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

  function stringAggregator:aggregate(value, t, k)
    super.aggregate(self, value, t, k)
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
  end

  function stringAggregator:finish(value)
    value.type = 'string'
    value.map = {}
    for k, v in pairs(self.map) do
      value.map[v] = k
    end
  end

end)

local function guessAggregatorClass(valueType, default)
  if valueType == 'number' then
    return NumberAggregator
  elseif valueType == 'boolean' then
    return BooleanAggregator
  elseif valueType == 'string' then
    return StringAggregator
  elseif valueType == 'integer' then
    return NumberAggregator
  end
  return default or ValueAggregator
end

local AnyValueAggregator = class.create(function(anyValueAggregator)

  function anyValueAggregator:initialize()
    self.va = ValueAggregator:new()
    self.vac = nil
  end

  function anyValueAggregator:aggregate(value, t, k)
    if value ~=nil and not self.vac then
      self.vac = guessAggregatorClass(type(value), ValueAggregator)
      self.va = self.vac:new():copy(self.va)
    end
    self.va:aggregate(value, t, k)
  end

  function anyValueAggregator:slice(values, time)
    self.va:slice(values, time)
  end

  function anyValueAggregator:finishAll(values)
    self.va:finishAll(values)
  end

end)


local DEFAULT_FILE_MINUTES = 10080 -- one week

return class.create(function(historicalTable)

  local HEADER_FORMAT = '>BI4I4' -- c3

  function historicalTable:initialize(dir, name, options)
    options = options or {}
    self.dir = dir
    self.name = name
    self.liveTable = options.table or {}
    self.previousTable = tables.deepCopy(self.liveTable)
    self:setUtc(options.utc)
    self:setFileMinutes(options.fileMin)
    self.file = nil
    self.time = nil
  end

  function historicalTable:isUtc()
    return self.utc
  end

  function historicalTable:setUtc(value)
    self.utc = value == true
  end

  function historicalTable:getFileMinutes()
    return self.fileMin
  end

  function historicalTable:setFileMinutes(fileMin)
    self.fileMin = fileMin or DEFAULT_FILE_MINUTES
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

  function historicalTable:aggregateValue(path, value)
    local prev, t, key = tables.setPath(self.liveTable, path, value)
    if value ~= nil and value ~= prev then
      if type(value) == 'number' then
        if prev ~= nil then
          computeMin(t, key, math.min(prev, value))
          computeMax(t, key, math.max(prev, value))
        end
      else
        computeChanges(t, key)
      end
      if logger:isLoggable(logger.INFO) then
        logger:info('historicalTable:aggregateValue("'..path..'", '..tostring(value)..') '..json.stringify(t, 2))
      end
    end
    return prev
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
    local t, time, err
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
      local kind, size
      kind, time, size = string.unpack(HEADER_FORMAT, header, 4)
      local isFull = (kind & 1) == 1
      local isDeflated = (kind & 2) == 2
      time = time * 1000
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
    return t, time
  end

  function historicalTable:removeJson()
    local jsonFile = self:getJsonFile()
    if jsonFile:isFile() then
      jsonFile:delete()
    end
  end

  function historicalTable:loadJson(remove)
    local jsonFile = self:getJsonFile()
    if jsonFile:isFile() then
      self.liveTable = json.decode(jsonFile:readAll())
      if remove then
        jsonFile:delete()
      end
    end
  end

  function historicalTable:loadLatest()
    self:selectLatestFile()
    local t
    if self.file and self.file:isFile() then
      t = self:forEachTableInFile(self.file, 0, Date.now())
    end
    self.liveTable = t or {}
    self:rollover()
    self:loadJson(true)
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

  function historicalTable:loadValues(fromTime, toTime, period, path, valueType)
    if logger:isLoggable(logger.FINE) then
      logger:fine('historicalTable:loadValues('..tostring(fromTime)..', '..tostring(toTime)..', '..tostring(period)..', "'..tostring(path)..'")')
    end
    local values = {}
    local AggregatorClass = guessAggregatorClass(valueType, AnyValueAggregator)
    local periodAggregator = AggregatorClass:new()
    self:forEachPeriod(fromTime, toTime, period, function(time)
      periodAggregator:slice(values, time)
    end, function(t)
      local value, tk, pk = tables.getPath(t, path)
      periodAggregator:aggregate(value, tk, pk)
    end)
    periodAggregator:finishAll(values)
    return values
  end

  function historicalTable:loadMultiValues(fromTime, toTime, period, paths, types)
    if logger:isLoggable(logger.FINE) then
      logger:fine('historicalTable:loadMultiValues('..tostring(fromTime)..', '..tostring(toTime)..', '..tostring(period)..', "'..tostring(#paths)..'")')
    end
    types = types or {}
    local count = #paths
    local pathsValues = {}
    local pathsAggregator = {}
    for i = 1, count do
      pathsValues[i] = {}
      local AggregatorClass = guessAggregatorClass(types[i], AnyValueAggregator)
      pathsAggregator[i] = AggregatorClass:new()
    end
    self:forEachPeriod(fromTime, toTime, period, function(time)
      for i = 1, count do
        pathsAggregator[i]:slice(pathsValues[i], time)
      end
    end, function(t)
      for i = 1, count do
        local value, tk, pk = tables.getPath(t, paths[i])
        pathsAggregator[i]:aggregate(value, tk, pk)
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

  function historicalTable:saveJson(t)
    local tt = t or tables.deepCopy(self.liveTable)
    local jsonFile = self:getJsonFile()
    jsonFile:write(json.stringify(tt, 2))
    return tt
  end

  function historicalTable:clearAggregation()
    removeTableKeys(self.liveTable, hasSuffix)
  end

  function historicalTable:rollover()
    local currentTable, previousTable
    previousTable = self.previousTable
    currentTable = tables.deepCopy(self.liveTable)
    self:clearAggregation()
    self.previousTable = currentTable
    return currentTable, previousTable
  end

  function historicalTable:save(isFull, time)
    if logger:isLoggable(logger.FINE) then
      logger:fine('historicalTable:save() '..self.name)
    end
    if not time then
      time = Date.now()
    end
    local file, isNew = self:getFileAt(time)
    local currentTable, previousTable = self:rollover()
    local kind, size, data
    if isFull or isNew then
      kind = 1
      data = json.encode(currentTable)
      size = #data
    else
      kind = 0
      local dt = tables.compare(previousTable, currentTable)
      size = 0
      if dt then
        data = json.encode(dt)
        size = #data
      end
    end
    if size > 8 then
      local deflater = Deflater:new()
      data = deflater:deflate(data, 'finish')
      size = #data
      kind = kind | 2
    end
    local header = 'LHA'..string.pack(HEADER_FORMAT, kind, time // 1000, size)
    local fd, err = FileDescriptor.openSync(file, 'a')
    if fd then
      fd:writeSync(header)
      if data then
        fd:writeSync(data)
      end
      fd:closeSync()
    else
      logger:warn('historicalTable:save() Cannot append file '..file:getPath()..' due to '..tostring(err))
    end
  end

end, function(HistoricalTable)

  HistoricalTable.DEFAULT_FILE_MINUTES = DEFAULT_FILE_MINUTES
  HistoricalTable.SUFFIX_SEPARATOR = SUFFIX_SEPARATOR
  HistoricalTable.CHANGES_SUFFIX = CHANGES_SUFFIX
  HistoricalTable.MIN_SUFFIX = MIN_SUFFIX
  HistoricalTable.MAX_SUFFIX = MAX_SUFFIX

  HistoricalTable.ValueAggregator = ValueAggregator
  HistoricalTable.BooleanAggregator = BooleanAggregator
  HistoricalTable.NumberAggregator = NumberAggregator
  HistoricalTable.StringAggregator = StringAggregator
  HistoricalTable.AnyValueAggregator = AnyValueAggregator

  HistoricalTable.computeChanges = computeChanges
  HistoricalTable.computeMin = computeMin
  HistoricalTable.computeMax = computeMax

end)