
local function onWebBase(extension, script)
  local webBaseExt = extension:getEngine():getExtensionById('web-base')
  if webBaseExt then
    if script then
      webBaseExt:registerAddonExtension(extension, script)
    else
      webBaseExt:unregisterAddonExtension(extension)
    end
  end
end

local function registerAddonExtension(extension, script)
  local started = false
  if script == nil then
    script = extension:getId()..'.js'
  end
  extension:subscribeEvent('startup', function()
    started = true
    onWebBase(extension, script)
  end)
  extension:subscribeEvent('web-base:startup', function()
    if started then
      onWebBase(extension, script)
    end
  end)
  extension:subscribeEvent('shutdown', function()
    started = false
    onWebBase(extension)
  end)
end

return {
  registerAddonExtension = registerAddonExtension,
  register = registerAddonExtension
}
