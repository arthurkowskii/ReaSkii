-- Regression tests for review findings, run inside real REAPER MIDI takes.
local root = assert(REASKII_ROOT)
local output = assert(REASKII_RESULT)
local f = assert(io.open(output, 'w'))
local count = 0
local function check(condition, name)
  assert(condition, name)
  count = count + 1
  f:write('PASS\t' .. name .. '\n'); f:flush()
end
local function ev(delta, flags, msg) return string.pack('i4Bs4', delta, flags, msg) end
local ok, err = xpcall(function()
  local C = dofile(root .. '/scripts/midi/ReaSkii_MIDI_Core.lua')
  -- Overlapping notes are represented, not rejected before a selected note is touched.
  local overlap = ev(0,1,string.char(0x90,60,90)) .. ev(0,1,string.char(0x90,60,80))
    .. ev(10,0,string.char(0x80,60,40)) .. ev(0,0,string.char(0x80,60,30)) .. ev(0,0,'')
  local shifted = C.decode(C.transform(overlap,'transpose',{amount=2}))
  check(#shifted==5,'overlapping same-pitch notes no longer abort a take')
  check(shifted[1].msg:byte(2)==62 and shifted[2].msg:byte(2)==62 and shifted[3].msg:byte(3)==40,
    'overlapping notes keep their own release velocities')
  check(C.transform(overlap,'velocity',{amount=0})==overlap,'no-op velocity is byte exact')
  -- Unselected overlap stays untouched; only selected notes may collide.
  local mixed = ev(0,1,string.char(0x90,60,90)) .. ev(0,1,string.char(0x90,62,90))
    .. ev(10,0,string.char(0x80,60,40)) .. ev(0,0,string.char(0x80,62,40)) .. ev(0,0,'')
  local mixed_out = C.decode(C.transform(mixed,'transpose',{amount=2}))
  check(mixed_out[1].msg:byte(2)==62 and mixed_out[2].msg:byte(2)==64,'selection-only pitch edit')
  -- Unterminated notes are ignored, they do not block the panel.
  local dangling = ev(0,1,string.char(0x90,67,90)) .. ev(0,0,'')
  check(C.transform(dangling,'transpose',{amount=1})==dangling,'unterminated note is ignored')
  -- Program change is preserved for transpose/velocity.
  local program = ev(0,0,string.char(0xC0,5)) .. ev(0,1,string.char(0x90,60,100))
    .. ev(10,0,string.char(0x80,60,10)) .. ev(0,0,'')
  local program_out = C.decode(C.transform(program,'transpose',{amount=1}))
  check(program_out[1].msg:byte(2)==5,'program change survives velocity and transpose')
  -- Expression blocks only timing changes.
  local cc = ev(0,0,string.char(0xB0,7,100)) .. ev(0,1,string.char(0x90,60,100))
    .. ev(10,0,string.char(0x80,60,10)) .. ev(0,0,'')
  check(C.transform(cc,'transpose',{amount=1})~=cc,'pitch edit allowed with CC present')
  check(not pcall(C.transform,cc,'strum',{low=0,high=100,grid=120}),'timing edit still refuses CC')
  -- A preview interrupted by an external edit is abandoned, never overwritten.
  reaper.InsertTrackAtIndex(0,true)
  local track=reaper.GetTrack(0,0)
  local item=reaper.CreateNewMIDIItemInProj(track,0,4,false)
  local take=reaper.GetActiveTake(item)
  local base = ev(0,1,string.char(0x90,60,100)) .. ev(120,0,string.char(0x80,60,37)) .. ev(0,0,'')
  assert(reaper.MIDI_SetAllEvts(take,base))
  reaper.Undo_OnStateChange2(0,'Overlap fixture')
  local s=C.session(take)
  s:preview('transpose',{amount=2})
  reaper.MIDI_InsertCC(take,false,false,30,0xB0,0,11,12)
  check(s:abandon()==true,'abandon keeps an external edit and frees the panel')
  local ok_after,kept=reaper.MIDI_GetAllEvts(take,'')
  check(ok_after and kept:find(string.char(0xB0,11,12),1,true)~=nil,'external edit is preserved by abandon')
  assert(reaper.MIDI_SetAllEvts(take,base))
  C._clear_recovery(take)
  local _,canonical=reaper.MIDI_GetAllEvts(take,'')
  -- An interrupted preview leaves a recovery block that can restore the original.
  local s2=C.session(take)
  s2:preview('velocity',{amount=20})
  local _,modified=reaper.MIDI_GetAllEvts(take,'')
  s2:simulate_crash()
  check(C.recover(take)==true,'recovery restores an interrupted preview')
  local _,restored=reaper.MIDI_GetAllEvts(take,'')
  check(restored==canonical,'recovery is byte exact')
  check(C.recover(take)==false,'recovery is consumed once')
  check(modified~=canonical,'the crash simulation had a real pending change')
  -- Recovery refuses when the take was changed after the preview.
  local s3=C.session(take)
  s3:preview('velocity',{amount=25})
  s3:simulate_crash()
  reaper.MIDI_InsertCC(take,false,false,30,0xB0,0,11,12)
  local _,external=reaper.MIDI_GetAllEvts(take,'')
  local recovered,message=pcall(C.recover,take)
  check(recovered and message==false,'recovery refuses a take edited elsewhere')
  local _,untouched=reaper.MIDI_GetAllEvts(take,'')
  check(untouched==external,'refused recovery never overwrites external edit')
end, debug.traceback)
if not ok then f:write('ERROR\t'..err..'\n') end
f:write('DONE\t'..count..'\n'); f:close()
