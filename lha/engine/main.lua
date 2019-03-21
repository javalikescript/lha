::main::

local logger = require('jls.lang.logger')
local File = require('jls.io.File')
local json = require('jls.util.json')
local runtime = require('jls.lang.runtime')
local loader = require('jls.lang.loader')
local Scheduler = require('jls.util.Scheduler')
local event = require('jls.lang.event')

local Engine = require('lha.engine.Engine')

if not arg[1] then
  logger:warn('please specify a working directory')
  runtime.exit(22)
end

local jlsProf = os.getenv('JLS_PROFILE')
local lmprofLib
if jlsProf then
  lmprofLib = require('lmprof')
  lmprofLib.start(jlsProf);
  logger:info('Profiling started')
end

-- compute root directory
local scriptFile = File:new(arg[0]):getAbsoluteFile()
local engineDir = scriptFile:getParentFile()
local workDir = File:new(arg[1]):getAbsoluteFile()

if not workDir:isDirectory() then
  logger:warn('invalid work directory '..workDir:getPath())
  runtime.exit(1)
end
logger:info('engineDir is '..engineDir:getPath())
logger:info('workDir is '..workDir:getPath())

-- load options
local optionsName = engineDir:getName()..'.json'
local optionsFile = File:new(workDir, optionsName)
logger:info('optionsFile is '..optionsFile:getPath())
if not optionsFile:isFile() then
  local engineConfigFile = File:new(engineDir, optionsName)
  logger:info('configuration file is missing '..optionsFile:getPath()..' copying from '..engineConfigFile:getPath())
  engineConfigFile:copyTo(optionsFile)
end
local options = json.decode(optionsFile:readAll())

local engine = Engine:new(engineDir, workDir, options)
engine:start()

engine:publishEvent('poll')

logger:debug('starting event loop')
event:loop()
event:close()
logger:debug('event loop ended')

if jlsProf then
  lmprofLib.stop();
  logger:info('Profiling stopped')
end

if engine.restart == true then
  logger:info('Restarting...')
  loader.unloadAll('^lha%.')
  loader.unloadAll('^jls%.')
  goto main
end
