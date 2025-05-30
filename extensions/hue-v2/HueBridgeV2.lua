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

local function formatBody(body)
  if type(body) == 'table' then
    return json.encode(body)
  elseif type(body) == 'string' then
    return body
  end
end

local function processResponse(response)
  local status, reason = response:getStatusCode()
  logger:finer('response status %d "%s"', status, reason)
  local contentType = response:getHeader('content-type')
  if not strings.equalsIgnoreCase(contentType, 'application/json') then
    return response:text():next(function(text)
      logger:fine('response body "%s"', text)
      return Promise.reject('Invalid or missing content type')
    end)
  end
  return response:json():next(function(content)
    if not (type(content) == 'table' and type(content.data) == 'table' and type(content.errors) == 'table') then
      logger:fine('response content %T', content)
      return Promise.reject('Invalid or missing content')
    end
    if status == 200 then
      return content.data
    end
    local descriptions = {}
    for _, item in ipairs(content.errors) do
      if type(item.description) == 'string' then
        table.insert(descriptions, item.description)
      end
    end
    local description = table.concat(descriptions, ', ')
    if status == 207 then
      if #description > 0 then
        logger:info('Errors in response: %s', description)
      end
      return content.data
    end
    return Promise.reject(string.format('Bad status (%d) %s', status, description))
  end)
end

local function processResponseV1(response)
  local status, reason = response:getStatusCode()
  logger:finer('response status %d "%s"', status, reason)
  local contentType = response:getHeader('content-type')
  if not strings.equalsIgnoreCase(contentType, 'application/json') then
    return response:text():next(function(text)
      logger:fine('response body "%s"', text)
      return Promise.reject('Invalid or missing content type')
    end)
  end
  return response:json():next(function(content)
    logger:finer('response content %T', content)
    if type(content) ~= 'table' then
      return Promise.reject('Invalid or missing content')
    end
    if status ~= 200 then
      return Promise.reject(string.format('Bad status (%d) %s', status, reason))
    end
    if #content > 0 and type(content[1]) == 'table' and content[1].success then
      local descriptions = {}
      for _, item in ipairs(content) do
        if type(item.error) == 'table' and type(item.error.description) == 'string' then
          table.insert(descriptions, item.error.description)
        end
      end
      if #content == #descriptions then
        return Promise.reject(table.concat(descriptions, ', '))
      end
      if #content == 1 then
        return content[1].success
      end
    end
    return content
  end)
end

local function createHttpClient(url)
  return HttpClient:new({
    url = url,
    secureContext = {
      alpnProtos = {'h2'}
    },
  })
end

local function httpRequest(client, method, path, headers, body)
  logger:fine('httpRequest(%s, %s, %T, %T)', method, path, headers, body)
  return utils.timeout(client:fetch(path or '/', {
    method = method or 'GET',
    headers = headers,
    body = formatBody(body),
  }))
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
    self.mapping = utils.replaceRefs(mapping or {}, {
      Thing = Thing, -- TODO remove
      color = utils, -- TODO remove
      logger = logger, -- TODO remove
      utils = utils,
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
    self:stopEventStream()
    if self.client then
      self.client:close()
    end
    self.client = nil
  end

  function hueBridge:getHttpClient()
    if not self.client then
      self.client = createHttpClient(self.url)
    end
    return self.client
  end

  function hueBridge:httpRequest(method, path, body)
    return httpRequest(self:getHttpClient(), method, path, self.headers, body):next(processResponse)
  end

  function hueBridge:httpRequestV1(method, path, body)
    local headers = Map.assign({
      ['Content-Type'] = 'application/json'
    })
    return httpRequest(self:getHttpClient(), method, '/api/'..self.key..path, headers, body):next(processResponseV1)
  end

  function hueBridge:getConfig()
    return self:httpRequestV1('GET', '/config')
  end

  function hueBridge:putConfig(config)
    return self:httpRequestV1('PUT', '/config', config)
  end

  function hueBridge:deleteUser(id)
    return self:httpRequestV1('DELETE', '/config/whitelist/'..tostring(id))
  end

  function hueBridge:getResourceMapById(name)
    name = name or 'device'
    return self:httpRequest('GET', '/clip/v2/resource/'..name):next(function(devices)
      local serviceTypeMap = {}
      for _, device in ipairs(devices) do
        logger:finest('%T', device)
        for _, service in ipairs(device.services) do
          serviceTypeMap[service.rtype] = true
        end
      end
      local rtypes = Map.skeys(serviceTypeMap)
      if logger:isLoggable(logger.FINE) then
        logger:fine('%s service rtypes: %s', name, List.join(rtypes, ', '))
      end
      logger:fine('get %s services...', name)
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
      local client = self.client
      if self.responseStream and client and not client:isClosed() then
        local http2 = client.http2
        if http2 then
          logger:finer('pinging...')
          return utils.timeout(http2:sendPing(), 5000):next(function()
            logger:fine('ping success')
            --http2:closePendings(30)
          end, function(reason)
            logger:warn('ping failure "%s"', reason)
            self:closeEventStream()
          end)
        end
      else
        return self:fetchEventStream()
      end
    end
    return Promise.resolve()
  end

  function hueBridge:startEventStream(onEvents)
    self.onEvents = onEvents
    return self:fetchEventStream()
  end

  function hueBridge:publishEvents(events)
    if self.onEvents then
      local status, e = Exception.pcall(self.onEvents, events)
      if not status then
        logger:warn('Hue event callback error "%s" with payload: %t', e, events)
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
            local isValue = utils.isValue(value)
            if isValue and info.adapter then
              value = info.adapter(value)
              isValue = utils.isValue(value)
            end
            if isValue or info.mandatory then
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
          if info.adapter then
            value = info.adapter(value)
            isValue = utils.isValue(value)
          end
          if isValue then
            local name = buildName(info, resource)
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
              local body
              local path = info.path
              if not path or path == '/' or path == '' then
                body = value
              else
                body = {}
                tables.setPath(body, info.path, value)
              end
              return self:httpRequest('PUT', '/clip/v2/resource/'..service.rtype..'/'..service.rid, body)
            end
          end
        end
      end
    end
    return Promise.reject(string.format('cannot set value "%s" for resource id "%s"', name, id))
  end

end, function(HueBridge)

  HueBridge.processResponse = processResponse
  HueBridge.processResponseV1 = processResponseV1
  HueBridge.createHttpClient = createHttpClient

end)
