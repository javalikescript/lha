local extension = ...

local StringBuffer = require('jls.lang.StringBuffer') 
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')

local contexts = {}

local function cleanup(server)
  for _, context in ipairs(contexts) do
    server:removeContext(context)
  end
  contexts = {}
end

local function addContext(server, ...)
  local context = server:createContext(...)
  table.insert(contexts, context)
end

--[[
local function os(cmd)
 local f, err = io.popen(cmd)
 if f then
  local r = f:read('a')
  f:close()
  return r
 end
 return err
end
os('uname -a')

local m = {}
for _, v in pairs(debug.getregistry()) do
 local t = type(v)
 if t == 'userdata' then
  local ut = tostring(v)
  ut = string.match(ut, '^([^:]+):.*')
  if ut then
   t = t..':'..ut
  end
 end
 m[t] = (m[t] or 0) + 1
end
for t, c in pairs(m) do
 print(t, c)
end

local c = 0
for cl, ex in pairs(engine:getHTTPServer().pendings) do
  c = c + 1
end
print('pending clients', c)

local luv = require('luv')
print('uname', luv.os_uname())
print('hostname', luv.os_gethostname())
print('pid', luv.os_getpid() >> 0)
print('printing active handles on stdout'); luv.print_active_handles()

require('jls.util.memprof').printReport(function(data)
  print('report', data)
end, false, false, 'csv')
]]
extension:subscribeEvent('startup', function()
  local engine = extension:getEngine()
  local server = engine:getHTTPServer()
  cleanup(server)
  addContext(server, '/engine/tools/(.*)', RestHttpHandler:new({
    ['execute?method=POST'] = function(exchange)
      local script = exchange:getRequest():getBody()
      local fn, err = load(table.concat({
        'local b, engine = ...',
        'print = function(v, ...)',
          'b:append(v)',
          'if ... then',
            'for _, w in ipairs({...}) do',
              'b:append("\\t"):append(w)',
            'end',
          'end',
          'b:append("\\n")',
        'end',
        script
      }, '\n'), 'tools/execute', 't')
      local b = StringBuffer:new()
      if fn then
        fn(b, engine)
        return b:toString()
      end
      return err or 'Error'
    end
  }))
  engine:onExtension('web-base', function(webBaseExtension)
    webBaseExtension:registerAddonExtension(extension, true)
  end)
end)

extension:subscribeEvent('shutdown', function()
  local engine = extension:getEngine()
  local server = engine:getHTTPServer()
  engine:onExtension('web-base', function(webBaseExtension)
    webBaseExtension:unregisterAddonExtension(extension)
  end)
  cleanup(server)
end)