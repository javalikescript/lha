_G.JLS_USE_XPCALL = true
require('lha.Engine').launch(require('jls.lang.system').getArguments())
require('jls.lang.event'):loop()
