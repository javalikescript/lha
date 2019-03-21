local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local File = require('jls.io.File')
local json = require('jls.util.json')
local EngineItem = require('lha.engine.EngineItem')
local Device = require('lha.engine.Device')

--- A Plugin class.
-- @type Plugin
return class.create(EngineItem, function(plugin, super)

  --- Creates a Plugin.
  -- Available events are:
  --  refresh: called depending on the configuration schedule
  --  startup: called after all the plugin have been loaded
  --  shutdown: called prior to stop the engine
  -- @function Plugin:new
  -- @param engine the engine that holds this plugin.
  -- @param dir the plugin directory
  -- @tparam table manifest the plugin manifest
  function plugin:initialize(engine, dir, manifest)
    super.initialize(self, engine, 'plugin', dir:getName())
    self.dir = dir
    self.manifest = manifest
    self.devices = {}
  end

  function plugin:getDir()
    return self.dir
  end

  function plugin:getManifest()
    return self.manifest
  end

  function plugin:getDeviceId(id)
    return self.id..'_'..id
  end

  function plugin:registerDevice(id, t)
    id = id or 'unknown'
    local device = Device:new(self:getEngine(), self:getDeviceId(id))
    table.insert(self.devices, device)
    if t then
      device:setDeviceData(t)
    end
    return device
  end

  function plugin:loadItem()
    -- TODO handle dependencies
    local mainFile = File:new(self.dir, 'main.lua')
    if mainFile:isFile() then
      logger:debug('loading plugin '..self.id)
      local pluginFn, err = loadfile(mainFile:getPath())
      if not pluginFn or err then
        logger:warn('Cannot load plugin "'..self.id..'" from "'..mainFile:getPath()..'" due to '..tostring(err))
      else
        pluginFn(self)
      end
    end
  end

  function plugin:cleanItem()
    for _, device in ipairs(self.devices) do
      device:cleanItem()
    end
    self.devices = {}
    super.cleanItem(self)
  end

  function plugin:getDevices()
    return self.devices
  end

  function plugin:getDevice(id)
    local deviceId = self:getDeviceId(id)
    for _, device in ipairs(self.devices) do
      if device:getId() == deviceId then
        return device
      end
    end
    return nil
  end

  function plugin:onPlugin(id, fn)
    local plugin = self:getEngine():getPlugin(id)
    if plugin then
      fn(plugin)
      return true
    end
    return false
  end

  function plugin:publishDevicesEvent(...)
    for _, device in ipairs(self.devices) do
      device:publishItemEvent(...)
    end
  end

  function plugin:publishItemEvent(...)
    super.publishItemEvent(self, ...)
    self:publishDevicesEvent(...)
  end

end, function(Plugin)

  function Plugin.read(engine, dir)
    local manifestFile = File:new(dir, 'manifest.json')
    if not manifestFile:isFile() then
      return nil
    end
    logger:debug('reading manifest for plugin '..dir:getName())
    local manifest = json.decode(manifestFile:readAll())
    return Plugin:new(engine, dir, manifest)
  end

end)