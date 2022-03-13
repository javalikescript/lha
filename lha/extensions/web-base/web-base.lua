local extension = ...

-- -config.extensions.web-base.assets ../../../assets/www_static/

local logger = require('jls.lang.logger')
local File = require('jls.io.File')
local json = require("jls.util.json")
local HttpExchange = require('jls.net.http.HttpExchange')
local HttpHandler = require('jls.net.http.HttpHandler')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local ZipFileHttpHandler = require('jls.net.http.handler.ZipFileHttpHandler')
local HttpContext = require('jls.net.http.HttpContext')
local utils = require('lha.engine.utils')

local AddonFileHttpHandler = require('jls.lang.class').create(FileHttpHandler, function(fileHttpHandler)

  function fileHttpHandler:getPath(httpExchange)
    return select(2, httpExchange:getRequestArguments())
  end

end)

extension.addons = {}

function extension:registerAddon(name, handler)
  self.addons[name] = handler
  logger:info('add-on '..name..' registered')
end

function extension:registerAddonExtension(ext)
  self:registerAddon(ext:getId(), AddonFileHttpHandler:new(ext:getDir()))
end

function extension:unregisterAddon(name)
  self.addons[name] = nil
  --server:removeContext(self.addons[name])
  logger:info('add-on '..name..' unregistered')
end

extension:subscribeEvent('startup', function()
  logger:info('startup web extension')

  local engine = extension:getEngine()
  local configuration = extension:getConfiguration()
  local assets = utils.getAbsoluteFile(configuration.assets or 'assets', extension:getDir())
  local assetsHandler
  if assets:isDirectory() then
    logger:info('Using assets directory "'..assets:getPath()..'"')
    assetsHandler = FileHttpHandler:new(assets)
  elseif assets:isFile() and string.find(assets:getPathName(), '%.zip$') then
    logger:info('Using assets file "'..assets:getPath()..'"')
    assetsHandler = ZipFileHttpHandler:new(assets)
  else
    assetsHandler = HttpContext.notFoundHandler
    logger:warn('Invalid assets directory "'..assets:getPath()..'"')
  end
  local wwwDir = File:new(extension:getDir(), 'www')

  local server = engine:getHTTPServer()
  extension.appContext = server:createContext('/(.*)', FileHttpHandler:new(wwwDir, 'r', 'app.html'))
  extension.baseContext = server:createContext('/static/(.*)', assetsHandler)
  extension.addonContext = server:createContext('/addon/([^/]*)/?(.*)', HttpHandler:new(function(self, exchange)
    local name, path = exchange:getRequestArguments()
    logger:fine('add-on handler "'..tostring(name)..'" / "'..tostring(path)..'"')
    if name == '' then
      local names = {}
      for n in pairs(extension.addons) do
        table.insert(names, n)
      end
      HttpExchange.ok(exchange, json.encode(names), 'application/json')
    else
      local addon = extension.addons[name]
      if addon then
        logger:fine('calling add-on "'..tostring(name)..'" handler')
        return addon:handle(exchange)
      end
      HttpExchange.notFound(exchange)
    end
  end))

end)

extension:subscribeEvent('shutdown', function()
  logger:info('shutdown web base extension')
  local server = extension:getEngine():getHTTPServer()
  server:removeContext(extension.appContext)
  server:removeContext(extension.baseContext)
  server:removeContext(extension.addonContext)
  extension.addons = {}
end)
