local extension = ...

local logger = require('jls.lang.logger')
local HttpServer = require('jls.net.http.HttpServer')
local BasicAuthenticationHttpFilter = require('jls.net.http.filter.BasicAuthenticationHttpFilter')
local Date = require('jls.util.Date')
local secure = require('jls.net.secure')
local utils = require('lha.utils')

local function writeCertificateAndPrivateKey(certFile, pkeyFile, commonName)
  local cacert, pkey = secure.createCertificate({
    --duration = (3600 * 24 * (365 + 31)),
    commonName = commonName
  })
  local cacertPem  = cacert:export('pem')
  local pkeyPem  = pkey:export('pem')
  certFile:write(cacertPem)
  pkeyFile:write(pkeyPem)
end

local function readCertificate(certFile)
  -- Certificate must have cer extension to be imported in windows phone
  -- openssl x509 -outform der -in cert.pem -out cert.cer
  -- openssl x509 -inform der -in cert.cer -out cert.pem
  local cert = secure.readCertificate(certFile:readAll())
  return cert
end

local httpSecureServer

local function closeServer()
  if httpSecureServer then
    httpSecureServer:close(false)
    httpSecureServer = nil
  end
end

extension:subscribeEvent('startup', function()
  local configuration = extension:getConfiguration()
  closeServer()

  local engine = extension:getEngine()
  local httpServer = engine:getHTTPServer()

  local certFile = utils.getAbsoluteFile(configuration.certificate, engine:getWorkDirectory())
  local pkeyFile = utils.getAbsoluteFile(configuration.key, engine:getWorkDirectory())
  if not certFile:exists() or not pkeyFile:exists() then
    writeCertificateAndPrivateKey(certFile, pkeyFile, configuration.commonName)
    logger:info('Generate certificate '..certFile:getPath()..' and associated private key '..pkeyFile:getPath())
  else
    -- check and log certificate expiration
    local cert = readCertificate(certFile)
    local isValid, notbefore, notafter = cert:validat()
    local notafterDate = Date:new(notafter:get() * 1000)
    local notafterText = notafterDate:toISOString(true)
    logger:info('Using certificate '..certFile:getPath()..' valid until '..notafterText)
    if not isValid then
      logger:warn('The certificate is no more valid since '..notafterText)
    end
  end

  httpSecureServer = HttpServer.createSecure({
    certificate = certFile:getPath(),
    key = pkeyFile:getPath()
  })
  httpSecureServer:bind(configuration.address, configuration.port):next(function()
    logger:info('Server secure bound to "'..tostring(configuration.address)..'" on port '..tostring(configuration.port))
  end, function(err) -- could fail if address is in use or hostname cannot be resolved
    logger:warn('Cannot bind HTTP secure server to "'..tostring(configuration.address)..'" on port '..tostring(configuration.port)..' due to '..tostring(err))
  end)
  -- share contexts
  httpSecureServer:setParentContextHolder(httpServer)
  if type(configuration.credentials) == 'table' and next(configuration.credentials) then
    local namePasswordMap = {}
    for _, credential in ipairs(configuration.credentials) do
      namePasswordMap[credential.name] = credential.password
    end
    httpSecureServer:addFilter(BasicAuthenticationHttpFilter:new(namePasswordMap, 'LHA'))
  end
end)

extension:subscribeEvent('poll', function()
  if httpSecureServer then
    httpSecureServer:closePendings(3600)
  end
end)

extension:subscribeEvent('shutdown', function()
  logger:info('shutdown MQTT Broker extension')
  closeServer()
end)
