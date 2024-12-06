
local function onStartup(extension)
  extension:getEngine():onExtension('web-base', function(webBaseExtension)
    webBaseExtension:registerAddonExtension(extension, true)
  end)
end

local function onShutdown(extension)
  extension:getEngine():onExtension('web-base', function(webBaseExtension)
    webBaseExtension:unregisterAddonExtension(extension)
  end)
end

local function registerAddonExtension(extension)
  extension:subscribeEvent('startup', function()
    onStartup(extension)
  end)
  extension:subscribeEvent('shutdown', function()
    onShutdown(extension)
  end)
end

return {
  onStartup = onStartup,
  onShutdown = onShutdown,
  registerAddonExtension = registerAddonExtension
}
