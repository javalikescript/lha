local extension = ...

local logger = require('jls.lang.logger')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local utils = require('lha.engine.utils')

local contexts = {}

local function cleanup(server)
  for _, context in ipairs(contexts) do
    server:removeContext(context)
  end
  contexts = {}
end

local function addContext(server, ...)
  local context = server:createContext(...)
  table.insert(contexts, context)
end

extension:subscribeEvent('startup', function()
  local configuration = extension:getConfiguration()
  local server = extension:getEngine():getHTTPServer()
  cleanup(server)
  if configuration.shares then
    for _, share in ipairs(configuration.shares) do
      local dir = utils.getAbsoluteFile(share.dir or 'share', extension:getDir())
      if dir:isDirectory() then
        logger:info('Using share directory "'..dir:getPath()..'"')
      else
        logger:warn('Invalid share directory "'..dir:getPath()..'"')
      end
      if share.name == 'engine' or share.name == 'things' then
        logger:warn('Invalid share name "'..share.name..'"')
      else
        addContext(server, '/'..share.name..'/(.*)', FileHttpHandler:new(dir, share.permissions))
      end
    end
  end
end)

extension:subscribeEvent('shutdown', function()
  local server = extension:getEngine():getHTTPServer()
  cleanup(server)
end)
