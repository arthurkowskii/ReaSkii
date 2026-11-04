-- Independent raw-MPE adapter contract tests (Lua 5.4).
local dir = (debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])') or './')
assert(loadfile(dir..'../scripts/midi/ReaSkii_MIDI_MPEAdapter.lua'))
assert(loadfile(dir..'midi_mpe_integration_native.lua'))
local M = dofile(dir..'../scripts/midi/ReaSkii_MIDI_MPEAdapter.lua')
local E = dofile(dir..'../scripts/midi/ReaSkii_MIDI_Expression.lua')
M.configure({E=E})
local n = 0
local function check(v, label) assert(v,label); n=n+1 end
local function eq(a,b,label) check(a==b,label) end
local function refuses(fn, fragment)
  local ok,err=pcall(fn)
  check(not ok and tostring(err):find(fragment,1,true), 'expected refusal '..fragment..': '..tostring(err))
end
local function raw(events)
  local parts,last={},0
  for _,e in ipairs(events) do parts[#parts+1]=string.pack('i4Bs4',e[1]-last,e[2],e[3]); last=e[1] end
  return table.concat(parts)
end
local function msg(...) return string.char(...) end
local function fixture(marker, overlap)
  return raw({{0,1,msg(0x91,60,100)},{0,0,msg(0x93,67,80)},
    {10,32,msg(0xB1,7,87)},{12,0,msg(0xE1,0,64)},{15,0,msg(0xD1,34)},
    {20,0,msg(0xB1,74,55)},{30,2,msg(0xF0,0x7D,1,0xF7)},
    {40,0,msg(0xFF,1,65)}, {50,1,msg(overlap and 0x91 or 0x92,64,99)},
    {100,2,msg(0x81,60,37)},{100,0,msg(0xE1,0,64)},
    {120,0,msg(0x83,67,21)},{150,0,msg(overlap and 0x81 or 0x82,64,45)},
    {480,0,marker or ''}})
end
local function opts(d)
 return {mpe=true, member_channels={1,2,3},pitchbend_range=48,dimension=d or 'pitch',
   samples=5,ppq=100,rate=1/4,amount=1,base=0}
end
local function copy(t) local r={} for k,v in pairs(t) do r[k]=v end return r end
local input=fixture()
for _,dim in ipairs({'pitch','slide','pressure'}) do
 local o=opts(dim); if dim~='pitch' then o.amount=60; o.base=64 end
 local output=M.transform(input,'lfo_mpe',o)
 check(output~=input,dim..' generates raw output')
 eq(M.transform(input,'lfo_mpe',o),output,dim..' deterministic')
 eq(M.transform(output,'lfo_mpe',o),output,dim..' replace idempotent')
 local a,b=E.decode(input),E.decode(output)
 local function edited(e)
  local s=e.msg:byte(1); if not s or (s&15)~=1 and (s&15)~=2 then return false end
  local target=dim=='pitch' and (s&0xF0)==0xE0 or dim=='pressure' and (s&0xF0)==0xD0
    or dim=='slide' and (s&0xF0)==0xB0 and e.msg:byte(2)==74
  return target and ((s&15)==1 and e.pos<=100 or (s&15)==2 and e.pos>=50 and e.pos<=150)
 end
 local function retained(events)
  local t={} for _,e in ipairs(events) do if not edited(e) then
   t[#t+1]=string.pack('i4Bs4',e.pos,e.flags,e.msg) end end
  return table.concat(t)
 end
 eq(retained(a),retained(b),dim..' unrelated bytes flags absolute positions and order preserved')
 eq(b[#b].msg,'',dim..' terminal empty marker preserved')
 eq(b[#b].pos,480,dim..' source length preserved')
 local off,reset
 for i,e in ipairs(b) do if e.pos==100 and e.msg==msg(0x81,60,37) then off=i end
  if e.pos==100 and e.msg==msg(0xE1,0,64) then reset=i end end
 check(off and reset and off<reset,dim..' noteoff before boundary reset')
end
local terminal=msg(0xB0,123,0)
local ccinput=fixture(terminal)
local ccout=M.transform(ccinput,'lfo_mpe',opts())
local last=E.decode(ccout); last=last[#last]
eq(last.msg,terminal,'native CC123 terminal bytes'); eq(last.pos,480,'native CC123 terminal position')
eq(ccout:sub(-12),ccinput:sub(-12),'native terminal raw record exact')
local melody=raw({{0,1,msg(0x91,60,100)},{100,0,msg(0x81,60,37)},
 {100,1,msg(0x92,64,100)},{200,0,msg(0x82,64,45)},{480,0,''}})
local go={mpe=true,member_channels={1,2},pitchbend_range=48,start_percent=50,curve=0,steps=5}
local glide=M.transform(melody,'glissando_mpe',go)
local bends={} for _,e in ipairs(E.decode(glide)) do if e.msg:byte(1)==0xE1 and e.pos<100 then bends[#bends+1]=e end end
eq(#bends,5,'glissando first note samples'); eq(bends[1].msg,msg(0xE1,0,64),'glissando starts neutral')
local v=bends[#bends].msg:byte(2)+(bends[#bends].msg:byte(3)<<7)
eq(v,8875,'glissando targets next selected pitch using declared range')
refuses(function() M.transform(input,'glissando_mpe',go) end,'successive')
refuses(function() M.transform(fixture(nil,true),'lfo_mpe',opts()) end,'sharing')
for key,value in pairs({mpe=false,member_channels={0,1},pitchbend_range=0,dimension='velocity',
 samples=1,ppq=0,rate=0,amount=math.huge,base=0/0,shape='random',attack=101,decay=-1,
 mode='add',bogus=true}) do
 local o=opts(); o[key]=value
 refuses(function() M.transform(input,'lfo_mpe',o) end,'MPE')
end
for _,key in ipairs({'mpe','member_channels','pitchbend_range','ppq'}) do
 local o=opts(); o[key]=nil
 refuses(function() M.transform(input,'lfo_mpe',o) end,'MPE')
end
for _,zone in ipairs({{1,1},{2,3},{1,3},{[1]=1,[3]=3},{1,2,extra=3}}) do
 local o=opts(); o.member_channels=zone
 refuses(function() M.transform(input,'lfo_mpe',o) end,'MPE')
end
refuses(function() M.transform(input,'other',opts()) end,'MPE')
refuses(function() M.transform(input:sub(1,-2),'lfo_mpe',opts()) end,'Truncated')
local function one(extra,channel)
 channel=channel or 1
 return raw({{0,1,msg(0x90|channel,60,100)},{10,0,extra},
 {100,0,msg(0x80|channel,60,37)},{480,0,''}})
end
for _,bad in ipairs({msg(0xB1,64,127),msg(0xB1,66,127),msg(0xB1,101,0),
 msg(0xB1,123,0),msg(0xA1,60,40),msg(0xE1,128,0),msg(0x91,60)}) do
 refuses(function() M.transform(one(bad),'lfo_mpe',opts()) end,'MPE')
end
refuses(function() M.transform(one(msg(0xB0,7,1),0),'lfo_mpe',opts()) end,'MPE')
local zero=raw({{0,1,msg(0x91,60,100)},{0,0,msg(0x81,60,0)},{480,0,''}})
refuses(function() M.transform(zero,'lfo_mpe',opts()) end,'MPE')
local none=raw({{0,0,msg(0x91,60,100)},{100,0,msg(0x81,60,37)},{480,0,''}})
eq(M.transform(none,'lfo_mpe',opts()),none,'no selection exact no-op with valid options')
-- Boundary reset generation must never displace the source marker from last.
local edge=raw({{0,1,msg(0x91,60,100)},{100,0,msg(0x81,60,37)},
 {100,0,terminal}})
local edge_o=opts('slide'); edge_o.base=64
local edge_out=E.decode(M.transform(edge,'lfo_mpe',edge_o))
eq(edge_out[#edge_out].msg,terminal,'terminal CC123 at release remains final after reset')
-- A generated curve must not leak channel state into a later unselected note.
local reuse=raw({{0,1,msg(0x91,60,100)},{100,0,msg(0x81,60,37)},
 {110,0,msg(0x91,65,90)},{200,0,msg(0x81,65,12)},{480,0,''}})
local reuse_options=opts('slide'); reuse_options.base=64
local restored=M.transform(reuse,'lfo_mpe',reuse_options)
local reset
for _,e in ipairs(E.decode(restored)) do
 if e.pos==100 and e.msg==msg(0xB1,74,0) then reset=e end
end
check(reset,'restore original slide state at release before channel reuse')
local master_rpn=raw({{0,0,msg(0xB0,101,0)},{0,1,msg(0x91,60,100)},
 {100,0,msg(0x81,60,37)},{480,0,''}})
refuses(function() M.transform(master_rpn,'lfo_mpe',opts()) end,'MPE')
-- Additional byte, sampling, envelope and refusal coverage.
local function points(output,status,stop)
 local list={} for _,e in ipairs(E.decode(output)) do
  if e.msg:byte(1)==status and e.pos<(stop or 100) then list[#list+1]=e end end
 return list
end
local single=raw({{0,1,msg(0x91,60,100)},{101,0,msg(0x81,60,37)},{480,0,''}})
for _,shape in ipairs({'sine','triangle','square'}) do
 local o=opts('pressure'); o.shape=shape; o.base=64; o.amount=40
 local list=points(M.transform(single,'lfo_mpe',o),0xD1,101)
 eq(#list,5,shape..' five samples')
 eq(list[2].pos,25,shape..' musical quarter period')
 eq(list[2].msg:byte(2),104,shape..' positive peak')
 eq(list[4].msg:byte(2),24,shape..' negative peak')
 o.attack=50; o.decay=50
 list=points(M.transform(single,'lfo_mpe',o),0xD1,101)
 eq(list[1].msg:byte(2),64,shape..' attack begins at base')
 eq(list[5].msg:byte(2),64,shape..' decay finishes at base')
end
local shift=opts('pressure'); shift.base=64; shift.amount=40; shift.time_shift=50
local shifted=points(M.transform(single,'lfo_mpe',shift),0xD1,101)
eq(shifted[2].msg:byte(2),64,'positive time shift delays wave')
shift.time_shift=-25
shifted=points(M.transform(single,'lfo_mpe',shift),0xD1,101)
eq(shifted[1].msg:byte(2),104,'negative time shift advances phase')
local short=raw({{0,1,msg(0x91,60,100)},{3,0,msg(0x81,60,37)},{480,0,''}})
eq(#points(M.transform(short,'lfo_mpe',opts()),0xE1,3),3,'short note tick deduplication')
for _,flags in ipairs({4,16,32}) do
 local shaped=raw({{0,1,msg(0x91,60,100)},{10,flags,msg(0xE1,0,64)},
  {100,0,msg(0x81,60,37)},{480,0,''}})
 refuses(function() M.transform(shaped,'lfo_mpe',opts()) end,'MPE')
end
for _,bad in ipairs({
 raw({{0,1,msg(0x91,60,100)},{100,0,msg(0x81,60,37)}}),
 raw({{0,1,msg(0x91,60,100)},{10,0,''},{100,0,msg(0x81,60,37)},{480,0,''}}),
 raw({{0,1,msg(0x91,60,100)},{480,0,''}}),
 raw({{0,1,msg(0x91,60,100)},{100,0,msg(0x81,60,37)},{100,1,msg(0x91,64,100)},
  {200,0,msg(0x81,64,37)},{480,0,''}}),
 one(msg(0xFF,15)..'CCBZ '..string.rep('\0',5)),
}) do refuses(function() M.transform(bad,'lfo_mpe',opts()) end,'MPE') end
local backwards=string.pack('i4Bs4',-1,0,'')
refuses(function() M.transform(backwards,'lfo_mpe',opts()) end,'Negative')
for _,v in ipairs({-100,100}) do local o=copy(go); o.curve=v
 check(M.transform(melody,'glissando_mpe',o)~=melody,'provisional curve extreme '..v) end
local clipped=copy(go); clipped.pitchbend_range=2
refuses(function() M.transform(melody,'glissando_mpe',clipped) end,'exceeds')
local envelope=opts(); envelope.attack=60; envelope.decay=60
refuses(function() M.transform(single,'lfo_mpe',envelope) end,'MPE')
local reverse_reset=raw({{0,1,msg(0x91,60,100)},{100,8,msg(0xE1,0,64)},
 {100,2,msg(0x81,60,37)},{480,0,''}})
local rr=E.decode(M.transform(reverse_reset,'lfo_mpe',opts()))
local oi,ri
for i,e in ipairs(rr) do if e.msg==msg(0x81,60,37) then oi=i end
 if e.pos==100 and e.msg==msg(0xE1,0,64) then ri=i; eq(e.flags,8,'existing reset flags retained') end end
check(oi<ri,'pre-existing early reset reordered after note-off safely')
local muted=raw({{0,3,msg(0x91,60,100)},{100,2,msg(0x81,60,37)},{480,0,''}})
for _,e in ipairs(points(M.transform(muted,'lfo_mpe',opts()),0xE1)) do
 eq(e.flags&2,2,'generated expression on muted selected note remains muted') end
for _,master_event in ipairs({msg(0xB0,64,127),msg(0xB0,66,127),msg(0xB0,123,0)}) do
 refuses(function() M.transform(one(master_event),'lfo_mpe',opts()) end,'MPE')
end
-- Exercise the documented dispatch hook with real Core and legacy fallback.
local C=dofile(dir..'../scripts/midi/ReaSkii_MIDI_Core.lua')
local previous_transform=C.transform
C.transform=function(raw,tool,o)
 if tool=='glissando_mpe' or tool=='lfo_mpe' then return M.transform(raw,tool,o) end
 return previous_transform(raw,tool,o)
end
eq(C.transform(input,'lfo_mpe',opts()),M.transform(input,'lfo_mpe',opts()),'documented Core dispatch wrapper routes MPE')
eq(C.transform(single,'velocity',{amount=1}),previous_transform(single,'velocity',{amount=1}),
 'documented Core dispatch wrapper preserves previous tools')
local large={}
for i=0,100 do
 large[#large+1]={i*200,1,msg(0x91,60,100)}
 large[#large+1]={i*200+100,0,msg(0x81,60,37)}
end
large[#large+1]={21000,0,''}
local dense=opts(); dense.samples=1024
refuses(function() M.transform(raw(large),'lfo_mpe',dense) end,'budget')
local desc=M.describe(); eq(desc.version,1,'schema version')
check(desc.provisional and desc.tools.glissando_mpe and desc.tools.lfo_mpe,'provisional tool schemas')
desc.tools.lfo_mpe=nil; check(M.describe().tools.lfo_mpe,'schema defensive copy')
local spy=0
M.configure({E={decode=E.decode,transform=function(...) spy=spy+1; return E.transform(...) end}})
M.transform(melody,'glissando_mpe',go); M.transform(input,'lfo_mpe',opts())
eq(spy,3,'both tools invoke existing Expression engine per edited note')
M.configure({E=E})
print('ASSERTIONS='..n)
return {passed=n}
