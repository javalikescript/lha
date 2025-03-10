local extension = ...

local logger = extension:getLogger()
local StreamHandler = require('jls.io.StreamHandler')
local ChunkedStreamHandler = require('jls.io.streams.ChunkedStreamHandler')
local json = require('jls.util.json')
local Serial = require('jls.io.Serial')
local List = require('jls.util.List')
local Thing = require('lha.Thing')

local COMMAND = {
  WELCOME = 0,
  INFO = 1,
  READ = 2,
  WRITE = 3,
  SUBSCRIBE = 4,
  ECHO = 5,
}

local ECHO_END_OF_TEXT = 3

local function createMessage(commandId, thingId, value, propertyId)
  local message = '['..tostring(commandId)..','..tostring(thingId or 0)..','..tostring(value or -1)..','..tostring(propertyId or 0)..']'
  logger:fine('serial message: %s', message)
  return message..'\r\n'
end

local serial
local welcomeReceived = false
local maxId = -1
local serialThings = {}
local allThings = {}

local serialLineHandler = StreamHandler:new()
function serialLineHandler:onData(line)
  logger:fine('serial received "%s"', line)
  if not serial then
    logger:warn('serial is closed')
    return false
  end
  if not line then
    return false
  end
  if #line == 0 then
    return true
  end
  local data = json.decode(line)
  if data.success ~= true then
    if data.error then
      logger:info('serial received error "%s"', data.error)
    else
      logger:info('serial received unsuccessful command "%s"', line)
    end
    return true
  end
  local thingId = nil
  if data.id then
    thingId = tostring(data.id)
  end
  if data.cmd == COMMAND.WELCOME then
    maxId = data.maxId or -1
    logger:info('Serial welcome received with maxId %s', maxId)
    local configuration = extension:getConfiguration()
    if type(configuration.setupMessages) == 'table' then
      for _, setupMessage in ipairs(configuration.setupMessages) do
        local message = createMessage(setupMessage.commandId, setupMessage.thingId, setupMessage.value, setupMessage.propertyId)
        logger:info('serial sending setup message: %s', string.gsub(message, '[\r\n]+', ''))
        serial:write(message)
      end
    end
    extension:cleanDiscoveredThings()
    serialThings = {}
    for id = 1, maxId do
      serial:write(createMessage(COMMAND.INFO, id))
    end
  elseif data.cmd == COMMAND.INFO then
    local thing = extension:getThingByDiscoveryKey(thingId)
    if not thing then
      local title = data.title or ('Serial '..thingId)
      thing = Thing:new(title)
      for propertyId, propertyName in ipairs(data.values) do
        if propertyName == 'humidity' then
          thing:addType('HumiditySensor')
          thing:addPropertyFromName('humidity')
        elseif propertyName == 'temperature' then
          thing:addType('TemperatureSensor')
          thing:addPropertyFromName('temperature')
        elseif propertyName == 'pressure' then
          thing:addType('BarometricPressureSensor')
          thing:addPropertyFromName('pressure')
        else
          thing:addProperty(propertyName, {
            ['@type'] = 'LevelProperty',
            type = 'integer',
            title = propertyName,
          })
        end
      end
      extension:discoverThing(thingId, thing)
      logger:info('Serial thing info received "%s" with id %s', title, thingId)
    end
    serialThings[thingId] = thing
  elseif data.cmd == COMMAND.READ then
    local thing = serialThings[thingId]
    if thing then
      if logger:isLoggable(logger.FINE) then
        logger:fine('serial looking for thing properties "%s"', List.join(thing:getPropertyNames(), '", "'))
      end
      for propertyName in pairs(thing:getProperties()) do
        local value = data[propertyName]
        if value then
          logger:fine('serial received read for thing %s "%s" = %s', thingId, propertyName, value)
          thing:updatePropertyValue(propertyName, value)
        else
          logger:fine('serial received read for thing %s with missing property "%s"', thingId, propertyName)
        end
      end
    else
      logger:warn('serial received read from unknown thing "%s"', line)
    end
  elseif data.cmd == COMMAND.WRITE then
  elseif data.cmd == COMMAND.SUBSCRIBE then
  elseif data.cmd == COMMAND.ECHO then
    if data.value == ECHO_END_OF_TEXT then
      logger:info('serialLineHandler:onData() close')
      serial:readStop()
      serial:close()
      return false
    end
  else
    logger:warn('serial received unsupported command "%s"', line)
  end
  return true
end
function serialLineHandler:onError(err)
  logger:warn('serialLineHandler:onError("%s")', err)
end

extension:subscribeEvent('startup', function()
  local bsHandler = ChunkedStreamHandler:new(serialLineHandler, '\r\n', 256)
  local configuration = extension:getConfiguration()
  if serial then
    logger:warn('serial extension already started')
    return
  end
  serial = Serial:open(configuration.portName, configuration)
  if not serial then
    logger:warn('Unable to open serial on "%s"', configuration.portName)
    return
  end
  -- the arduino serial receive buffer holds 64 bytes
  serial:readStart(bsHandler)
  logger:info('Reading serial on "%s"', configuration.portName)
end)

extension:subscribeEvent('things', function()
  logger:info('looking for serial things')
  if serial then
    serial:write(createMessage(COMMAND.WELCOME))
  else
    logger:info('things serial device disabled as serial is not available')
  end
end)

extension:subscribeEvent('poll', function()
  if serial then
    logger:info('poll serial device %s things', maxId)
    for id = 1, maxId do
      serial:write(createMessage(COMMAND.READ, id))
    end
    logger:fine('serial device done')
  else
    logger:info('poll serial device disabled as serial is not available')
  end
end)

extension:subscribeEvent('shutdown', function()
  logger:info('shutdown serial extension')
  if serial then
    serial:write(createMessage(COMMAND.ECHO, 0, ECHO_END_OF_TEXT)) -- End of Text
    serial = nil
  end
end)

