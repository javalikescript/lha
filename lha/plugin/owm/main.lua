local plugin = ...

local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local http = require('jls.net.http')
local json = require('jls.util.json')
local tables = require('jls.util.tables')

-- Helper classes and functions

local OpenWeatherMap = class.create(function(openWeatherMap)

  function openWeatherMap:initialize(apiUrl, apiKey, cityId)
    self.apiKey = apiKey
    self.cityId = cityId
    self.apiUrl = apiUrl
    self.units = 'metric'
  end

  function openWeatherMap:getUrl(path)
    return self.apiUrl..path..'?id='..self.cityId..'&units='..self.units..'&APPID='..self.apiKey
  end

  function openWeatherMap:httpRequest(path, method, body)
    local client = http.Client:new({
      method = method or 'GET',
      url = self:getUrl(path),
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

  function openWeatherMap:get(path)
    return self:httpRequest(path):next(function(body)
      if logger:isLoggable(logger.DEBUG) then
        if logger:isLoggable(logger.FINEST) then
          logger:finest('openWeatherMap:get() => '..tostring(body))
        else
          logger:debug('openWeatherMap:get() => #'..tostring(#body))
        end
      end
      return json.decode(body)
    end)
  end

end)
-- End Helper classes and functions

local configuration = plugin:getConfiguration()

tables.merge(configuration, {
  apiUrl = 'http://api.openweathermap.org/data/2.5/',
  apiKey = '',
  cityId = '11111'
}, true)

local owm = OpenWeatherMap:new(configuration.apiUrl, configuration.apiKey, configuration.cityId)
logger:info('OpenWeatherMap city id: "'..configuration.cityId..'"')

-- TODO load configured devices

-- Current weather data
local weatherDevice = plugin:registerDevice('weather', {})
-- 5 day weather forecast
local forecastDevice = plugin:registerDevice('forecast', {})

--tables.merge(weatherDevice:getConfiguration(), {
--  archiveData = false
--}, true)

local function update(device, path, fn)
  owm:get(path):next(function(data)
    if data then
      if type(fn) == 'function' then
        data = fn(data)
      end
      --device:applyDeviceData(data)
    else
      data = {}
    end
    device:setDeviceData(data)
  end):catch(function(err)
    logger:warn('fail to get OWM '..path..', due to "'..tostring(err)..'"')
    -- cleaning data in case of polling failure
    device:setDeviceData({})
  end)
end

local function adaptWeather(w)
  local data = {}
  if (w.main) then
    data.temperature = w.main.temp
    data.pressure = w.main.pressure * 100
    data.humidityPercent = w.main.humidity
  end
  if (w.clouds) then
    data.cloudsPercent = w.clouds.all
  end
  if (w.wind) then
    data.windSpeed = w.wind.speed
    data.windDirection = w.wind.deg
  end
  -- snow
  if (w.rain) then
    data.rain = w.rain['3h']
  end
  return data
end

local function adaptForecast(f)
  if f and f.list and f.cnt and f.cnt > 7 then
    return {
      nextHours = adaptWeather(f.list[1]),
      tomorrow = adaptWeather(f.list[7]),
      nextDays = adaptWeather(f.list[f.cnt - 1])
    }
  end
  return {}
end

-- Do not send OWM requests more than 1 time per 10 minutes from one device/one API key
weatherDevice:subscribePollEvent(function()
  logger:info('poll OpenWeatherMap virtual weather device')
  update(weatherDevice, 'weather', adaptWeather)
end, 600)

forecastDevice:subscribePollEvent(function()
  logger:info('poll OpenWeatherMap virtual forecast device')
  update(forecastDevice, 'forecast', adaptForecast)
end, 600)

