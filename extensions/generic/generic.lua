local extension = ...

local logger = extension:getLogger()
local File = require('jls.io.File')
local json = require('jls.util.json')
local Map = require('jls.util.Map')
local strings = require('jls.util.strings')
local tables = require('jls.util.tables')

local Thing = require('lha.Thing')


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

local METADATA_KEYS = {'type', '@type', 'unit', 'title', 'description', 'enum', 'minimum', 'maximum', 'readOnly', 'writeOnly', 'configuration'}

local METADATA_DEFAUT_VALUES = {
  readOnly = false,
  writeOnly = false,
  configuration = false,
}

local PROPERTY_TYPE_BY_TYPE = {
  boolean_RO = 'BooleanProperty',
  boolean = 'OnOffProperty',
  number = 'LevelProperty',
  string = 'StringProperty',
}

local CAPABILITY_BY_TYPE = {
  boolean_RO = 'BinarySensor',
  boolean = 'OnOffSwitch',
  number_RO = 'MultiLevelSensor',
  number = 'MultiLevelSwitch',
}

local function createThing(thingConfig)
  local typeSet = Map:new()
  typeSet:add('GenericThing')
  local thing = Thing:new(firstOf(thingConfig.title, 'Generic Thing'), firstOf(thingConfig.description, 'Generic Thing'))
  for _, propertyConfig in ipairs(thingConfig.properties) do
    local name = firstOf(propertyConfig.name, 'value')
    local primitiveType = tostring(propertyConfig.type)
    -- guess the semantic type
    local adaptedType = primitiveType
    if propertyConfig.type == 'integer' then
      adaptedType = 'number'
    end
    if propertyConfig.readOnly then
      adaptedType = adaptedType..'_RO'
    end
    local semanticType = PROPERTY_TYPE_BY_TYPE[adaptedType] or PROPERTY_TYPE_BY_TYPE[primitiveType] or 'GenericProperty'
    -- filter property metadata values
    local metadata = {}
    for _, key in ipairs(METADATA_KEYS) do
      local value = propertyConfig[key]
      if not isEmpty(value) and value ~= METADATA_DEFAUT_VALUES[key] then
        metadata[key] = value
      end
    end
    thing:addProperty(name, Map.assign({
      title = name,
      ['@type'] = semanticType,
      description = semanticType
    }, metadata))
    -- guess thing type based on property type
    local capability = CAPABILITY_BY_TYPE[adaptedType] or CAPABILITY_BY_TYPE[primitiveType]
    if capability then
      typeSet:add(capability)
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

local function createThings(things, thingsByKey)
  if type(things) == 'table' then
    for _, thingConfig in ipairs(things) do
      if not isEmpty(thingConfig.properties) then
        if thingConfig.id == '' or type(thingConfig.id) ~= 'string' then
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
        if thing then
          if thingConfig.save and thing.thingId then
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
        else
          local discoveredThing = createThing(thingConfig)
          if discoveredThing then
            if logger:isLoggable(logger.FINEST) then
              logger:finest('discovered thing "%s": %T', thingConfig.id, discoveredThing:asThingDescription())
            end
            extension:discoverThing(thingConfig.id, discoveredThing)
          end
        end
      end
    end
  end
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
  local configuration = extension:getConfiguration()
  extension:cleanDiscoveredThings()
  local thingsByKey = extension:getThingsByDiscoveryKey()
  createThings(configuration.basicThings, thingsByKey)
  createThings(configuration.things, thingsByKey)
  createThings(configuration.list, thingsByKey)
end)
