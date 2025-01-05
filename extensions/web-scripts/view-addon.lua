local extension = ...

local webBaseAddons = extension:require('web-base.addons', true)

webBaseAddons.register(extension, 'init.js')
