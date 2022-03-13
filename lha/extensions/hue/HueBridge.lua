local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local http = require('jls.net.http')
local Url = require('jls.net.Url')
local json = require('jls.util.json')
local Date = require('jls.util.Date')
local protectedCall = require('jls.lang.protectedCall')
local WebSocket = require('jls.net.http.ws').WebSocket

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

  function hueBridge:initialize(url, user, onWebSocket)
    self.user = user or ''
    self.url = url or ''
    self.delta = 0
    self.onWebSocket = onWebSocket
  end

  function hueBridge:close()
    if self.ws then
      self.ws:close(false)
      self.ws = nil
    end
  end

  function hueBridge:configure(config)
    if config.UTC then
      local bridgeTime = Date.fromISOString(config.UTC, true)
      --local time = Date.UTC()
      local time = Date.now()
      self.delta = time - bridgeTime
      logger:info('Bridge time '..config.UTC..' '..Date:new(bridgeTime):toISOString()..' time: '..Date:new(time):toISOString())
    else
      self.delta = 0
    end
    logger:info('Using bridge delta time: '..tostring(self.delta))
    if config.devicename then
      logger:info('Hue device is '..tostring(config.devicename))
    end
    if config.websocketport then
      -- config.websocketnotifyall
      local tUrl = Url.parse(self.url)
      local wsUrl = Url:new('ws', tUrl.host, config.websocketport):toString()
      if self.onWebSocket and not self.ws then
        local webSocket = WebSocket:new(wsUrl)
        self.ws = webSocket
        webSocket:open():next(function()
          webSocket:readStart()
          logger:info('Hue WebSocket connect on '..tostring(wsUrl))
        end, function(reason)
          logger:warn('Cannot open Hue WebSocket on '..tostring(wsUrl)..' due to '..tostring(reason))
        end)
        webSocket.onTextMessage = function(_, payload)
          if logger:isLoggable(logger.FINER) then
            logger:finer('Hue WebSocket received '..tostring(payload))
          end
          local status, info = protectedCall(json.decode, payload)
          if status then
            if type(info) == 'table' and info.t == 'event' then
              status, info = protectedCall(self.onWebSocket, info)
              if not status then
                logger:warn('Hue WebSocket callback error "'..tostring(info)..'" with payload '..tostring(payload))
                webSocket:close(false)
              end
            end
          else
            logger:warn('Hue WebSocket received invalid JSON payload '..tostring(payload))
            webSocket:close(false)
          end
        end
      end
    end
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
      local status, reason = response:getStatusCode()
      if status ~= 200 then
        return Promise.reject(tostring(status)..': '..tostring(reason))
      end
      return response:getBody()
    end)
    --return http.request(self.url..self.user..'/'..path)
  end

  function hueBridge:httpJson(method, path, value)
    local b
    if value then
      b = json.encode(value)
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
    -- [{"success":{"username": "abcdef0123456789"}}]
    return self:httpJson('POST', '', {
      devicetype = applicationName..'#'..deviceName
    })
  end

  local function isValue(value)
    return value ~= nil and value ~= json.null
  end

  local function computeBrightness(state)
    if isValue(state.bri) then
      -- Hue Brightness is 0-255
      return math.floor(state.bri * 100 / 255)
    end
  end

  local function computeColorTemperature(state)
    if isValue(state.ct) then
      -- Mirek color temperature, M=1000000/T, Hue 2012 connected lamps are capable of 153 (6500K) to 500 (2000K)
      return math.floor(1000000 / state.ct)
    end
  end

  local function computeColor(state)
    if isValue(state.hue) and isValue(state.sat) and isValue(state.bri) then
      -- Hue has hue and sat properties
      return Thing.hsvToRgbHex(state.hue / 65535, state.sat / 254, state.bri / 254)
    end
  end

  local function computeLightLevel(state)
    if isValue(state.lightlevel) then
      --[[
        From ZigBee Cluster Library
        u16IlluminanceTargetLevel is a mandatory attribute representing the illuminance level at the centre of the target band. 
        The value of this attribute is calculated as 10000 x log10(Illuminance) where Illuminance is measured in Lux (lx) and can take values in the range 1 lx ≤Illuminance≤ 3.576x106 lx,
        corresponding to attribute values in the range 0x0000 to 0xFFFE. The value 0xFFFF is used to indicate that the attribute is invalid.
      ]]
      -- ConBee examples: 9614=>9 0=>0
      -- From Hue Dev: Light level in 10000 log10 (lux) +1 measured by info.
      -- Logarithm scale used because the human eye adjusts to light levels and small changes at low lux levels are more noticeable than at high lux levels.  
      return state.lightlevel
    end
  end

  local function computeIlluminance(state)
    if isValue(state.lightlevel) then
      return math.floor(10 ^ ((state.lightlevel - 1) / 10000))
    end
  end

  local function computeTemperature(state)
    if isValue(state.temperature) then
      -- Current temperature in 0.01 degrees Celsius. (3000 is 30.00 degree)
      return state.temperature / 100
    end
  end

  local function computeHumidity(state)
    if isValue(state.humidity) then
      return state.humidity / 100
    end
  end

  local computeFnByName = {
    brightness = computeBrightness,
    colorTemperature = computeColorTemperature,
    color = computeColor,
    lightlevel = computeLightLevel,
    humidity = computeHumidity,
    temperature = computeTemperature,
  }

  local function updateValue(thing, state, name)
    local computeFn = computeFnByName[name]
    local value = computeFn and computeFn(state) or state[name]
    if isValue(value) then
      thing:updatePropertyValue(name, value)
    end
  end

  local function updateValues(thing, state, names)
    for _, name in ipairs(names) do
      updateValue(thing, state, name)
    end
  end

  local function lazyUpdateValue(thing, state, name)
    if thing:hasProperty(name) then
      updateValue(thing, state, name)
    end
  end

  local function lazyUpdateValues(thing, state, names)
    for _, name in ipairs(names) do
      lazyUpdateValue(thing, state, name)
    end
  end

  local allNames = {
    'on',
    'brightness',
    'colorTemperature',
    'color',
    'lightlevel',
    'presence',
    'humidity',
    'temperature',
    'pressure',
  }

  function hueBridge:lazyUpdateThing(thing, info)
    if info.state then
      lazyUpdateValues(thing, info.state, allNames)
    end
  end

  local namesByType = {
    ['Color temperature light'] = {'on', 'brightness', 'colorTemperature'},
    ['Extended color light'] = {'on', 'brightness', 'colorTemperature', 'color'},
    ['Dimmable light'] = {'on', 'brightness'},
    ['On/Off plug-in unit'] = {'on'},
    ['On/Off light'] = {'on'},
    ['ZLLLightLevel'] = {'lightlevel'},
    ['ZHALightLevel'] = {'lightlevel'},
    ['ZLLTemperature'] = {'temperature'},
    ['ZHATemperature'] = {'temperature'},
    ['ZLLPresence'] = {'presence'},
    ['ZHAPresence'] = {'presence'},
    --['ZLLSwitch'] = {''},
    --['ZHASwitch'] = {''},
    ['ZHAHumidity'] = {'humidity'},
    ['ZHAPressure'] = {'pressure'},
  }

  function hueBridge:updateThing(thing, info, time, lastPollTime)
    if info.type == 'ZLLPresence' or info.type == 'ZHAPresence' then
      local infoState = info.state
      if isValue(infoState.presence) then
        local lastupdatedTime
        if infoState.lastupdated and infoState.lastupdated ~= json.null then
          lastupdatedTime = self:parseDateTime(infoState.lastupdated)
        end
        local updatedDuringLastPoll = lastupdatedTime and lastPollTime and lastupdatedTime >= lastPollTime and lastupdatedTime < time
          -- presence True if info detects presence
        -- lastupdated Last time the info state was updated, probably UTC
        -- see https://developers.meethue.com/develop/hue-api/supported-devices/
        if lastupdatedTime and lastPollTime then
          thing:updatePropertyValue('presence', updatedDuringLastPoll)
        else
          thing:updatePropertyValue('presence', infoState.presence)
        end
      end
    else
      local names = namesByType[info.type]
      if names then
        updateValues(thing, info.state, names)
      end
    end
  end

  function hueBridge:setThingPropertyValue(thing, id, name, value)
    if name == 'on' and thing:hasType('Light') then -- and thing:hasType('OnOffSwitch')
      self:put(CONST.LIGHTS..'/'..id..'/state', {on = value})
    end
    if name == 'brightness' and thing:hasType('Light') then
      self:put(CONST.LIGHTS..'/'..id..'/state', {bri = math.floor(value * 255 / 100)})
    end
    if name == 'colorTemperature' and thing:hasType('ColorControl') then
      self:put(CONST.LIGHTS..'/'..id..'/state', {ct = math.floor(1000000 / value)})
    end
    if name == 'color' and thing:hasType('ColorControl') then
      local h, s, v = Thing.rgbHexToHsv(value)
      self:put(CONST.LIGHTS..'/'..id..'/state', {hue = math.floor(h * 65535), sat = math.floor(s * 254), bri = math.floor(v * 254)})
    end
  end

  function hueBridge:connectThing(thing, id)
    --thing.hueId = id
    return thing:connect(function(t, name, value)
      self:setThingPropertyValue(t, id, name, value)
    end)
  end

end, function(HueBridge)

  HueBridge.CONST = CONST

  function HueBridge.createThingForType(info)
    -- see https://developers.meethue.com/develop/hue-api/supported-devices/
    -- type: Daylight, ZLLSwitch, Extended color light, Color temperature light
    -- On/off light, Dimmable light, Color light, ZGPSwitch
    -- CLIPGenericStatus, CLIPSwitch, CLIPOpenClose, CLIPPresence, CLIPTemperature, CLIPHumidity, CLIPLightlevel
    local infoType = info.type
    if infoType == 'Color temperature light' then
      local t = Thing:new(info.name or 'Color temperature light', 'Color temperature light', {'Light', 'OnOffSwitch', 'ColorControl'})
      return t:addOnOffProperty():addBrightnessProperty():addColorTemperatureProperty()
    elseif infoType == 'Extended color light' then
      local t = Thing:new(info.name or 'Extended color light', 'Extended color light', {'Light', 'OnOffSwitch', 'ColorControl'})
      return t:addOnOffProperty():addBrightnessProperty():addColorTemperatureProperty():addColorProperty()
    elseif infoType == 'Dimmable light' then
      local t = Thing:new(info.name or 'Dimmable light', 'Dimmable light', {'Light', 'OnOffSwitch'})
      return t:addOnOffProperty():addBrightnessProperty():addColorTemperatureProperty()
    elseif infoType == 'On/Off plug-in unit' or infoType == 'On/Off light' then
      local t = Thing:new(info.name or 'On/Off light', 'On/Off light', {'Light', 'OnOffSwitch'})
      return t:addOnOffProperty()
    elseif infoType == 'ZLLLightLevel' or infoType == 'ZHALightLevel' then
      return Thing:new(info.name or 'Light Level', 'Light Level Sensor', {'MultiLevelSensor'}):addLightLevelProperty()
    elseif infoType == 'ZLLTemperature' or infoType == 'ZHATemperature' then
      return Thing:new(info.name or 'Temperature', 'Temperature Sensor', {'TemperatureSensor'}):addTemperatureProperty()
    elseif infoType == 'ZLLPresence' or infoType == 'ZHAPresence' then
      return Thing:new(info.name or 'Presence', 'Motion Sensor', {'MotionSensor'}):addPresenceProperty()
    elseif infoType == 'ZLLSwitch' then
      return Thing:new(info.name or 'Switch', 'Switch Button', {'PushButton'}):addProperty('on', {
        ['@type'] = 'PushedProperty',
        title = 'Switch Button',
        type = 'boolean',
        description = 'Switch Button',
        readOnly = true
      }, false)
    elseif infoType == 'ZHAHumidity' then
      return Thing:new(info.name or 'Relative Humidity', 'Humidity Sensor', {'MultiLevelSensor'}):addRelativeHumidityProperty()
    elseif infoType == 'ZHAPressure' then
      return Thing:new(info.name or 'Atmospheric Pressure', 'Pressure Sensor', {'MultiLevelSensor'}):addAtmosphericPressureProperty()
    elseif infoType == 'ZHASwitch' then
      return Thing:new(info.name or 'Switch', 'Switch Button', {'PushButton'}):addProperty('on', {
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
