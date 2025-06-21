local extension = ...

local logger = extension:getLogger()
local File = require('jls.io.File')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
local HttpExchange = require('jls.net.http.HttpExchange')
local json = require('jls.util.json')
local Date = require('jls.util.Date')
local strings = require('jls.util.strings')
local ZipFile = require('jls.util.zip.ZipFile')

local webBaseAddons = extension:require('web-base.addons', true)

webBaseAddons.register(extension)

local function deployScript(exchange, engine, extId)
  local zipName = exchange:getRequest():getBody() or 'lha-ext.zip'
  local backup = File:new(engine:getTemporaryDirectory(), zipName)
  if not backup:isFile() then
    HttpExchange.notFound(exchange)
    return false
  end
  local extDir = File:new(engine:getScriptsDirectory(), extId)
  if extDir:exists() or not extDir:mkdir() then
    HttpExchange.internalServerError(exchange)
    return false
  end
  if not ZipFile.unzipTo(backup, extDir) then
    extDir:deleteRecursive()
    HttpExchange.badRequest(exchange)
    return false
  end
  logger:fine('Deployed script "%s"', extId)
  engine:loadExtensionFromDirectory(extDir, 'script')
  return extId
end

local function replaceProperties(scriptsDir, changes, dryRun)
  logger:fine('replaceProperties(%s, %T)', scriptsDir, changes)
  local delimitersByName = {
    ['blocks.xml'] = {'>', '<'},
    ['script.lua'] = {"'", "'"},
    ['config.json'] = {'"', '"'},
  }
  local replace = not dryRun
  local count = 0
  local fileCount = 0
  local propertyCount = 0
  local names = {}
  local scriptDirs = scriptsDir:listFiles()
  if scriptDirs and type(changes) == 'table' then
    for _, scriptDir in ipairs(scriptDirs) do
      local files = scriptDir:listFiles()
      if files then
        local n = 0 -- modified files
        for _, file in ipairs(files) do
          local pc = 0 -- modified properties
          local delimiters = delimitersByName[file:getName()]
          if delimiters then
            local content = file:readAll()
            local changed = false
            for _, change in ipairs(changes) do
              local from = change.from
              if from then
                local f = delimiters[1]..from..delimiters[2]
                if string.find(content, f, 1, true) then
                  changed = true
                  logger:finer('Property "%s" found in "%s"', from, file)
                  if replace then
                    local t = delimiters[1]..change.to..delimiters[2]
                    local c
                    content, c = string.gsub(content, strings.escape(f), t)
                    pc = pc + c
                  end
                end
              end
            end
            if changed then
              n = n + 1
              if pc > 0 then
                propertyCount = propertyCount + pc
                file:write(content)
              end
            end
          end
        end
        if n > 0 then
          fileCount = fileCount + n
          count = count + 1
          table.insert(names, scriptDir:getName())
        end
      end
    end
  end
  return {count = count, fileCount = fileCount, propertyCount = propertyCount, names = names}
end


local REST_SCRIPTS = {
  ['(engine)?method=GET'] = function(_, engine)
    local list = {}
    for _, ext in ipairs(engine.extensions) do
      if ext:getType() == 'script' then
        local item = ext:toJSON()
        item.hasBlocks = File:new(ext:getDir(), 'blocks.xml'):isFile()
        item.hasView = File:new(ext:getDir(), 'view.xml'):isFile()
        table.insert(list, item)
      end
    end
    return list
  end,
  ['(engine, name, script)?method=PUT&:LHA-Name-=name&:LHA-Script-=script'] = function(_, engine, name, script)
    local extId = engine:generateId()
    local extDir = File:new(engine:getScriptsDirectory(), extId)
    extDir:mkdir()
    if not script then
      script = 'script.lua'
      local scriptFile = File:new(extDir, script)
      scriptFile:write('local script = ...\n\n')
    end
    local manifestFile = File:new(extDir, 'manifest.json')
    local manifest = {
      name = name or 'New script',
      version = '1.0',
      script = script
    }
    manifestFile:write(json.stringify(manifest, 2))
    logger:fine('Created script "%s"', extId)
    engine:loadExtensionFromDirectory(extDir, 'script')
    return extId
  end,
  ['(engine)?method=POST'] = function(exchange, engine)
    return deployScript(exchange, engine, engine:generateId())
  end,
  ['{+}(engine)'] = function(exchange, name, engine)
    local ext = engine:getExtensionById(name)
    if ext and ext:getType() == 'script' then
      exchange:setAttribute('extension', ext)
    end
  end,
  ['{extensionId}'] = {
    ['(engine, extension)?method=DELETE'] = function(_, engine, ext)
      local extensionDir = ext:getDir()
      if ext:isActive() then
        ext:publishEvent('shutdown')
      end
      ext:cleanExtension()
      engine:removeExtension(ext)
      extensionDir:deleteRecursive()
    end,
    ['deploy(engine, extensionId)?method=PUT'] = function(exchange, engine, extId)
      return deployScript(exchange, engine, extId)
    end,
    ['export(engine, extension)'] = function(_, engine, ext)
      local backup = File:new(engine:getTemporaryDirectory(), 'lha-ext-'..ext:getId()..'.'..Date.timestamp()..'.zip')
      return ZipFile.zipToAsync(backup, ext:getDir():listFiles()):next(function()
        return backup:getName()
      end)
    end,
    ['reload(extension)'] = function(_, ext)
      ext:restartExtension()
    end,
    ['name(extension)?method=PUT'] = function(exchange, ext)
      local name = exchange:getRequest():getBody()
      local extensionDir = ext:getDir()
      local manifestFile = File:new(extensionDir, 'manifest.json')
      ext.manifest.name = name
      manifestFile:write(json.stringify(ext.manifest, 2))
      return 'Renamed'
    end
  },
}

function extension:replaceProperties(exchange, changes, dryRun)
  logger:fine('replaceProperties(%T, %s)', changes, dryRun)
  local engine = extension:getEngine()
  local result = replaceProperties(engine:getScriptsDirectory(), changes, dryRun)
  if dryRun then
    logger:info('replaceProperties() -> %T', result)
  else
    logger:fine('replaceProperties() -> %T', result)
    --engine:reloadScripts(false) -- TODO reload only modified scripts
  end
  return string.format('%s scripts modified, %s properties in %s files', result.count, result.propertyCount, result.fileCount)
end

extension:subscribeEvent('startup', function()
  local engine = extension:getEngine()
  extension:addContext('/engine/scripts/(.*)', RestHttpHandler:new(REST_SCRIPTS, {engine = engine}))
  extension:addContext('/engine/scriptFiles/(.*)', FileHttpHandler:new(engine:getScriptsDirectory(), 'rw'))
end)

-- TODO use event to replace properties in all extensions
--extension:subscribeEvent('replaceProperties', function(changes, dryRun) end)
