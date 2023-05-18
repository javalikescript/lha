local HttpExchange = require('jls.net.http.HttpExchange')
local HttpFilter = require('jls.net.http.HttpFilter')

local location = '/login.html'

return HttpFilter.byPath(HttpFilter:new(function(_, exchange)
  local session = exchange:getSession()
  if session and not session.attributes.user then
    HttpExchange.redirect(exchange, location)
    return false
  end
end)):excludePath(location, '/login')
