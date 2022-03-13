local extension = ...

local logger = require('jls.lang.logger')

extension:subscribeEvent('startup', function()
  logger:info('startup web test extension')
  extension:getEngine():onExtension('web-base', function(webBaseExtension)
    webBaseExtension:registerAddonExtension(extension)
  end)
end)
