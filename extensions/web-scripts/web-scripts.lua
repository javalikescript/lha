local extension = ...

local logger = extension:getLogger()
local File = require('jls.io.File')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
local HttpExchange = require('jls.net.http.HttpExchange')
local json = require('jls.util.json')

local webBaseAddons = extension:require('web-base.addons', true)

webBaseAddons.registerAddonExtension(extension)

local REST_SCRIPTS = {
  ['(engine)?method=GET'] = function(exchange, engine)
    local list = {}
    for _, ext in ipairs(engine.extensions) do
      if ext:getType() == 'script' then
        local item = ext:toJSON()
        item.hasBlocks = File:new(ext:getDir(), 'blocks.xml'):isFile()
        item.hasView = File:new(ext:getDir(), 'view.xml'):isFile()
        table.insert(list, item)
      end
    end
    return list
  end,
  ['(engine)?method=PUT'] = function(exchange, engine)
    local dir = engine:getScriptsDirectory()
    local scriptName = 'script.lua'
    local extId = engine:generateId()
    local extDir = File:new(dir, extId)
    extDir:mkdir()
    local scriptFile = File:new(extDir, scriptName)
    scriptFile:write('local script = ...\n\n')
    local manifestFile = File:new(extDir, 'manifest.json')
    local manifest = {
      name = 'New script',
      version = '1.0',
      script = scriptName
    }
    manifestFile:write(json.stringify(manifest, 2))
    logger:fine('Created script "%s"', extId)
    engine:loadExtensionFromDirectory(extDir, 'script')
    return extId
  end,
  ['{+}(engine)'] = function(exchange, name, engine)
    local ext = engine:getExtensionById(name)
    if ext:getType() ~= 'script' then
      HttpExchange.notFound(exchange)
      return false
    end
    exchange:setAttribute('extension', ext)
  end,
  ['{extensionId}'] = {
    ['(engine, extension)?method=DELETE'] = function(exchange, engine, ext)
      local extensionDir = ext:getDir()
      if ext:isActive() then
        ext:publishEvent('shutdown')
      end
      ext:cleanExtension()
      engine:removeExtension(ext)
      extensionDir:deleteRecursive()
    end,
    ['reload(extension)'] = function(exchange, ext)
      ext:restartExtension()
    end,
    ['name(extension)?method=PUT'] = function(exchange, ext)
      local name = exchange:getRequest():getBody()
      local extensionDir = ext:getDir()
      local manifestFile = File:new(extensionDir, 'manifest.json')
      ext.manifest.name = name
      manifestFile:write(json.stringify(ext.manifest, 2))
      return 'Renamed'
    end
  },
}

extension:subscribeEvent('startup', function()
  local engine = extension:getEngine()
  extension:addContext('/engine/scripts/(.*)', RestHttpHandler:new(REST_SCRIPTS, {engine = engine}))
  extension:addContext('/engine/scriptFiles/(.*)', FileHttpHandler:new(engine:getScriptsDirectory(), 'rw'))
end)
