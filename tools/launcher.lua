_G.JLS_USE_XPCALL = true
local engine = require('lha.Engine').launch(require('jls.lang.system').getArguments())
local hasLuv, luvLib = pcall(require, 'luv')
if hasLuv then
  local signal = luvLib.new_signal()
  luvLib.ref(signal)
  luvLib.signal_start(signal, 'sigint', function()
    luvLib.unref(signal)
    signal:stop()
    engine:stop()
  end)
end
require('jls.lang.event'):loop()
