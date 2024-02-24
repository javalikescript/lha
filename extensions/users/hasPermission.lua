local HttpExchange = require('jls.net.http.HttpExchange')

return function(exchange, minPermission)
  local session = exchange:getSession()
  local permission = session.attributes.permission or ''
  if permission < minPermission then
    HttpExchange.forbidden(exchange)
    return false
  end
  return true
end
