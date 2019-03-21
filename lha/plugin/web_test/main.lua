local plugin = ...

local logger = require('jls.lang.logger')
local httpHandler = require('jls.net.http.handler')

plugin:subscribeEvent('startup', function()
  logger:info('startup web test plugin')
  plugin:onPlugin('web_base', function(webBasePlugin)
    webBasePlugin:registerAddonPlugin(plugin)
  end)
end)


