-- Project-local persistence for Device Rack controls.
local S={}
local Model=dofile((debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])') or '')..'ReaSkii_DeviceRackModel.lua')
S.SECTION='ReaSkii_DeviceRack'
function S.key(R,track,fx)
  local trackGuid=R.GetTrackGUID and R.GetTrackGUID(track) or ''
  local fxGuid=R.TrackFX_GetFXGUID and R.TrackFX_GetFXGUID(track,fx) or ''
  if trackGuid=='' or fxGuid=='' then return nil end
  return trackGuid..'|'..fxGuid
end
function S.load(R,project,track,fx)
  local key=S.key(R,track,fx)
  if not key then return {},'No stable track or FX GUID; configuration not read' end
  local present,value=R.GetProjExtState(project,S.SECTION,key)
  if present==0 or value==nil or value=='' then return {},nil end
  local controls,err=Model.decode(value)
  if not controls then return {},err end
  return controls,err
end
function S.save(R,project,track,fx,controls)
  local key=S.key(R,track,fx)
  assert(key,'No stable track or FX GUID; configuration not saved')
  local text=Model.encode(controls)
  local written=R.SetProjExtState(project,S.SECTION,key,text)
  assert(written and written~=0,'Device-rack save was refused')
  local present,readback=R.GetProjExtState(project,S.SECTION,key)
  assert(present==1 and readback==text,'Device-rack save readback mismatch')
  return true
end
return S
