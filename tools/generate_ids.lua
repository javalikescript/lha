local IdGenerator = require('lha.IdGenerator')

local os_time = os.time
local function sleep(millis)
  local t = os_time() + (millis / 1000)
  while os_time() < t do end
end

local function waitNextSecond()
  print('Waiting the next second...')
  sleep(1000)
end


local firstIdGenerator = IdGenerator:new()
waitNextSecond()
local secondIdGenerator = IdGenerator:new()

local function printNewId(idGenerator, text)
  print(' ', idGenerator:generate(), text)
end

for i = 1, 3 do
  waitNextSecond()
  printNewId(firstIdGenerator, 'first')
  printNewId(secondIdGenerator, 'second')
end

print()

--[[
  for i = 1, 100 do
    printNewId(firstIdGenerator, 'first')
  end
]]

--[[
Example:
Z9yc SuHiD HsMsR  first
Z9yc SuHiD C5FY8  second
LHA- SuHiD 00001  prefixed

Z9yc SuHiE HsMsS  first
Z9yc SuHiE C5FY9  second
LHA- SuHiE 00002  prefixed

Z9yc SuHiF HsMsT  first
Z9yc SuHiF C5FYA  second
LHA- SuHiF 00003  prefixed
]]
