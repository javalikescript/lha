local logger = require('jls.lang.logger')
local HTTP_CONST = require('jls.net.http.HttpMessage').CONST
local HttpExchange = require('jls.net.http.HttpExchange')
local json = require('jls.util.json')
local tables = require('jls.util.tables')

return require('jls.lang.class').create('jls.net.http.HttpHandler', function(tableHandler)

  function tableHandler:initialize(engine, path, editable, publish)
    self.engine = engine
    self.path = path or ''
    self.editable = editable == true
    self.publish = publish == true
  end

  function tableHandler:handle(exchange)
    local request = exchange:getRequest()
    local method = string.upper(request:getMethod())
    local path = exchange:getRequestArguments()
    local tp = self.path..string.gsub(path, '/$', '')
    logger:fine('tableHandler(), method: "%s", path: "%s"', method, tp)
    if method == HTTP_CONST.METHOD_GET then
      local value = tables.getPath(self.engine.root, tp)
      if value then
        HttpExchange.ok(exchange, json.encode({
          value = value
        }), 'application/json')
      else
        HttpExchange.notFound(exchange)
      end
    elseif not self.editable then
      HttpExchange.methodNotAllowed(exchange)
    elseif method == HTTP_CONST.METHOD_PUT or method == HTTP_CONST.METHOD_POST then
      request:bufferBody()
      return request:json():next(function(data)
        if type(data) == 'table' and data.value then
          self.engine:setRootValues(tp, data.value, self.publish, method == HTTP_CONST.METHOD_PUT)
        end
        HttpExchange.ok(exchange)
      end)
    else
      HttpExchange.methodNotAllowed(exchange)
    end
    if logger:isLoggable(logger.FINE) then
      logger:fine('tableHandler(), status: %s', exchange:getResponse():getStatusCode())
    end
  end

end)
