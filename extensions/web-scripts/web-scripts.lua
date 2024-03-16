local extension = ...

local logger = extension:getLogger()
local File = require('jls.io.File')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
local HttpExchange = require('jls.net.http.HttpExchange')
local json = require('jls.util.json')

local REST_SCRIPTS = {
  [''] = function(exchange)
    local request = exchange:getRequest()
    local method = string.upper(request:getMethod())
    local engine = exchange:getAttribute('engine')
    if method == HTTP_CONST.METHOD_GET then
      local list = {}
      for _, ext in ipairs(engine.extensions) do
        if ext:getType() == 'script' then
          --local scriptDir = File:new(engine.scriptsDir, ext:getId())
          local blocksFile = File:new(ext:getDir(), 'blocks.xml')
          local item = ext:toJSON()
          item.hasBlocks = blocksFile:isFile()
          table.insert(list, item)
        end
      end
      return list
    elseif method == HTTP_CONST.METHOD_PUT then
      if engine.scriptsDir:isDirectory() then
        local scriptId = engine:generateId()
        local scriptDir = File:new(engine.scriptsDir, scriptId)
        scriptDir:mkdir()
        local blocksFile = File:new(scriptDir, 'blocks.xml')
        local scriptFile = File:new(scriptDir, 'script.lua')
        local manifestFile = File:new(scriptDir, 'manifest.json')
        local manifest = {
          name = "New script",
          version = "1.0",
          script = scriptFile:getName()
        }
        blocksFile:write('<xml xmlns="http://www.w3.org/1999/xhtml"></xml>')
        scriptFile:write('local script = ...\n\n')
        manifestFile:write(json.stringify(manifest, 2))
        logger:fine('Created script "%s"', scriptId)
        engine:loadExtensionFromDirectory(scriptDir, 'script')
        return scriptId
      else
        logger:warn('Cannot create script')
      end
    else
      HttpExchange.methodNotAllowed(exchange)
      return false
    end
  end,
  ['{+}'] = function(exchange, name)
    local engine = exchange:getAttribute('engine')
    exchange:setAttribute('extension', engine:getExtensionById(name))
  end,
  ['{extensionId}'] = {
    [''] = function(exchange)
      local request = exchange:getRequest()
      local method = string.upper(request:getMethod())
      local engine = exchange:getAttribute('engine')
      local ext = exchange:getAttribute('extension')
      if method == HTTP_CONST.METHOD_DELETE and ext:getType() == 'script' then
        local extensionDir = ext:getDir()
        if ext:isActive() then
          ext:publishEvent('shutdown')
        end
        engine:removeExtension(ext)
        extensionDir:deleteRecursive()
      else
        HttpExchange.methodNotAllowed(exchange)
        return false
      end
    end,
    reload = function(exchange)
      exchange.attributes.extension:restartExtension()
    end,
    ['name?method=PUT'] = function(exchange)
      local name = exchange:getRequest():getBody()
      local ext = exchange:getAttribute('extension')
      local extensionDir = ext:getDir()
      local manifestFile = File:new(extensionDir, 'manifest.json')
      --local manifest = json.decode(manifestFile:readAll())
      ext.manifest.name = name
      manifestFile:write(json.stringify(ext.manifest, 2))
      return 'Renamed'
    end
  },
}

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
  -- TODO Move to extension handler
  addContext(server, '/engine/scripts/(.*)', RestHttpHandler:new(REST_SCRIPTS, {engine = engine}))
  addContext(server, '/engine/scriptFiles/(.*)', FileHttpHandler:new(engine:getScriptsDirectory(), 'rw'))
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
