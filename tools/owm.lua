
local json = require('jls.util.json')
local File = require('jls.io.File')
local Map = require('jls.util.Map')

local utils = require('lha.utils')
local adapter = require('extensions.owm.adapter')

local data = json.parse(File:new(arg[1]):readAll())
local time
if arg[2] then
  time = utils.timeFromString(arg[2])
end

local function printWeather(w, l)
  if l then
    print(l)
  end
  for k, v in Map.spairs(w) do
    print(string.format('  %s: %s', k, v))
  end
end

if data.list then
  time = time or (data.list[1].dt - 3600)
  print('', 'date', 'temp', 'rain', 'cloud', 'wind')
  for i, w in ipairs(data.list) do
    local d = utils.timeToString(w.dt)
    print(i, d, w.main and w.main.temp or 0, w.rain and w.rain['3h'] or 0, w.clouds and w.clouds.all or 0, w.wind and w.wind.speed or 0)
  end
  print()
  print('time',  utils.timeToString(time))
  printWeather(adapter.computeNextHours(data, time), 'nextHours')
  printWeather(adapter.computeTomorrow(data, time), 'tomorrow')
  printWeather(adapter.computeNextDays(data, time), 'nextDays')
else
  printWeather(adapter.computeCurrent(data), 'current')
end
