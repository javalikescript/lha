local extension = ...

local logger = require('jls.lang.logger')
local HttpClient = require('jls.net.http.HttpClient')
local Date = require('jls.util.Date')
local base64 = require('jls.util.base64')

local Thing = require('lha.Thing')
local utils = require('lha.utils')

local function fetchJson(url, options)
  local client = HttpClient:new(url)
  return client:fetch(nil, options):next(utils.rejectIfNotOk):next(utils.getJson):finally(function()
    client:close()
  end)
end

local function updateHourValue(thing, name, values, hour)
  for _, value in ipairs(values) do
    if value.pas == hour then
      thing:updatePropertyValue(name, value.hvalue)
      break
    end
  end
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
  thing:addProperty('nextDayValue', {
    ['@type'] = Thing.PROPERTY_TYPES.LevelProperty,
    title = 'Next Day Value',
    type = 'integer',
    description = 'Next day value',
    enum = SIGNAL_ENUM,
    readOnly = true
  })
  thing:addProperty('nextHourValue', {
    ['@type'] = Thing.PROPERTY_TYPES.LevelProperty,
    title = 'Next Hour Value',
    type = 'integer',
    description = 'Next hour value',
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
  fetchJson(oauth.url, {
    method = 'POST',
    headers = {
      ['Authorization'] = 'Basic '..base64.encode(basicRaw),
      ['Content-Type'] = 'application/x-www-form-urlencoded'
    }
  }):next(function(token)
    logger:info('Get signals from "%s"', configuration.url)
    -- {"access_token":"...", "token_type":"Bearer", "expires_in":7200}
    return fetchJson(configuration.url, {
      method = 'GET',
      headers = {
        ['Authorization'] = string.format('%s %s', token.token_type, token.access_token)
      }
    })
  end):next(function(data)
    local signal = data.signals[1]
    logger:info('Ecowatt message: %s', signal.message)
    ecowattThing:updatePropertyValue('dayValue', signal.dvalue)
    local hour = Date:new():getHours()
    updateHourValue(ecowattThing, 'hourValue', signal.values, hour)
    local nextSignal = data.signals[2]
    logger:info('Ecowatt next message: %s', nextSignal.message)
    ecowattThing:updatePropertyValue('nextDayValue', nextSignal.dvalue)
    if hour < 23 then
      hour = hour + 1
    else
      hour = 0
      signal = nextSignal
    end
    updateHourValue(ecowattThing, 'nextHourValue', signal.values, hour)
  end):catch(function(reason)
    logger:warn('Unable to get Ecowatt signals, due to error: %s', reason)
  end)
end, configuration.minIntervalMin * 60)

