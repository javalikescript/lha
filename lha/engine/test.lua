local logger = require('jls.lang.logger')
local File = require('jls.io.File')
local json = require('jls.util.json')
local runtime = require('jls.lang.runtime')
local system = require('jls.lang.system')
local Scheduler = require('jls.util.Scheduler')
local event = require('jls.lang.event')
local Engine = require('lha.engine.Engine')


local function toJson(value)
  if value == nil then
    return 'nil'
  end
  return json.encode(value)
end


-- compute root directory
local scriptFile = File:new(arg[0]):getAbsoluteFile()
local engineDir = scriptFile:getParentFile()
local rootDir = engineDir:getParentFile()
local workDir = rootDir
local pluginDir = rootDir

-- parse arguments
if arg[1] then
  workDir = File:new(arg[1]):getAbsoluteFile()
else
  logger:warn('please specify a working directory')
  runtime.exit(22)
end
if arg[2] then
  pluginDir = File:new(arg[2]):getAbsoluteFile()
else
  logger:warn('please specify a plugin directory')
  runtime.exit(22)
end

if not workDir:isDirectory() then
  logger:warn('invalid work directory '..workDir:getPath())
  runtime.exit(1)
end
logger:info('workDir is '..workDir:getPath())

-- load options
local optionsFile = File:new(workDir, engineDir:getName()..'.json')
logger:info('optionsFile is '..optionsFile:getPath())
if not optionsFile:isFile() then
  logger:info('configuration file is missing '..optionsFile:getPath())
  runtime.exit(22)
end
local options = json.decode(optionsFile:readAll())

local engine = Engine:new(workDir, options)

engine:load()
local plugin = engine:loadPlugin(pluginDir)

for i = 3, 100 do
  local action = arg[i]
  if not action then
    break
  end
  if action == 'poll' then
    engine:pollDevices()
  elseif action == 'sleep' then
    system.sleep(2000)
  elseif action == 'refresh' then
    engine:refreshPlugins()
  elseif action == 'print' then
    for _, device in ipairs(engine.devices) do
      print(device.id, toJson(device:getDeviceData()))
    end
  elseif action == 'printConfig' then
    print('config', toJson(plugin:getConfiguration()))
  elseif action == 'save' then
    engine.dataHistory:save(true)
  elseif action == 'saveConfig' then
    engine.configHistory:save(true, true)
  else
    print('Unknown action, skipping', action)
  end
end

logger:debug('starting event loop')
event:loop()

engine:stopPlugins()

event:close()
logger:debug('main ended')
