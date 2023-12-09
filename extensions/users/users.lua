local extension = ...

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local form = require('jls.net.http.form')
local HttpExchange = require('jls.net.http.HttpExchange')
local HttpFilter = require('jls.net.http.HttpFilter')
local MessageDigest = require('jls.util.MessageDigest')
local Codec = require('jls.util.Codec')

local User = class.create(function(user)
  function user:initialize(configuration)
    self.name = configuration.name
    self.password = configuration.password
    self.permission = configuration.permission
  end
  function user:checkPassword(password)
    return self.password and password == self.password
  end
end)

local contexts, filter, base64, md, userMap

local function cleanup(server)
  if contexts then
    for _, context in ipairs(contexts) do
      server:removeContext(context)
    end
  end
  contexts = {}
  if filter then
    server:removeFilter(filter)
    filter = nil
  end
  userMap = {}
  base64 = Codec.getInstance('base64')
  md = MessageDigest.getInstance('SHA-1')
end

local function addContext(server, ...)
  local context = server:createContext(...)
  table.insert(contexts, context)
end

local function encrypt(value)
  if string.byte(value, 1, 1) == 9 then
    return value
  end
  md:reset()
  md:update(value)
  return '\t'..base64:encode(md:digest())
end

local function refreshUsers(users)
  if users then
    for _, user in ipairs(users) do
      user.password = encrypt(user.password)
      userMap[user.name] = User:new(user)
    end
  end
end

local sessionFilter

extension:subscribeEvent('startup', function()
  local configuration = extension:getConfiguration()
  local engine = extension:getEngine()
  local server = engine:getHTTPServer()
  if sessionFilter then
    sessionFilter:close()
  end
  sessionFilter = HttpFilter.session(configuration.maxAge, configuration.idleTimeout)
  cleanup(server)
  refreshUsers(configuration.users)
  function sessionFilter:onCreated(session)
    session.attributes.user = nil
    session.attributes.permission = configuration.defaultPermission or ''
  end
  addContext(server, '/logout', function(exchange)
    if HttpExchange.methodAllowed(exchange, 'POST') then
      sessionFilter:onCreated(exchange:getSession())
      HttpExchange.redirect(exchange, '/')
    end
  end)
  addContext(server, '/login', function(exchange)
    if not HttpExchange.methodAllowed(exchange, 'POST') then
      return
    end
    local info = form.parseFormUrlEncoded(exchange:getRequest())
    if info and info.name and info.password then
      local user = userMap[info.name]
      if user and user:checkPassword(encrypt(info.password)) then
        local session = exchange:getSession()
        session.attributes.user = user
        if user.permission then
          session.attributes.permission = user.permission
        end
        HttpExchange.redirect(exchange, '/')
        return
      else
        logger:warn('user "%s" from %s is not authorized', info.name, exchange:clientAsString())
      end
      HttpExchange.forbidden(exchange)
    else
      HttpExchange.badRequest(exchange)
    end
  end)
  local userFilter = HttpFilter:new(function(_, exchange)
    local request = exchange:getRequest()
    local method = request:getMethod()
    if method == 'GET' or method == 'HEAD' then
      return
    end
    local path = request:getTargetPath()
    local session = exchange:getSession()
    local permission = session.attributes.permission
    if string.match(path, '^/things') then
      if permission > 'r' then
        return
      end
    elseif string.match(path, '^/engine/admin/') then
      if permission > 'rwc' then
        return
      end
    elseif permission > 'rw' or path == '/login' or path == '/logout' or string.match(path, '^/user') then
      return
    end
    HttpExchange.forbidden(exchange)
    return false
  end)
  local filters = HttpFilter.multiple(sessionFilter, userFilter)
  if configuration.login then
    local redirect = extension:require('users.login-redirect', true)
    filters:addFilter(redirect)
  end
  filter = HttpFilter.byPath(filters):exclude('^/static')
  server:addFilter(filter)
  engine:onExtension('web-base', function(webBaseExtension)
    webBaseExtension:registerAddonExtension(extension, 'user.js')
  end)
end)

extension:subscribeEvent('poll', function()
  if sessionFilter then
    sessionFilter:cleanup()
  end
end)

extension:subscribeEvent('refresh', function()
  local configuration = extension:getConfiguration()
  refreshUsers(configuration.users)
end)

extension:subscribeEvent('shutdown', function()
  local engine = extension:getEngine()
  local server = engine:getHTTPServer()
  engine:onExtension('web-base', function(webBaseExtension)
    webBaseExtension:unregisterAddonExtension(extension)
  end)
  cleanup(server)
end)
