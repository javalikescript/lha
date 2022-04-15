local HTTP_CONST = require('jls.net.http').CONST
local HttpExchange = require('jls.net.http.HttpExchange')
local json = require('jls.util.json')
local Map = require('jls.util.Map')

local REST_THING = {
  [''] = function(exchange)
    return exchange.attributes.thing:asThingDescription()
  end,
  properties = {
    [''] = function(exchange)
      local request = exchange:getRequest()
      local method = string.upper(request:getMethod())
      if method == HTTP_CONST.METHOD_GET then
        return exchange.attributes.thing:getPropertyValues()
      elseif method == HTTP_CONST.METHOD_PUT then
        local rt = json.decode(request:getBody())
        for name, value in pairs(rt) do
          exchange.attributes.thing:setPropertyValue(name, value)
        end
      else
        HttpExchange.methodNotAllowed(exchange)
        return false
      end
    end,
    ['{propertyName}(propertyName)'] = function(exchange, propertyName)
      local request = exchange:getRequest()
      local method = string.upper(request:getMethod())
      local property = exchange.attributes.thing:getProperty(propertyName)
      if property then
        if method == HTTP_CONST.METHOD_GET then
          return {[propertyName] = property:getValue()}
        elseif method == HTTP_CONST.METHOD_PUT then
          local rt = json.decode(request:getBody())
          local value = rt[propertyName]
          exchange.attributes.thing:setPropertyValue(propertyName, value)
        else
          HttpExchange.methodNotAllowed(exchange)
          return false
        end
      else
        HttpExchange.notFound(exchange)
        return false
      end
    end,
  }
}

return {
  [''] = function(exchange)
    local engine = exchange:getAttribute('engine')
    local descriptions = {}
    for _, thing in Map.spairs(engine.things) do
      local description = thing:asThingDescription()
      table.insert(descriptions, description)
    end
    return descriptions
  end,
  ['{+}'] = function(exchange, name)
    local engine = exchange:getAttribute('engine')
    local thing = engine.things[name]
    if thing then
      exchange:setAttribute('thing', thing)
    else
      error('Thing not found '..tostring(name))
    end
  end,
  ['{thingId}'] = REST_THING,
}
