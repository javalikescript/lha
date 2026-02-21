_G.JLS_USE_XPCALL = true
local event = require('jls.lang.event')
local signal = require('jls.lang.signal')
local Engine = require('lha.Engine')
local engine = Engine.launch(require('jls.lang.system').getArguments())
local cancel = signal('?!sigint', function()
  engine:stop()
end)
engine:released():next(cancel)

event:loop()
