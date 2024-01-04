local system = require('jls.lang.system')
local logger = require('jls.lang.logger')
local File = require('jls.io.File')
local Date = require('jls.util.Date')
local Map = require('jls.util.Map')
local List = require('jls.util.List')
local tables = require('jls.util.tables')
local json = require('jls.util.json')

local HistoricalTable = require('lha.HistoricalTable')

local function stringify(t)
  return json.stringify(t, 2)
end

local HOUR_SEC = 3600
local DAY_SEC = 24 * HOUR_SEC
local WEEK_SEC = 7 * DAY_SEC

local options = tables.createArgumentTable(arg, {
  aliases = {
    h = 'help',
    a = 'action',
    s = 'source',
    t = 'target',
    m = 'mapping',
    pp = 'path.pattern',
    ppe = 'path.patternExclude',
    sa = 'show.tables',
    sm = 'show.mapping',
    st = 'show.times',
    sl = 'show.last',
    ll = 'log-level',
  },
  helpPath = 'help',
  schema = {
    title = 'Historical Table Utility',
    type = 'object',
    additionalProperties = false,
    properties = {
      help = {
        title = 'Show the help',
        type = 'boolean',
        default = false
      },
      action = {
        title = 'The action',
        type = 'string',
        default = 'none',
        enum = {'files'}
      },
      source = {
        title = 'The table source directory',
        type = 'string',
        default = 'work'
      },
      target = {
        title = 'The table target directory',
        type = 'string'
      },
      mapping = {
        title = 'The table mapping file',
        type = 'string',
        default = 'mapping.json'
      },
      name = {
        title = 'The table name',
        type = 'string',
        default = 'data'
      },
      from = {
        title = 'Seconds from time',
        type = 'integer',
        default = DAY_SEC * 2
      },
      to = {
        title = 'Seconds to time',
        type = 'integer',
        default = HOUR_SEC * 2
      },
      all = {
        title = 'All time',
        type = 'boolean',
        default = false
      },
      path = {
        type = 'object',
        additionalProperties = false,
        properties = {
          pattern = {
            title = 'The path pattern',
            type = 'string'
          },
          patternExclude = {
            title = 'The path pattern',
            type = 'string'
          },
        }
      },
      show = {
        type = 'object',
        additionalProperties = false,
        properties = {
          times = {
            title = 'Show times',
            type = 'boolean',
            default = false
          },
          tables = {
            title = 'Show tables',
            type = 'boolean',
            default = false
          },
          mapping = {
            title = 'Show mapping',
            type = 'boolean',
            default = false
          },
          last = {
            title = 'Show last table',
            type = 'boolean',
            default = false
          },
        }
      },
      ['log-level'] = {
        title = 'The log level',
        type = 'string',
        default = 'warn',
        enum = {'error', 'warn', 'info', 'config', 'fine', 'finer', 'finest', 'debug', 'all'}
      },
    }
  }
})

logger:setLevel(options['log-level'])

local sourceDir = options.source and File:new(options.source)
local destDir = options.target and File:new(options.target)
local mappingFile = options.mapping and File:new(options.mapping)
local pathPattern = options.path.pattern
local pathPatternExclude = options.path.patternExclude
local showTimes = options.show.times
local showTables = options.show.tables
local showMapping = options.show.mapping

-- 10080 -- one week -- 43200 -- 4 weeks
local fileMin = HistoricalTable.DEFAULT_FILE_MINUTES
local time = Date.now()

if not sourceDir:isDirectory() then
  print('Please specify a valid source directory')
  system.exit(22)
end

local toTime = time + options.to * 1000
local fromTime = toTime - options.from * 1000

if options.all then
  toTime = time + WEEK_SEC * 1000
  fromTime = 0
end

print('from '..Date:new(fromTime):toISOString()..' to '..Date:new(toTime):toISOString())
print('fileMin:', fileMin)

local htSource = HistoricalTable:new(sourceDir, options.name, {fileMin = fileMin})

local htDest
if destDir then
  if destDir:isDirectory() then
    htDest = HistoricalTable:new(destDir, options.name, {fileMin = fileMin})
  else
    print('Please specify a valid target directory')
    system.exit(22)
  end
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
          system.exit(1)
        end
      end
    end
    mapping[srcPath] = mt
  end
  print('mapping', stringify(rawMap))
end

if options.action == 'files' then
  print('files:')
  htSource:forEachFile(fromTime, toTime, function(file)
    print(file:getPath())
    htSource:forEachTableInFile(file, fromTime, toTime, function(t, tTime)
      local date = Date:new(tTime)
      print(date:toISOString(), t)
      if false and htDest then
        htDest:setLiveTable(t)
        --htDest:save(isFull, nil, time)
      end
    end)
  end)
  system.exit(0)
end

local lastTable
local values = {}

print('processing tables...')
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
    htDest:save(isFull, nil, tTime)
  end
  lastTable = dt
end)

if lastTable and options.show.last then
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
