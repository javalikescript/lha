local extension = ...

local logger = require('jls.lang.logger')
local Exception = require('jls.lang.Exception')
local Promise = require('jls.lang.Promise')
local HttpClient = require('jls.net.http.HttpClient')
local json = require('jls.util.json')
local Date = require('jls.util.Date')
local base64 = require('jls.util.base64')

local Thing = require('lha.Thing')

local function fetch(options)
  local client = HttpClient:new(options)
  return client:connect():next(function()
    logger:debug('client connected')
    return client:sendReceive()
  end):next(function(response)
    client:close()
    return response
  end)
end

local function getJson(response)
  local status, reason = response:getStatusCode()
  if status == 200 then
    local body = response:getBody()
    local result
    status, result = Exception.pcall(json.decode, body)
    if status then
      return result
    end
    logger:warn('Invalid JSON: "%s", with payload: "%s"', result, body)
    return Promise.reject('Invalid JSON')
  end
  return Promise.reject(string.format('%s: %s', status, reason))
end


-- 1 vert, 2 orange, 3 rouge
local SIGNAL_ENUM = {1, 2, 3}

local function createThing(targetName)
  local thing = Thing:new('Ecowatt', 'Ecowatt signals', {Thing.CAPABILITIES.MultiLevelSensor})
  thing:addProperty('dayValue', {
    ['@type'] = Thing.PROPERTY_TYPES.LevelProperty,
    title = 'Day Value',
    type = 'integer',
    description = 'Current day value',
    enum = SIGNAL_ENUM,
    readOnly = true
  })
  thing:addProperty('hourValue', {
    ['@type'] = Thing.PROPERTY_TYPES.LevelProperty,
    title = 'Hour Value',
    type = 'integer',
    description = 'Current hour value',
    enum = SIGNAL_ENUM,
    readOnly = true
  })
  return thing
end

local ecowattThing

extension:subscribeEvent('things', function()
  ecowattThing = extension:syncDiscoveredThingByKey('lua', createThing)
end)

local configuration = extension:getConfiguration()

extension:subscribePollEvent(function()
  local oauth = extension:getConfiguration().oauth
  local basicRaw = string.format('%s:%s', oauth.clientId, oauth.clientSecret)
  logger:info('Get OAuth token from "%s"', oauth.url)
  fetch({
    method = 'POST',
    url = oauth.url,
    headers = {
      ['Authorization'] = 'Basic '..base64.encode(basicRaw),
      ['Content-Type'] = 'application/x-www-form-urlencoded'
    }
  }):next(getJson):next(function(token)
    logger:info('Get signals from "%s"', configuration.url)
    -- {"access_token":"...", "token_type":"Bearer", "expires_in":7200}
    return fetch({
      method = 'GET',
      url = configuration.url,
      headers = {
        ['Authorization'] = string.format('%s %s', token.token_type, token.access_token)
      }
    })
  end):next(getJson):next(function(response)
    local signal = response.signals[1]
    logger:info('Ecowatt message: %s', signal.message)
    ecowattThing:updatePropertyValue('dayValue', signal.dvalue)
    local hour = Date:new():getHours()
    for _, value in ipairs(signal.values) do
      if value.pas == hour then
        ecowattThing:updatePropertyValue('hourValue', value.hvalue)
        break
      end
    end
  end):catch(function(reason)
    logger:warn('Unable to get Ecowatt signals, due to error: %s', reason)
  end)
end, configuration.minIntervalMin * 60)
