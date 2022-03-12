local logger = require('jls.lang.logger')
local tables = require('jls.util.tables')
local Thing = require('lha.engine.Thing')

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

local function createThing(thingConfig)
  local thing = Thing:new(thingConfig.title or 'Generic Thing', thingConfig.description or 'Generic Thing', {'GenericThing'})
  for _, propertyConfig in ipairs(thingConfig.properties) do
    local metadata = METADATA_BY_TYPE[propertyConfig.type]
    if metadata then
      local name = propertyConfig.name or 'value'
      thing:addProperty(name, tables.merge({
        title = propertyConfig.title or name,
        description = propertyConfig.description
      }, metadata))
    end
  end
  return thing
end

local function formatKey(index, thingConfig)
  return '#'..tostring(index)
end

local function discoverThings(extension)
  local configuration = extension:getConfiguration()
  extension:cleanDiscoveredThings()
  local things = extension:getThings()
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

local extension = ...

extension:subscribeEvent('startup', function()
  logger:info('startup generic extension')
end)

extension:subscribeEvent('things', function()
  logger:info('looking for generic things')
  discoverThings(extension)
end)
