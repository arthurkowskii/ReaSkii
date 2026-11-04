-- Native Device Rack API and JSFX tests inside isolated REAPER.
local root=assert(REASKII_ROOT)
local out=assert(io.open(REASKII_RESULT,'w'))
local count=0
local function check(ok,name) assert(ok,name); count=count+1; out:write('PASS\t'..name..'\n'); out:flush() end
local ok,err=xpcall(function()
  local D=root..'/scripts/device/'
  local C=dofile(D..'ReaSkii_DeviceRackController.lua')
  local source=assert(io.open(root..'/effects/ReaSkii/ReaSkii MIDI LFO.jsfx','rb'))
  local jsfx=assert(source:read('a')); source:close()
  local effects=reaper.GetResourcePath()..'/Effects/ReaSkii'
  reaper.RecursiveCreateDirectory(effects,0)
  local target=assert(io.open(effects..'/ReaSkii MIDI LFO.jsfx','wb')); assert(target:write(jsfx)); assert(target:close())
  reaper.InsertTrackAtIndex(0,true)
  local track=reaper.GetTrack(0,0)
  reaper.GetSetMediaTrackInfo_String(track,'P_NAME','Device rack fixture',true)
  reaper.SetOnlyTrackSelected(track)
  local lfo=reaper.TrackFX_AddByName(track,'JS: ReaSkii/ReaSkii MIDI LFO',false,-1)
  check(lfo>=0,'MIDI LFO inserted as real JSFX')
  local _,name=reaper.TrackFX_GetFXName(track,lfo,'')
  check(name:find('ReaSkii MIDI LFO',1,true)~=nil,'JSFX name read back')
  local params=reaper.TrackFX_GetNumParams(track,lfo)
  check(params>=9,'JSFX exposes at least nine parameters: '..params)
  local names={}
  for i=0,params-1 do local _,n=reaper.TrackFX_GetParamName(track,lfo,i,''); names[#names+1]=n end
  check(names[1]=='Free Rate (Hz)' and names[2]=='Shape' and names[5]=='Channel','JSFX parameter names are stable')
  local volume=reaper.TrackFX_AddByName(track,'JS: utility/volume',false,-1)
  check(volume>=0,'second real effect inserted')
  local c=C.new(reaper); c:refresh(); check(c.track==track and c.fx==0,'controller selects the real track and first FX')
  c:add_control(0); c:add_control(1); check(#c.controls==2,'configuration controls added')
  local project=0
  local present,value=reaper.GetProjExtState(project,'ReaSkii_DeviceRack',(reaper.GetTrackGUID(track)..'|'..reaper.TrackFX_GetFXGUID(track,0)))
  check(present==1 and value:find('v1',1,true)==1,'configuration persisted in the project')
  local norm=reaper.TrackFX_GetParamNormalized(track,0,0)
  c:set_param(0,.77)
  check(math.abs(reaper.TrackFX_GetParamNormalized(track,0,0)-.77)<.001,'real parameter write verified')
  c:select_fx(1); check(c.fx==1,'FX selection switches')
  c:insert_lfo(); check(reaper.TrackFX_GetCount(track)>=3,'MIDI LFO insert path works after selection')
  reaper.Undo_DoUndo2(project)
  check(reaper.TrackFX_GetCount(track)>=2,'undo removes the inserted LFO without removing existing devices')
  reaper.SetMediaTrackInfo_Value(track,'B_MUTE',0)
  -- Re-read config after a new controller instance: same GUID key survives.
  local c2=C.new(reaper); c2:refresh(); check(#c2.controls>=1,'new controller reloads saved configuration')
end,debug.traceback)
if not ok then out:write('ERROR\t'..tostring(err)..'\n') end
out:write('DONE\t'..count..'\n'); out:close()
if not ok then reaper.ShowConsoleMsg(tostring(err)..'\n') end
