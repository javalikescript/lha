local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local Exception = require('jls.lang.Exception')
local HttpClient = require('jls.net.http.HttpClient')
local StreamHandler = require('jls.io.StreamHandler')
local ChunkedStreamHandler = require('jls.io.streams.ChunkedStreamHandler')
local Url = require('jls.net.Url')
local json = require('jls.util.json')
local tables = require('jls.util.tables')
local Map = require('jls.util.Map')
local List = require('jls.util.List')
local strings = require('jls.util.strings')

local Thing = require('lha.Thing')
local utils = require('lha.utils')

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
    self.mapping = utils.replaceRefs(mapping or {}, {
      Thing = Thing,
      color = utils,
      math = math,
      -- one of initial_press, repeat, short_release, long_release, double_short_release, long_press
      BUTTON_EVENT = {
        ['initial_press'] = 'pressed',
        ['repeat'] = 'hold',
        ['short_release'] = 'released',
        ['long_release'] = 'long-released',
        ['double_short_release'] = 'long-released',
        ['long_press'] = 'pressed',
      },
      BUTTON_NAME = {'On', 'DimUp', 'DimDown', 'Off'},
    })
  end

  function hueBridge:close()
    self:closeHttpClient()
  end

  function hueBridge:closeHttpClient()
    if self.client then
      self:stopEventStream()
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
      self.bridgeResource = nil
      --[[
        return Promise.all(List.map(rtypes, function(rtype)
          return self:httpRequest('GET', '/clip/v2/resource/'..rtype)
        end))
      ]]
      -- as of 2023-10 the bridge cannot handle concurrent requests on h2 stream replying "Oops, there appears to be no lighting here"
      -- https://developers.meethue.com/develop/hue-api-v2/core-concepts/#limitations
      return List.reduce(rtypes, function(p, rtype, index)
        return p:next(function(services)
          return self:httpRequest('GET', '/clip/v2/resource/'..rtype):next(function(service)
            services[index] = service
            return services
          end)
        end)
      end, Promise.resolve({})):next(function(services)
        table.insert(services, devices)
        local byId = {}
        for _, items in ipairs(services) do
          for _, item in ipairs(items) do
            if byId[item.id] then
              logger:warn('duplicated id %s', item.id)
            end
            byId[item.id] = item
            if item.type == 'bridge' then
              self.bridgeResource = item
            end
          end
        end
        return byId
      end)
    end)
  end

  function hueBridge:checkEventStream()
    if self.onEvents then
      if self.responseStream and self.client and not self.client:isClosed() then
        if self.client.http2 then
          logger:finer('pinging...')
          self.client.http2:sendPing():next(function()
            logger:fine('ping success')
          end, function(reason)
            logger:warn('ping failure "%s"', reason)
            self:closeEventStream()
          end)
        end
      else
        self:fetchEventStream()
      end
    end
  end

  function hueBridge:startEventStream(onEvents)
    self.onEvents = onEvents
    self:fetchEventStream()
  end

  function hueBridge:publishEvents(events)
    if self.onEvents then
      local status, e = Exception.pcall(self.onEvents, events)
      if not status then
        logger:warn('Hue event callback error "%s" with payload: %s', e, json.stringify(events))
      end
    end
  end

  function hueBridge:updateConnectedState(value)
    logger:fine('updateConnectedState(%s)', value)
    if self.bridgeResource then
      self:publishEvents({
        {
          type = 'update',
          data = {
            id = self.bridgeResource.id,
            owner = {
              rid = self.bridgeResource.owner.rid,
              rtype = 'device'
            },
            connected = value == true
          }
        }
      })
    end
  end

  function hueBridge:fetchEventStream()
    logger:fine('Hue V2 fetch event stream')
    self:closeEventStream()
    local client = self:getHttpClient()
    client:fetch('/eventstream/clip/v2', {
      method = 'GET',
      headers = Map.assign({Accept = 'text/event-stream'}, self.headers)
    }):next(function(response)
      if response:getStatusCode() ~= 200 then
        logger:warn('Hue V2 event stream response status: %d', response:getStatusCode())
        self:closeEventStream()
        return
      end
      self.responseStream = response
      self:updateConnectedState(true)
      local sh = StreamHandler:new(function(err, rawEvent)
        if err then
          logger:warn('Hue event error: "%s"', err)
          self:closeEventStream()
        elseif rawEvent then
          logger:fine('event: "%s"', rawEvent)
          local index = string.find(rawEvent, 'data: ', 1, true)
          if index then
            local status, events = pcall(json.parse, string.sub(rawEvent, index + 6))
            if status and type(events) == 'table' then
              self:publishEvents(events)
            else
              logger:warn('Hue event received invalid "%s" JSON payload: "%s"', events, rawEvent)
            end
          elseif rawEvent == 'hi' or rawEvent == ': hi' then -- seems broken since 1962097030
            logger:info('Hue V2 event stream connected')
          else
            logger:warn('Hue event received invalid payload: "%s"', rawEvent)
          end
        else
          logger:fine('Hue event stream no data')
          self:closeEventStream()
        end
      end)
      local csh = ChunkedStreamHandler:new(sh, '\n\n', true)
      if logger:isLoggable(logger.FINEST) then
        csh = StreamHandler.tee(csh, StreamHandler:new(function(err, data)
          logger:finest('event: %s, %s', err, (string.gsub(data, '%c', function(c)
            return string.format('%%%02X', string.byte(c))
          end)))
        end))
      end
      response:setBodyStreamHandler(csh)
      logger:fine('Hue V2 consume event stream')
      return response:consume()
    end):next(function()
      logger:info('event stream ended')
    end, function(reason)
      logger:warn('event stream error: %s', reason)
    end)
  end

  function hueBridge:closeEventStream()
    if self.responseStream then
      self.responseStream:close()
      self.responseStream = nil
      self:updateConnectedState(false)
    end
  end

  function hueBridge:stopEventStream()
    self.onEvents = nil
    self:closeEventStream()
  end

  local function buildName(info, resource)
    return utils.expand(info.name, resource, info)
  end

  function hueBridge:createThingFromDeviceId(resourceMap, id)
    local device = resourceMap[id]
    if device and device.type == 'device' then
      local title = utils.expand(self.mapping.title, device)
      local description = utils.expand(self.mapping.description, device)
      local thing = Thing:new(title, description)
      for _, service in ipairs(device.services) do
        local resource = resourceMap[service.rid]
        local type = self.mapping.types[service.rtype]
        if resource and type then
          if type.capabilities then
            for _, capability in ipairs(type.capabilities) do
              thing:addType(capability)
            end
          end
          for _, info in ipairs(type.properties) do
            local value = info.path and tables.getPath(resource, info.path)
            if utils.isValue(value) or info.mandatory then
              local name = buildName(info, resource)
              utils.addThingPropertyFromInfo(thing, name, info, resource)
            end
          end
        end
      end
      if next(thing:getProperties()) then
        return thing
      end
    end
  end

  function hueBridge:updateThingResource(thing, resource, data, isEvent)
    local type = self.mapping.types[resource.type]
    if type then
      for _, info in ipairs(type.properties) do
        local value = info.path and tables.getPath(data, info.path)
        local isValue = utils.isValue(value)
        if isValue then
          local name = buildName(info, resource)
          if info.adapter then
            value = info.adapter(value)
            isValue = utils.isValue(value)
          end
          if isValue then
            local publish = false
            if isEvent and value == 'hold' and info.path == 'button/button_report/event' then
              publish = true
            end
            thing:updatePropertyValue(name, value, publish)
          end
        end
      end
    end
  end

  function hueBridge:updateThing(thing, resourceMap, id)
    local device = resourceMap[id]
    if device then
      for _, service in ipairs(device.services) do
        local resource = resourceMap[service.rid]
        if resource and resource.type == service.rtype then
          self:updateThingResource(thing, resource, resource)
        end
      end
    end
  end

  function hueBridge:setResourceValue(resourceMap, id, name, value)
    local device = resourceMap[id]
    if device then
      for _, service in ipairs(device.services) do
        local resource = resourceMap[service.rid]
        local type = self.mapping.types[service.rtype]
        if resource and type then
          for _, info in ipairs(type.properties) do
            local n = buildName(info, resource)
            if n == name then
              if info.setAdapter then
                value = info.setAdapter(value)
              end
              local body = {}
              tables.setPath(body, info.path, value)
              return self:httpRequest('PUT', '/clip/v2/resource/'..service.rtype..'/'..service.rid, body)
            end
          end
        end
      end
    end
    return Promise.reject(string.format('cannot set value "%s" for resource id "%s"', name, id))
  end

end)
