local extension = ...

local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local http = require('jls.net.http')

-- Helper classes and functions

local FreeMobileSms = class.create(function(freeMobileSms)

  function freeMobileSms:initialize(apiUrl, user, pass)
    self.apiUrl = apiUrl or 'https://smsapi.free-mobile.fr/sendmsg'
    self.user = user or ''
    self.pass = pass or ''
    self.usePost = true
  end

  function freeMobileSms:getUser()
    return self.user
  end

  function freeMobileSms:getUrl()
    return apiUrl..'?user='..self.user..'&pass='..self.pass
  end

  function freeMobileSms:getMessageUrl(msg)
    -- encode msg
    --msg = URL.encodePercent(msg)
    return self:getUrl()..'&msg='..msg
  end

  --[[
  200 : Le SMS a été envoyé sur votre mobile.
  400 : Un des paramètres obligatoires est manquant.
  402 : Trop de SMS ont été envoyés en trop peu de temps.
  403 : Le service n'est pas activé sur l'espace abonné, ou login / clé incorrect.
  500 : Erreur côté serveur. Veuillez réessayer ultérieurement.
  ]]

  function freeMobileSms:sendMessage(msg)
    local client
    if self.usePost then
      client = http.Client:new({
        method = 'POST',
        url = self:getUrl(),
        body = msg
      })
    else
      local client = http.Client:new({
        method = 'GET',
        url = self:getMessageUrl(msg)
      })
    end
    return client:connect():next(function()
      logger:debug('client connected')
      return client:sendReceive()
    end):next(function(response)
      client:close()
    end)
  end

end)
-- End Helper classes and functions

local configuration = extension:getConfiguration()

local fms = FreeMobileSms:new(configuration.apiUrl, configuration.user, configuration.pass)
logger:info('FreeMobileSms user is "'..fms:getUser()..'"')

--[[
  extension:watchDataValue(extension:getPath('sms'), function(value, previousValue, path)
    logger:info('FreeMobileSms message: "'..tostring(value)..'"')
    fms:sendMessage(msg)
  end)
]]
