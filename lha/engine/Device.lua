local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local tables = require('jls.util.tables')
local EngineItem = require('lha.engine.EngineItem')

--- A Device class.
-- @type Device
return class.create(EngineItem, function(device, super)

  --- Creates a Device.
  -- @function Device:new
  -- @param engine the engine that holds this device.
  -- @tparam string id the device id.
  function device:initialize(engine, id)
    super.initialize(self, engine, 'device', id)
  end

  function device:isDataArchived()
    return tables.getPath(self.engine.root, 'configuration/'..self:getPath('archiveData'), false)
  end

  function device:setDataArchived(value)
    tables.setPath(self.engine.root, 'configuration/'..self:getPath('archiveData'), value)
  end

  function device:applyDeviceData(data, volatile)
    local archiveData
    if volatile == nil then
      archiveData = self:isDataArchived()
    else
      archiveData = not volatile
    end
    self.engine:setDataValues(self, self:getPath(), data, archiveData)
  end

  function device:setDeviceData(data, volatile)
    local archiveData
    if volatile == nil then
      archiveData = self:isDataArchived()
    else
      archiveData = not volatile
    end
    self.engine:setDataValue(self, self:getPath(), data, archiveData)
  end

  function device:getDeviceData()
    return tables.getPath(self.engine.root, 'data/'..self:getPath())
  end

  function device:toJSON()
    local t = super.toJSON(self)
    --t.pluginId = plugin:getId(),
    t.archiveData = self:isDataArchived()
    return t
  end

end)