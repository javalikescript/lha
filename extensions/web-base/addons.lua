
local function onStartup(extension, script)
  extension:getEngine():onExtension('web-base', function(webBaseExtension)
    webBaseExtension:registerAddonExtension(extension, script or true)
  end)
end

local function onShutdown(extension)
  extension:getEngine():onExtension('web-base', function(webBaseExtension)
    webBaseExtension:unregisterAddonExtension(extension)
  end)
end

local function registerAddonExtension(extension, script)
  extension:subscribeEvent('startup', function()
    onStartup(extension, script)
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
