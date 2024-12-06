local extension = ...

local Pipe = require('jls.io.Pipe')
local StreamHandler = require('jls.io.StreamHandler')
local StringBuffer = require('jls.lang.StringBuffer') 
local ProcessBuilder = require('jls.lang.ProcessBuilder')
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
local LogHttpFilter = require('jls.net.http.filter.LogHttpFilter')

local hasPermission = extension:require('users.hasPermission', true)
local webBaseAddons = extension:require('web-base.addons', true)

webBaseAddons.registerAddonExtension(extension)

local logFilter

local function cleanup()
  if logFilter then
    local server = extension:getEngine():getHTTPServer()
    server:removeFilter(logFilter)
    logFilter = nil
  end
end

extension:subscribeEvent('startup', function()
  local engine = extension:getEngine()
  local server = engine:getHTTPServer()
  cleanup()
  extension:addContext('/engine/tools/(.*)', RestHttpHandler:new({
    ['run?method=POST'] = function(exchange)
      if not hasPermission(exchange, 'rwca') then
        return false
      end
      local script = exchange:getRequest():getBody()
      local fn, err = load(table.concat({
        'local b, engine = ...',
        'print = function(v, ...)',
          'b:append(tostring(v))',
          'if ... then',
            'for _, w in ipairs({...}) do',
              'b:append("\\t"):append(tostring(w))',
            'end',
          'end',
          'b:append("\\n")',
        'end',
        script
      }, '\n'), 'tools/run', 't')
      local b = StringBuffer:new()
      if fn then
        fn(b, engine)
        return b:toString()
      end
      return err or 'Error'
    end,
    ['execute?method=POST'] = function(exchange)
      if not hasPermission(exchange, 'rwca') then
        return false
      end
      local command = exchange:getRequest():getBody()
      local args = {'/bin/sh', '-c', command}
      local pb = ProcessBuilder:new(args)
      local sb = StreamHandler.buffer()
      local p = Pipe:new()
      pb:setRedirectOutput(p)
      local ph = assert(pb:start())
      p:readStart(sb)
      return ph:ended():next(function(exitCode)
        p:close()
        return sb:getBuffer()
      end)
    end
  }))
  if extension:getConfiguration().log then
    logFilter = LogHttpFilter:new()
    server:addFilter(logFilter)
  end
end)

extension:subscribeEvent('shutdown', cleanup)
