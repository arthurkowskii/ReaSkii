local D='scripts/midi/'
local C=dofile(D..'ReaSkii_MIDI_Core.lua'); local A=dofile(D..'ReaSkii_MIDI_Adapter.lua'); local O=dofile(D..'ReaSkii_MIDI_PanelOperations.lua'); local P=dofile(D..'ReaSkii_MIDI_PanelController.lua'); local U=dofile(D..'ReaSkii_MIDI_PanelUI.lua')
A.configure({C=C,T=O.wrap(dofile(D..'ReaSkii_MIDI_Transformations.lua')),G=O.generators(dofile(D..'ReaSkii_MIDI_Generators.lua'))})
local dir=assert(os.getenv('TMPDIR'))..'/midi-expansion-integration-'..tostring(os.time())..'-'..tostring(math.floor(os.clock()*1000000))
assert(os.execute('mkdir -p '..dir))
local current,undo,sets,fail=false,0,0,false
local take,item,project={},{},{}
reaper={EnumProjects=function() return project end,ValidatePtr2=function(p,t) return p==project and (t==take or t==item) end,TakeIsMIDI=function() return true end,
 GetSetMediaItemTakeInfo_String=function() return true,'{TAKE}' end,GetSetMediaItemInfo_String=function() return true,'{ITEM}' end,GetMediaItemTake_Item=function() return item end,GetMediaItemTakeByGUID=function() return take end,GetResourcePath=function() return dir end,GetProjectName=function() return 'fixture' end,GetProjectPath=function() return dir end,
 RecursiveCreateDirectory=function(path) assert(os.execute('mkdir -p '..path)) end,MIDI_GetAllEvts=function() return true,current end,
 MIDI_SetAllEvts=function(_,r) sets=sets+1; if fail then return false end; current=r; return true end,UpdateItemInProject=function() end,Undo_BeginBlock2=function() end,Undo_EndBlock2=function() undo=undo+1 end,time_precise=function() return os.clock() end}
local function ev(d,f,m) return string.pack('i4Bs4',d,f,m) end
local baseline=ev(960,1,string.char(144,60,90))..ev(240,0,string.char(128,60,37))..ev(480,1,string.char(144,64,100))..ev(240,0,string.char(128,64,40))..ev(7680,0,string.char(176,123,0))
local empty=ev(9600,0,string.char(176,123,0))
local context={grid_ppq=240,ppq=960,anchor=960,range_start=960,range_end=1920,generate_start=0,generate_end=9600,range_label='item',pitch_low=60,pitch_high=64}
local dispatch={transform=function(raw,t,p) return O.transform(raw,t,p,A) end}
C.transform=function(raw,t,p) return P.transform(raw,t,p,dispatch,C) end
local c=P.new(C,function() return take,context end)
local count=0
local function test(name,fn)
 if c.session then c:cancel() end
 current=baseline; c.auto=false
 fn(); count=count+1; print('PASS\t'..name)
end
local function nnotes() local n=0; for _,e in ipairs(C.decode(current)) do if #e.msg==3 and e.msg:byte(1)==144 and e.msg:byte(3)>0 then n=n+1 end end; return n end
test('all inline transformation dispatch paths preserve cancel snapshot',function()
 for _,t in ipairs({'arpeggiate','chop','connect','ornament','quantize','recombine','span','velocity_shaper','strum'}) do
  c:choose(t); c:reset(t); c.values.density=100; c.values.mirror=1
  c:preview(t); c:cancel(); assert(current==baseline,t)
 end
end)
test('all generators support empty, preview cancel and explicit commit',function()
 for _,t in ipairs({'rhythm','euclidean','seed','shape','stacks'}) do
  current=empty; c:choose(t,true); c:reset(t); c:preview(t); assert(nnotes()>0,t); c:cancel(); assert(current==empty,t)
  c:generate(); assert(nnotes()>0 and not c.session,t)
 end
end)
test('new pitch actions and Auto-off Stretch commit',function()
 for _,t in ipairs({'add_interval','set_length','humanize','transpose','stretch'}) do
  current=baseline; c.values.interval=7; c.values.transpose=2; c.values.stretch=2; c.values.grid=3
  c:action(t); assert(current~=baseline and not c.session,t)
 end
end)
test('add collision refusal, explicit replace and zero-note replacement protection',function()
 current=baseline; c:choose('rhythm',true); c:reset('rhythm'); c.values.hits=8
 assert(not pcall(c.generate,c)); assert(current==baseline); c:cancel(); c:mode(); c:generate(); assert(nnotes()>2)
 c.values.hits=0; local before=current
  -- Exercise the real guarded private generator wrapper, not a substitute transform.
 assert(not pcall(c.generate,c)); assert(current==before); c:cancel()
end)
test('journal preserved on external selection-only edit and explicitly archived',function()
 c:preview('stretch'); local preview=current
 local events=C.decode(current); local raw={}; local previous=0
 for _,e in ipairs(events) do raw[#raw+1]=ev(e.pos-previous,e.flags & ~1,e.msg); previous=e.pos end
 current=table.concat(raw); local external=current
 assert(not c:poll() and c.session and C.recovery_pending(take)); c:close(); assert(current==external)
 local R=dofile(D..'ReaSkii_MIDI_PanelRecovery.lua'); local path=c.session.journal_path
 local files=R.archive(path,'test'); assert(#files==1 and not C.recovery_pending(take) and current==external)
 local f=assert(io.open(files[1],'rb')); assert(#f:read('*a')>#preview); f:close(); os.remove(files[1])
 c.session=nil; c.active=nil; c.blocked=nil; c.context=nil
end)
test('failed host write retains retryable session; parameter value rolls back',function()
 c.auto=true; c.values.high=0; fail=true; local before=current
 assert(not pcall(c.set,c,'high',50)); assert(current==before and c.values.high==0 and c.session)
 fail=false; c:cancel(); assert(current==baseline)
end)
-- UI coordinates are discovered from actual draw dispatch, not hardcoded historical positions.
gfx={mouse_wheel=0,mouse_cap=0,mouse_x=0,mouse_y=0,w=260,h=950,measurestr=function(s) return #s*6 end,showmenu=function() return 0 end}
for _,n in ipairs({'set','rect','roundrect','circle','line','drawstr','setimgdim','blit'}) do gfx[n]=function() end end
local ui=U.new(c,P); local controls={}; local number,button=ui.number,ui.button
function ui:number(k,x,y,w,...) controls['n:'..k]={x+w/2,y+9}; return number(self,k,x,y,w,...) end
function ui:button(x,y,w,label,...) controls['b:'..label]={x+w/2,y+9}; return button(self,x,y,w,label,...) end
local function draw() ui:draw(0) end
local function click(label) local xy=assert(controls[label],label); gfx.mouse_x,gfx.mouse_y=xy[1],xy[2]; gfx.mouse_cap=1; draw(); gfx.mouse_cap=0; draw() end
test('actual UI pitch buttons and non-Auto Stretch application',function()
 ui.sections.Clip=false; ui.sections.Transform=false; c.values.stretch=2; draw(); click('b:Apply Stretch'); assert(current~=baseline and not c.session)
end)
test('actual UI numeric Auto wheel and Transform lifecycle',function()
 ui.sections['Pitch & Time']=false; ui.sections.Transform=true; c:choose('chop'); c.auto=true; c.values.parts=2; draw()
 local xy=controls['n:parts']; gfx.mouse_x,gfx.mouse_y=xy[1],xy[2]; gfx.mouse_wheel=120; draw(); assert(c.values.parts==3 and nnotes()==6 and c.session)
 click('b:Auto ON'); assert(current==baseline); click('b:Transform'); assert(nnotes()==6 and not c.session)
end)
test('actual entrypoint Escape and explicit conflict archive preserve external MIDI',function()
 local panel,loop
 local loadfile_original=dofile
 function dofile(path)
  local module=loadfile_original(path)
  if path:match('PanelController.lua$') then local new=module.new; module.new=function(...) panel=new(...); return panel end end
  return module
 end
 reaper.set_action_options=function() end
 reaper.MIDIEditor_GetActive=function() return 9 end; reaper.MIDIEditor_GetMode=function() return 0 end; reaper.MIDIEditor_GetTake=function() return take end
 reaper.MIDI_GetPPQPosFromProjQN=function(_,q) return q*960 end; reaper.MIDI_GetPPQPosFromProjTime=function(_,t) return t*1920 end
 reaper.GetMediaItemInfo_Value=function(_,key) return ({D_POSITION=0,D_LENGTH=5,B_LOOPSRC=0})[key] end
 reaper.GetMediaItemTakeInfo_Value=function(_,key) return key=='D_PLAYRATE' and 1 or 0 end
 reaper.GetSet_LoopTimeRange2=function() return 0,0 end
 reaper.MIDI_GetGrid=function() return .25 end
 reaper.MIDI_CountEvts=function() return true,2 end
 reaper.MIDI_GetNote=function(_,i) return true,true,false,960+i*720,1200+i*720,0,60+i*4,100 end
 reaper.atexit=function() end; reaper.ShowConsoleMsg=function() end
 reaper.ShowMessageBox=function() return 6 end
 reaper.defer=function(fn) loop=fn end
 gfx.init=function() end; gfx.quit=function() end; gfx.setfont=function() end; gfx.update=function() end
 local key=0; gfx.getchar=function() return key end; gfx.mouse_cap=0
 loadfile_original(D..'ReaSkii_MIDI_Panel.lua'); dofile=loadfile_original
 panel.auto=true; panel:set('stretch',2)
 local journal=panel.session.journal_path
 current=current..ev(0,0,string.char(192,7)); local external=current
 key=27; loop(); assert(panel.session and current==external and panel.status:find('Restore refused',1,true))
 -- Execute the entrypoint's actual, confirmed archive menu branch.
 key=0; gfx.mouse_cap=2; gfx.showmenu=function() return 4 end
 loop(); gfx.mouse_cap=0
 assert(current==external and not panel.session and panel.status:find('Recovery archived',1,true))
 assert(not C.recovery_pending(take))
 -- Inspect only this test's exact archive, then remove test evidence from scratch.
 local archived=panel.status:match('Recovery archived: (.*)$'); local f=assert(io.open(archived,'rb')); assert(#f:read('*a')>0); f:close(); os.remove(archived)
end)
test('fine wheel accumulates substeps on integer parameters',function()
 ui.sections['Pitch & Time']=false; ui.sections.Transform=false; ui.sections.Generate=true
 c:choose('rhythm',true); c.auto=false; c.values.hits=4; draw()
 local xy=assert(controls['n:hits'],'hits control missing')
 gfx.mouse_x,gfx.mouse_y=xy[1],xy[2]; gfx.mouse_cap=8
 for _=1,10 do gfx.mouse_wheel=120; draw() end
 gfx.mouse_cap=0; gfx.mouse_wheel=0
 assert(c.values.hits==5,'ten fine-wheel ticks should accumulate +1, got '..tostring(c.values.hits))
 for _=1,5 do gfx.mouse_cap=8; gfx.mouse_wheel=-120; draw() end
 gfx.mouse_cap=0; assert(c.values.hits==4,'five fine-wheel ticks down should return to 4, got '..tostring(c.values.hits))
end)
for _,name in ipairs({'Panel','PanelController','PanelUI','PanelOperations','PanelContext','PanelFeatures','PanelRecovery'}) do assert(loadfile(D..'ReaSkii_MIDI_'..name..'.lua')) end
print('PASS\tall seven panel entrypoints/helpers compile'); count=count+1
print('DONE\t'..count)
