local logger = require('jls.lang.logger'):get(...)
local Promise = require('jls.lang.Promise')
local Exception = require('jls.lang.Exception')
local HttpClient = require('jls.net.http.HttpClient')
local Url = require('jls.net.Url')
local WebSocket = require('jls.net.http.WebSocket')
local json = require('jls.util.json')
local List = require('jls.util.List')
local Map = require('jls.util.Map')
local tables = require('jls.util.tables')

local Thing = require('lha.Thing')
local utils = require('lha.utils')

return require('jls.lang.class').create(function(hueBridge)

  function hueBridge:initialize(apiUrl, user, mapping)
    self.url = Url:new(apiUrl)
    self.user = user or ''
    self.mapping = utils.replaceRefs(mapping or {}, {
      Thing = Thing, -- TODO remove
      color = utils, -- TODO remove
      utils = utils,
      math = math,
      BUTTON_EVENT = {'pressed', 'hold', 'released', 'long-released'}
    })
  end

  function hueBridge:setOnWebSocket(onWebSocket)
    if type(onWebSocket) == 'function' then
      self.onWebSocket = onWebSocket
    else
      self.onWebSocket = nil
    end
    return self
  end

  function hueBridge:configure(config)
    if config.websocketport and config.websocketnotifyall then
      self.wsUrl = Url:new('ws', self.url:getHost(), config.websocketport):toString()
      self:checkWebSocket()
    elseif self.onWebSocket then
      logger:warn('Hue WebSocket is not available')
    end
  end

  function hueBridge:close()
    self:closeWebSocket()
  end

  function hueBridge:publishEvent(name, state)
    if self.onWebSocket then
      self.onWebSocket({t = 'event', e = 'changed', r = name, state = state or {}})
    else
      logger:fine('Event %s not published', name)
    end
  end

  function hueBridge:updateConnectedState(value)
    self:publishEvent('websocket', {connected = value})
  end

  function hueBridge:startWebSocket()
    self:closeWebSocket()
    self.ws = Map.assign(WebSocket:new(self.wsUrl), {
      onClose = function()
        logger:info('Hue WebSocket closed')
        self:updateConnectedState(false)
        self.ws = nil
      end,
      onError = function(reason)
        logger:warn('Hue WebSocket error: %s', reason)
      end,
      onTextMessage = function(webSocket, payload)
        logger:finer('Hue WebSocket received %s', payload)
        local status, info = Exception.pcall(json.decode, payload)
        if status then
          if type(info) == 'table' and info.t == 'event' then
            status, info = Exception.pcall(self.onWebSocket, info)
            if not status then
              logger:warn('Hue WebSocket callback error "%s" with payload: %s', info, payload)
              webSocket:close(false)
            end
          end
        else
          logger:warn('Hue WebSocket received invalid "%s" JSON payload: %s', info, payload)
          webSocket:close(false)
        end
      end
    })
    self.ws:open():next(function()
      self.ws:readStart()
      logger:info('Hue WebSocket connect on %s', self.wsUrl)
      self:updateConnectedState(true)
    end, function(reason)
      logger:warn('Cannot open Hue WebSocket on %s due to %s', self.wsUrl, reason)
      self:updateConnectedState(false)
      self.ws = nil
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
    if self.onWebSocket and self.wsUrl and (not self.ws or self.ws:isClosed()) then
      self:startWebSocket()
    end
  end

  function hueBridge:httpJson(method, path, body)
    local client = HttpClient:new(self.url)
    local resource = self.url:getFile()..path
    if body then
      body = json.encode(body)
    end
    return client:fetch(resource, {
      method = method,
      body = body
    }):next(utils.rejectIfNotOk):next(utils.getJson):finally(function()
      client:close()
    end)
  end

  function hueBridge:httpUserJson(method, path, t)
    return self:httpJson(method, string.gsub(self.user..'/'..path, '//+', '/'), t)
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
    return self:get('config'):next(function(config)
      if config then
        logger:info('update bridge configuration')
        self:configure(config)
      end
    end):catch(function(err)
      logger:warn('fail to get bridge configuration, due to "%s"', err)
    end)
  end

  local function getMacAddress(uid)
    return string.match(uid, '^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x:%x%x:%x%x')
  end

  local function isPrimary(resource, resourceMap)
    -- In case of a combined sensors (same MAC address portion in uniqueID), name and device information should be used from the resource with “primary”:true
    local capabilities = resource.capabilities
    if type(capabilities) == 'table' then
      return capabilities.primary
    else
      local uid = resource.uniqueid
      local mac = getMacAddress(uid)
      if mac and #uid > 23 then
        local count, primaryid = 0, ''
        for id in pairs(resourceMap) do
          local ma = getMacAddress(id)
          if ma == mac then
            count = count + 1
            if id > primaryid then
              primaryid = id
            end
          end
        end
        --logger:info('found %d for mac %s', count, mac)
        if count > 1 then
          local primary = uid == primaryid
          resource.capabilities = {primary = primary}
          return primary
        end
      end
    end
  end

  function hueBridge:getResourceMapById()
    return List.reduce({'lights', 'sensors'}, function(p, path)
      return p:next(function(byId)
        return self:get(path):next(function(resources)
          if resources then
            for id, resource in pairs(resources) do
              local uid = resource.uniqueid
              if uid and getMacAddress(uid) then
                resource.id_v1 = '/'..path..'/'..id
                byId[uid] = resource
              end
            end
          end
          return byId
        end)
      end)
    end, Promise.resolve({})):next(function(byId)
      local byMacAddress = {}
      for uid, resource in pairs(byId) do
        if isPrimary(resource, byId) then
          local mac = getMacAddress(uid)
          byMacAddress[mac] = uid
        end
      end
      for uid, resource in pairs(byId) do
        if isPrimary(resource, byId) == false then
          local mac = getMacAddress(uid)
          local primaryid = byMacAddress[mac]
          resource.primaryid = primaryid
          local pr = byId[primaryid]
          if pr.subids then
            table.insert(pr.subids, uid)
          else
            pr.subids = {uid}
          end
        end
      end
      return byId
    end)
  end

  local function isValue(value)
    return value ~= nil and value ~= json.null
  end

  function hueBridge:forEachProperty(resource, data, fn)
    local typed = self.mapping.types[resource.type]
    if typed then
      for _, group in ipairs(typed.groups) do
        local properties = self.mapping.group[group]
        if properties then
          for _, info in ipairs(properties) do
            local value = tables.getPath(data, info.path)
            if isValue(value) then
              fn(info, info.name, value)
            end
          end
        else
          logger:warn('Hue mapping properties not found for group "%s"', type)
        end
      end
    else
      logger:warn('Hue mapping types not found for type "%s"', resource.type)
    end
  end

  function hueBridge:addThingProperties(thing, resource)
    local typed = self.mapping.types[resource.type]
    if typed and typed.capabilities then
      for _, capability in ipairs(typed.capabilities) do
        thing:addType(capability)
      end
    end
    self:forEachProperty(resource, resource, function(info, name)
      utils.addThingPropertyFromInfo(thing, name, info, resource)
    end)
  end

  function hueBridge:createThingFromDeviceId(resourceMap, id)
    local resource = resourceMap[id]
    if resource and not resource.primaryid then
      local title = utils.expand(self.mapping.title, resource)
      local description = utils.expand(self.mapping.description, resource)
      logger:fine('title "%s", description "%s"', title, description)
      local thing = Thing:new(title, description)
      self:addThingProperties(thing, resource)
      if resource.subids then
        for _, suid in ipairs(resource.subids) do
          local r = resourceMap[suid]
          if r then
            self:addThingProperties(thing, r)
          end
        end
      end
      if next(thing:getProperties()) then
        return thing
      end
    end
  end

  function hueBridge:updateThingResource(thing, resource, data, isEvent)
    self:forEachProperty(resource, data, function(info, name, value)
      if info.adapter then
        value = info.adapter(value)
      end
      if isValue(value) then
        local publish = false
        if isEvent and info.path == 'state/buttonevent' then
          if value == 'released' then
            -- simulate a pressed event
            thing:updatePropertyValue(name, 'pressed')
          elseif value == 'hold' then
            publish = true
          end
        end
        thing:updatePropertyValue(name, value, publish)
      end
    end)
  end

  function hueBridge:setResourceValue(resource, name, value)
    local category, path, val
    self:forEachProperty(resource, resource, function(info, n)
      if n == name then
        category, path = string.match(info.path, '^([^/]+)/(.+)$')
        if info.setAdapter then
          val = info.setAdapter(value)
        else
          val = value
        end
      end
    end)
    logger:fine('hueBridge:setResourceValue(%s, %s) => %s, %s, %s', name, value, category, path, val)
    if val ~= nil and category then
      -- /api/<username>/lights/<id>/state
      local body = {}
      tables.setPath(body, path, val)
      return self:put(resource.id_v1..'/'..category, body)
    end
    return Promise.reject('not found')
  end

end)
