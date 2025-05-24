local extension = ...

local logger = extension:getLogger()
local event = require('jls.lang.event')
local Promise = require('jls.lang.Promise')
local HttpClient = require('jls.net.http.HttpClient')
local Url = require('jls.net.Url')
local List = require('jls.util.List')
local json = require('jls.util.json')

local Thing = require('lha.Thing')
local utils = require('lha.utils')

local function formatBody(body)
  if type(body) == 'table' then
    return json.encode(body)
  elseif type(body) == 'string' then
    return body
  end
end

local function processResponse(response)
  local status, reason = response:getStatusCode()
  logger:finer('response status %d "%s"', status, reason)
  local success = status // 100 == 2
  if not response:hasHeaderValueIgnoreCase('content-type', 'application/json') then
    for n, v in pairs(response:getHeadersTable()) do
        logger:fine('response header "%s" is "%s"', n, v)
    end
    return response:text():next(function(text)
      logger:fine('response body "%s"', text)
      return Promise.reject('Invalid or missing content type')
    end)
  end
  if not success then
    return Promise.reject('Error '..tostring(status)..' requesting API, due to '..tostring(reason))
  end
  return response:json():next(function(content)
    if not content.success then
      return Promise.reject('Error '..tostring(content.error_code)..' requesting API, due to '..tostring(content.msg))
    end
    return content.result
  end)
end

local function httpRequest(client, method, path, headers, body)
  if client == nil or type(client) == 'string' then
    local url = Url:new(client or path)
    local c = HttpClient:new(client)
    return httpRequest(c, method, client and path or url:getPath(), headers, body):finally(function()
      c:close()
    end)
  end
  logger:finer('httpRequest(%s, %s, %T, %T)', method, path, headers, body)
  if type(body) == 'table' then
    headers = headers or {}
    headers['Content-Type'] = 'application/json'
  end
  return utils.timeout(client:fetch(path or '/', {
    method = method or 'GET',
    headers = headers,
    body = formatBody(body),
  }))
end

local function openSession(client, appToken)
  local hmac = require('openssl').hmac.hmac -- TODO Expose HMAC on jls
  return httpRequest(client, 'GET', '/api/v4/login/'):next(processResponse):next(function(result)
    logger:finer('freebox login is %T', result)
    local password = hmac('sha1', result.challenge, appToken)
    return httpRequest(client, 'POST', '/api/v4/login/session/', nil, {
      app_id = 'lha.'..extension:getId(),
      password = password
    })
  end):next(processResponse):next(function(result)
    logger:finer('freebox session is %T', result)
    return result.session_token
  end)
end

local function listLanHosts(client, sessionToken)
  local sessionHeaders = {['X-Fbx-App-Auth'] = sessionToken}
  return httpRequest(client, 'GET', '/api/v4/lan/browser/interfaces/', sessionHeaders):next(processResponse):next(function(result)
    logger:finer('freebox interfaces are %T', result)
    return Promise.all(List.map(result, function(interface)
      return httpRequest(client, 'GET', '/api/v4/lan/browser/'..interface.name..'/', sessionHeaders):next(processResponse)
    end))
  end):next(function(results)
    logger:finest('freebox interfaces are %t', results)
    local lanHosts = {}
    for _, lanHost in pairs(results) do
      List.concat(lanHosts, lanHost)
    end
    return lanHosts
  end)
end


local configuration = extension:getConfiguration()
local lastTimePoll = nil

extension:subscribeEvent('startup', function()
  logger:fine('Using freebox API URL is %s', configuration.apiUrl)
end)

extension:subscribeEvent('poll', function()
  if not(configuration.apiUrl and configuration.appToken) then
    return
  end
  local client = HttpClient:new(configuration.apiUrl)
  openSession(client, configuration.appToken):next(function(sessionToken)
    return listLanHosts(client, sessionToken)
  end):next(function(lanHosts)
    logger:fine('Found %l LAN hosts', lanHosts)
    extension:cleanDiscoveredThings()
    local things = extension:getThingsByDiscoveryKey()
    local time = utils.time()
    local discoveryDelay = (configuration.discoveryDelay or 10080) * 60
    for _, lanHost in pairs(lanHosts) do
      if lanHost.id and lanHost.reachable ~= nil then
        local lastTimeReachable = lanHost.last_time_reachable or 0 -- TODO Does the Freebox time is in sync?
        local thing = things[lanHost.id]
        if not thing and discoveryDelay >= 0 and (lanHost.reachable or (time - lastTimeReachable) < discoveryDelay) then
          thing = Thing:new(lanHost.primary_name or 'Host', 'Host Reachability', {'BinarySensor'}):addProperty('reachable', {
            ['@type'] = 'BooleanProperty',
            title = 'Host Reachability',
            type = 'boolean',
            description = 'Test the reachability of a host on the network',
            readOnly = true
          }, false)
          extension:discoverThing(lanHost.id, thing)
        end
        if thing then
          local reachable = lanHost.reachable == true
          if not reachable and lastTimePoll and (lastTimeReachable > lastTimePoll) then
            reachable = true
          end
          logger:fine('LAN host %s "%s" is %s', lanHost.id, lanHost.primary_name, lanHost.reachable)
          thing:updatePropertyValue('reachable', reachable)
        end
      end
    end
    lastTimePoll = time
  end):catch(function(reason)
    logger:warn('Failure due to %s', reason)
  end):finally(function()
    client:close()
  end)
end)

function extension:generateToken(exchange)
  if not configuration.apiUrl then
    return Promise.reject('The API URL is missing')
  end
  local session = exchange:getSession()
  local sessionId = session and session:getId()
  local client = HttpClient:new(configuration.apiUrl)
  return httpRequest(client, 'POST', '/api/v4/login/authorize/', nil, {
    app_id = 'lha.'..extension:getId(),
    app_name = extension:name(),
    app_version = extension:version(),
    device_name = 'localhost'
  }):next(processResponse):next(function(result)
    logger:finer('freebox auth is %T', result)
    local appToken = result.app_token
    local trackId = result.track_id
    return Promise:new(function(resolve, reject)
      local duration, timeout = 0, 180
      local function checkStatus()
        httpRequest(client, 'GET', '/api/v4/login/authorize/'..trackId):next(processResponse):next(function(result)
          logger:fine('authorize status is %s (%d/%ds)', result.status, duration, timeout)
          if result.status == 'granted' then
            configuration.appToken = appToken
            resolve(result)
          elseif result.status ~= 'pending' then
            reject(result.status)
          elseif duration > timeout then
            reject('timeout')
          else
            extension:notify('Pending authorization', sessionId)
            local delay = 5
            duration = duration + delay
            event:setTimeout(checkStatus, delay * 1000)
          end
        end, reject)
      end
      logger:fine('waiting for authorize to be granted')
      checkStatus()
    end)
  end):finally(function()
    client:close()
  end)
end
