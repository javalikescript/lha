local extension = ...

local logger = extension:getLogger()
local File = require('jls.io.File')
local json = require('jls.util.json')
local List = require('jls.util.List')
local Map = require('jls.util.Map')
local strings = require('jls.util.strings')
local tables = require('jls.util.tables')

local Thing = require('lha.Thing')

logger:info('generic extension')

local METADATA_BY_TYPE = {
  boolean = {
    ['@type'] = 'OnOffProperty',
    type = 'boolean',
    description = 'Boolean property'
  },
  boolean_readOnly = {
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

local function isEmpty(value)
  return value == nil or value == '' or (type(value) == 'table' and next(value) == nil)
end

local function firstOf(...)
  local l = select('#', ...)
  if l > 0 then
    local values = {...}
    for i = 1, l do
      local value = values[i]
      if not isEmpty(value) then
        return value
      end
    end
  end
end

local mdKeys = {'type', '@type', 'unit', 'title', 'description', 'enum', 'minimum', 'maximum', 'readOnly', 'writeOnly', 'configuration'}

local function createThing(thingConfig)
  local typeSet = Map:new()
  typeSet:add('GenericThing')
  local thing = Thing:new(firstOf(thingConfig.title, 'Generic Thing'), firstOf(thingConfig.description, 'Generic Thing'))
  for _, propertyConfig in ipairs(thingConfig.properties) do
    local name = firstOf(propertyConfig.name, 'value')
    local sType = tostring(propertyConfig.type)
    local fType = sType
    if propertyConfig.readOnly then
      fType = fType..'_readOnly'
    end
    -- filter property metadata values
    local metadata = {}
    for _, key in ipairs(mdKeys) do
      local value = propertyConfig[key]
      if not isEmpty(value) then
        metadata[key] = value
      end
    end
    metadata = Map.assign({title = name}, METADATA_BY_TYPE[fType] or METADATA_BY_TYPE[sType], metadata)
    thing:addProperty(name, metadata)
    -- guess thing type based on property type
    if propertyConfig.readOnly then
      if propertyConfig.type == 'boolean' then
        typeSet:add('BinarySensor')
      else
        typeSet:add('MultiLevelSensor')
      end
    else
      typeSet:add('MultiLevelSwitch')
    end
  end
  local tType = thingConfig['@type']
  if isEmpty(tType) then
    tType = typeSet:skeys()
  end
  thing.type = tType
  return thing
end

local thingTable
local valuesFile

local function saveValues()
  if thingTable and valuesFile then
    local data = json.stringify(thingTable, 2)
    valuesFile:write(data)
  end
end

local function setThingPropertyValue(thing, name, value)
  local property = thing:getProperty(name)
  if property and value ~= nil then
    if property:isWritable() then
      local path = thing.thingId..'/'..name
      local prev = tables.setPath(thingTable, path, value)
      if value ~= prev then
        extension:putTimer('save', saveValues, 1000)
      end
      thing:updatePropertyValue(name, value)
    end
  end
end

local function createThings(thingsByKey, things)
  if type(things) == 'table' then
    for _, thingConfig in ipairs(things) do
      if not isEmpty(thingConfig.properties) then
        if isEmpty(thingConfig.id) then
          local configuration = extension:getConfiguration()
          local lastId = configuration.lastId
          if math.type(lastId) == 'integer' then
            lastId = lastId + 1
          else
            lastId = 1
          end
          configuration.lastId = lastId
          thingConfig.id = strings.formatInteger(lastId, 64)
        end
        local thing = thingsByKey[thingConfig.id]
        if not thing then
          thing = createThing(thingConfig)
          if thing then
            if logger:isLoggable(logger.FINEST) then
              logger:finest('discovered thing "%s": %T', thingConfig.id, thing:asThingDescription())
            end
            extension:discoverThing(thingConfig.id, thing)
          end
        end
        if thing and thingConfig.save then
          local values = thingTable[thing.thingId]
          if values then
            for name, value in pairs(values) do
              local property = thing:getProperty(name)
              if property then
                property:setValue(value)
              end
            end
          end
          thing.setPropertyValue = setThingPropertyValue
        end
      end
    end
  end
end

local function getConfiguredThings()
  local configuration = extension:getConfiguration()
  return List.concat({}, configuration.basicThings, configuration.things)
end

extension:subscribeEvent('startup', function()
  thingTable = {}
  local engine = extension:getEngine()
  valuesFile = File:new(engine:getWorkDirectory(), 'generic-things.json')
  if valuesFile:isFile() then
    local status, t = pcall(json.decode, valuesFile:readAll())
    if status then
      thingTable = t
    else
      logger:warn('Fail to load generic thing values, %s', t)
    end
  end
end)

extension:subscribeEvent('things', function()
  logger:info('Looking for generic things')
  extension:cleanDiscoveredThings()
  createThings(extension:getThingsByDiscoveryKey(), getConfiguredThings())
end)
