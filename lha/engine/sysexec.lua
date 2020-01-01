local Promise = require('jls.lang.Promise')
local uv = require('luv')

local function execute(command, callback)
  local cb, d = Promise.ensureCallback(callback)
  local async
  async = uv.new_async(function(status, kind, code)
    if type(code) == 'number' then
      code = math.floor(code)
    end
    if kind == 'exit' then
      cb(nil, code)
    elseif kind == 'signal' then
      cb(nil, 1000 + code)
    else
      cb(kind or 'Error')
    end
    async:close()
  end)
  uv.new_thread(function(async, command)
    local status, kind, code = os.execute(command)
    async:send(status, kind, code)
  end, async, command)
  return d
end

return {
  execute = execute
}
