local system = require('jls.lang.system')

local function padLeft(s, l, c)
  local sl = #s
  if sl < l then
    return string.rep(c or '0', l - sl)..s
  elseif sl > l then
    return string.sub(s, -l)
  end
  return s
end

-- The character order is respected to allow comparison
-- The characters are usable as file name or URL path
local CHARS = '-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz'

local function formatInteger(i, radix, l)
  if not radix or radix > #CHARS then
    radix = 10
  end
  local m
  local s = ''
  while i > 0 do
    m = (i % radix) + 1
    i = i // radix
    s = string.sub(CHARS, m, m)..s
  end
  if l then
    return padLeft(s, l)
  end
  return s
end

local RADIX = 64

local function maxIdPart(l)
  return math.floor(RADIX ^ l)
end

local function formatIdPart(i, l)
  return formatInteger(i % maxIdPart(l), RADIX, l)
end

-- using 64^5 for seconds there will be possible collisions every 34 years
local PREFIX_LEN = 7
local TIME_LEN = 2
local TIME_MAX = maxIdPart(TIME_LEN)
-- 64^5 contains 1 billion distinct values, 64^4 contains 16 million distinct values
local INDEX_LEN = 5
local INDEX_MAX = maxIdPart(INDEX_LEN)

local function getTimeMillis()
  return system.currentTimeMillis()
  --return os.time() * 1000
end

-- This id generator is a compromise between collisions, readability, simplicity, shortness and usability.
-- The ids are generated using the generator instanciation time, the id generation time and index.
-- The ids have 14 characters length and are usable as file name or URL path.
return require('jls.lang.class').create(function(idGenerator)

  function idGenerator:initialize()
    local time = getTimeMillis()
    self:setInitTime(time)
    self.lastTime = time
  end

  function idGenerator:setInitTime(time)
    math.randomseed(time)
    self.index = 0
    self.initTime = time
    self.baseIndex = math.random(INDEX_MAX)
    self.baseTime = math.random(TIME_MAX)
    self.baseId = formatIdPart(time, PREFIX_LEN)
  end

  function idGenerator:getIndex()
    return self.index
  end

  -- Returns a newly generated id
  function idGenerator:generate()
    local time = getTimeMillis()
    self.index = self.index + 1
    if self.index > INDEX_MAX then
      self:setInitTime(self.lastTime)
    end
    self.lastTime = time
    return formatIdPart(self.baseIndex + self.index, INDEX_LEN)..self.baseId..formatIdPart(self.baseTime + (time - self.initTime), TIME_LEN)
  end

end)
