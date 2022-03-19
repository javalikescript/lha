local extension = ...

local logger = require('jls.lang.logger')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local utils = require('lha.engine.utils')

local context

local function cleanup(server)
  if context then
    server:removeContext(context)
    context = nil
  end
end

extension:subscribeEvent('startup', function()
  local configuration = extension:getConfiguration()
  local server = extension:getEngine():getHTTPServer()
  cleanup(server)
  local dir = utils.getAbsoluteFile(configuration.dir or 'share', extension:getDir())
  if dir:isDirectory() then
    logger:info('Using share directory "'..dir:getPath()..'"')
  else
    logger:warn('Invalid share directory "'..dir:getPath()..'"')
  end
  if configuration.name == 'engine' or configuration.name == 'things' then
    logger:warn('Invalid share name "'..configuration.name..'"')
  else
    context = server:createContext('/'..configuration.name..'/(.*)', FileHttpHandler:new(dir, configuration.permissions))
  end
end)

extension:subscribeEvent('shutdown', function()
  local server = extension:getEngine():getHTTPServer()
  cleanup(server)
end)
