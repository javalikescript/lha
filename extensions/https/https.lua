local extension = ...

local logger = extension:getLogger()
local Promise = require('jls.lang.Promise')
local File = require('jls.io.File')
local secure = require('jls.net.secure')
local HttpServer = require('jls.net.http.HttpServer')
local HttpExchange = require('jls.net.http.HttpExchange')
local FileHttpHandler = require('jls.net.http.handler.FileHttpHandler')
local Date = require('jls.util.Date')

local utils = require('lha.utils')

-- TODO Use a passhprase to protect private keys

local function writeCertificateAndPrivateKey(certFile, pkeyFile, commonName)
  local cacert, pkey
  if pkeyFile:exists() then
    pkey = secure.readPrivateKey(pkeyFile:readAll(), 'pem')
  end
  cacert, pkey = secure.createCertificate({
    commonName = commonName,
    privateKey = pkey
  })
  local cacertPem = cacert:export('pem')
  certFile:write(cacertPem)
  if not pkeyFile:exists() then
    local pkeyPem  = pkey:export('pem')
    pkeyFile:write(pkeyPem)
  end
end

local function readCertificate(certFile)
  -- Certificate must have cer extension to be imported in windows phone
  -- openssl x509 -outform der -in cert.pem -out cert.cer
  -- openssl x509 -inform der -in cert.cer -out cert.pem
  local cert = secure.readCertificate(certFile:readAll())
  return cert
end

local httpSecureServer, httpRedirectServer

local function closeServer()
  if httpSecureServer then
    httpSecureServer:close(false)
    httpSecureServer = nil
  end
  if httpRedirectServer then
    httpRedirectServer:close(false)
    httpRedirectServer = nil
  end
end

function extension:getHTTPServer()
  return httpSecureServer
end

local function startSecureServer(certFile, pkeyFile)
  local configuration = extension:getConfiguration()

  httpSecureServer = HttpServer.createSecure({
    certificate = certFile:getPath(),
    key = pkeyFile:getPath(),
    alpnSelectProtos = configuration.h2 and {'h2', 'http/1.1'} or nil,
  })
  httpSecureServer:bind(configuration.address, configuration.port):next(function()
    logger:info('Server secure bound to "%s" on port %s', configuration.address, configuration.port)
  end, function(err) -- could fail if address is in use or hostname cannot be resolved
    logger:warn('Cannot bind HTTP secure server to "%s" on port %s due to %s', configuration.address, configuration.port, err)
  end)
  if configuration.login then
    local redirect = extension:require('users.login-redirect', true)
    httpSecureServer:addFilter(redirect)
  end
  -- share contexts
  httpSecureServer:setParentContextHolder(extension:getEngine():getHTTPServer())
end

extension:subscribeEvent('startup', function()
  local configuration = extension:getConfiguration()
  local workDir = extension:getEngine():getWorkDirectory()
  local certFile = utils.getAbsoluteFile(configuration.certificate, workDir)
  local pkeyFile = utils.getAbsoluteFile(configuration.key, workDir)
  local acmeDir

  closeServer()

  if configuration.httpPort and configuration.httpPort > 0 then
    acmeDir = File:new(workDir, 'acme-challenge')
    if not acmeDir:isDirectory() then
      acmeDir:mkdir()
      logger:info('ACME challenge directory created "%s"', acmeDir)
    end
    httpRedirectServer = HttpServer:new()
    httpRedirectServer:bind(configuration.address, configuration.httpPort):next(function()
      logger:info('Server redirect bound to "%s" on port %s', configuration.address, configuration.httpPort)
    end, function(err)
      logger:warn('Cannot bind HTTP redirect server to "%s" on port %s due to %s', configuration.address, configuration.httpPort, err)
    end)
    httpRedirectServer:createContext('/%.well%-known/acme%-challenge/(.*)', FileHttpHandler:new(acmeDir))
    httpRedirectServer:createContext('/?.*', function(exchange)
      HttpExchange.redirect(exchange, 'https://'..configuration.commonName..'/') -- TODO Support port redirection
    end)
  end

  local needCreateOrRenew = false
  if not certFile:exists() or not pkeyFile:exists() then
    needCreateOrRenew = true
  else
    -- check and log certificate expiration
    local cert = readCertificate(certFile)
    local isValid, notbefore, notafter = cert:validat()
    local notafterDate = Date:new(notafter:get() * 1000)
    local notafterText = notafterDate:toISOString(true)
    logger:info('Using certificate %s valid until %s', certFile, notafterText)
    if not isValid then
      logger:warn('The certificate is no more valid since %s', notafterText)
      needCreateOrRenew = true
    end
  end
  if needCreateOrRenew then
    if configuration.acme and configuration.acme.enabled and acmeDir then
      local Acme = require('jls.net.Acme')
      local accountKeyFile = utils.getAbsoluteFile(configuration.acme.accountKey, workDir)
      local acme = Acme:new(configuration.acme.url, {
        acmeDir = acmeDir,
        domains = configuration.commonName,
        accountKeyFile = accountKeyFile,
        domainKeyFile = pkeyFile
      })
      return acme:orderCertificate():next(function(rawCertificate)
        local cacert = secure.readCertificate(rawCertificate)
        certFile:write(cacert:export('pem'))
        logger:info('Generated certificate %s and associated private key %s', certFile, pkeyFile)
        startSecureServer(certFile, pkeyFile)
      end):finally(function()
        acme:close()
      end)
    end
    writeCertificateAndPrivateKey(certFile, pkeyFile, configuration.commonName)
    logger:info('Generated self-signed certificate %s and associated private key %s', certFile, pkeyFile)
  end
  startSecureServer(certFile, pkeyFile)
end)

extension:subscribeEvent('poll', function()
  if httpSecureServer then
    httpSecureServer:closePendings(3600)
  end
  if httpRedirectServer then
    httpRedirectServer:closePendings(3600)
  end
end)

extension:subscribeEvent('shutdown', function()
  closeServer()
end)
