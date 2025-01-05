local extension = ...
local loader = require('jls.lang.loader')
local coreExtPath = extension:getEngine().lhaExtensionsDir:getPath()
local webBaseAddons = loader.load('web-base.addons', coreExtPath)
webBaseAddons.register(extension, 'init.js')