local extension = ...

local logger = require('jls.lang.logger')
local http = require('jls.net.http')
local httpHandler = require('jls.net.http.handler')
local File = require('jls.io.File')
local json = require("jls.util.json")

extension.addons = {}

local configuration = extension:getConfiguration()

-- activate the extension by default
if type(configuration.active) ~= 'boolean' then
  configuration.active = true
end

function extension:registerAddon(name, handler, attributes, path)
  if not path then
    path = '(.*)'
  end
  self.addons[name] = http.Context:new(handler, '/addon/'..name..'/'..path, attributes)
  --server:createContext('/addon/'..name..'/'..path, handler, attributes)
  logger:info('add-on '..name..' registered')
end

function extension:registerAddonExtension(extension)
  self:registerAddon(extension:getId(), httpHandler.files, {rootFile = extension:getDir()})
end

function extension:unregisterAddon(name)
  self.addons[name] = nil
  --server:removeContext(self.addons[name])
  logger:info('add-on '..name..' unregistered')
end

extension:subscribeEvent('startup', function()
  logger:info('startup web extension')

  local engine = extension:getEngine()
  local server = engine:getHTTPServer()
  local assetsDir = engine:getAssetsDir()
  logger:info('using assetsDir "'..assetsDir:getPath()..'"')

  extension.appContext = server:createContext('/(.*)', httpHandler.file, {
    defaultFile = 'app.html',
    rootFile = File:new(extension:getDir(), 'www')
  })

  extension.baseContext = server:createContext('/static/(.*)', httpHandler.file, {
    rootFile = File:new(assetsDir, 'www_static')
  })

  extension.addonContext = server:createContext('/addon/([^/]*)/?(.*)', function(exchange)
    local name, path = exchange:getRequestArguments()
    logger:fine('add-on handler "'..tostring(name)..'" / "'..tostring(path)..'"')
    if name == '' then
      local names = {}
      for name, addon in pairs(extension.addons) do
        table.insert(names, name)
      end
      httpHandler.ok(exchange, json.encode(names), 'application/json')
    else
      local addon = extension.addons[name]
      if addon then
        exchange:setContext(addon)
        local handler = addon:getHandler()
        logger:fine('calling add-on "'..tostring(name)..'" handler')
        return handler(exchange)
      else
        httpHandler.notFound(exchange)
      end
    end
  end)

end)

extension:subscribeEvent('shutdown', function()
  logger:info('shutdown web base extension')
  local server = extension:getEngine():getHTTPServer()
  server:removeContext(extension.appContext)
  server:removeContext(extension.baseContext)
  server:removeContext(extension.addonContext)
  extension.addons = {}
end)
