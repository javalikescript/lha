local extension = ...

local logger = extension:getLogger()
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local ProxyHttpHandler = require('jls.net.http.handler.ProxyHttpHandler')
local WebDavHttpHandler = require('jls.net.http.handler.WebDavHttpHandler')
local utils = require('lha.utils')

local function isValidPath(name)
  if not name or name == '' or name == 'engine' or name == 'things' then
    logger:warn('Invalid share name "%s"', name)
    return false
  end
  return true
end

extension:subscribeEvent('startup', function()
  local configuration = extension:getConfiguration()
  if configuration.shares then
    for _, share in ipairs(configuration.shares) do
      local dir = utils.getAbsoluteFile(share.dir or 'share', extension:getDir())
      if not dir:exists() then
        logger:warn('Share directory "%s" not found', dir)
      elseif not dir:isDirectory() then
        logger:warn('Invalid share directory "%s"', dir)
      end
      if isValidPath(share.name) then
        logger:info('Share directory "%s" on "%s"', dir, share.name)
        local path = '/'..share.name..'/(.*)'
        if share.useWebDAV then
          extension:addContext(path, WebDavHttpHandler:new(dir, share.permissions))
        else
          extension:addContext(path, FileHttpHandler:new(dir, share.permissions))
        end
      end
    end
  end
  if configuration.proxies then
    for _, proxy in ipairs(configuration.proxies) do
      if isValidPath(proxy.name) and proxy.url then
        logger:info('Reverse proxy to "%s" on "%s"', proxy.url, proxy.name)
        local path = '/'..proxy.name..'/(.*)'
        extension:addContext(path, ProxyHttpHandler:new():configureReverse(proxy.url))
      end
    end
  end
end)
