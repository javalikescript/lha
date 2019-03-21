local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local tables = require('jls.util.tables')
local File = require('jls.io.File')
local EngineItem = require('lha.engine.EngineItem')

--- A Script class.
-- @type Script
return class.create(EngineItem, function(script, super)

  --- Creates a Script.
  -- @function Script:new
  function script:initialize(engine, dir, id)
    super.initialize(self, engine, 'script', id)
    self.dir = dir
    self.id = id
    self.file = File:new(self.dir, self.id..'.lua')
    self.lastModified = 0
  end

  function script:getValue(path)
    return tables.getPath(self.engine.root, path, '')
  end

  function script:fireChange(path, value)
    --self.engine:publishItemsEvent(self, 'change', path, value)
    self:fireItemEvent('change', path, value)
  end

  function script:setValue(path, value)
    --tables.setPath(self.engine.root, path, value)
    self.engine:setRootValue(self, path, value, true)
    --self.engine:setDataValue(self, path, value)
  end

  function script:refresh()
    if self.file:isFile() then
      local lastModified = self.file:lastModified()
      if lastModified > self.lastModified then
        logger:info('reloading script '..self.id)
        self.lastModified = lastModified
        self:reloadItem()
      end
    else
      self.lastModified = 0
      self:cleanItem()
    end
  end

  function script:loadItem()
    self:subscribeEvent('poll', function()
      self:refresh()
    end)
    if self.file:isFile() then
      if logger:isLoggable(logger.FINE) then
        logger:fine('loading script '..self.id)
      end
      self.lastModified = self.file:lastModified()
      local scriptPath = self.file:getPath()
      local scriptFn, err = loadfile(scriptPath)
      if not scriptFn or err then
        logger:warn('Cannot load script "'..self.id..'" from "'..scriptPath..'" due to '..tostring(err))
      else
        scriptFn(self)
      end
    end
  end

end)