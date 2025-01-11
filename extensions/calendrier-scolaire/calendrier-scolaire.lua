local extension = ...

local logger = extension:getLogger()
local Promise = require('jls.lang.Promise')
local HttpClient = require('jls.net.http.HttpClient')
local Url = require('jls.net.Url')
local Date = require('jls.util.Date')

local Thing = require('lha.Thing')

local function concatPath(a, b)
  if string.find(a, '/$') then
    return a..b
  end
  return a..'/'..b
end

local function createThing()
  return Thing:new('School Calendar', 'French school calendar', 'BinarySensor'):addProperty('holiday', {
    ['@type'] = 'BooleanProperty',
    title = 'Holiday',
    type = 'boolean',
    description = 'Holiday',
    readOnly = true
  }, '')
end

local function whereIn(name, year)
  return string.format("%s > date'%s-01-01' and %s < date'%s-12-31'", name, year, name, year)
end

local function getRecords(year)
  local configuration = extension:getConfiguration()
  local url = Url:new(configuration.apiUrl) -- https://data.opendatasoft.com/api/explore/v2.1/
  local path = concatPath(url:getPath(), 'catalog/datasets/'..configuration.datasetId..'/records')
  local resource = path..'?'..Url.mapToQuery({limit = 20, refine = {
    'location:"'..configuration.location..'"', 'population:"-"'
  }, where = string.format("(%s) or (%s)", whereIn('start_date', year), whereIn('end_date', year))})
  logger:fine('fetching %s', resource)
  local client = HttpClient:new(url)
  return client:fetch(resource):next(function(response)
    if response:getStatusCode() == 200 then
      return response:json()
    end
    return Promise.reject('Response status is '..response:getStatusCode())
  end):next(function(records)
    if type(records) == 'table' and type(records.results) == 'table' and #records.results == records.total_count and records.total_count > 0 then
      return records.results
    end
    return Promise.reject('Invalid response')
  end):finally(function()
    client:close()
  end)
end

local function findRecord(records, time)
  for _, record in ipairs(records) do
    local startTime = Date.fromISOString(record.start_date, true)
    local endTime = Date.fromISOString(record.end_date, true)
    if time >= startTime and time < endTime then
      return record
    end
  end
end

local function updateThing(thing, records)
  local holiday = findRecord(records, Date.now()) ~= nil
  --logger:info('updateThing() christmas: %s, holiday: %s', findRecord(records, Date.fromISOString('2025-12-25', true)) ~= nil, holiday)
  logger:fine('updateThing() holiday: %s', holiday)
  thing:updatePropertyValue('holiday', holiday)
end

local year
local records
local thing

local function update()
  if thing then
    local y = os.date('%Y')
    if records and y == year then
      updateThing(thing, records)
    else
      getRecords(y):next(function(r)
        logger:fine('records %T', r)
        records = r
        year = y
        if logger:isLoggable(logger.INFO) then
          for _, record in ipairs(records) do
            logger:info('%s %s %s', record.start_date, record.end_date, record.description)
          end
        end
        updateThing(thing, records)
      end):catch(function(reason)
        logger:warn('Fail to fetch records due to %s', reason)
      end)
    end
  end
end

extension:subscribeEvent('things', function()
  thing = extension:syncDiscoveredThingByKey('calendrier-scolaire', createThing)
  update()
end)

extension:subscribeEvent('refresh', update)
