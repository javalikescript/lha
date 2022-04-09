local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local protectedCall = require('jls.lang.protectedCall')
local http = require('jls.net.http')
local Url = require('jls.net.Url')
local WebSocket = require('jls.net.http.ws').WebSocket
local json = require('jls.util.json')
local Date = require('jls.util.Date')
local Map = require('jls.util.Map')

local Thing = require('lha.Thing')

--[[
  ZigBee Home Automation
  Generic Devices
    On/Off Switch
    On/Off Output
    Remote Control
    Door Lock
    Door Lock Controller
    Simple Sensor
    Smart Plug
  Lighting Devices
    On/Off Light
    Dimmable Light
    Colour Dimmable Light
    On/Off Light Switch
    Dimmer Switch
    Colour Dimmer Switch
    Light Sensor
    Occupancy Sensor
  ZigBee Light Link
  Lighting Devices
    On/Off Light
    On/Off Plug-in Unit
    Dimmable Light
    Dimmable Plug-in Unit
    Colour Light
    Extended Colour Light
    Colour Temperature Light
    ZLL Device Device ID
  Controller Devices
    Colour Controller
    Colour Scene Controller
    Non-Colour Controller
    Non-Colour Scene Controller
    Control Bridge
    On/Off Sensor
]]

local CONST = {
  sensors = 'sensors',
  groups = 'groups',
  lights = 'lights',
  rules = 'rules',
  config = 'config',
  state = 'state',
  resourcelinks = 'resourcelinks',
  capabilities = 'capabilities',
  schedules = 'schedules',
}

local DEVICE = {
  ColorTemperatureLight = 'ColorTemperatureLight',
  ExtendedColorLight = 'ExtendedColorLight',
  DimmableLight = 'DimmableLight',
  OnOffLight = 'OnOffLight',
  LightLevelSensor = Thing.CAPABILITIES.LightLevelSensor,
  MotionSensor = Thing.CAPABILITIES.MotionSensor,
  TemperatureSensor = Thing.CAPABILITIES.TemperatureSensor,
  HumiditySensor = Thing.CAPABILITIES.HumiditySensor,
  BarometricPressureSensor = Thing.CAPABILITIES.BarometricPressureSensor,
  PushButton = Thing.CAPABILITIES.PushButton,
}

-- see https://developers.meethue.com/develop/hue-api/supported-devices/
-- type: Daylight, ZLLSwitch, Extended color light, Color temperature light
-- On/off light, Dimmable light, Color light, ZGPSwitch
-- CLIPGenericStatus, CLIPSwitch, CLIPOpenClose, CLIPPresence, CLIPTemperature, CLIPHumidity, CLIPLightlevel
-- ZLL:  ZigBee Light Link, ZHA: ZigBee Home Automation
local deviceByType = {
  ['Color temperature light'] = DEVICE.ColorTemperatureLight,
  ['Extended color light'] = DEVICE.ExtendedColorLight,
  ['Dimmable light'] = DEVICE.DimmableLight,
  ['Dimmable plug-in unit'] = DEVICE.DimmableLight,
  ['On/Off light'] = DEVICE.OnOffLight, 
  ['On/Off plug-in unit'] = DEVICE.OnOffLight,
  ['ZLLLightLevel'] = DEVICE.LightLevelSensor,
  ['ZHALightLevel'] = DEVICE.LightLevelSensor,
  ['ZLLTemperature'] = DEVICE.TemperatureSensor,
  ['ZHATemperature'] = DEVICE.TemperatureSensor,
  ['ZLLPresence'] = DEVICE.MotionSensor,
  ['ZHAPresence'] = DEVICE.MotionSensor,
  ['ZLLSwitch'] = DEVICE.PushButton,
  ['ZHASwitch'] = DEVICE.PushButton,
  ['ZHAHumidity'] = DEVICE.HumiditySensor,
  ['ZHAPressure'] = DEVICE.BarometricPressureSensor,
  --['Daylight'] = 0,
}

local capabilitiesByDevice = {
  [DEVICE.ColorTemperatureLight] = {Thing.CAPABILITIES.Light, Thing.CAPABILITIES.OnOffSwitch, Thing.CAPABILITIES.ColorControl},
  [DEVICE.ExtendedColorLight] = {Thing.CAPABILITIES.Light, Thing.CAPABILITIES.OnOffSwitch, Thing.CAPABILITIES.ColorControl},
  [DEVICE.DimmableLight] = {Thing.CAPABILITIES.Light, Thing.CAPABILITIES.OnOffSwitch},
  [DEVICE.OnOffLight] = {Thing.CAPABILITIES.OnOffSwitch},
  [DEVICE.LightLevelSensor] = {Thing.CAPABILITIES.LightSensor},
  [DEVICE.TemperatureSensor] = {Thing.CAPABILITIES.TemperatureSensor},
  [DEVICE.MotionSensor] = {Thing.CAPABILITIES.MotionSensor},
  [DEVICE.PushButton] = {Thing.CAPABILITIES.PushButton},
  [DEVICE.HumiditySensor] = {Thing.CAPABILITIES.HumiditySensor},
  [DEVICE.BarometricPressureSensor] = {Thing.CAPABILITIES.BarometricPressureSensor},
}

local namesByDevice = {
  [DEVICE.ColorTemperatureLight] = {'on', 'brightness', 'colorTemperature'},
  [DEVICE.ExtendedColorLight] = {'on', 'brightness', 'colorTemperature', 'color'},
  [DEVICE.DimmableLight] = {'on', 'brightness'},
  [DEVICE.OnOffLight] = {'on'},
  [DEVICE.LightLevelSensor] = {'lightlevel'},
  [DEVICE.TemperatureSensor] = {'temperature'},
  [DEVICE.MotionSensor] = {'presence', 'battery', 'enabled', 'sensitivity'},
  [DEVICE.PushButton] = {'battery'},
  [DEVICE.HumiditySensor] = {'humidity'},
  [DEVICE.BarometricPressureSensor] = {'pressure'},
}

local titleByDevice = {
  [DEVICE.LightLevelSensor] = 'Light Level',
  [DEVICE.TemperatureSensor] = 'Temperature',
  [DEVICE.MotionSensor] = 'Motion',
  [DEVICE.PushButton] = 'Switch',
  [DEVICE.HumiditySensor] = 'Relative Humidity',
  [DEVICE.BarometricPressureSensor] = 'Atmospheric Pressure',
}

local categoryByName = {
  on = CONST.state,
  brightness = CONST.state,
  colorTemperature = CONST.state,
  color = CONST.state,
  lightlevel = CONST.state,
  presence = CONST.state,
  humidity = CONST.state,
  temperature = CONST.state,
  pressure = CONST.state,
  lastupdated = CONST.state,
  buttonevent = CONST.state,
  battery = CONST.config,
  enabled = CONST.config,
  reachable = CONST.config,
  ledindication = CONST.config,
  sensitivity = CONST.config,
}

local allNames = Map.keys(categoryByName)

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

local function isValue(value)
  return value ~= nil and value ~= json.null
end

local function computeBrightness(info)
  local value = (info.state or {}).bri
  if type(value) == 'number' then
    -- Hue Brightness is 0-255
    return math.floor(value * 100 / 255)
  end
end

local function toPostBrightness(value)
  return {bri = math.floor(value * 255 / 100)}
end

local function computeColorTemperature(info)
  local value = (info.state or {}).ct
  if type(value) == 'number' then
    -- Mirek color temperature, M=1000000/T, Hue 2012 connected lamps are capable of 153 (6500K) to 500 (2000K)
    return math.floor(1000000 / value)
  end
end

local function toPostColorTemperature(value)
  return {ct = math.floor(1000000 / value)}
end

local function computeColor(info)
  local state = info.state
  if state and isValue(state.hue) and isValue(state.sat) and isValue(state.bri) then
    -- Hue has hue and sat properties
    return Thing.hsvToRgbHex(state.hue / 65535, state.sat / 254, state.bri / 254)
  end
end

local function toPostColor(value)
  local h, s, v = Thing.rgbHexToHsv(value)
  return {
    hue = math.floor(h * 65535),
    sat = math.floor(s * 254),
    bri = math.floor(v * 254)
  }
end

local function computeLightLevel(info)
  local value = (info.state or {}).lightlevel
  if type(value) == 'number' then
    --[[
      From ZigBee Cluster Library
      u16IlluminanceTargetLevel is a mandatory attribute representing the illuminance level at the centre of the target band. 
      The value of this attribute is calculated as 10000 x log10(Illuminance) where Illuminance is measured in Lux (lx) and can take values in the range 1 lx ≤Illuminance≤ 3.576x106 lx,
      corresponding to attribute values in the range 0x0000 to 0xFFFE. The value 0xFFFF is used to indicate that the attribute is invalid.
    ]]
    -- ConBee examples: 9614=>9 0=>0
    -- From Hue Dev: Light level in 10000 log10 (lux) +1 measured by info.
    -- Logarithm scale used because the human eye adjusts to light levels and small changes at low lux levels are more noticeable than at high lux levels.
    return value
  end
end

local function computeIlluminance(info)
  local value = (info.state or {}).lightlevel
  if type(value) == 'number' then
    return math.floor(10 ^ ((value - 1) / 10000))
  end
end

local function computeTemperature(info)
  local value = (info.state or {}).temperature
  if type(value) == 'number' then
    -- Current temperature in 0.01 degrees Celsius. (3000 is 30.00 degree)
    return value / 100
  end
end

local function computeHumidity(info)
  local value = (info.state or {}).humidity
  if type(value) == 'number' then
    return value / 100
  end
end

local function computeEnabled(info)
  return (info.config or {}).on
end

local function toPostEnabled(value)
  return {on = value}
end

local function getInfoProperty(info, name)
  local category = categoryByName[name]
  if category then
    local t = info[category]
    if t then
      local value = t[name]
      if isValue(value) then
        return value
      end
    end
  end
end

local function toPost(value, name)
  return {[name] = value}
end

local computeFnByName = {
  brightness = computeBrightness,
  colorTemperature = computeColorTemperature,
  color = computeColor,
  lightlevel = computeLightLevel,
  humidity = computeHumidity,
  temperature = computeTemperature,
  enabled = computeEnabled,
}

local toPostFnByName = {
  brightness = toPostBrightness,
  colorTemperature = toPostColorTemperature,
  color = toPostColor,
  enabled = toPostEnabled,
}

local function updateValue(thing, info, name)
  local computeFn = computeFnByName[name] or getInfoProperty
  local value = computeFn(info, name)
  if isValue(value) then
    thing:updatePropertyValue(name, value)
  end
end

local function updateValues(thing, info, names)
  for _, name in ipairs(names) do
    updateValue(thing, info, name)
  end
end

local function lazyUpdateValue(thing, info, name)
  if thing:hasProperty(name) then
    updateValue(thing, info, name)
  end
end

return require('jls.lang.class').create(function(hueBridge)

  function hueBridge:initialize(url, user, onWebSocket)
    self.user = user or ''
    self.url = url or ''
    self.delta = 0
    self.onWebSocket = onWebSocket
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
      self.wsUrl = Url:new('ws', tUrl.host, config.websocketport):toString()
      self:checkWebSocket()
    end
  end

  function hueBridge:close()
    self:closeWebSocket()
  end

  function hueBridge:startWebSocket()
    local webSocket = Map.assign(WebSocket:new(self.wsUrl), {
      onClose = function()
        logger:info('Hue WebSocket closed')
        self.ws = nil
      end,
      onTextMessage = function(webSocket, payload)
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
    })
    self:closeWebSocket()
    webSocket:open():next(function()
      webSocket:readStart()
      logger:info('Hue WebSocket connect on '..tostring(self.wsUrl))
      self.ws = webSocket
    end, function(reason)
      logger:warn('Cannot open Hue WebSocket on '..tostring(self.wsUrl)..' due to '..tostring(reason))
    end)
  end

  function hueBridge:closeWebSocket()
    if self.ws then
      self.ws:close(false)
      self.ws = nil
    end
  end

  function hueBridge:isWebSocketConnected()
    return self.ws ~= nil
  end

  function hueBridge:checkWebSocket()
    if self.onWebSocket and not self.ws and self.wsUrl then
      self:startWebSocket()
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
    return self:get(CONST.config):next(function(config)
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

  function hueBridge:lazyUpdateThing(thing, info)
    for _, name in ipairs(allNames) do
      lazyUpdateValue(thing, info, name)
    end
  end

  function hueBridge:updateThing(thing, info)
    local alias = deviceByType[info.type]
    if alias then
      local names = namesByDevice[alias]
      if names then
        updateValues(thing, info, names)
      end
    end
  end

  function hueBridge:setThingPropertyValue(thing, id, name, value)
    local category = categoryByName[name]
    local toPostFn = toPostFnByName(name) or toPost
    local t = toPostFn(value, name)
    local path
    if thing:hasType(Thing.CAPABILITIES.OnOffSwitch) or thing:hasType(Thing.CAPABILITIES.Light) then
      path = CONST.lights
    elseif thing:hasType(Thing.CAPABILITIES.MotionSensor) then
      path = CONST.sensors
    end
    if path and category and t then
      self:put(path..'/'..id..'/'..category, t)
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
  HueBridge.DEVICE = DEVICE

  local PROPERTY_METADATA_BY_NAME = {
    sensitivity = {
      ['@type'] = 'LevelProperty',
      type = 'integer',
      title = 'Sensitivity Level',
      description = 'The sensor sensitivity',
      configuration = true,
    },
  }

  function HueBridge.createThingForType(info)
    local alias = deviceByType[info.type]
    if not alias then
      logger:warn('Unknown type "'..tostring(info.type)..'"')
      return
    end
    local capabilities = capabilitiesByDevice[alias]
    if not capabilities then
      logger:warn('Missing capabilities for "'..tostring(info.type)..'" ('..tostring(alias)..')')
      return
    end
    local names = namesByDevice[alias]
    if not capabilities then
      logger:warn('Missing names for "'..tostring(info.type)..'" ('..tostring(alias)..')')
      return
    end
    local title = titleByDevice[alias] or info.type
    local t = Thing:new(info.name or title, title, capabilities)
    for _, name in ipairs(names) do
      local md = PROPERTY_METADATA_BY_NAME[name]
      if md then
        t:addPropertyFrom(name, md)
      else
        t:addPropertyFromName(name)
      end
    end
    return t
  end

end)
