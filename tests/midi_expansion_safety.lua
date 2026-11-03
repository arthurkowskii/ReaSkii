local P=dofile('scripts/midi/ReaSkii_MIDI_PanelController.lua')
local count=0
local function test(n,f) f(); count=count+1; print('PASS\t'..n) end
local live,which,failcancel,failpreview=100,1,false,false
local history={}
local engine={session=function(t)
 local s={take=t}
 function s:check() assert(live~=-1,'external edit') end
 function s:preview(tool,o) self:check(); assert(not failpreview,'preview failed'); history[#history+1]={tool,o}; live=o.anchor or 10 end
 function s:cancel() self:check(); assert(not failcancel,'cancel failed'); live=100 end
 function s:apply() self:check() end
 return s
end}
local c=P.new(engine,function() return which,{anchor=live,grid_ppq=240,range_start=live,range_end=1000} end)
test('baseline anchor frozen across repeated Stretch',function()
 c:set('stretch',2); live=80; c:set('stretch',3); assert(history[#history][2].anchor==100)
end)
test('switch tool cancels before acquiring fresh context',function()
 c:preview('strum'); c:preview('stretch'); assert(history[#history][2].anchor==100)
end)
test('failed adjustment rolls back displayed value',function()
 failpreview=true; local old=c.values.stretch; assert(not pcall(c.set,c,'stretch',4)); assert(c.values.stretch==old); failpreview=false
end)
test('cancel failure retains recoverable session',function()
 failcancel=true; assert(not pcall(c.cancel,c)); assert(c.session); c:poll(); assert(c.session); failcancel=false; c:cancel()
end)
test('target switch cannot write new target in same gesture',function()
 c:preview('stretch'); which=2; local n=#history; assert(not pcall(c.preview,c,'strum')); assert(#history==n); assert(not c.session)
end)
test('external edit poll retains failed cancellation',function()
 c:preview('strum'); live=-1; assert(not c:poll()); assert(c.session); assert(not pcall(c.commit,c)); live=100; c:cancel()
end)
test('marker note-offs precede CC123 at same tick',function()
 local C=dofile('scripts/midi/ReaSkii_MIDI_Core.lua'); local A=dofile('scripts/midi/ReaSkii_MIDI_Adapter.lua')
 A.configure({C=C,T=dofile('scripts/midi/ReaSkii_MIDI_Transformations.lua')})
 local function e(d,f,m) return string.pack('i4Bs4',d,f,m) end
 local raw=e(100,1,string.char(144,60,90))..e(100,0,string.char(128,60,30))..e(0,0,string.char(176,123,0))
 local out=C.decode(P.transform(raw,'stretch',{anchor=100,factor=1},A,C))
 assert(out[2].msg:byte(1)==128 and out[3].msg:byte(1)==176)
end)
print('DONE\t'..count)
