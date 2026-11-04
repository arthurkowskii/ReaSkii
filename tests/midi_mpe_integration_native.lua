-- Real take writes in an isolated native REAPER process, never mock host APIs.
local out=assert(io.open(REASKII_RESULT,'w'))
local count=0
local function check(v,s) assert(v,s); count=count+1; out:write('PASS\t'..s..'\n'); out:flush() end
local function info(s) out:write('INFO\t'..s..'\n'); out:flush() end
local ok,err=xpcall(function()
 local D=REASKII_ROOT..'/scripts/midi/'
 local C=dofile(D..'ReaSkii_MIDI_Core.lua')
 local E=dofile(D..'ReaSkii_MIDI_Expression.lua')
 local M=dofile(D..'ReaSkii_MIDI_MPEAdapter.lua').configure({E=E})
 -- This is the documented caller wrapper, not a change to Core/Panel.
 local previous=C.transform
 C.transform=function(raw,tool,options)
  if tool=='glissando_mpe' or tool=='lfo_mpe' then return M.transform(raw,tool,options) end
  return previous(raw,tool,options)
 end
 local function pack(list)
  local t,last={},0
  for _,e in ipairs(list) do t[#t+1]=string.pack('i4Bs4',e[1]-last,e[2],e[3]); last=e[1] end
  return table.concat(t)
 end
 local function m(...) return string.char(...) end
 reaper.InsertTrackAtIndex(0,true)
 local item=reaper.CreateNewMIDIItemInProj(reaper.GetTrack(0,0),0,4,false)
 local take=reaper.GetActiveTake(item)
 local function get() local ok,raw=reaper.MIDI_GetAllEvts(take,''); assert(ok); return raw end
 local function seed(overlap)
  local native=E.decode(get()); local marker=native[#native]
  local raw=pack({{0,1,m(0x91,60,100)},{0,0,m(0x93,67,80)},
   {10,0,m(0xE1,0,64)},{20,0,m(0xD1,33)},{30,0,m(0xB1,74,55)},
   {40,0,m(0xB1,7,88)},{50,0,m(0xF0,0x7D,1,0xF7)},
   {60,0,m(0xFF,1,65)},{overlap and 80 or 240,1,m(overlap and 0x91 or 0x92,64,99)},
   {480,0,m(0x81,60,37)},{480,0,m(0xE1,0,64)},
   {600,0,m(0x83,67,21)},{720,0,m(overlap and 0x81 or 0x82,64,45)},
   {marker.pos,marker.flags,marker.msg}})
  assert(reaper.MIDI_SetAllEvts(take,raw))
  -- REAPER Undo canonicalizes same-tick event order. Seed a host-sorted
  -- baseline, as with ordinary editor-created MIDI; preview/cancel below
  -- still require exact bytes. This does not prove arbitrary raw-order Undo.
  reaper.MIDI_Sort(take)
  local actual=get()
  info('fixture exact initial readback='..tostring(actual==raw)..'; terminal='..#marker.msg..' bytes at '..marker.pos)
  return actual
 end
 local original=seed(false)
 reaper.Undo_OnStateChange2(0,'MPE native fixture')
 check(reaper.GetMediaItemTakeByGUID~=nil,'native take GUID lookup available')
 local p={mpe=true,member_channels={1,2,3},pitchbend_range=48,ppq=960,
  dimension='pitch',samples=9,rate=1/4,amount=3,base=0}
 local expected=M.transform(original,'lfo_mpe',p)
 check(expected~=original,'pure adapter computes native terminal input')
 -- Direct write/readback proves byte roundtrip separately from session safety.
 assert(reaper.MIDI_SetAllEvts(take,expected))
 local direct=get()
 check(direct==expected,'actual native raw MPE write reads back byte-exact')
 local ev=E.decode(direct); local before=E.decode(original)
 check(ev[#ev].msg==before[#before].msg and ev[#ev].pos==before[#before].pos,
  'native terminal CC123 source boundary retained')
 assert(reaper.MIDI_SetAllEvts(take,original)); check(get()==original,'direct fixture restoration exact')
 local session=C.session(take)
 local preview_ok,preview_err=pcall(function() session:preview('lfo_mpe',p) end)
 info('Core preview='..tostring(preview_ok)..'; '..tostring(preview_err))
 if not preview_ok then
  -- Never weaken Core's readback guard. Record actual normalization and cancel.
  local actual=get()
  info('expected bytes='..#expected..'; actual bytes='..#actual)
  for i=1,math.max(#expected,#actual) do if expected:byte(i)~=actual:byte(i) then
   info('first mismatch byte='..i); break end end
  check(session.previewing,'native rejection occurred after tracked write')
  session:cancel(); check(get()==original,'rejected native preview cancels exactly')
  info('SAFE_SESSION_REJECTED\t'..tostring(preview_err))
 else
  check(get()==expected,'Core safe session previews native MPE take exactly')
  p.amount=5; session:preview('lfo_mpe',p)
  check(get()==M.transform(original,'lfo_mpe',p),'safe preview recalculates from original')
  session:cancel(); check(get()==original,'safe cancel restores raw take exactly')
  local commit=C.session(take); commit:preview('lfo_mpe',p)
  check(commit:apply('ReaSkii MPE integration test'),'native MPE apply succeeds')
  check(reaper.Undo_CanUndo2(0)=='ReaSkii MPE integration test','native MPE named undo point')
  reaper.Undo_DoUndo2(0)
  local undone=get()
  if undone~=original then
   info('Undo raw lengths original='..#original..' undone='..#undone)
   local a=assert(io.open(REASKII_RESULT..'.original','wb')); a:write(original); a:close()
   local b=assert(io.open(REASKII_RESULT..'.undone','wb')); b:write(undone); b:close()
  end
  check(undone==original,'native MPE undo restores original raw take')
  check(not C.recovery_pending(take),'successful native session clears recovery journal')
 end
 -- All dimensions have real writes/readbacks, regardless of session verdict.
 for _,dim in ipairs({'slide','pressure'}) do
  p.dimension=dim; p.base=64; p.amount=40
  local source=get(); local target=M.transform(source,'lfo_mpe',p)
  assert(reaper.MIDI_SetAllEvts(take,target))
  check(get()==target,dim..' native raw write exact')
  assert(reaper.MIDI_SetAllEvts(take,source)); check(get()==source,dim..' raw restoration exact')
 end
 local bad=seed(true)
 local rejected=C.session(take)
 p.dimension='pitch'; p.base=0; p.amount=1
 local rok,rerr=pcall(function() rejected:preview('lfo_mpe',p) end)
 check(not rok and tostring(rerr):find('sharing',1,true),'native same-channel polyphony refused')
 check(get()==bad,'overlap refusal makes no partial take write')
 check(not C.recovery_pending(take),'overlap refusal creates no recovery journal')
 rejected:cancel()
 original=seed(false)
 for _,change in ipairs({{dimension='velocity'},{pitchbend_range=0},{mpe=false},{samples=1}}) do
  local o={} for k,v in pairs(p) do o[k]=v end for k,v in pairs(change) do o[k]=v end
  local s=C.session(take)
  check(not pcall(function() s:preview('lfo_mpe',o) end),'native invalid '..next(change)..' refused')
  check(get()==original,'native invalid config no partial write '..next(change)); s:cancel()
 end
 -- Glissando needs a successive melody, not the overlapping LFO fixture.
 local marker=E.decode(original); marker=marker[#marker]
 local melody=pack({{0,1,m(0x91,60,100)},{240,0,m(0x81,60,37)},
  {240,1,m(0x92,64,100)},{480,0,m(0x82,64,45)},
  {marker.pos,marker.flags,marker.msg}})
 assert(reaper.MIDI_SetAllEvts(take,melody)); melody=get()
 local gp={mpe=true,member_channels={1,2},pitchbend_range=48,steps=9}
 local gs=C.session(take); gs:preview('glissando_mpe',gp)
 check(get()==M.transform(melody,'glissando_mpe',gp),'native Glissando safe preview exact')
 gs:cancel(); check(get()==melody,'native Glissando cancel exact')
end,debug.traceback)
if not ok then out:write('ERROR\t'..tostring(err)..'\n') end
out:write('DONE\t'..count..'\n'); out:close()
