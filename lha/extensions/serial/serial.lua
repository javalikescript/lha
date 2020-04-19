local extension = ...

local logger = require('jls.lang.logger')
--local system = require('jls.lang.system')
local streams = require('jls.io.streams')
local json = require('jls.util.json')
local Serial = require('jls.io.Serial')
--local tables = require('jls.util.tables')
local TableList = require('jls.util.TableList')
local Thing = require('lha.engine.Thing')

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
  if logger:isLoggable(logger.FINE) then
    logger:fine('serial message: '..message)
  end
  return message..'\r\n'
end

local serial
local welcomeReceived = false
local maxId = -1
local serialThings = {}
local allThings = {}

local serialLineHandler = streams.StreamHandler:new()
function serialLineHandler:onData(line)
  if logger:isLoggable(logger.FINE) then
    logger:fine('handleSerialLine("'..tostring(line)..'")')
  end
  --logger:info('serial received "'..tostring(line)..'"')
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
      logger:info('serial received error "'..tostring(data.error)..'"')
    else
      logger:info('serial received unsuccessful command "'..tostring(line)..'"')
    end
    return true
  end
  local thingId = nil
  if data.id then
    thingId = tostring(data.id)
  end
  if data.cmd == COMMAND.WELCOME then
    maxId = data.maxId or -1
    logger:info('Serial welcome received with maxId '..tostring(maxId))
    local configuration = extension:getConfiguration()
    if type(configuration.setupMessages) == 'table' then
      for _, setupMessage in ipairs(configuration.setupMessages) do
        local message = createMessage(setupMessage.commandId, setupMessage.thingId, setupMessage.value, setupMessage.propertyId)
        logger:info('serial sending setup message: '..string.gsub(message, '[\r\n]+', ''))
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
          thing:addType('MultiLevelSensor')
          thing:addRelativeHumidityProperty()
        elseif propertyName == 'temperature' then
          thing:addType('TemperatureSensor')
          thing:addTemperatureProperty()
        elseif propertyName == 'pressure' then
          thing:addType('MultiLevelSensor')
          thing:addAtmosphericPressureProperty()
        else
          thing:addProperty(propertyName, {
            ['@type'] = 'LevelProperty',
            type = 'integer',
            title = propertyName,
          })
        end
      end
      extension:discoverThing(thingId, thing)
      logger:info('Serial thing info received "'..title..'" with id '..thingId)
    end
    serialThings[thingId] = thing
  elseif data.cmd == COMMAND.READ then
    local thing = serialThings[thingId]
    if thing then
      if logger:isLoggable(logger.FINE) then
        logger:fine('serial looking for thing properties "'..tostring(TableList.concat(thing:getPropertyNames(), '", "'))..'"')
      end
      for propertyName in pairs(thing:getProperties()) do
        local value = data[propertyName]
        if value then
          if logger:isLoggable(logger.FINE) then
            logger:fine('serial received read for thing '..thingId..' "'..tostring(propertyName)..'" = '..tostring(value))
          end
          thing:updatePropertyValue(propertyName, value)
        else
          logger:warn('serial received read for thing '..thingId..' with missing property "'..tostring(propertyName)..'"')
        end
      end
    else
      logger:warn('serial received read from unknown thing "'..tostring(line)..'"')
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
    logger:warn('serial received unsupported command "'..tostring(line)..'"')
  end
  return true
end
function serialLineHandler:onError(err)
  logger:warn('serialLineHandler:onError("'..err..'")')
end

extension:subscribeEvent('startup', function()
  local bsHandler = streams.ChunkedStreamHandler:new(serialLineHandler, '\r\n', 256)
  local configuration = extension:getConfiguration()
  if serial then
    logger:warn('serial extension already started')
    return
  end
  serial = Serial.open(configuration.portName, configuration)
  if not serial then
    logger:warn('Unable to open serial on "'..configuration.portName..'"')
    return
  end
  -- the arduino serial receive buffer holds 64 bytes
  serial:readStart(bsHandler)
  logger:info('Reading serial on "'..configuration.portName..'"')
end)

extension:subscribeEvent('things', function()
  logger:info('looking for serial things')
  serial:write(createMessage(COMMAND.WELCOME))
end)

extension:subscribeEvent('poll', function()
  if serial then
    logger:info('poll serial device '..tostring(maxId)..' things')
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

