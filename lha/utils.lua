local logger = require('jls.lang.logger')
local runtime = require('jls.lang.runtime')
local File = require('jls.io.File')
local json = require('jls.util.json')

local utils = {}

function utils.createDirectoryOrExit(dir)
  if not dir:isDirectory() then
    if dir:mkdir() then
      logger:info('Created directory "'..dir:getPath()..'"')
    else
      logger:warn('Unable to create the directory "'..dir:getPath()..'"')
      runtime.exit(1)
    end
  end
end

function utils.checkDirectoryOrExit(dir)
  if not dir:isDirectory() then
    logger:warn('The directory "'..dir:getPath()..'" does not exist')
    runtime.exit(1)
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

return utils
