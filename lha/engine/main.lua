local logger = require('jls.lang.logger')
local tables = require('jls.util.tables')
local system = require('jls.lang.system')
local event = require('jls.lang.event')

local Engine = require('lha.engine.Engine')

local options = tables.createArgumentTable(system.getArguments(), {
  configPath = 'config',
  emptyPath = 'work',
  helpPath = 'help',
  schema = 'lha.engine.schema'
})

logger:setLevel(options.loglevel)

local engine = Engine:new(options)
engine:start()
engine:publishEvent('poll')
logger:debug('starting event loop')
event:loop()
logger:debug('event loop ended')
logger:info('Engine stopped')
