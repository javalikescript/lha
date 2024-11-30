local List = require('jls.util.List')
local tables = require('jls.util.tables')

local utils = require('lha.utils')

-- temp_min temp_max
-- sys.sunrise: 1485720272
-- sys.sunset: 1485766550
-- city.name: "Paris"

local FIELD_MAP = {
  temperature = 'main/temp',
  humidity = 'main/humidity',
  pressure = 'main/pressure',
  cloud = 'clouds/all',
  windSpeed = 'wind/speed',
  windDirection = 'wind/deg',
  rain = 'rain/3h', -- Rain volume for last 3 hours
}

local CUMULATIVE_FIELD_MAP = {
  rain = true,
}

local function adapt(w, d)
  local a = {}
  for k, p in pairs(FIELD_MAP) do
    a[k] = tables.getPath(w, p, d)
  end
  a.date = utils.timeToString(w.dt)
  return a
end

local function adaptNil(w)
  return adapt(w)
end

local function sumFields(a, w)
  for k, v in pairs(w) do
    if type(v) == 'number' then
      a[k] = (a[k] or 0) + v
    else
      a[k] = v
    end
  end
  return a
end

local function range(days, from, to, time)
  local t = time or os.time()
  local d = os.date('*t', t + 86400 * (days or 0))
  d.min = 15
  d.sec = 0
  d.hour = from or 0
  local ft = os.time(d)
  d.hour = to or 23
  local tt = os.time(d)
  return function(w)
    return w.dt >= t and w.dt >= ft and w.dt < tt
  end
end

local function ranges(from, to, time)
  local t = time or os.time()
  local r3 = range(2, from, to, t)
  local r4 = range(3, from, to, t)
  local r5 = range(4, from, to, t)
  return function(w)
    return r3(w) or r4(w) or r5(w)
  end
end

local function aggregate(list)
  local w = List.reduce(List.map(list, adaptNil), sumFields, adapt({}, 0))
  local a, n = {}, #list
  for k, v in pairs(w) do
    if type(v) == 'number' and not CUMULATIVE_FIELD_MAP[k] then
      a[k] = (v * 100 // n) / 100
    else
      a[k] = v
    end
  end
  return a
end

-- 5 day forecast includes weather forecast data with 3-hour step

return {
  computeCurrent = function(weather)
    return adapt(weather)
  end,
  computeNextHours = function(forecast, time)
    return aggregate(List.filter(forecast.list, range(0, 7, 19, time)))
  end,
  computeTomorrow = function(forecast, time)
    return aggregate(List.filter(forecast.list, range(1, 7, 19, time)))
  end,
  computeNextDays = function(forecast, time)
    return aggregate(List.filter(forecast.list, ranges(7, 19, time)))
  end
}