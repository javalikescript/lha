local extension = ...

local logger = require('jls.lang.logger')
local class = require('jls.lang.class')
local Promise = require('jls.lang.Promise')
local HttpClient = require('jls.net.http.HttpClient')
local Url = require('jls.net.Url')

local Thing = require('lha.Thing')
local utils = require('lha.utils')

-- Helper classes and functions

local FreeMobileSms = class.create(function(freeMobileSms)

  function freeMobileSms:initialize(apiUrl, user, pass)
    self.apiUrl = apiUrl
    self.user = user
    self.pass = pass
  end

  function freeMobileSms:getUser()
    return self.user
  end

  --[[
  200 : Le SMS a été envoyé sur votre mobile.
  400 : Un des paramètres obligatoires est manquant.
  402 : Trop de SMS ont été envoyés en trop peu de temps.
  403 : Le service n'est pas activé sur l'espace abonné, ou login / clé incorrect.
  500 : Erreur côté serveur. Veuillez réessayer ultérieurement.
  ]]

  function freeMobileSms:sendMessage(msg)
    logger:info('Sending message: "%s"', msg)
    local url = Url:new(self.apiUrl or 'https://smsapi.free-mobile.fr/sendmsg')
    local resource = url:getFile()..'?'..Url.mapToQuery({user = self.user, pass = self.pass, msg = msg})
    local client = HttpClient:new(url)
    return client:fetch(resource):next(function(response)
      response:consume()
      local statusCode, reason = response:getStatusCode()
      if statusCode == 200 then
        logger:fine('SMS sent')
      elseif statusCode == 403 then
        return Promise.reject('The SMS service is not activated')
      else
        return Promise.reject('Error '..tostring(statusCode)..' sending SMS, '..tostring(reason))
      end
    end):finally(function()
      client:close()
    end)
  end

end)
-- End Helper classes and functions

local configuration = extension:getConfiguration()

local fms

extension:subscribeEvent('startup', function()
  if configuration.apiUrl and configuration.user and configuration.pass then
    fms = FreeMobileSms:new(configuration.apiUrl, configuration.user, configuration.pass)
    logger:info('FreeMobileSms user is "%s"', fms:getUser())
  end
end)

function extension:sendSMS(msg)
  if fms then
    return fms:sendMessage(msg)
  end
  return Promise.reject('Extension not started')
end

local function onMessage(property, value)
  value = type(value) == 'string' and string.match(value, '^%s*(.-)%s*$') or ''
  if fms and value ~= '' then
    fms:sendMessage(value):catch(function(reason)
      logger:warn('Unable to send SMS, due to %s', reason)
    end)
  end
end

local function createThing(targetName)
  return Thing:new('FreeMobileSms', 'FreeMobileSms Message', {'Message'}):addProperty('message', {
    ['@type'] = 'MessageProperty',
    title = 'Message',
    type = 'string',
    description = 'Send the message',
    writeOnly = true
  }, '')
end

extension:subscribeEvent('things', function()
  local thing = extension:syncDiscoveredThingByKey('lua', createThing)
  local p = thing:getProperty('message')
  if p then
    p.setValue = onMessage
  end
end)
