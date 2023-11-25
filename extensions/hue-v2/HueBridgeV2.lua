local logger = require('jls.lang.logger')
local Promise = require('jls.lang.Promise')
local Exception = require('jls.lang.Exception')
local HttpClient = require('jls.net.http.HttpClient')
local HttpMessage = require('jls.net.http.HttpMessage')
local Url = require('jls.net.Url')
local json = require('jls.util.json')
local tables = require('jls.util.tables')
local Date = require('jls.util.Date')
local Map = require('jls.util.Map')
local List = require('jls.util.List')
local strings = require('jls.util.strings')

local Thing = require('lha.Thing')
local utils = require('lha.utils')

local color = {}

function color.mirekToColorTemperature(value)
  return math.floor(1000000 / value)
end

-- see https://github.com/Shnoo/js-CIE-1931-rgb-color-converter/blob/master/ColorConverter.js

local function getGammaCorrectedValue(value)
  if value > 0.04045 then
    return ((value + 0.055) / (1.0 + 0.055)) ^ 2.4
  end
  return value / 12.92
end

function color.rgbToXy(red, green, blue)
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

function color.xyBriToRgb(x, y, Y)
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

local function parseAdapters(rawAdapters, env)
  local adapters = {}
  if rawAdapters then
    for name, rawMap in pairs(rawAdapters) do
      local map = {}
      for key, rawFn in pairs(rawMap) do
        map[key] = load('local value = ...; '..rawFn, 'adapters/'..name..'/'..key, 't', env)
      end
      adapters[name] = map
    end
  end
  return adapters
end

return require('jls.lang.class').create(function(hueBridge)

  function hueBridge:initialize(url, key, mapping)
    self.url = Url:new(url)
    self.key = key or ''
    local path = self.url:getPath()
    if string.sub(path, -1) ~= '/' then
      path = path..'/'
    end
    self.path = path
    self.headers = {
      ['hue-application-key'] = self.key
    }
    self.mapping = mapping or {}
    self.mapping.adapters = parseAdapters(self.mapping.adapters, {
      Thing = Thing,
      color = color
    })
  end

  function hueBridge:close()
    self:closeHttpClient()
  end

  function hueBridge:closeHttpClient()
    if self.client then
      self.client:close()
    end
    self.client = nil
  end

  function hueBridge:getHttpClient()
    if not self.client then
      self.client = HttpClient:new({
        url = self.url,
        secureContext = {
          alpnProtos = {'h2'}
        },
      })
    end
    return self.client
  end

  local function formatBody(body)
    if type(body) == 'table' then
      return json.encode(body)
    elseif type(body) == 'string' then
      return body
    end
  end

  local function rejectResponse(response, reason)
    return response:text():next(function(text)
      logger:fine('response body "%s"', text)
      return Promise.reject(reason)
    end)
  end

  function hueBridge:httpRequest(method, path, body)
    local client = self:getHttpClient()
    logger:fine('httpRequest(%s, %s)', method, path)
    return client:fetch(path or '/', {
      method = method or 'GET',
      headers = self.headers,
      body = formatBody(body),
    }):next(function(response)
      local status, reason = response:getStatusCode()
      logger:finer('response status: %d', status)
      if status ~= 200 then
        -- TODO Process errors content
        -- TODO Use exception
        return rejectResponse(response, string.format('response status is %s', status))
      end
      local contentType = response:getHeader('content-type')
      if not strings.equalsIgnoreCase(contentType, 'application/json') then
        return rejectResponse(response, 'Invalid or missing content type')
      end
      return response:json()
    end):next(function(content)
      if not (type(content) == 'table' and type(content.data) == 'table' and type(content.errors) == 'table') then
        return Promise.reject('Invalid or missing content')
      end
      if #content.errors > 0 then
        return Promise.reject('Error, '..tostring(content.errors[1].description))
      end
      return content.data
    end)
  end

  function hueBridge:getResourceMapById()
    return self:httpRequest('GET', '/clip/v2/resource/device'):next(function(devices)
      local serviceTypeMap = {}
      for _, device in ipairs(devices) do
        if logger:isLoggable(logger.FINEST) then
          logger:finest(json.stringify(device, '  '))
        end
        for _, service in ipairs(device.services) do
          serviceTypeMap[service.rtype] = true
        end
      end
      local rtypes = Map.skeys(serviceTypeMap)
      if logger:isLoggable(logger.FINE) then
        logger:fine('device service rtypes: %s', List.join(rtypes, ', '))
      end
      logger:fine('get device services...')

      local services = {}
      --[[
        return Promise.all(List.map(rtypes, function(rtype)
          return self:httpRequest('GET', '/clip/v2/resource/'..rtype)
        end))
      ]]
      -- as of 2023-10 the bridge cannot handle concurrent requests on h2 stream replying "Oops, there appears to be no lighting here"
      -- https://developers.meethue.com/develop/hue-api-v2/core-concepts/#limitations
      return List.reduce(rtypes, function(p, rtype, index)
        return p:next(function()
          return self:httpRequest('GET', '/clip/v2/resource/'..rtype):next(function(service)
            services[index] = service
          end)
        end)
      end, Promise.resolve()):next(function()
        return services
      end):next(function(services)
        table.insert(services, devices)
        local byId = {}
        for _, items in ipairs(services) do
          for _, item in ipairs(items) do
            if byId[item.id] then
              logger:warn('duplicated id %s', item.id)
            end
            byId[item.id] = item
          end
        end
        return byId
      end)
    end)
  end

  local function buildName(info, resource)
    if type(info) == 'string' then
      return info
    elseif type(info) == 'table' then
      if info.name then
        return info.name
      end
      if info.nameKey and info.nameValues then
        local key = tables.getPath(resource, info.nameKey)
        return key and info.nameValues[tostring(key)]
      end
    end
  end

  function hueBridge:createThingFromDeviceId(resourceMap, id)
    local device = resourceMap[id]
    if not device then
      return nil
    end
    local title = tables.getPath(device, self.mapping.title)
    local description = tables.getPath(device, self.mapping.description)
    local thing = Thing:new(title, description)
    for _, service in ipairs(device.services) do
      local resource = resourceMap[service.rid]
      local properties = self.mapping.types[service.rtype]
      if resource and properties then
        for path, info in pairs(properties) do
          local value = tables.getPath(resource, path)
          if value ~= nil then
            local name = buildName(info, resource)
            if info.metadata then
              thing:addPropertyFrom(name, info.metadata)
            else
              thing:addPropertyFromName(name)
            end
          end
        end
      end
    end
    return thing
  end

  function hueBridge:getAdapter(info, kind)
    if info.adapter then
      local adapter = self.mapping.adapters[info.adapter]
      if adapter then
        return adapter[kind]
      end
    end
  end

  function hueBridge:updateThing(thing, resourceMap, id)
    local device = resourceMap[id]
    if device then
      for _, service in ipairs(device.services) do
        local resource = resourceMap[service.rid]
        local properties = self.mapping.types[service.rtype]
        if resource and properties then
          for path, info in pairs(properties) do
            local value = tables.getPath(resource, path)
            if value ~= nil then
              local name = buildName(info, resource)
              local adapt = self:getAdapter(info, 'get')
              if adapt then
                value = adapt(value)
              end
              thing:updatePropertyValue(name, value)
            end
          end
        end
      end
    end
  end

  function hueBridge:setThingPropertyValue(resourceMap, id, name, value)
    local device = resourceMap[id]
    if device then
      for _, service in ipairs(device.services) do
        local resource = resourceMap[service.rid]
        local properties = self.mapping.types[service.rtype]
        if resource and properties then
          for path, info in pairs(properties) do
            local n = buildName(info, resource)
            if n == name then
              local adapt = self:getAdapter(info, 'set')
              if adapt then
                value = adapt(value)
              end
              local body = {}
              tables.setPath(body, path, value)
              return self:httpRequest('PUT', '/clip/v2/resource/'..service.rtype..'/'..service.rid, body)
            end
          end
        end
      end
    end
    return Promise.reject()
  end

end, function(HueBridge)

  HueBridge.color = color

end)
