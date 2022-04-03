local File = require('jls.io.File')
local Date = require("jls.util.Date")
local tables = require("jls.util.tables")
local HistoricalTable = require('lha.HistoricalTable')
local json = require('jls.util.json')
local runtime = require('jls.lang.runtime')

local function usage(msg)
  if msg then
    print(msg)
  end
  print('try: -s source_dir [-sm] [-d dest_dir] [-m mapping_file]')
  runtime.exit(22)
end

local function stringify(t)
  return json.stringify(t, 2)
end

local HOUR_SEC = 3600
local DAY_SEC = 24 * HOUR_SEC
local WEEK_SEC = 7 * DAY_SEC
local time = Date.now()

local tArg = tables.createArgumentTable(arg, {keepComma = true})
--print(json.stringify(tArg, 2))

if tables.getArgument(tArg, '-h') or tables.getArgument(tArg, '--help') then
  usage()
end
local sourceDirname = tables.getArgument(tArg, '-s')
local pathPattern = tables.getArgument(tArg, '-pp')
local pathPatternExclude = tables.getArgument(tArg, '-ppe')
local destDirname = tables.getArgument(tArg, '-d')
local mappingFilename = tables.getArgument(tArg, '-m')
local htName = tables.getArgument(tArg, '-n', 'data')
local destName = tables.getArgument(tArg, '-dn', htName)
local fromSeconds = tonumber(tables.getArgument(tArg, '-fs', DAY_SEC * 2))
local toSeconds = tonumber(tables.getArgument(tArg, '-ts', HOUR_SEC * 2))
local all = tables.getArgument(tArg, '-fs') == nil
local fileMin = tonumber(tables.getArgument(tArg, '-fm', HistoricalTable.DEFAULT_FILE_MINUTES))
local periodSeconds = tonumber(tables.getArgument(tArg, '-ps', 60 * 10))
local showTables = tables.getArgument(tArg, '-st')
local showMapping = tables.getArgument(tArg, '-sm')
local showTimes = tables.getArgument(tArg, '-t')

local sourceDir = sourceDirname and File:new(sourceDirname)
local destDir = destDirname and File:new(destDirname)
local mappingFile = mappingFilename and File:new(mappingFilename)

if not (sourceDir and sourceDir:isDirectory()) then
  usage('Please specify a source directory')
end

local period = periodSeconds * 1000
local toTime = time + toSeconds * 1000
local fromTime = toTime - toSeconds * 1000

if all then
  toTime = time + WEEK_SEC * 1000
  fromTime = 0
end

print('from '..Date:new(fromTime):toISOString()..' to '..Date:new(toTime):toISOString())
print('fileMin:', fileMin, 'periodSeconds:', periodSeconds)

local htSource = HistoricalTable:new(sourceDir, htName, {fileMin = fileMin})

local htDest
if destDir and destDir:isDirectory() then
  htDest = HistoricalTable:new(destDir, destName, {fileMin = fileMin})
end

local mapping
if mappingFile and mappingFile:isFile() then
  local rawMap = json.decode(mappingFile:readAll())
  mapping = {}
  for srcPath, rawMt in pairs(rawMap) do
    local mt
    if type(rawMt) == 'string' then
      mt = {
        path = rawMt
      }
    elseif type(rawMt) == 'table' and type(rawMt.path) == 'string' then
      mt = {
        path = rawMt.path
      }
      if type(rawMt.adapt) == 'string' then
        local fn, err = load('local value, t = ...; '..rawMt.adapt)
        if fn then
          mt.adapt = fn
        else
          print('Error', err, 'while loading', rawMt.adapt)
          runtime.exit(1)
        end
      end
    end
    mapping[srcPath] = mt
  end
  print('mapping', stringify(rawMap))
end

--[[
print('files:')
htSource:forEachFile(fromTime, toTime, function(file)
  print(file:getPath())
  htSource:forEachTableInFile(file, fromTime, toTime, function(t, tTime)
    local date = Date:new(tTime)
    print(date:toISOString(), t)
    if htDest then
      htDest:setLiveTable(t)
      --htDest:save(isFull, withJson, time)
    end
  end)
end)
]]

local lastTable
local values = {}

print('processing tables')
htSource:forEachTable(fromTime, toTime, function(t, tTime, isFull)
  local date = Date:new(tTime)
  local keys = tables.keys(t)
  if showTimes then
    print(date:toISOString(), isFull, #keys)
  end
  if showTables then
    print(stringify(t))
  end
  if showMapping then
    values = tables.merge(values, tables.mapValuesByPath(t))
  end
  local dt = t
  if mapping then
    dt = {}
    for srcPath, mt in pairs(mapping) do
      local value = tables.getPath(t, srcPath)
      if value then
        if type(mt.adapt) == 'function' then
          value = mt.adapt(value, t, dt)
        end
        tables.setPath(dt, mt.path, value)
      end
    end
    if showTables then
      print('after mapping', stringify(dt))
    end
  end
  if htDest then
    htDest:setLiveTable(dt)
    htDest:save(isFull, tTime)
  end
  lastTable = dt
end)

if lastTable and not showTables then
  print('last table:')
  print(stringify(lastTable))
end

if showMapping then
  local identityMapping = {}
  local paths = tables.keys(values)
  table.sort(paths)
  for _, path in ipairs(paths) do
    if pathPattern then
      if string.find(path, pathPattern) then
        identityMapping[path] = path
      end
    elseif pathPatternExclude then
      if not string.find(path, pathPatternExclude) then
        identityMapping[path] = path
      end
    else
      identityMapping[path] = path
    end
  end
  print('identity mapping:')
  print(stringify(identityMapping))
end
