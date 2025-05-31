local extension = ...

local class = require('jls.lang.class')
local serialization = require('jls.lang.serialization')
local logger = extension:getLogger()
local File = require('jls.io.File')
local HttpExchange = require('jls.net.http.HttpExchange')
local HttpFilter = require('jls.net.http.HttpFilter')
local Url = require('jls.net.Url')
local MessageDigest = require('jls.util.MessageDigest')
local Codec = require('jls.util.Codec')
local webBaseAddons = extension:require('web-base.addons', true)

webBaseAddons.register(extension)

local function getRemoteName(exchange)
  local client = exchange:getClient()
  if client then
    local ip, port = client:getRemoteName()
    if ip then
      return ip, port
    end
  end
  return 'n/a'
end

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

local filter, base64, md, userMap

local function cleanup()
  if filter then
    local server = extension:getEngine():getHTTPServer()
    server:removeFilter(filter)
    filter = nil
  end
  userMap = {}
  base64 = Codec.getInstance('base64')
  md = MessageDigest.getInstance('SHA-1')
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

local function getSessionsFile()
  return File:new(extension:getEngine():getWorkDirectory(), 'sessions.dat')
end

local sessionFilter

extension:subscribeEvent('startup', function()
  local configuration = extension:getConfiguration()
  local server = extension:getEngine():getHTTPServer()
  if sessionFilter then
    sessionFilter:close()
  end
  sessionFilter = HttpFilter.session(configuration.maxAge, configuration.idleTimeout)
  if configuration.keepSessions then
    local sessionsFile = getSessionsFile()
    if sessionsFile:isFile() then
      local status, sessions = pcall(serialization.deserialize, sessionsFile:readAll(), '{jls.net.http.HttpSession}')
      if status then
        logger:info('restoring %l session(s)', sessions)
        sessionFilter:addSessions(sessions)
        sessionFilter:cleanup()
        sessionsFile:delete()
      else
        logger:warn('unable to read sessions due to %s', sessions)
      end
    end
  end
  cleanup()
  refreshUsers(configuration.users)
  function sessionFilter:onCreated(session)
    session.attributes.userName = nil
    session.attributes.permission = configuration.defaultPermission or ''
  end
  extension:addContext('/logout', function(exchange)
    if HttpExchange.methodAllowed(exchange, 'POST') then
      sessionFilter:onCreated(exchange:getSession())
      HttpExchange.redirect(exchange, '/')
    end
  end)
  extension:addContext('/login', function(exchange)
    if not HttpExchange.methodAllowed(exchange, 'POST') then
      return
    end
    local info = Url.queryToMap(exchange:getRequest():getBody())
    if info and info.name and info.password then
      local remoteName = getRemoteName(exchange)
      local user = userMap[info.name]
      if user and user:checkPassword(encrypt(info.password)) then
        local session = exchange:getSession()
        session.attributes.userName = info.name
        if user.permission then
          session.attributes.permission = user.permission
        end
        HttpExchange.redirect(exchange, '/')
        logger:info('user "%s" from %s is authenticated', info.name, remoteName)
        -- TODO keep a list of authenticated clients
        return
      else
        logger:warn('user "%s" from %s cannot be authenticated', info.name, remoteName)
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
  if extension:getConfiguration().keepSessions then
    sessionFilter:cleanup()
    local sessions = sessionFilter:getSessions()
    if #sessions > 0 then
      local s = serialization.serialize(sessions)
      getSessionsFile():write(s)
    end
  end
  cleanup()
end)
