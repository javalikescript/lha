local extension = ...

local logger = extension:getLogger()
local File = require('jls.io.File')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local Url = require('jls.net.Url')

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

local function checkDir(dir)
  if not dir:isDirectory() then
    if not dir:mkdir() then
      logger:warn('Unable to create the directory "'..dir:getPath()..'"')
    end
  end
  return dir
end

extension:subscribeEvent('startup', function()
  local engine = extension:getEngine()
  local server = engine:getHTTPServer()
  cleanup(server)
  local notesDir = File:new(engine:getWorkDirectory(), 'notes')
  local handler = FileHttpHandler:new(checkDir(notesDir), 'rwl')
  function handler:findFile(exchange, path)
    local session = exchange:getSession()
    local userDir = self.rootFile
    if session and session.attributes.user then
      local dirName = Url.encodePercent(session.attributes.user.name)
      userDir = checkDir(File:new(userDir, dirName))
    end
    return File:new(userDir, path)
  end
  addContext(server, '/user%-notes/(.*)', handler)
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
