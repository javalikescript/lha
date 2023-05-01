local extension = ...

local logger = require('jls.lang.logger')
local StreamHandler = require('jls.io.StreamHandler')
local ChunkedStreamHandler = require('jls.io.streams.ChunkedStreamHandler')
local Serial = require('jls.io.Serial')
local strings = require('jls.util.strings')

local Thing = require('lha.Thing')

local function createThing()
  local thing = Thing:new('TIC', 'Téléinformation client', {Thing.CAPABILITIES.Alarm, Thing.CAPABILITIES.EnergyMonitor, Thing.CAPABILITIES.MultiLevelSensor})
  thing:addPropertiesFromNames('alarm', 'current')
  thing:addProperty('power', {
    ['@type'] = Thing.PROPERTY_TYPES.ApparentPowerProperty,
    type = 'number',
    title = 'Apparent power',
    description = 'The apparent power',
    readOnly = true,
    unit = 'voltampere'
  })
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
end

local FIELD_MAP = {
  IINST = 'current',
  PAPP = 'power',
  ISOUSC = 'isousc',
  HCHC = 'hchc',
  HCHP = 'hchp',
}

local ticThing, serial

local function closeSerial()
  if serial then
    serial:close()
    serial = nil
  end
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
      local field, value, horodate, checksum
      if #fields == 3 then
        field, value, checksum = table.unpack(fields)
      elseif #fields == 4 then
        field, value, horodate, checksum = table.unpack(fields)
      end
      -- Le format utilisé pour les horodates est SAAMMJJhhmmss, c'est-à-dire Saison, Année, Mois, Jour, heure, minute, seconde.
      -- Checksum = (S1 & 0x3F) + 0x20
      local name = FIELD_MAP[field]
      if name then
        local v = tonumber(value)
        if v ~= nil and ticThing then
          ticThing:updatePropertyValue(name, v)
        end
      elseif field == 'ADPS' then
        alarm = true
      end
    end
    if ticThing then
      ticThing:updatePropertyValue('alarm', alarm)
    end
  end), '\x03', true, 4096)
  serial:readStart(sh)
  logger:info('Reading TiC on "%s"', configuration.portName)
end

extension:subscribeEvent('things', function()
  ticThing = extension:syncDiscoveredThingByKey('tic', createThing)
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

