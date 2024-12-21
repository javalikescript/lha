local extension = ...

local logger = extension:getLogger()
local File = require('jls.io.File')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local Url = require('jls.net.Url')

local webBaseAddons = extension:require('web-base.addons', true)

webBaseAddons.registerAddonExtension(extension)

local function checkDir(dir)
  if not dir:isDirectory() then
    if dir:mkdir() then
      logger:info('Created directory "%s"', dir)
    else
      logger:warn('Unable to create the directory "%s"', dir)
    end
  end
  return dir
end

extension:subscribeEvent('startup', function()
  local engine = extension:getEngine()
  local notesDir = checkDir(File:new(engine:getWorkDirectory(), 'notes'))
  local sharedNotesDir = checkDir(File:new(notesDir, '_shared'))
  local handler = FileHttpHandler:new(notesDir, 'rwl')
  local lastUserName
  function handler:findFile(exchange, path)
    local session = exchange:getSession()
    local userDir = sharedNotesDir
    if session and session.attributes.user then
      local userName = session.attributes.user.name
      local dirName = Url.encodePercent(userName)
      userDir = File:new(self.rootFile, dirName)
      if userName ~= lastUserName then
        lastUserName = userName
        checkDir(userDir)
      end
    end
    logger:finer('file is "%s" / "%s"', userDir, path)
    return File:new(userDir, path)
  end
  extension:addContext('/user%-notes/(.*)', FileHttpHandler:new(sharedNotesDir, 'rwl'))
  extension:addContext('/user%-notes/me/(.*)', handler)
end)
