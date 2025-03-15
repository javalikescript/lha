local Map = require('jls.util.Map')

return {
  ['(engine)'] = function(_, engine)
    local descriptions = {}
    for _, thing in Map.spairs(engine.things) do
      local description = thing:asThingDescription()
      table.insert(descriptions, description)
    end
    return descriptions
  end,
  ['{+thing}(engine)'] = function(_, name, engine)
    return engine.things[name]
  end,
  ['{thingId}'] = {
    [''] = function(exchange)
      return exchange.attributes.thing:asThingDescription()
    end,
    properties = {
      ['(thing)?method=GET'] = function(_, thing)
        return thing:getPropertyValues()
      end,
      ['(thing, requestJson)?method|=POST|PUT'] = function(_, thing, rt)
        for name, value in pairs(rt) do
          thing:setPropertyValue(name, value)
        end
      end,
      ['{+property}(thing)'] = function(_, propertyName, thing)
        return thing:getProperty(propertyName)
      end,
      ['{propertyName}'] = {
        ['(property, propertyName)?method=GET'] = function(_, property, propertyName)
          return {[propertyName] = property:getValue()}
        end,
        ['(thing, propertyName, requestJson)?method=PUT'] = function(_, thing, propertyName, rt)
          local value = rt[propertyName]
          thing:setPropertyValue(propertyName, value)
        end,
      },
    }
  }
}
