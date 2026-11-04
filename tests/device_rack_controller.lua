-- Device-rack controller against a deterministic REAPER mock.
local C=dofile('scripts/device/ReaSkii_DeviceRackController.lua')
local count=0
local function test(name,fn) fn(); count=count+1; print('PASS\t'..name) end
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local selected=1
local store={}
local tracks={
 [1]={guid='{T1}',name='MIDI 1',fx={
  {guid='{F1}',name='JS: ReaSkii/ReaSkii MIDI LFO',enabled=true,params={'Rate','Shape','Depth','CC'},norm={.2,.1,.7,.5}},
  {guid='{F2}',name='VST: Test EQ',enabled=true,params={'Cutoff','Mode'},norm={.4,0}},
 }},
 [2]={guid='{T2}',name='Audio 2',fx={{guid='{F3}',name='JS: volume',enabled=true,params={'Volume'},norm={.8}}}},
}
local undo={begin=0,ended=0}
local R={}
R.GetSelectedTrack=function() return tracks[selected] end
R.GetTrackGUID=function(t) return t.guid end
R.GetTrackName=function(t) return t.name end
R.TrackFX_GetCount=function(t) return #t.fx end
R.TrackFX_GetFXName=function(t,i) return t.fx[i+1].name end
R.TrackFX_GetFXGUID=function(t,i) return t.fx[i+1].guid end
R.TrackFX_GetNumParams=function(t,i) return #t.fx[i+1].params end
R.TrackFX_GetParamName=function(t,i,p) return t.fx[i+1].params[p+1] end
R.TrackFX_GetParamNormalized=function(t,i,p) return t.fx[i+1].norm[p+1] end
R.TrackFX_SetParamNormalized=function(t,i,p,v) t.fx[i+1].norm[p+1]=v; return true end
R.TrackFX_GetFormattedParamValue=function(t,i,p) return string.format('%.2f',t.fx[i+1].norm[p+1]) end
R.TrackFX_GetParameterStepSizes=function(t,i,p) return true,.01,.001,.1,t.fx[i+1].params[p+1]=='Mode' end
R.TrackFX_GetParamEx=function(t,i,p) return t.fx[i+1].norm[p+1],0,1,.5 end
R.TrackFX_GetEnabled=function(t,i) return t.fx[i+1].enabled end
R.TrackFX_SetEnabled=function(t,i,v) t.fx[i+1].enabled=v; return true end
R.TrackFX_AddByName=function(t,name) assert(name==C.LFO_NAME); t.fx[#t.fx+1]={guid='{FNEW}',name=name,enabled=true,params={'Free Rate (Hz)','Shape'},norm={.5,.5}}; return #t.fx-1 end
R.Undo_BeginBlock2=function() undo.begin=undo.begin+1 end
R.Undo_EndBlock2=function() undo.ended=undo.ended+1 end
R.GetProjExtState=function(_,section,key) return store[section] and store[section][key] and 1 or 0,store[section] and store[section][key] or '' end
R.SetProjExtState=function(_,section,key,value) store[section]=store[section] or {}; store[section][key]=value; return 1 end

test('refresh selects first FX and loads empty configuration',function()
 local c=C.new(R); selected=1; assert(c:refresh()); eq(c.fx,0); eq(#c.controls,0); eq(c.fx_count,2)
end)
test('add, reorder, remove and persist configuration in project state',function()
 local c=C.new(R); c:refresh(); assert(c:add_control(0)); assert(c:add_control(1)); eq(#c.controls,2)
 c:move_control(1,-1); eq(c.controls[1].param,1); c:remove_control(0); eq(#c.controls,1)
 local c2=C.new(R); c2:refresh(); eq(#c2.controls,1); eq(c2.controls[1].param,1)
end)
test('parameter writes go to the selected FX and follow formatted value',function()
 local c=C.new(R); c:refresh(); assert(c:set_param(0,.75)); eq(tracks[1].fx[1].norm[1],.75)
 local norm,formatted,toggle=c:param_value(0); eq(norm,.75); eq(formatted,'0.75'); eq(toggle,false)
 c:select_fx(1); c:set_param(1,1); eq(tracks[1].fx[2].norm[2],1)
 norm,formatted,toggle=c:param_value(1); eq(toggle,true)
end)
test('track change never writes to the previous track',function()
 local c=C.new(R); c:refresh(); c:set_param(0,.9)
 selected=2; assert(c:refresh()); eq(c.fx,0); eq(#c.controls,0)
 c:set_param(0,.1); eq(tracks[1].fx[1].norm[1],.9); eq(tracks[2].fx[1].norm[1],.1)
 selected=1
end)
test('bypass uses one named undo bracket per change',function()
 local c=C.new(R); c:refresh(); local before=undo.begin
 assert(c:set_fx_enabled(0,false)); eq(c:fx_enabled(0),false); eq(undo.begin,before+1); eq(undo.ended,undo.begin)
end)
test('insert LFO uses undo, selects new device and exposes params',function()
 local c=C.new(R); c:refresh(); local before=#tracks[1].fx
 assert(c:insert_lfo()); eq(#tracks[1].fx,before+1); eq(c.fx,before)
 eq(c:param_name(0),'Free Rate (Hz)'); eq(#c.controls,2); eq(undo.ended,undo.begin)
end)
test('missing track refuses edits and reports status',function()
 local c=C.new(R); selected=nil; c:refresh(); assert(not c:set_param(0,.5)); assert(c.status:find('Select a track',1,true))
 selected=1
end)
print('DONE\t'..count)
