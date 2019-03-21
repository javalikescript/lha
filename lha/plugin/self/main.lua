local plugin = ...

local logger = require('jls.lang.logger')

logger:info('self plugin under '..plugin:getDir():getPath())

local device = plugin:registerDevice('memory')

device:subscribeEvent('poll', function()
  logger:info('poll self device')
  device:applyDeviceData({
    memory = math.floor(collectgarbage('count') * 1024)
  })
end)

