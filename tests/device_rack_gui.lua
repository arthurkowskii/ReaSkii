-- Real-host fixture for the Device Rack. Test-only capture; production has no hooks.
local root=assert(REASKII_ROOT)
local statePath=assert(REASKII_STATE)
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
assert(lfo>=0)
local volume=reaper.TrackFX_AddByName(track,'JS: utility/volume',false,-1)
assert(volume>=0)
local c,u,uiControls
local original=dofile
function dofile(path)
  local module=original(path)
  if path:match('ReaSkii_DeviceRackController.lua$') then
    local new=module.new; module.new=function(...) c=new(...); return c end
  elseif path:match('ReaSkii_DeviceRackUI.lua$') then
    local new=module.new; module.new=function(...)
      u=new(...); uiControls={}
      local draw,button,slider=u.draw,u.button,u.slider_cell
      function u:button(x,y,w,label,...) uiControls['b:'..label]={x=x+w/2,y=y+9}; return button(self,x,y,w,label,...) end
      function u:slider_cell(control,x,y,w,...) uiControls['s:'..control.param]={x=x,y=y+28,w=w}; return slider(self,control,x,y,w,...) end
      function u:draw(...) uiControls={}; return draw(self,...) end
      return u
    end
  end
  return module
end
dofile(root..'/scripts/device/ReaSkii_DeviceRack.lua')
dofile=original
local token=''
local function json(v)
  if type(v)=='string' then return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','')..'"'
  elseif type(v)=='number' or type(v)=='boolean' then return tostring(v)
  elseif type(v)=='table' then
    local a={}; if #v>0 then for _,x in ipairs(v) do a[#a+1]=json(x) end; return '['..table.concat(a,',')..']' end
    for k,x in pairs(v) do a[#a+1]=json(tostring(k))..':'..json(x) end; return '{'..table.concat(a,',')..'}'
  end
  return 'null'
end
local function observe()
  local file=io.open(statePath..'.cmd','r')
  if file then
    local code=file:read('*a'); file:close(); os.remove(statePath..'.cmd')
    local fn,err=load(code,'fixture command','t',setmetatable({c=c,u=u,track=track,lfo=lfo,volume=volume,reaper=reaper}, {__index=_G}))
    local ok,result=false,err
    if fn then ok,result=pcall(fn) end
    token=token..'x'; if not ok then c:set_status(tostring(result)) end
  end
  local fx={}
  for i=0,reaper.TrackFX_GetCount(track)-1 do fx[#fx+1]={name=c:device_name(i),enabled=c:fx_enabled(i)} end
  local controls={}
  for _,control in ipairs(c.controls or {}) do controls[#controls+1]={param=control.param,label=control.label,kind=control.kind} end
  local _,trackName=reaper.GetTrackName(track,'')
  local data={token=token,status=c.status,configure=c.configure,fx=c.fx,fx_count=c.fx_count,track_name=trackName,devices=fx,controls=controls,ui=uiControls,width=gfx.w,height=gfx.h,dock=gfx.dock(-1)}
  local params={}
  for p=0,c:param_count()-1 do local norm,formatted,toggle=c:param_value(p); params[#params+1]={param=p,name=c:param_name(p),norm=norm,formatted=formatted,toggle=toggle} end
  data.params=params
  local out=assert(io.open(statePath..'.tmp','w')); out:write(json(data)); out:close(); os.rename(statePath..'.tmp',statePath)
  reaper.defer(observe)
end
observe()
