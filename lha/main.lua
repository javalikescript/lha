_G.JLS_USE_XPCALL = true
require('lha.engine.Engine').launch(require('jls.lang.system').getArguments())
require('jls.lang.event'):loop()
