local plugin = ...

local logger = require('jls.lang.logger')
local http = require('jls.net.http')
local httpHandler = require('jls.net.http.handler')
local File = require('jls.io.File')
local json = require("jls.util.json")

plugin.addons = {}

local configuration = plugin:getConfiguration()

if type(configuration.active) ~= 'boolean' then
  configuration.active = true
end

function plugin:registerAddon(name, handler, attributes, path)
  if not path then
    path = '(.*)'
  end
  self.addons[name] = http.Context:new(handler, '/addon/'..name..'/'..path, attributes)
  --server:createContext('/addon/'..name..'/'..path, handler, attributes)
  logger:info('add-on '..name..' registered')
end

function plugin:registerAddonPlugin(plugin)
  self:registerAddon(plugin:getId(), httpHandler.files, {rootFile = plugin:getDir()})
end

function plugin:unregisterAddon(name)
  self.addons[name] = nil
  --server:removeContext(self.addons[name])
  logger:info('add-on '..name..' unregistered')
end

plugin:subscribeEvent('startup', function()
  logger:info('startup web plugin')

  local engine = plugin:getEngine()
  local server = engine:getHTTPServer()
  local lhaDir = engine.dir:getParentFile()
  local topDir = lhaDir:getParentFile()

  plugin.appContext = server:createContext('/(.*)', httpHandler.file, {
    defaultFile = 'app.html',
    rootFile = File:new(plugin:getDir(), 'www')
  })

  plugin.baseContext = server:createContext('/static/(.*)', httpHandler.file, {
    rootFile = File:new(topDir, 'lha_assets/www_static')
  })

  plugin.addonContext = server:createContext('/addon/([^/]*)/?(.*)', function(exchange)
    local name, path = exchange:getRequestArguments()
    logger:fine('add-on handler "'..tostring(name)..'" / "'..tostring(path)..'"')
    if name == '' then
      local names = {}
      for name, addon in pairs(plugin.addons) do
        table.insert(names, name)
      end
      httpHandler.ok(exchange, json.encode(names), 'application/json')
    else
      local addon = plugin.addons[name]
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

plugin:subscribeEvent('shutdown', function()
  logger:info('shutdown web plugin')
  local server = plugin:getEngine():getHTTPServer()
  server:removeContext(plugin.appContext)
  server:removeContext(plugin.baseContext)
  server:removeContext(plugin.addonContext)
  plugin.addons = {}
end)
