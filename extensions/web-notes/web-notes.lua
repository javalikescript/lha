local extension = ...

local logger = require('jls.lang.logger')
local File = require('jls.io.File')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')

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
  local engine = extension:getEngine()
  local server = engine:getHTTPServer()
  cleanup(server)
  local notesDir = File:new(engine:getWorkDirectory(), 'notes')
  if not notesDir:isDirectory() then
    if not notesDir:mkdir() then
      logger:warn('Unable to create the directory "'..notesDir:getPath()..'"')
    end
  end
  addContext(server, '/notes/(.*)', FileHttpHandler:new(notesDir, 'rwl'))
  engine:onExtension('web-base', function(webBaseExtension)
    webBaseExtension:registerAddonExtension(extension, true)
  end)
end)

extension:subscribeEvent('shutdown', function()
  local engine = extension:getEngine()
  local server = engine:getHTTPServer()
  engine:onExtension('web-base', function(webBaseExtension)
    webBaseExtension:unregisterAddonExtension(extension)
  end)
  cleanup(server)
end)
