local extension = ...

local logger = extension:getLogger()
local File = require('jls.io.File')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
local HttpExchange = require('jls.net.http.HttpExchange')
local json = require('jls.util.json')
local Date = require('jls.util.Date')
local ZipFile = require('jls.util.zip.ZipFile')

local webBaseAddons = extension:require('web-base.addons', true)

webBaseAddons.register(extension)

local function deployScript(exchange, engine, extId)
  local zipName = exchange:getRequest():getBody() or 'lha-ext.zip'
  local backup = File:new(engine:getTemporaryDirectory(), zipName)
  if not backup:isFile() then
    HttpExchange.notFound(exchange)
    return false
  end
  local extDir = File:new(engine:getScriptsDirectory(), extId)
  if extDir:exists() or not extDir:mkdir() then
    HttpExchange.internalServerError(exchange)
    return false
  end
  if not ZipFile.unzipTo(backup, extDir) then
    extDir:deleteRecursive()
    HttpExchange.badRequest(exchange)
    return false
  end
  logger:fine('Deployed script "%s"', extId)
  engine:loadExtensionFromDirectory(extDir, 'script')
  return extId
end

local REST_SCRIPTS = {
  ['(engine)?method=GET'] = function(_, engine)
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
    local name = exchange:getRequest():getBody()
    if not name or name == '' then
      name = 'New script'
    end
    local scriptName = 'script.lua'
    local extId = engine:generateId()
    local extDir = File:new(engine:getScriptsDirectory(), extId)
    extDir:mkdir()
    local scriptFile = File:new(extDir, scriptName)
    scriptFile:write('local script = ...\n\n')
    local manifestFile = File:new(extDir, 'manifest.json')
    local manifest = {
      name = name,
      version = '1.0',
      script = scriptName
    }
    manifestFile:write(json.stringify(manifest, 2))
    logger:fine('Created script "%s"', extId)
    engine:loadExtensionFromDirectory(extDir, 'script')
    return extId
  end,
  ['(engine)?method=POST'] = function(exchange, engine)
    return deployScript(exchange, engine, engine:generateId())
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
    ['(engine, extension)?method=DELETE'] = function(_, engine, ext)
      local extensionDir = ext:getDir()
      if ext:isActive() then
        ext:publishEvent('shutdown')
      end
      ext:cleanExtension()
      engine:removeExtension(ext)
      extensionDir:deleteRecursive()
    end,
    ['deploy(engine, extensionId)?method=PUT'] = function(exchange, engine, extId)
      return deployScript(exchange, engine, extId)
    end,
    ['export(engine, extension)'] = function(_, engine, ext)
      local backup = File:new(engine:getTemporaryDirectory(), 'lha-ext-'..ext:getId()..'.'..Date.timestamp()..'.zip')
      return ZipFile.zipToAsync(backup, ext:getDir():listFiles()):next(function()
        return backup:getName()
      end)
    end,
    ['reload(extension)'] = function(_, ext)
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
