local logger = require('jls.lang.logger')
local File = require('jls.io.File')
local json = require('jls.util.json')
local runtime = require('jls.lang.runtime')
local event = require('jls.lang.event')

local Engine = require('lha.engine.Engine')

local DEFAULT_CONFIG = {
  ["address"] = "::",
  ["port"] = 8080,
  ["-hostname"] = "localhost",
  ["-secure"] = {
    ["port"] = 8443,
    ["certificate"] = "cer.pem",
    ["key"] = "key.pem",
    ["credentials"] = {
      ["lha"] = "lha"
    }
  },
  ["-assets"] = "assets",
  ["-work"] = "work",
  ["heartbeat"] = 15000
}


local argFile = arg[1] and File:new(arg[1]):getAbsoluteFile()

if not (argFile and argFile:exists()) then
  logger:warn('Please specify a root directory or configuration file')
  runtime.exit(22)
end

local configFile, rootDir
if argFile:isDirectory() then
  configFile = File:new(argFile, 'engine.json')
  rootDir = argFile
elseif argFile:isFile() then
  configFile = argFile
  rootDir = argFile:getParentFile()
else
  logger:warn('Please specify an existing directory or configuration file')
  runtime.exit(1)
end

local scriptFile = File:new(arg[0]):getAbsoluteFile()
local engineDir = scriptFile:getParentFile()

logger:info('Root directory is "'..rootDir:getPath()..'"')
logger:info('Engine configuration file is "'..configFile:getPath()..'"')
logger:info('Engine directory is "'..engineDir:getPath()..'"')

if not configFile:isFile() then
  logger:info('Installing configuration file "'..configFile:getPath()..'"')
  configFile:write(json.encode(DEFAULT_CONFIG))
end
local status, options = pcall(json.decode, configFile:readAll())
if not status then
  logger:warn('Invalid configuration file "'..configFile:getPath()..'", error is '..tostring(options))
  runtime.exit(1)
end


local engine = Engine:new(engineDir, rootDir, options)
engine:start()

engine:publishEvent('poll')

logger:debug('starting event loop')

event:loop()

logger:debug('event loop ended')
logger:info('Engine stopped')
