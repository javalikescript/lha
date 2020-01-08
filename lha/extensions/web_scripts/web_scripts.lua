local extension = ...

local logger = require('jls.lang.logger')

extension:subscribeEvent('startup', function()
  logger:info('startup web scripts extension')
  if not extension:getEngine():onExtension('web_base', function(webBaseExtension)
    webBaseExtension:registerAddonExtension(extension)
    logger:info('web scripts addon registered')
  end) then
    logger:info('extension web_base not found')
  end
end)


