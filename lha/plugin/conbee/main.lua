local plugin = ...

local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local http = require('jls.net.http')
local json = require('jls.util.json')
local tables = require('jls.util.tables')
local Date = require('jls.util.Date')

-- Helper classes and functions

local CONST = {
  SENSORS = 'sensors',
  CONFIG = 'config'
}

local Gateway = class.create(function(gateway)

  function gateway:initialize(url, user)
    self.user = user or ''
    self.url = url or ''
    self.delta = 0
  end

  function gateway:configure(config)
    if config.UTC then
      local gatewayTime = Date.fromISOString(config.UTC, true)
      --local time = Date.UTC()
      local time = Date.now()
      self.delta = time - gatewayTime
      logger:info('gatewayTime('..config.UTC..'): '..Date:new(gatewayTime):toISOString()..' time: '..Date:new(time):toISOString())
    else
      self.delta = 0
    end
    logger:info('using ConBee gateway delta time: '..tostring(self.delta))
  end

  function gateway:parseDateTime(dt)
    --logger:info('parseDateTime('..tostring(dt)..'['..type(dt)..'])')
    local d = Date.fromISOString(dt, true)
    if d then
      return d + self.delta
    end
  end

  function gateway:getUrl(path)
    if path then
      return self.url..self.user..'/'..path
    end
    return self.url..self.user..'/'
  end

  function gateway:httpRequest(method, path, body)
    local client = http.Client:new({
      method = method,
      url = self.url..path,
      body = body
    })
    return client:connect():next(function()
      logger:debug('client connected')
      return client:sendReceive()
    end):next(function(response)
      client:close()
      return response:getBody()
    end)
    --return http.request(self.url..self.user..'/'..path)
  end

  function gateway:httpJson(method, path, t)
    local b
    if t then
      b = json.encode(t)
    end
    return self:httpRequest(method, path, b):next(function(body)
      local t = nil
      if body and #body > 0 then
        if logger:isLoggable(logger.DEBUG) then
          logger:debug('gateway:httpJson('..method..') => #'..tostring(#body))
        end
        t = json.decode(body)
        if logger:isLoggable(logger.FINE) then
          logger:dump(t, 'gateway:httpJson('..method..')')
        end
      end
      return t
    end)
  end

  function gateway:httpUserJson(method, path, t)
    return self:httpJson(method, self.user..'/'..path, t)
  end

  function gateway:get(path)
    return self:httpUserJson('GET', path)
  end

  function gateway:put(path, t)
    return self:httpUserJson('PUT', path, t)
  end

  function gateway:post(path, t)
    return self:httpUserJson('POST', path, t)
  end

  function gateway:updateConfiguration()
    return self:get(CONST.CONFIG):next(function(config)
      if config then
        logger:info('update gateway configuration')
        self:configure(config)
      end
    end):catch(function(err)
      logger:warn('fail to get gateway configuration, due to "'..tostring(err)..'"')
    end)
  end

  function gateway:createUser(applicationName, deviceName)
    return self:httpJson('POST', '', {
      devicetype = applicationName..'#'..deviceName
    })
    --[[
      [{"success":{"username": "abcdef0123456789"}}]
    ]]
  end

end)


function plugin:setDevicesData(data)
  for _, device in pairs(self:getDevices()) do
    device:setDeviceData(data)
  end
end

local function getBaseId(uniqueid)
  return string.match(uniqueid, '^([^-]+)(.*)$')
end

-- End Helper classes and functions


local configuration = plugin:getConfiguration()

tables.merge(configuration, {
  url = 'http://localhost/api/',
  user = 'unknown',
  ids = {}
}, true)

local conbeeGateway = Gateway:new(configuration.url, configuration.user)
logger:info('ConBee gateway: "'..configuration.url..'"')

local deviceIdMap = configuration.ids

local lastPollTime

plugin:subscribeEvent('poll', function()
  logger:info('poll ConBee plugin')
  conbeeGateway:get(CONST.SENSORS):next(function(allSensors)
    local time = Date.now()
    if allSensors then
      for _, sensor in pairs(allSensors) do
        if sensor.state and sensor.uniqueid then
          local id = deviceIdMap[sensor.uniqueid]
          if id and id ~= '' then
            local device = plugin:getDevice(id)
            if not device then
              logger:info('register device '..id)
              device = plugin:registerDevice(id, {})
            end
            local state = sensor.state
            local data = {}
            local lastupdatedTime
            if state.lastupdated and state.lastupdated ~= json.null then
              lastupdatedTime = conbeeGateway:parseDateTime(state.lastupdated)
              --logger:info('device '..id..'('..sensor.type..') last updated: '..Date:new(lastupdatedTime):toISOString())
            end
            if sensor.type == 'ZLLLightLevel' and state.lightlevel ~= json.null then
              -- Light level in 10000 log10 (lux) +1 measured by sensor.
              -- Logarithm scale used because the human eye adjusts to light levels and small changes at low lux levels are more noticeable than at high lux levels.  
              data.lightlevel = state.lightlevel
              -- dark, daylight true/false, lastupdated
            elseif (sensor.type == 'ZLLTemperature') or (sensor.type == 'ZHATemperature') and state.temperature ~= json.null then
              -- Current temperature in 0.01 degrees Celsius. (3000 is 30.00 degree)
              -- lastupdated
              data.temperature = state.temperature / 100
            elseif sensor.type == 'ZHAHumidity' and state.humidity ~= json.null then
              -- lastupdated
              data.humidity = state.humidity / 100
            elseif sensor.type == 'ZHAPressure' and state.pressure ~= json.null then
              -- lastupdated
              data.pressure = state.pressure
            elseif sensor.type == 'ZLLPresence' and state.presence ~= json.null then
              -- presence True if sensor detects presence
              -- lastupdated Last time the sensor state was updated, probably UTC
              -- see https://developers.meethue.com/develop/hue-api/supported-devices/
              if lastupdatedTime and lastPollTime then
                data.presence = state.presence and lastupdatedTime >= lastPollTime and lastupdatedTime < time
              else
                data.presence = state.presence
              end
            end
            device:applyDeviceData(data)
          elseif not id then
            deviceIdMap[sensor.uniqueid] = ''
            logger:info('new device found '..tostring(sensor.uniqueid))
          end
        end
      end
    else
      plugin:setDevicesData({})
    end
    lastPollTime = time
  end):catch(function(err)
    logger:warn('fail to get sensors, due to "'..tostring(err)..'"')
    -- cleaning data in case of polling failure
    plugin:setDevicesData({})
  end)
end)

plugin:subscribeEvent('refresh', function()
  logger:info('refresh ConBee plugin')
  conbeeGateway:updateConfiguration()
  -- refresh deviceIdMap
end)

plugin:subscribeEvent('startup', function()
  logger:info('startup ConBee plugin')
  conbeeGateway:updateConfiguration()
  -- refresh deviceIdMap
end)

