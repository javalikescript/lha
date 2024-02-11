local extension = ...

local logger = extension:getLogger()
local StreamHandler = require('jls.io.StreamHandler')
local ChunkedStreamHandler = require('jls.io.streams.ChunkedStreamHandler')
local Serial = require('jls.io.Serial')
local strings = require('jls.util.strings')

local Thing = require('lha.Thing')
local utils = require('lha.utils')

local function updateThing(thing, fieldMap, field, value)
  local name = fieldMap[field]
  if name then
    local n = tonumber(value)
    if n ~= nil and thing then
      thing:updatePropertyValue(name, n)
    end
    return true
  end
  return false
end

local FIELD_MAP = {
  IINST = 'current',
  PAPP = 'power',
}
local INDEX_FIELD_MAP = {
  ISOUSC = 'isousc',
  HCHC = 'hchc',
  HCHP = 'hchp',
}
local ticThing, ticIndexThing, serial

local function updateConnected(value)
  if ticThing then
    ticThing:updatePropertyValue('connected', value == true)
  end
end

local function closeSerial()
  if serial then
    serial:close()
    serial = nil
  end
  updateConnected(false)
end

local function openSerial()
  local configuration = extension:getConfiguration()
  local modeHistorique = configuration.mode == 'historique'
  serial = Serial:open(configuration.portName, {
    baudRate = modeHistorique and 1200 or 9600,
    dataBits = 7,
    stopBits = 1,
    parity = 2
  })
  if not serial then
    updateConnected(false)
    logger:warn('Unable to open TiC on serial port "%s"', configuration.portName)
    return
  end
  local fieldSeparator = modeHistorique and ' ' or '\t'
  local sh = ChunkedStreamHandler:new(StreamHandler:new(function(err, data)
    if err or not data then
      logger:warn('Error reading TiC "%s"', err or 'no data')
      closeSerial()
      return
    end
    -- if string.sub(data, 1, 1) == '\x02' then data = string.sub(data, 2) end
    local alarm = false
    for line in string.gmatch(data, '\n([^\r]+)\r') do
      local fields = strings.split(line, fieldSeparator, true)
      local field, value
      -- Le format utilisé pour les horodates est SAAMMJJhhmmss, c'est-à-dire Saison, Année, Mois, Jour, heure, minute, seconde.
      -- Checksum = (S1 & 0x3F) + 0x20
      if #fields == 3 or #fields == 4 then
        field, value = table.unpack(fields)
      end
      if field then
        if field == 'ADPS' then
          alarm = true
        else
          if not updateThing(ticThing, FIELD_MAP, field, value) then
            updateThing(ticIndexThing, INDEX_FIELD_MAP, field, value)
          end
        end
      end
    end
    if ticThing then
      ticThing:updatePropertyValue('alarm', alarm)
      ticThing:updatePropertyValue('lastupdated', utils.timeToString())
    end
  end), '\x03', true, 4096)
  serial:readStart(sh)
  updateConnected(true)
  logger:info('Reading TiC on "%s"', configuration.portName)
end

extension:subscribeEvent('things', function()
  ticThing = extension:syncDiscoveredThingByKey('tic', function()
    local thing = Thing:new('TIC', 'Téléinformation client', {Thing.CAPABILITIES.Alarm, Thing.CAPABILITIES.EnergyMonitor})
    thing:addPropertiesFromNames('alarm', 'current', 'connected', 'lastupdated')
    thing:addProperty('power', {
      ['@type'] = Thing.PROPERTY_TYPES.ApparentPowerProperty,
      type = 'number',
      title = 'Apparent power',
      description = 'The apparent power',
      readOnly = true,
      unit = 'voltampere'
    })
    return thing
  end)
  ticIndexThing = extension:syncDiscoveredThingByKey('ticIndex', function()
    local thing = Thing:new('TIC Indexes', 'Téléinformation client index', {Thing.CAPABILITIES.MultiLevelSensor})
    thing:addProperty('isousc', {
      ['@type'] = Thing.PROPERTY_TYPES.CurrentProperty,
      type = 'number',
      title = 'Intensité souscrite',
      description = 'Intensité souscrite',
      readOnly = true,
      unit = 'ampere'
    })
    thing:addProperty('hchc', {
      ['@type'] = Thing.PROPERTY_TYPES.LevelProperty,
      type = 'number',
      title = 'Index Heures Creuses',
      description = 'Index option Heures Creuses',
      readOnly = true,
      unit = 'watthour'
    })
    thing:addProperty('hchp', {
      ['@type'] = Thing.PROPERTY_TYPES.LevelProperty,
      type = 'number',
      title = 'Index Heures Pleines',
      description = 'Index option Heures Pleines',
      readOnly = true,
      unit = 'watthour'
    })
    return thing
  end)
end)

extension:subscribeEvent('startup', function()
  closeSerial()
  openSerial()
end)

extension:subscribeEvent('poll', function()
  if not serial then
    openSerial()
  end
end)

extension:subscribeEvent('shutdown', function()
  logger:info('shutdown TiC extension')
  closeSerial()
end)

