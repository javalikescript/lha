local extension = ...

local logger = require('jls.lang.logger')
local Map = require('jls.util.Map')
local Thing = require('lha.Thing')

logger:info('generic extension')

local METADATA_BY_TYPE = {
  boolean = {
    ['@type'] = 'BooleanProperty',
    type = 'boolean',
    description = 'Boolean property'
  },
  integer = {
    ['@type'] = 'LevelProperty',
    type = 'integer',
    description = 'Integer property'
  },
  number = {
    ['@type'] = 'LevelProperty',
    type = 'number',
    description = 'Number property'
  },
  string = {
    ['@type'] = 'StringProperty',
    type = 'string',
    description = 'String property'
  },
}

local function oneOf(...)
  for _, value in ipairs({...}) do
    if value ~= nil and value ~= '' and (type(value) ~= 'table' or next(value) ~= nil) then
      return value
    end
  end
end

local function createThing(thingConfig)
  local thing = Thing:new(oneOf(thingConfig.title, 'Generic Thing'), oneOf(thingConfig.description, 'Generic Thing'), oneOf(thingConfig.sType, {'GenericThing'}))
  for _, propertyConfig in ipairs(thingConfig.properties) do
    local name = propertyConfig.name or 'value'
    local metadata = Map.assign({title = name}, METADATA_BY_TYPE[propertyConfig.type], propertyConfig)
    thing:addProperty(name, metadata)
  end
  return thing
end

local function formatKey(index, thingConfig)
  if thingConfig and thingConfig.id and thingConfig.id ~= '' then
    return thingConfig.id
  end
  return '#'..tostring(index)
end

local function discoverThings(extension)
  local configuration = extension:getConfiguration()
  extension:cleanDiscoveredThings()
  local things = extension:getThings()
  if configuration.things then
    for index, thingConfig in ipairs(configuration.things) do
      local key = formatKey(index, thingConfig)
      local thing = things[key]
      if thing then
        thing:connect()
      else
        local discoveredThing = createThing(thingConfig)
        if discoveredThing then
          extension:discoverThing(key, discoveredThing)
        end
      end
    end
  end
end

extension:subscribeEvent('things', function()
  logger:info('looking for generic things')
  discoverThings(extension)
end)
