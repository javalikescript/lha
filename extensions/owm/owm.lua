local extension = ...

local logger = extension:getLogger()
local HttpClient = require('jls.net.http.HttpClient')
local Url = require('jls.net.Url')

local Thing = require('lha.Thing')
local utils = require('lha.utils')

local adapter = extension:require('adapter')

local function createWeatherThing(title, description)
  local thing = Thing:new(title or 'Weather', description or 'Weather Data', {
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
  thing:addProperty('date', {
    ['@type'] = "DateTimeProperty",
    configuration = true,
    description = "The date of the data",
    readOnly = true,
    title = "Date",
    type = "string",
    unit = "date time"
  })
  return thing
end

local function updateWeatherThing(thing, w)
  if not (thing and type(w) == 'table') then
    return
  end
  for k, v in pairs(w) do
    thing:updatePropertyValue(k, v)
  end
end

local THINGS_BY_KEY = {
  current = createWeatherThing('Weather Now'),
  nextHours = createWeatherThing('Weather Next Hours'),
  tomorrow = createWeatherThing('Weather Tomorrow'),
  nextDays = createWeatherThing('Weather Next Days')
}
local thingByKey = {}
local configuration = extension:getConfiguration()

extension:subscribeEvent('startup', function()
  logger:info('OpenWeatherMap at %s - %s', configuration.latitude, configuration.longitude)
  extension:getEngine():onExtension('web-base', function(webBaseExtension)
    webBaseExtension:registerAddonExtension(extension, true)
  end)
end)

extension:subscribeEvent('shutdown', function()
  extension:getEngine():onExtension('web-base', function(webBaseExtension)
    webBaseExtension:unregisterAddonExtension(extension)
  end)
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

local function updateForecastThing(data, time)
  updateWeatherThing(thingByKey.tomorrow, adapter.computeTomorrow(data, time))
  updateWeatherThing(thingByKey.nextHours, adapter.computeNextHours(data, time))
  updateWeatherThing(thingByKey.nextDays, adapter.computeNextDays(data, time))
end

local demo = false
if demo then
  extension:subscribeEvent('poll', function()
    local json = require('jls.util.json')
    local File = require('jls.io.File')
    local data = json.parse(File:new('work-misc/weather.json'):readAll())
    updateWeatherThing(thingByKey.current, adapter.computeCurrent(data))
    data = json.parse(File:new('work-misc/forecast.json'):readAll())
    local time = data.list[1].dt - 3600
    updateForecastThing(data, time)
  end)
else
  -- Do not send OWM requests more than 1 time per 10 minutes from one device/one API key
  extension:subscribePollEvent(function()
    logger:info('poll OpenWeatherMap extension')
    local url = Url:new(configuration.apiUrl or 'http://api.openweathermap.org/data/2.5/')
    local path = url:getFile()
    local query = '?'..Url.mapToQuery({
      lat = configuration.latitude,
      lon = configuration.longitude,
      units = configuration.units or 'metric',
      lang = configuration.lang,
      appid = configuration.apiKey
    })
    local client = HttpClient:new(url)
    return client:fetch(path..'weather'..query):next(utils.rejectIfNotOk):next(utils.getJson):next(function(data)
      updateWeatherThing(thingByKey.current, adapter.computeCurrent(data))
      return client:fetch(path..'forecast'..query)
    end):next(utils.rejectIfNotOk):next(utils.getJson):next(function(data)
      updateForecastThing(data, os.time())
    end):catch(function(reason)
      logger:warn('fail to get OWM, due to "%s"', reason)
    end):finally(function()
      client:close()
    end)
  end, configuration.maxPollingDelay)
end
