local D='scripts/midi/'
local P=dofile(D..'ReaSkii_MIDI_PanelController.lua')
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local count=0
local function test(name,fn) fn(); count=count+1; print('PASS\t'..name) end
local current='base'
local commits=0
local engine={session=function(take)
  local s={take=take,original=current,last=current}
  function s:check() assert(current==self.last,'external edit') end
  function s:preview(tool,p) self:check(); self.last=self.original..':'..tool..':'..tostring(p.factor or p.high); current=self.last end
  function s:cancel() self:check(); current=self.original; self.closed=true end
  function s:apply() self:check(); commits=commits+1; self.closed=true end
  return s
end}
local c=P.new(engine,function() return 1,{grid_ppq=240,anchor=0,range_start=0,range_end=1920,pivot=64} end)
test('Auto defaults on, neutral Strum defaults',function() eq(c.auto,true); eq(c.values.high,0); eq(c.values.tension,0) end)
test('limits, quantization and fine drag mapping',function()
 eq(P.adjust('stretch',1,20,false),1.2); eq(P.adjust('stretch',1,20,true),1.02)
 eq(P.limit('high',999),100); eq(P.limit('stretch',-3),.01); eq(P.limit('high',12.7),13)
end)
test('Strum graph position is horizontal, upper high/lower low',function()
 eq(P.graph_value(0,0,200),-100); eq(P.graph_value(100,0,200),0); eq(P.graph_value(500,0,200),100)
 local o=c:options('strum'); eq(o.tension,0); eq(o.onset_tolerance,0); eq(o.grid_ppq,240)
end)
test('noncumulative original-based Auto preview',function()
 c:set('high',20); eq(current,'base:strum:20'); c:set('high',40); eq(current,'base:strum:40')
end)
test('Auto off restores original, off edits do not write',function()
 c:toggle_auto(); eq(current,'base'); c:set('high',60); eq(current,'base')
end)
test('Transform commits once with Auto off; new preview cancels to commit',function()
 c:transform(); eq(commits,1); eq(current,'base:strum:60'); c:toggle_auto(); c:set('high',80)
 c:cancel(); eq(current,'base:strum:60')
end)
test('Reset params never writes MIDI or discards commit',function()
 c:reset(); eq(c.values.high,0); eq(current,'base:strum:60')
end)
test('Stretch preview maps factor; close restores baseline',function()
 c:set('stretch',2); eq(current,'base:strum:60:stretch:2.0'); c:close(); eq(current,'base:strum:60')
end)
test('external edit rejected and never overwritten on close',function()
 c:set('high',30); current='external'; assert(not c:poll()); c:close(); eq(current,'external')
end)
test('native terminal CC123 preserved, boundary and other expression refused',function()
 local C=dofile(D..'ReaSkii_MIDI_Core.lua')
 local A=dofile(D..'ReaSkii_MIDI_Adapter.lua')
 A.configure({C=C,T=dofile(D..'ReaSkii_MIDI_Transformations.lua')})
 local function e(delta,flags,msg) return string.pack('i4Bs4',delta,flags,msg) end
 local note=e(100,1,string.char(0x90,60,100))..e(100,0,string.char(0x80,60,40))
 local raw=note..e(800,0,string.char(0xB0,123,0))
 eq(P.transform(raw,'stretch',{factor=1,anchor=100},A,C),raw)
 local output=C.decode(P.transform(raw,'stretch',{factor=2,anchor=100},A,C))
 eq(output[2].pos,300); eq(output[#output].msg,string.char(0xB0,123,0)); eq(output[#output].pos,1000)
 assert(not pcall(P.transform,raw,'stretch',{factor=20,anchor=100},A,C))
 local cc=note..e(10,0,string.char(0xB0,1,20))..e(790,0,string.char(0xB0,123,0))
 assert(not pcall(P.transform,cc,'stretch',{factor=2,anchor=100},A,C))
 local marked=note..e(800,1,string.char(0xB0,123,0))
 assert(not pcall(P.transform,marked,'stretch',{factor=2,anchor=100},A,C))
end)
test('inline edit commit/cancel, wheel limits through actual UI control dispatch',function()
 local U=dofile(D..'ReaSkii_MIDI_PanelUI.lua')
 local ui=U.new(c,P); c.auto=false
 gfx={mouse_wheel=0,mouse_cap=0,mouse_x=150,mouse_y=415,w=224,h=850,
   measurestr=function(s) return #s*6 end}
 for _,name in ipairs({'set','rect','roundrect','circle','line','drawstr','setimgdim','blit'}) do gfx[name]=function() end end
 ui.edit={key='high',buffer='250'}; ui:key(13); eq(c.values.high,100)
 ui.edit={key='high',buffer='-32'}; ui:key(27); eq(c.values.high,100)
 gfx.mouse_wheel=-120000; ui:draw(0); eq(c.values.high,-100)
 gfx.mouse_wheel=120000; ui:draw(0); eq(c.values.high,100)
 gfx.mouse_x=45; gfx.mouse_y=274; gfx.mouse_wheel=-120000; ui:draw(0); eq(c.values.stretch,.01)
 gfx.mouse_wheel=12000000; ui:draw(0); eq(c.values.stretch,100)
end)
for _,name in ipairs({'ReaSkii_MIDI_Panel.lua','ReaSkii_MIDI_PanelUI.lua','ReaSkii_MIDI_PanelController.lua'}) do assert(loadfile(D..name)) end
print('DONE\t'..count)
