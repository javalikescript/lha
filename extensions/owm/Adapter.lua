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

local HOUR_SEC = 3600
local DAY_SEC = 86400

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

local function between(from, to)
  return function(w)
    return w.dt >= from and w.dt < to
  end
end

local function tomorrow(time)
  local d = os.date('*t', time + DAY_SEC)
  d.hour = 0
  d.min = 15
  d.sec = 0
  return os.time(d)
end

local function hour(time)
  local d = os.date('*t', time + DAY_SEC)
  return d.hour
end

local function range(days, from, to, time)
  local t = time or os.time()
  local d = os.date('*t', t + DAY_SEC * (days or 0))
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
  local z = adapt({}, 0)
  local n = #list
  if n == 0 then
    return z
  elseif n == 1 then
    return adapt(list[1], 0)
  end
  local w = List.reduce(List.map(list, adaptNil), sumFields, z)
  local a = {}
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

return require('jls.lang.class').create(function(adapter)

  function adapter:initialize(dayMorning, dayEvening, minToday)
    self.dayMorning = dayMorning or 7
    self.dayEvening = dayEvening or 19
    self.minToday = minToday or 12
  end

  function adapter:computeCurrent(weather)
    return adapt(weather)
  end

  function adapter:computeNextHours(forecast, time)
    local t = time or os.time()
    return aggregate(List.filter(forecast.list, between(t, t + 4 * HOUR_SEC)))
  end

  function adapter:computeToday(forecast, time)
    local t = time or os.time()
    if hour(t) <= self.minToday then
      return aggregate(List.filter(forecast.list, range(0, self.dayMorning, self.dayEvening, t)))
    end
    return aggregate(List.filter(forecast.list, between(t, tomorrow(t))))
  end

  function adapter:computeTomorrow(forecast, time)
    return aggregate(List.filter(forecast.list, range(1, self.dayMorning, self.dayEvening, time)))
  end

  function adapter:computeNextDays(forecast, time)
    return aggregate(List.filter(forecast.list, ranges(self.dayMorning, self.dayEvening, time)))
  end

end)
