local fsep = string.sub(package.config, 1, 1)
local cext = fsep == '\\' and '.dll' or '.so'
package.path = 'lua'..fsep..'?.lua;lua'..fsep..'?'..fsep..'init.lua'
package.cpath = 'bin'..fsep..'?'..cext
require('lha.Engine').launch(require('jls.lang.system').getArguments())
require('jls.lang.event'):loop()
