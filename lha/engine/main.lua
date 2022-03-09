local logger = require('jls.lang.logger')
local system = require('jls.lang.system')
local event = require('jls.lang.event')

local Engine = require('lha.engine.Engine')
Engine.launch(system.getArguments())
event:loop()
logger:info('Engine stopped')
