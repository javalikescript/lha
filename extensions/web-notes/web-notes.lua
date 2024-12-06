local extension = ...

local logger = extension:getLogger()
local File = require('jls.io.File')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local Url = require('jls.net.Url')

local webBaseAddons = extension:require('web-base.addons', true)

webBaseAddons.registerAddonExtension(extension)

local function checkDir(dir)
  if not dir:isDirectory() then
    if not dir:mkdir() then
      logger:warn('Unable to create the directory "%s"', dir)
    end
  end
  return dir
end

extension:subscribeEvent('startup', function()
  local engine = extension:getEngine()
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
  extension:addContext('/user%-notes/(.*)', handler)
end)
