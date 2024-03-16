local extension = ...

local logger = extension:getLogger()
local Promise = require('jls.lang.Promise')
local SerialWorker = require('jls.util.SerialWorker')

local serialWorker

local function closeServer()
  if serialWorker then
    serialWorker:close()
    serialWorker = nil
  end
end

local function os_execute(cmd)
  local status, kind, code = os.execute(cmd)
  return tostring(status)..' '..kind..' '..tostring(code)
end

function extension:execute(command, anyCode)
  if not serialWorker then
    return Promise.reject('Execute serialWorker not available')
  end
  logger:finer('executing "%s"', command)
  return serialWorker:call(os_execute, command):next(function(result)
    local status, kind, code = string.match(result, '^(%a+) (%a+) %-?(%d+)$')
    if status == 'true' or anyCode then
      if kind == 'exit' then
        return tonumber(code)
      elseif kind == 'signal' then
        return tonumber(code) + 128
      end
    else
      return Promise.reject('Execute fails with '..tostring(kind)..' code '..tostring(code))
    end
  end)
end

extension:subscribeEvent('startup', function()
  closeServer()
  serialWorker = SerialWorker:new()
  logger:info('Execute SerialWorker started')
end)

extension:subscribeEvent('shutdown', function()
  logger:info('Execute SerialWorker stopped')
  closeServer()
end)
