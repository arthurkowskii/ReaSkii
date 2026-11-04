-- Device Rack UI smoke and input dispatch under a gfx mock.
local C=dofile('scripts/device/ReaSkii_DeviceRackController.lua')
local U=dofile('scripts/device/ReaSkii_DeviceRackUI.lua')
local count=0
local function test(name,fn) fn(); count=count+1; print('PASS\t'..name) end
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local store={}
local track={guid='{T1}',name='MIDI 1',fx={{guid='{F1}',name='JS: ReaSkii/ReaSkii MIDI LFO',enabled=true,params={'Rate','Shape','Depth','CC'},norm={.2,.1,.7,.5}}}}
local R={}
R.GetSelectedTrack=function() return track end
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
R.TrackFX_GetParameterStepSizes=function(t,i,p) return true,.01,.001,.1,t.fx[i+1].params[p+1]=='Shape' end
R.TrackFX_GetParamEx=function(t,i,p) return t.fx[i+1].norm[p+1],0,1,.5 end
R.TrackFX_GetEnabled=function(t,i) return t.fx[i+1].enabled end
R.TrackFX_SetEnabled=function(t,i,v) t.fx[i+1].enabled=v; return true end
R.TrackFX_AddByName=function(t,name) t.fx[#t.fx+1]={guid='{FNEW}',name=name,enabled=true,params={'Rate','Shape'},norm={.5,.5}}; return #t.fx-1 end
R.Undo_BeginBlock2=function() end
R.Undo_EndBlock2=function() end
R.GetProjExtState=function(_,s,k) return store[s] and store[s][k] and 1 or 0,store[s] and store[s][k] or '' end
R.SetProjExtState=function(_,s,k,v) store[s]=store[s] or {}; store[s][k]=v; return 1 end
reaper={time_precise=function() return os.clock() end}
gfx={w=1200,h=340,mouse_x=0,mouse_y=0,mouse_cap=0,mouse_wheel=0,measurestr=function(s) return #s*6 end}
local labels={}
gfx.set=function() end; gfx.rect=function() end; gfx.roundrect=function() end; gfx.circle=function() end; gfx.line=function() end
gfx.drawstr=function(s) labels[#labels+1]={s=s,x=gfx.x,y=gfx.y} end
gfx.setimgdim=function() end; gfx.blit=function() end; gfx.showmenu=function() return 0 end
local function has(label) for _,v in ipairs(labels) do if v.s==label then return v end end end
local c=C.new(R); c:refresh(); local ui=U.new(c)
local function draw() labels={}; ui:draw() end
local function click(x,y)
  gfx.mouse_x,gfx.mouse_y=x,y; gfx.mouse_cap=1; draw()
  gfx.mouse_cap=0; draw()
end
test('draw renders device chain and configuration actions',function()
 draw(); assert(has('DEVICE RACK')); assert(has('Configure')); assert(has('Add MIDI LFO')); assert(has('01'))
 assert(has('No preview controls for this device.'))
end)
test('Configure click reveals parameter browser and adds a control',function()
 draw(); click(1000,12); draw(); assert(has('PANEL')); assert(has('PARAMETERS')); assert(has('Done'))
 click(600,145); draw(); eq(#c.controls,1); eq(c.controls[1].param,0); assert(store.ReaSkii_DeviceRack)
end)
test('Done returns to preview and drag writes real normalized value',function()
 draw(); click(1000,12); draw(); assert(has('Rate'))
 local tw=(1200-34)/2-16-4
 click(20+tw*.8,153); eq(math.abs(track.fx[1].norm[1]-.8)<.02,true)
end)
test('wheel over slider changes value and toggle cell writes binary',function()
 draw(); gfx.mouse_x,gfx.mouse_y=100,153; gfx.mouse_wheel=-120; draw(); assert(track.fx[1].norm[1]<.8)
 c:add_control(1); c:refresh(); draw(); click(650,165); assert(track.fx[1].norm[2]==1 or track.fx[1].norm[2]==0)
end)
print('DONE\t'..count)
