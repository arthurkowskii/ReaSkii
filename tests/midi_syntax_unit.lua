-- Compile every current UI/runtime module without requiring REAPER/gfx.
-- This catches errors that pure transformation/adapter tests never load.
local path=debug.getinfo(1,'S').source:sub(2)
local root=(path:match('^(.*[/\\])') or './')..'..'
local passed=0
for _,name in ipairs({'Core','Transformations','Generators','Adapter','Tools'}) do
  local file=root..'/scripts/midi/ReaSkii_MIDI_'..name..'.lua'
  local fn,err=loadfile(file)
  assert(fn,'Cannot compile '..file..': '..tostring(err))
  passed=passed+1
end
print('PASS MIDI syntax: '..passed..' modules')
return {passed=passed}
