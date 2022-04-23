local logger = require('jls.lang.logger')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HttpExchange = require('jls.net.http.HttpExchange')
local json = require('jls.util.json')
local tables = require('jls.util.tables')

return function(exchange)
  local request = exchange:getRequest()
  local context = exchange:getContext()
  local engine = context:getAttribute('engine')
  local publish = context:getAttribute('publish') == true
  local basePath = context:getAttribute('path') or ''
  local method = string.upper(request:getMethod())
  local path = exchange:getRequestArguments()
  local tp = basePath..string.gsub(path, '/$', '')
  if logger:isLoggable(logger.FINE) then
    logger:fine('tableHandler(), method: "'..method..'", path: "'..tp..'"')
  end
  if method == HTTP_CONST.METHOD_GET then
    local value = tables.getPath(engine.root, tp)
    if value then
      HttpExchange.ok(exchange, json.encode({
        value = value
      }), 'application/json')
    else
      HttpExchange.notFound(exchange)
    end
  elseif not context:getAttribute('editable') then
    HttpExchange.methodNotAllowed(exchange)
  elseif method == HTTP_CONST.METHOD_PUT or method == HTTP_CONST.METHOD_POST then
    if logger:isLoggable(logger.FINEST) then
      logger:finest('tableHandler(), request body: "'..request:getBody()..'"')
    end
    local rt = json.decode(request:getBody())
    if type(rt) == 'table' and rt.value then
      engine:setRootValues(tp, rt.value, publish, method == HTTP_CONST.METHOD_PUT)
    end
    HttpExchange.ok(exchange)
  else
    HttpExchange.methodNotAllowed(exchange)
  end
  if logger:isLoggable(logger.FINE) then
    logger:fine('tableHandler(), status: '..tostring(exchange:getResponse():getStatusCode()))
  end
end
