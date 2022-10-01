local extension = ...

local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')
local HttpClient = require('jls.net.http.HttpClient')
local json = require('jls.util.json')
local Thing = require('lha.Thing')

-- Helper classes and functions

local OpenWeatherMap = class.create(function(openWeatherMap)

  function openWeatherMap:initialize(apiUrl, apiKey, cityId, units)
    self.apiKey = apiKey or ''
    self.cityId = cityId or ''
    self.apiUrl = apiUrl or 'http://api.openweathermap.org/data/2.5/'
    self.units = units or 'metric'
  end

  function openWeatherMap:getCityId()
    return self.cityId
  end

  function openWeatherMap:getUrl(path)
    return self.apiUrl..path..'?id='..self.cityId..'&units='..self.units..'&APPID='..self.apiKey
  end

  function openWeatherMap:httpRequest(path, method, body)
    local client = HttpClient:new({
      method = method or 'GET',
      url = self:getUrl(path),
      body = body
    })
    return client:connect():next(function()
      logger:debug('client connected')
      return client:sendReceive()
    end):next(function(response)
      client:close()
      local status, reason = response:getStatusCode()
      if status ~= 200 then
        return Promise.reject(tostring(status)..': '..tostring(reason))
      end
      return response:getBody()
    end)
    --return http.request(self.url..self.user..'/'..path)
  end

  function openWeatherMap:get(path)
    return self:httpRequest(path):next(function(body)
      if logger:isLoggable(logger.FINER) then
        if logger:isLoggable(logger.FINEST) then
          logger:finest('openWeatherMap:get() => '..tostring(body))
        else
          logger:finer('openWeatherMap:get() => #'..tostring(#body))
        end
      end
      return json.decode(body)
    end)
  end

end)



local function createWeatherThing(title)
  local thing = Thing:new(title or 'Weather', 'Weather Data', {
    Thing.CAPABILITIES.TemperatureSensor,
    Thing.CAPABILITIES.HumiditySensor,
    Thing.CAPABILITIES.BarometricPressureSensor,
    Thing.CAPABILITIES.MultiLevelSensor
  })
  thing:addPropertiesFromNames('temperature', 'humidity', 'pressure')
  thing:addProperty('cloud', {
    ['@type'] = 'LevelProperty',
    title = 'Cloudiness',
    type = 'number',
    description = 'The cloudiness as percent',
    minimum = 0,
    maximum = 100,
    readOnly = true,
    unit = 'percent'
  })
  thing:addProperty('rain', {
    ['@type'] = 'LevelProperty',
    title = 'Rain volume',
    type = 'number',
    description = 'The rain volume in millimeter',
    minimum = 0,
    readOnly = true,
    unit = 'mm'
  })
  thing:addProperty('windSpeed', {
    ['@type'] = 'LevelProperty',
    title = 'Wind speed',
    type = 'number',
    description = 'The wind speed in meter/sec',
    minimum = 0,
    readOnly = true,
    unit = 'meter/sec'
  })
  thing:addProperty('windDirection', {
    ['@type'] = 'LevelProperty',
    title = 'Wind direction',
    type = 'number',
    description = 'The wind direction in degrees',
    minimum = 0,
    maximum = 360,
    readOnly = true,
    unit = 'degree'
  })
  return thing
end

local function updateWeatherThing(thing, w)
  if not (thing and type(w) == 'table') then
    return
  end
  --logger:info('rain '..json.stringify(w, 2))
  if w.main then
    -- temp_min temp_max
    thing:updatePropertyValue('temperature', w.main.temp)
    thing:updatePropertyValue('humidity', w.main.humidity)
    thing:updatePropertyValue('pressure', w.main.pressure)
  end
  if w.clouds then
    thing:updatePropertyValue('cloud', w.clouds.all)
  end
  if w.wind then
    thing:updatePropertyValue('windSpeed', w.wind.speed)
    thing:updatePropertyValue('windDirection', w.wind.deg)
  end
  if w.rain and w.rain['3h'] then
    thing:updatePropertyValue('rain', w.rain['3h'])
  end
  -- sys.sunrise: 1485720272
  -- sys.sunset: 1485766550
  -- city.name: "Paris"
end

-- End Helper classes and functions

local THINGS_BY_KEY = {
  current = createWeatherThing("Weather Now"),
  nextHours = createWeatherThing("Weather Next Hours"),
  tomorrow = createWeatherThing("Weather Tomorrow"),
  nextDays = createWeatherThing("Weather Next Days")
}
local thingByKey = {}
local configuration = extension:getConfiguration()
local owm = OpenWeatherMap:new(configuration.apiUrl, configuration.apiKey, configuration.cityId)

extension:subscribeEvent('startup', function()
  logger:info('startup OpenWeatherMap extension')
  logger:info('OpenWeatherMap city id is "'..owm:getCityId()..'"')
end)

extension:subscribeEvent('things', function()
  logger:info('looking for OpenWeatherMap things')
  extension:cleanDiscoveredThings()
  thingByKey = {}
  local things = extension:getThingsByDiscoveryKey()
  for key, refThing in pairs(THINGS_BY_KEY) do
    local thing = things and things[key]
    if thing then
      thingByKey[key] = thing
    else
      thingByKey[key] = refThing
      extension:discoverThing(key, refThing)
    end
  end
end)

-- Do not send OWM requests more than 1 time per 10 minutes from one device/one API key
extension:subscribePollEvent(function()
  logger:info('poll OpenWeatherMap extension')
  owm:get('weather'):next(function(data)
    updateWeatherThing(thingByKey.current, data)
  end):catch(function(err)
    logger:warn('fail to get OWM weather, due to "'..tostring(err)..'"')
    -- cleaning data in case of polling failure
  end)
  owm:get('forecast'):next(function(data)
    if data and data.list and data.cnt and data.cnt > 7 then
      updateWeatherThing(thingByKey.nextHours, data.list[1])
      updateWeatherThing(thingByKey.tomorrow, data.list[7])
      updateWeatherThing(thingByKey.nextDays, data.list[data.cnt - 1])
    end
  end):catch(function(err)
    logger:warn('fail to get OWM forecast, due to "'..tostring(err)..'"')
    -- cleaning data in case of polling failure
  end)
end, configuration.maxPollingDelay)
