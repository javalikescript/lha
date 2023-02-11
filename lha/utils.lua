local logger = require('jls.lang.logger')
local system = require('jls.lang.system')
local File = require('jls.io.File')
local json = require('jls.util.json')
local Date = require('jls.util.Date')

local utils = {}

function utils.createDirectoryOrExit(dir)
  if not dir:isDirectory() then
    if dir:mkdir() then
      logger:info('Created directory "'..dir:getPath()..'"')
    else
      logger:warn('Unable to create the directory "'..dir:getPath()..'"')
      system.exit(1)
    end
  end
end

function utils.checkDirectoryOrExit(dir)
  if not dir:isDirectory() then
    logger:warn('The directory "'..dir:getPath()..'" does not exist')
    system.exit(1)
  end
end

function utils.getAbsoluteFile(path, dir)
  local file = File:new(path)
  if file:isAbsolute() then
    return file
  end
  if dir then
    return File:new(dir, path)
  end
  return file:getAbsoluteFile()
end

function utils.requireJson(name)
  local jsonpath = string.gsub(package.path, '%.lua', '.json')
  local path = assert(package.searchpath(name, jsonpath))
  local file = File:new(path)
  return json.decode(file:readAll())
end

function utils.removeEmptyPaths(t)
  local c = 0
  for k, v in pairs(t) do
    c = c + 1
    if type(v) == 'table' then
      if utils.removeEmptyPaths(v) == 0 then
        t[k] = nil
        c = c - 1
      end
    end
  end
  return c
end

utils.time = os.time

function utils.dateToString(date)
  return string.sub(date:toISOString(true), 1, 16)..'Z'
end

function utils.timeToString(time)
  if type(time) ~= 'number' then
    time = utils.time()
  end
  return utils.dateToString(Date:new(time * 1000))
end

function utils.dateFromString(value)
  return Date:new(Date.fromISOString(value))
end

function utils.timeFromString(value)
  return (Date.fromISOString(value) or 0) // 1000
end

function utils.hms(h, m, s)
  return (tonumber(h) or 0) + (tonumber(m) or 0) / 60 + (tonumber(s) or 0) / 3600
end

function utils.parseHms(value)
  return utils.hms(string.match(value, '(%d+):?(%d*):?(%d*)'))
end

function utils.timeToHms(value)
  return utils.parseHms(os.date('%H:%M:%S', value))
end

return utils
