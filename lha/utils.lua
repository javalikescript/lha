local logger = require('jls.lang.logger'):get(...)
local event = require('jls.lang.event')
local system = require('jls.lang.system')
local Promise = require('jls.lang.Promise')
local File = require('jls.io.File')
local Date = require('jls.util.Date')
local json = require('jls.util.json')
local tables = require('jls.util.tables')

local utils = {}

function utils.createDirectoryOrExit(dir)
  if not dir:isDirectory() then
    if dir:mkdir() then
      logger:info('Created directory "'..dir:getPath()..'"')
    else
      logger:warn('Unable to create the directory "'..dir:getPath()..'"')
      system.exit(1)
    end
  end
end

function utils.checkDirectoryOrExit(dir)
  if not dir:isDirectory() then
    logger:warn('The directory "'..dir:getPath()..'" does not exist')
    system.exit(1)
  end
end

function utils.getAbsoluteFile(path, dir)
  local file = File:new(path)
  if file:isAbsolute() then
    return file
  end
  if dir then
    return File:new(dir, path)
  end
  return file:getAbsoluteFile()
end

function utils.requireJson(name)
  local jsonpath = string.gsub(package.path, '%.lua', '.json')
  local path = assert(package.searchpath(name, jsonpath))
  local file = File:new(path)
  return json.decode(file:readAll())
end

function utils.removeEmptyPaths(t)
  local c = 0
  for k, v in pairs(t) do
    c = c + 1
    if type(v) == 'table' then
      if utils.removeEmptyPaths(v) == 0 then
        t[k] = nil
        c = c - 1
      end
    end
  end
  return c
end

function utils.getJson(response)
  return response:json()
end

function utils.rejectIfNotOk(response)
  local status, reason = response:getStatusCode()
  if status == 200 then
    return response
  end
  return response:consume():next(function()
    return Promise.reject(string.format('HTTP status not ok, %s: "%s"', status, reason))
  end)
end

function utils.timeout(promise, delayMs, reason)
  return Promise:new(function(resolve, reject)
    local timer = event:setTimeout(function()
      reject(reason or 'timeout')
    end, delayMs or 30000)
    promise:finally(function(...)
      event:clearTimeout(timer)
    end)
    promise:next(resolve, reject)
  end)
end

utils.time = os.time

function utils.dateToString(date)
  return string.sub(date:toISOString(true), 1, 16)..'Z'
end

function utils.timeToString(time)
  if type(time) ~= 'number' then
    time = utils.time()
  end
  return utils.dateToString(Date:new(time * 1000))
end

function utils.dateFromString(value)
  return Date:new(Date.fromISOString(value))
end

function utils.timeFromString(value)
  return (Date.fromISOString(value) or 0) // 1000
end

function utils.hms(h, m, s)
  return (tonumber(h) or 0) + (tonumber(m) or 0) / 60 + (tonumber(s) or 0) / 3600
end

function utils.parseHms(value)
  return utils.hms(string.match(value, '(%d+):?(%d*):?(%d*)'))
end

function utils.timeToHms(value)
  return utils.parseHms(os.date('%H:%M:%S', value))
end

function utils.findKey(map, value)
  for k, v in pairs(map) do
    if v == value then
      return k
    end
  end
end

function utils.isValue(value)
  return value ~= nil and value ~= json.null
end

local function expand(value, m, ...)
  if type(value) == 'string' then
    return (string.gsub(value, '%${([^{}]+)}', function(p)
      local w = tables.getPath(m, p)
      if w == nil then
        return ''
      end
      return tostring(w)
    end))
  elseif type(value) == 'function' then
    return value(m, ...)
  end
  return nil
end
utils.expand = expand

local function deepExpand(t, m)
  local c = {}
  for k, v in pairs(t) do
    local tv = type(v)
    if tv == 'table' then
      c[k] = deepExpand(v, m)
    elseif tv == 'string' then
      c[k] = expand(v, m)
    else
      c[k] = v
    end
  end
  return c
end
utils.deepExpand = deepExpand

local function replaceRef(t, fn, r)
  for k, v in pairs(t) do
    local tv = type(v)
    if tv == 'table' then
      replaceRef(v, fn, r)
    elseif tv == 'string' then
      local l, w = string.match(v, '^%$(%w+):(.+)$')
      if l then
        local s, x = fn(l, w, t, k)
        if s then
          t[k] = x
          if r and type(x) == 'table' then
            replaceRef(x, fn, r)
          end
        end
      end
    end
  end
end
utils.replaceRef = replaceRef

function utils.replaceRefs(t, env)
  replaceRef(t, function(kind, value, tt, k)
    if kind == 'lua' then
      return true, load('local value, v2 = ...; '..expand(value, tt), 'mapping', 't', env)
    end
  end)
  replaceRef(t, function(kind, value, tt)
    if kind == 'ref' then
      local v = tables.getPath(t, expand(value, tt))
      -- tables.deepCopy(v)
      return true, v
    end
  end)
  replaceRef(t, function(kind, value, tt)
    if kind == 'merge' then
      local pa, pb = string.match(expand(value, tt), '^([^:]+):(.+)$')
      if pa then
        local a = tables.getPath(t, pa)
        local b = tables.getPath(t, pb)
        if type(a) == 'table' and type(b) == 'table' then
          local c = tables.deepCopy(a)
          tables.merge(c, b)
          return true, c
        end
      end
    end
  end)
  return t
end

function utils.addThingPropertyFromInfo(thing, name, info, t)
  if thing:hasProperty(name) then
    logger:warn('The thing "%s" already has the property "%s"', thing:getTitle(), name)
  else
    local title = expand(info.title, t)
    local description = expand(info.description, t)
    if info.metadata then
      thing:addPropertyFrom(name, utils.deepExpand(info.metadata, t), title, description, info.initialValue)
    else
      thing:addPropertyFromName(name, title, description, info.initialValue)
    end
  end
end


function utils.mirekToColorTemperature(value)
  return math.floor(1000000 / value)
end

-- see https://github.com/Shnoo/js-CIE-1931-rgb-color-converter/blob/master/ColorConverter.js

local function getGammaCorrectedValue(value)
  if value > 0.04045 then
    return ((value + 0.055) / (1.0 + 0.055)) ^ 2.4
  end
  return value / 12.92
end

function utils.rgbToXy(red, green, blue)
  red = getGammaCorrectedValue(red)
  green = getGammaCorrectedValue(green)
  blue = getGammaCorrectedValue(blue)

  local X = red * 0.649926 + green * 0.103455 + blue * 0.197109
  local Y = red * 0.234327 + green * 0.743075 + blue * 0.022598
  local Z = red * 0.0000000 + green * 0.053077 + blue * 1.035763

  local S = X + Y + Z
  if S == 0 then
    return 0, 0
  end

  local x, y = X / S, Y / S
  -- TODO check value is in gamut range, depending on the model, or find closest value
  return x, y
end

local function getReversedGammaCorrectedValue(value)
  if value <= 0.0031308 then
    return 12.92 * value
  end
  return (1.0 + 0.055) * (value ^ (1.0 / 2.4)) - 0.055
end

function utils.xyBriToRgb(x, y, Y)
  if y == 0 then
    return 0, 0, 0
  end
  Y = Y or 1.0
  local z = 1.0 - x - y
  local X = (Y / y) * x
  local Z = (Y / y) * z
  local r = X * 1.656492 - Y * 0.354851 - Z * 0.255038
  local g = -X * 0.707196 + Y * 1.655397 + Z * 0.036152
  local b =  X * 0.051713 - Y * 0.121364 + Z * 1.011530

  r = getReversedGammaCorrectedValue(r)
  g = getReversedGammaCorrectedValue(g)
  b = getReversedGammaCorrectedValue(b)

  -- Bring all negative components to zero
  r = math.max(r, 0)
  g = math.max(g, 0)
  b = math.max(b, 0)

  -- If one component is greater than 1, weight components by that value
  local max = math.max(r, g, b)
  if (max > 1) then
      r = r / max
      g = g / max
      b = b / max
  end

  return r, g, b
end

-- Transforms a color expressed with hue, saturation and value to red, green and blue.
-- @tparam number h the hue value from 0 to 1.
-- @tparam number s the saturation value from 0 to 1.
-- @tparam number v the value from 0 to 1.
-- @treturn number the red component value from 0 to 1.
-- @treturn number the green component value from 0 to 1.
-- @treturn number the blue component value from 0 to 1.
function utils.hsvToRgb(h, s, v)
  if s <= 0 then
    return v, v, v
  end
  local c = v * s -- chroma
  local hp = h * 6
  local x = c * (1 - math.abs((hp % 2) - 1))
  local r, g, b
  if hp <= 1 then
    r, g, b = c, x, 0
  elseif hp <= 2 then
    r, g, b = x, c, 0
  elseif hp <= 3 then
    r, g, b = 0, c, x
  elseif hp <= 4 then
    r, g, b = 0, x, c
  elseif hp <= 5 then
    r, g, b = x, 0, c
  else
    r, g, b = c, 0, x
  end
  local m = v - c
  return r + m, g + m, b + m
end

-- Transforms a color expressed with red, green and blue to hue, saturation and value.
-- @tparam number r the red component value from 0 to 1.
-- @tparam number g the green component value from 0 to 1.
-- @tparam number b the blue component value from 0 to 1.
-- @treturn number the hue value from 0 to 1.
-- @treturn number the saturation value from 0 to 1.
-- @treturn number the value from 0 to 1.
function utils.rgbToHsv(r, g, b)
  local minValue = math.min(r, g, b)
  local maxValue = math.max(r, g, b)
  local deltaValue = maxValue - minValue
  local h, s
  local v = maxValue
  if maxValue == 0 then
    h = 0 -- undefined
    s = 0
  else
    s = deltaValue / maxValue
    if deltaValue == 0 then
      h = 0
    elseif r == maxValue then
      h = (g - b) / deltaValue
      if h < 0 then
        h = h + 6
      end
    elseif g == maxValue then
      h = 2 + (b - r) / deltaValue
    else
      h = 4 + (r - g) / deltaValue
    end
    h = h / 6
  end
  return h, s, v
end

return utils
