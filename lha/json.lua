local File = require('jls.io.File')
local Date = require("jls.util.Date")
local tables = require("jls.util.tables")
local json = require('jls.util.json')
local runtime = require('jls.lang.runtime')

-- lua lha\engine\json.lua -f work\configuration\config.json -p "/things/(.*)/description/title"

local function usage(msg)
  if msg then
    print(msg)
  end
  print('try: -f filename')
  runtime.exit(22)
end

local tArg = tables.createArgumentTable(arg, {keepComma = true})

if tables.getArgument(tArg, '-h') or tables.getArgument(tArg, '--help') then
  usage()
end
local filename = tables.getArgument(tArg, '-f')
local filterPatterns = tables.getArguments(tArg, '-p')

local file = filename and File:new(filename)

if not (file and file:isFile()) then
  usage('Please specify a JSON file')
end

local t = json.decode(file:readAll())

local valuesByPath = tables.mapValuesByPath(t)

local paths = tables.keys(valuesByPath)
table.sort(paths)

local lastMatch
for _, path in ipairs(paths) do
  local value = valuesByPath[path]
  if #filterPatterns > 0 then
    for _, filterPattern in ipairs(filterPatterns) do
      local match, mm = string.match(path, filterPattern)
      if match then
        if match ~= lastMatch then
          lastMatch = match
          print(match, mm or value)
        else
          print('', mm or value)
        end
        break
      end
    end
  else
    print(path, value)
  end
end

