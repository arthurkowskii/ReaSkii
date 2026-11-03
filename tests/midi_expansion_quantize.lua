-- Quantize control/behavior contract: official manual + explicitly local tie policy.
local D='scripts/midi/'
local O=dofile(D..'ReaSkii_MIDI_PanelOperations.lua')
local P=dofile(D..'ReaSkii_MIDI_PanelController.lua')
local C=dofile(D..'ReaSkii_MIDI_Core.lua')
local A=dofile(D..'ReaSkii_MIDI_Adapter.lua')
A.configure({C=C,T=O.wrap(dofile(D..'ReaSkii_MIDI_Transformations.lua'))})
local count=0
local function test(name,fn) fn(); count=count+1; print('PASS\t'..name) end
local function n(s,e,sel,pitch) return {startppq=s,endppq=e,pitch=pitch or 60,vel=100,channel=0,selected=sel~=false,muted=false,release_velocity=37} end
local function params(start,finish,amount) return {grid_ppq=60,strength=amount or 1,adjust_start=start,adjust_end=finish} end
test('Quantize start-only moves with duration preserved',function()
 local r=O.apply({n(110,410)},'quantize',params(true,false)); assert(r[1].startppq==120 and r[1].endppq==420)
end)
test('Quantize end-only stretches with unchanged start and release',function()
 local input={n(110,410)}; local r=O.apply(input,'quantize',params(false,true)); assert(r[1].startppq==110 and r[1].endppq==420 and r[1].release_velocity==37); assert(input[1].endppq==410)
end)
test('Quantize both and proportional Amount',function()
 local r=O.apply({n(110,410)},'quantize',params(true,true,.5)); assert(r[1].startppq==115 and r[1].endppq==415)
 local e=O.apply({n(110,410)},'quantize',params(false,true,.5)); assert(e[1].startppq==110 and e[1].endppq==415)
end)
test('No flags and zero Amount are exact no-ops',function()
 local r=O.apply({n(110,410)},'quantize',params(false,false)); assert(r[1].startppq==110 and r[1].endppq==410)
 r=O.apply({n(110,410)},'quantize',params(true,true,0)); assert(r[1].startppq==110 and r[1].endppq==410)
end)
test('Unselected untouched; collapsed durations and collisions refused',function()
 local r=O.apply({n(110,410),n(800,900,false)},'quantize',params(false,true)); assert(r[2].endppq==900)
 assert(not pcall(O.apply,{n(110,119)},'quantize',params(true,true)))
 assert(not pcall(O.apply,{n(110,410),n(415,500,false)},'quantize',params(false,true)))
end)
test('Controller meter, triplets and independent note edge options',function()
 local c=P.new({},function() return 1,{grid_ppq=73,ppq=960} end)
 local p=c:options('quantize'); assert(p.grid_ppq==73 and p.adjust_start==true and p.adjust_end==false)
 c.auto=false; c:set('quantize_grid',2,'quantize'); c:set('quantize_triplets',1,'quantize'); c:set('quantize_start',0,'quantize'); c:set('quantize_end',1,'quantize')
 p=c:options('quantize'); assert(p.grid_ppq==320 and not p.adjust_start and p.adjust_end)
 c:reset('quantize'); assert(c.values.quantize_grid==0 and c.values.quantize_triplets==0 and c.values.quantize_start==1 and c.values.quantize_end==0 and c.values.strength==100)
end)
test('Adapter retains CC refusals and terminal release ordering',function()
 local function e(d,f,m) return string.pack('i4Bs4',d,f,m) end
 local raw=e(110,1,string.char(144,60,100))..e(300,0,string.char(128,60,37))..e(10,0,string.char(176,123,0))
 local dispatch={transform=function(r,t,p) return O.transform(r,t,p,A) end}
 local output=C.decode(P.transform(raw,'quantize',params(false,true),dispatch,C))
 assert(output[2].pos==420 and output[2].msg:byte(1)==128 and output[3].msg:byte(1)==176)
 local cc=e(0,0,string.char(176,1,20))..raw
 assert(not pcall(P.transform,cc,'quantize',params(false,true),dispatch,C))
end)
test('Dedicated UI matches official control inventory and dispatch',function()
 local c=P.new({},function() return 1,{grid_ppq=240,ppq=960} end); c.auto=false; c.tool='quantize'
 gfx={mouse_cap=0,mouse_wheel=0,mouse_x=0,mouse_y=0,w=260,h=850,measurestr=function(s) return #s*6 end}
 for _,key in ipairs({'set','rect','roundrect','circle','line','drawstr','setimgdim','blit'}) do gfx[key]=function() end end
 reaper={time_precise=function() return os.clock() end}
 local U=dofile(D..'ReaSkii_MIDI_PanelUI.lua'); local ui=U.new(c,P)
 ui.sections.Clip=false; ui.sections['Pitch & Time']=false
 local buttons={}; local button=ui.button
 function ui:button(x,y,w,label,fn,enabled) buttons[label]={x=x+w/2,y=y+9,fn=fn,enabled=enabled}; return button(self,x,y,w,label,fn,enabled) end
 ui:draw(0)
 for _,label in ipairs({'Grid','1/4','1/8','1/16','1/32','Triplets','Start','End'}) do assert(buttons[label],'Missing reference control '..label) end
 assert(buttons.Triplets.enabled==false)
 buttons['1/8'].fn(); ui:draw(0); assert(buttons.Triplets.enabled~=false); buttons.Triplets.fn(); buttons.End.fn()
 assert(c.values.quantize_grid==2 and c.values.quantize_triplets==1 and c.values.quantize_end==1)
 buttons.Grid.fn(); assert(c.values.quantize_grid==0)
end)
print('DONE\t'..count)
