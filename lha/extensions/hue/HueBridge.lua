local logger = require('jls.lang.logger')
local http = require('jls.net.http')
local json = require('jls.util.json')
local Date = require('jls.util.Date')
local Thing = require('lha.engine.Thing')

local CONST = {
  SENSORS = 'sensors',
  GROUPS = 'groups',
  LIGHTS = 'lights',
  RULES = 'rules',
  CONFIG = 'config',
  RESOURCE_LINKS = 'resourcelinks',
  CAPABILITIES = 'capabilities',
  SCHEDULES = 'schedules'
}

local function hsvToRgb(h, s, v)
  if s <= 0 then
    return v, v, v
  end
  local c = v * s
  local x = (1 - math.abs((h % 2) - 1)) * c
  local m = v - c
  local r, g, b = 0, 0, 0
  if h < 1 then
    r, g, b = c, x, 0
  elseif h < 2 then
    r, g, b = x, c, 0
  elseif h < 3 then
    r, g, b = 0, c, x
  elseif h < 4 then
    r, g, b = 0, x, c
  elseif h < 5 then
    r, g, b = x, 0, c
  else
    r, g, b = c, 0, x
  end
  return r + m, g + m, b + m
end

local function hsvToRgb255(h, s, v)
  local r, g, b = hsvToRgb(h, s, v)
  return math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)
end

local function hsvToRgbHex(h, s, v)
  local r, g, b = hsvToRgb255(h, s, v)
  return string.format('%02X%02X%02X', r, g, b)
end

local BUTTON = {
  ON = 1000,
  DIM_UP = 2000,
  DIM_DOWN = 3000,
  OFF = 4000
}

local BUTTON_EVENT = {
  INITIAL_PRESS = 0,
  HOLD = 1,
  SHORT_RELEASED = 2,
  LONG_RELEASED = 3
}

return require('jls.lang.class').create(function(hueBridge)

  function hueBridge:initialize(url, user)
    self.user = user or ''
    self.url = url or ''
    self.delta = 0
  end

  function hueBridge:configure(config)
    if config.UTC then
      local bridgeTime = Date.fromISOString(config.UTC, true)
      --local time = Date.UTC()
      local time = Date.now()
      self.delta = time - bridgeTime
      logger:info('Bridge time '..config.UTC..': '..Date:new(bridgeTime):toISOString()..' time: '..Date:new(time):toISOString())
    else
      self.delta = 0
    end
    logger:info('Using bridge delta time: '..tostring(self.delta))
  end

  function hueBridge:parseDateTime(dt)
    --logger:info('parseDateTime('..tostring(dt)..'['..type(dt)..'])')
    local d = Date.fromISOString(dt, true)
    if d then
      return d + self.delta
    end
  end

  function hueBridge:getUrl(path)
    if path then
      return self.url..self.user..'/'..path
    end
    return self.url..self.user..'/'
  end

  function hueBridge:httpRequest(method, path, body)
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

  function hueBridge:httpJson(method, path, t)
    local b
    if t then
      b = json.encode(t)
    end
    return self:httpRequest(method, path, b):next(function(body)
      local t = nil
      if body and #body > 0 then
        if logger:isLoggable(logger.DEBUG) then
          logger:debug('hueBridge:httpJson('..method..') => #'..tostring(#body))
        end
        t = json.decode(body)
        if logger:isLoggable(logger.FINE) then
          logger:dump(t, 'hueBridge:httpJson('..method..')')
        end
      end
      return t
    end)
  end

  function hueBridge:httpUserJson(method, path, t)
    return self:httpJson(method, self.user..'/'..path, t)
  end

  function hueBridge:get(path)
    return self:httpUserJson('GET', path)
  end

  function hueBridge:put(path, t)
    return self:httpUserJson('PUT', path, t)
  end

  function hueBridge:post(path, t)
    return self:httpUserJson('POST', path, t)
  end

  function hueBridge:updateConfiguration()
    return self:get(CONST.CONFIG):next(function(config)
      if config then
        logger:info('update bridge configuration')
        self:configure(config)
      end
    end):catch(function(err)
      logger:warn('fail to get bridge configuration, due to "'..tostring(err)..'"')
    end)
  end

  function hueBridge:createUser(applicationName, deviceName)
    return self:httpJson('POST', '', {
      devicetype = applicationName..'#'..deviceName
    })
    --[[
      [{"success":{"username": "abcdef0123456789"}}]
    ]]
  end

  function hueBridge:updateThing(thing, info, time, lastPollTime)
    local state = info.state
    local lastupdatedTime
    if state.lastupdated and state.lastupdated ~= json.null then
      lastupdatedTime = self:parseDateTime(state.lastupdated)
    end
    local updatedDuringLastPoll = lastupdatedTime and lastPollTime and lastupdatedTime >= lastPollTime and lastupdatedTime < time
    if info.type == 'Color temperature light' then
      thing:updatePropertyValue('on', state.on)
      thing:updatePropertyValue('brightness', math.floor(state.bri * 100 / 255))
      thing:updatePropertyValue('colorTemperature', math.floor(1000000 / state.ct))
    elseif info.type == 'Extended color light' then
      thing:updatePropertyValue('on', state.on)
      thing:updatePropertyValue('brightness', math.floor(state.bri * 100 / 255))
      thing:updatePropertyValue('colorTemperature', math.floor(1000000 / state.ct))
      thing:updatePropertyValue('color', hsvToRgbHex(state.hue / 65535, state.sat / 254, state.bri / 254))
    elseif info.type == 'ZLLLightLevel' and state.lightlevel ~= json.null then
      -- Light level in 10000 log10 (lux) +1 measured by info.
      -- Logarithm scale used because the human eye adjusts to light levels and small changes at low lux levels are more noticeable than at high lux levels.  
      thing:updatePropertyValue('lightlevel', state.lightlevel)
      -- dark, daylight true/false, lastupdated
    elseif info.type == 'ZLLTemperature' and state.temperature ~= json.null then
      -- Current temperature in 0.01 degrees Celsius. (3000 is 30.00 degree)
      -- lastupdated
      thing:updatePropertyValue('temperature', state.temperature / 100)
    elseif info.type == 'ZLLPresence' and state.presence ~= json.null then
      -- presence True if info detects presence
      -- lastupdated Last time the info state was updated, probably UTC
      -- see https://developers.meethue.com/develop/hue-api/supported-devices/
      if lastupdatedTime and lastPollTime then
        thing:updatePropertyValue('presence', updatedDuringLastPoll)
      else
        thing:updatePropertyValue('presence', state.presence)
      end
    elseif info.type == 'ZLLSwitch' then
      -- TODO
      -- state.buttonevent
    elseif info.type == 'ZHAHumidity' and state.humidity ~= json.null then
      -- lastupdated
      thing:updatePropertyValue('humidity', state.humidity / 100)
    elseif info.type == 'ZHAPressure' and state.pressure ~= json.null then
      -- lastupdated
      thing:updatePropertyValue('pressure', state.pressure)
    elseif info.type == 'ZHASwitch' then
      -- TODO
      -- state.buttonevent
    end
  end

end, function(HueBridge)

  HueBridge.CONST = CONST

  function HueBridge.addLightOnOff(thing)
    return thing:addProperty('on', {
      ['@type'] = 'OnOffProperty',
      title = 'On/Off',
      type = 'boolean',
      description = 'Whether the lamp is turned on'
    }, false)
  end

  function HueBridge.addLightBrightness(thing)
    return thing:addProperty('brightness', {
      ['@type'] = 'BrightnessProperty',
      title = 'Brightness',
      type = 'integer',
      description = 'The level of light from 0-100',
      -- Hue Brightness is 0-255
      minimum = 0,
      maximum = 100,
      unit = 'percent'
    }, 0)
  end

  function HueBridge.addLightColorTemperature(thing)
    return thing:addProperty('colorTemperature', {
      ['@type'] = 'ColorTemperatureProperty',
      title = 'Color temperature',
      type = 'integer',
      -- Mirek color temperature, M=1000000/T, Hue 2012 connected lamps are capable of 153 (6500K) to 500 (2000K)
      description = 'Color temperature',
      unit = 'kelvin',
      minimum = 2000,
      maximum = 6600
    }, 0)
  end

  function HueBridge.addLightColor(thing)
    return thing:addProperty('color', {
      ['@type'] = 'ColorProperty',
      title = 'Color',
      type = 'string', -- hexadecimal RGB color code, e.g. #FF0000
      -- Hue has hue and sat properties
      description = 'Color'
    }, 0)
  end

  function HueBridge.createThingForType(type)
    -- see https://developers.meethue.com/develop/hue-api/supported-devices/
    -- type: Daylight, ZLLSwitch, Extended color light, Color temperature light
    -- On/off light, Dimmable light, Color light, ZGPSwitch
    -- CLIPGenericStatus, CLIPSwitch, CLIPOpenClose, CLIPPresence, CLIPTemperature, CLIPHumidity, CLIPLightlevel
    if type == 'Color temperature light' then
      local t = Thing:new('Color temperature light', 'Color temperature light', {'Light', 'OnOffSwitch', 'ColorControl'})
      HueBridge.addLightOnOff(t)
      HueBridge.addLightBrightness(t)
      HueBridge.addLightColorTemperature(t)
      return t
    elseif type == 'Extended color light' then
      local t = Thing:new('Extended color light', 'Extended color light', {'Light', 'OnOffSwitch', 'ColorControl'})
      HueBridge.addLightOnOff(t)
      HueBridge.addLightBrightness(t)
      HueBridge.addLightColorTemperature(t)
      HueBridge.addLightColor(t)
      return t
    elseif type == 'ZLLLightLevel' then
      return Thing:new('Hue Light Level', 'Light Level Sensor', {'MultiLevelSensor'}):addProperty('lightlevel', {
        ['@type'] = 'LevelProperty',
        title = 'Light Level',
        type = 'integer',
        description = 'Light Level',
        minimum = 0,
        readOnly = true,
        unit = 'byte'
      }, 0)
    elseif type == 'ZLLTemperature' then
      return Thing:new('Hue Temperature', 'Temperature Sensor', {'TemperatureSensor'}):addProperty('temperature', {
        ['@type'] = 'TemperatureProperty',
        title = 'Light Level',
        type = 'number',
        description = 'Ambient temperature',
        readOnly = true,
        unit = 'degree celsius'
      }, 0)
    elseif type == 'ZLLPresence' then
      return Thing:new('Hue Motion', 'Motion Sensor', {'MotionSensor'}):addProperty('presence', {
        ['@type'] = 'Motion',
        title = 'Light Level',
        --label = 'Present',
        type = 'boolean',
        description = 'Motion',
        readOnly = true
      }, false)
    elseif type == 'ZLLSwitch' then
      return Thing:new('Pressure', 'Pressure Sensor', {'PushButton'}):addProperty('on', {
        ['@type'] = 'PushedProperty',
        title = 'Switch Button',
        type = 'boolean',
        description = 'Switch Button',
        readOnly = true
      }, false):addEvent('press', {
        ['@type'] = 'LongPressedEvent',
        title = 'Long Press',
        description = 'Indicates the button has been long-pressed'
      })
    elseif type == 'ZHAHumidity' then
      return Thing:new('Humidity', 'Humidity Sensor', {'MultiLevelSensor'}):addProperty('humidity', {
        ['@type'] = 'LevelProperty',
        title = 'Humidity',
        type = 'number',
        description = 'Relative humidity',
        readOnly = true,
        unit = 'percent'
      }, 0)
    elseif type == 'ZHAPressure' then
      return Thing:new('Pressure', 'Pressure Sensor', {'MultiLevelSensor'}):addProperty('pressure', {
        ['@type'] = 'LevelProperty',
        title = 'Pressure',
        type = 'number',
        description = 'Atmospheric Pressure',
        readOnly = true,
        minimum = 800,
        maximum = 1100,
        unit = 'hPa'
      }, 0)
    elseif type == 'ZHASwitch' then
      return Thing:new('Pressure', 'Pressure Sensor', {'PushButton'}):addProperty('on', {
        ['@type'] = 'PushedProperty',
        title = 'Switch Button',
        type = 'boolean',
        description = 'Switch Button',
        readOnly = true
      }, false):addEvent('press', {
        ['@type'] = 'LongPressedEvent',
        title = 'Long Press',
        description = 'Indicates the button has been long-pressed'
      })
    end
  end

end)
