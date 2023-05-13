local extension = ...

local class = require('jls.lang.class')
local logger = require('jls.lang.logger')
local RestHttpHandler = require('jls.net.http.handler.RestHttpHandler')
local HttpExchange = require('jls.net.http.HttpExchange')
local strings = require('jls.util.strings')
local tables = require('jls.util.tables')
local Date = require('jls.util.Date')

local HistoricalDataHandler = class.create('jls.net.http.HttpHandler', function(tableHandler)

  function tableHandler:initialize(dataHistory)
    self.dataHistory = dataHistory
  end

  function tableHandler:handle(exchange)
    if HttpExchange.methodAllowed(exchange, 'GET') then
      local path = exchange:getRequestArguments()
      local request = exchange:getRequest()
      local toTime = tonumber(request:getHeader("X-TO-TIME"))
      if toTime then
        toTime = toTime * 1000
      end
      local period = tonumber(request:getHeader("X-PERIOD"))
      if not period then
        local t
        local tp = string.gsub(path, '/$', '')
        if toTime then
          t = self.dataHistory:getTableAt(toTime) or {}
        else
          t = self.dataHistory:getLiveTable()
        end
        RestHttpHandler.replyJson(exchange, {
          value = tables.getPath(t, '/'..tp)
        })
        return
      end
      local fromTime = tonumber(request:getHeader("X-FROM-TIME"))
      local subPaths = request:getHeader("X-PATHS")
      if logger:isLoggable(logger.FINE) then
        logger:fine('process data request '..tostring(fromTime)..' - '..tostring(toTime)..' / '..tostring(period)..' on "'..tostring(path)..'"')
      end
      period = period * 1000
      if not toTime then
        toTime = Date.now()
      end
      if fromTime then
        fromTime = fromTime * 1000
      else
        -- use 100 data points by default
        fromTime = toTime - period * 100
      end
      if fromTime < toTime and ((toTime - fromTime) / period) < 10000 then
        local result
        if subPaths then
          local paths = strings.split(subPaths, ',')
          for i = 1, #paths do
            paths[i] = path..paths[i]
          end
          result = self.dataHistory:loadMultiValues(fromTime, toTime, period, paths)
        else
          -- TODO provide property types
          result = self.dataHistory:loadValues(fromTime, toTime, period, path)
        end
        RestHttpHandler.replyJson(exchange, result)
      else
        HttpExchange.badRequest(exchange)
      end
    end
  end
end)

local context

local function cleanup(server)
  if context then
    server:removeContext(context)
  end
end

extension:subscribeEvent('startup', function()
  local engine = extension:getEngine()
  local server = engine:getHTTPServer()
  cleanup(server)
  -- TODO Move to extension handler
  context = server:createContext('/engine/historicalData/(.*)', HistoricalDataHandler:new(engine.dataHistory))
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
