local extension = ...

local logger = extension:getLogger()
local HttpClient = require('jls.net.http.HttpClient')
local Url = require('jls.net.Url')

local Thing = require('lha.Thing')
local utils = require('lha.utils')

-- Helper classes and functions

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

extension:subscribeEvent('startup', function()
  logger:info('startup OpenWeatherMap extension')
  logger:info('OpenWeatherMap city id is "%s"', configuration.cityId)
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
  local url = Url:new(configuration.apiUrl or 'http://api.openweathermap.org/data/2.5/')
  local path = url:getFile()
  local query = '?'..Url.mapToQuery({
    id = configuration.cityId or '',
    units = configuration.units or 'metric',
    APPID = configuration.apiKey or ''
  })
  local client = HttpClient:new(url)
  return client:fetch(path..'weather'..query):next(utils.rejectIfNotOk):next(utils.getJson):next(function(data)
    updateWeatherThing(thingByKey.current, data)
    return client:fetch(path..'forecast'..query)
  end):next(utils.rejectIfNotOk):next(utils.getJson):next(function(data)
    if data and data.list and data.cnt and data.cnt > 7 then
      updateWeatherThing(thingByKey.nextHours, data.list[1])
      updateWeatherThing(thingByKey.tomorrow, data.list[7])
      updateWeatherThing(thingByKey.nextDays, data.list[data.cnt - 1])
    end
  end):catch(function(reason)
    logger:warn('fail to get OWM, due to "%s"', reason)
  end):finally(function()
    client:close()
  end)
end, configuration.maxPollingDelay)
