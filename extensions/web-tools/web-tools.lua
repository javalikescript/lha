local extension = ...

local Pipe = require('jls.io.Pipe')
local StreamHandler = require('jls.io.StreamHandler')
local StringBuffer = require('jls.lang.StringBuffer') 
local ProcessBuilder = require('jls.lang.ProcessBuilder')
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
local LogHttpFilter = require('jls.net.http.filter.LogHttpFilter')

local hasPermission = extension:require('users.hasPermission', true)

local logFilter
local contexts = {}

local function cleanup(server)
  for _, context in ipairs(contexts) do
    server:removeContext(context)
  end
  contexts = {}
  if logFilter then
    server:removeFilter(logFilter)
    logFilter = nil
  end
end

local function addContext(server, ...)
  local context = server:createContext(...)
  table.insert(contexts, context)
end

extension:subscribeEvent('startup', function()
  local engine = extension:getEngine()
  local server = engine:getHTTPServer()
  cleanup(server)
  addContext(server, '/engine/tools/(.*)', RestHttpHandler:new({
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
  engine:onExtension('web-base', function(webBaseExtension)
    webBaseExtension:registerAddonExtension(extension, true)
  end)
  if extension:getConfiguration().log then
    logFilter = LogHttpFilter:new()
    server:addFilter(logFilter)
  end
end)

extension:subscribeEvent('shutdown', function()
  local engine = extension:getEngine()
  local server = engine:getHTTPServer()
  engine:onExtension('web-base', function(webBaseExtension)
    webBaseExtension:unregisterAddonExtension(extension)
  end)
  cleanup(server)
end)
