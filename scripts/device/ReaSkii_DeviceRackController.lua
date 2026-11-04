-- Device Rack controller: selected track, FX chain, config and parameter writes.
local C={}
local directory=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\\\])') or ''
local Model=dofile(directory..'ReaSkii_DeviceRackModel.lua')
local Store=dofile(directory..'ReaSkii_DeviceRackStore.lua')
C.LFO_NAME='JS: ReaSkii/ReaSkii MIDI LFO'

function C.new(R)
  local c={R=R,status='Select a track to show its devices.',configure=false,chain_scroll=0,param_scroll=0}
  local function safe_name(fn,...)
    local ok,a,b=pcall(fn,...)
    if ok then return a,b end
    return nil,tostring(a)
  end
  function c:project() return 0 end
  function c:track_guid(track)
    if not track then return nil end
    local ok,guid=pcall(self.R.GetTrackGUID,track)
    return ok and guid or nil
  end
  function c:track_name()
    if not self.track then return 'no track' end
    local ok,a,b=pcall(self.R.GetTrackName,self.track,'')
    local name=(type(b)=='string' and b) or (type(a)=='string' and a)
    return name or 'track'
  end
  function c:device_name(fx)
    local track=self.track
    if not track then return '' end
    local ok,a,b=pcall(self.R.TrackFX_GetFXName,track,fx,'')
    local name=(type(b)=='string' and b) or (type(a)=='string' and a)
    if not ok or not name or name=='' then return 'FX '..tostring(fx+1) end
    name=name:gsub('^JS: ','')
    return name
  end
  function c:refresh()
    local R=self.R
    local track=R.GetSelectedTrack(0,0)
    local guid=self:track_guid(track)
    if track~=self.track or guid~=self.track_guid_value then
      self.track,self.track_guid_value=track,guid
      self.fx=nil; self.controls={}; self.loaded_key=nil; self.chain_scroll=0
    end
    if not track then
      self.fx=nil; self.controls={}; self.loaded_key=nil
      self.status='Select a track to show its devices.'
      return false
    end
    local count=R.TrackFX_GetCount(track)
    self.fx_count=count
    if count==0 then
      self.fx=nil; self.controls={}; self.loaded_key=nil
      self.status='No devices on this track. Add a MIDI effect or use Add MIDI LFO.'
      return false
    end
    if type(self.fx)~='number' or self.fx<0 or self.fx>=count then self.fx=0 end
    local fxGuid=R.TrackFX_GetFXGUID and R.TrackFX_GetFXGUID(track,self.fx) or tostring(self.fx)
    if type(fxGuid)=='string' and fxGuid~='' then
      local key=(guid or '')..'|'..fxGuid
      if key~=self.loaded_key then
        self.loaded_key=key
        local controls,err=Store.load(R,self:project(),track,self.fx)
        self.controls=controls or {}
        self.status='Track: '..self:track_name()..' / '..self:device_name(self.fx)
        if err then self.status='Configuration warning: '..tostring(err) end
      end
    end
    return true
  end
  function c:select_fx(index)
    if not self.track then return false end
    if index<0 or index>=self.fx_count then return false end
    self.fx=index; self.loaded_key=nil; self.configure=false; self.param_scroll=0
    self:refresh()
    self.status='Device: '..self:device_name(index)
    return true
  end
  function c:fx_enabled(index)
    if not self.track then return false end
    local ok,value=pcall(self.R.TrackFX_GetEnabled,self.track,index or self.fx)
    return ok and value==true
  end
  function c:set_fx_enabled(index,enabled)
    if not self.track then return false end
    local R=self.R
    local project=self:project()
    R.Undo_BeginBlock2(project)
    local ok=pcall(R.TrackFX_SetEnabled,self.track,index,enabled and true or false)
    R.Undo_EndBlock2(project,'ReaSkii Device Rack: bypass device',-1)
    if not ok then self.status='Could not change device bypass.'; return false end
    self.status=self:device_name(index)..(enabled and ' enabled' or ' bypassed')
    return true
  end
  function c:param_count()
    if not self.track or not self.fx then return 0 end
    local ok,count=pcall(self.R.TrackFX_GetNumParams,self.track,self.fx)
    return ok and count or 0
  end
  function c:param_name(param)
    if not self.track or not self.fx then return 'Param '..tostring(param) end
    local ok,a,b=pcall(self.R.TrackFX_GetParamName,self.track,self.fx,param,'')
    local name=(type(b)=='string' and b) or (type(a)=='string' and a)
    return name or ('Param '..tostring(param))
  end
  function c:param_value(param)
    if not self.track or not self.fx then return 0,'',false end
    local R=self.R
    local ok,norm=pcall(R.TrackFX_GetParamNormalized,self.track,self.fx,param)
    if not ok or type(norm)~='number' then norm=0 end
    local okf,a,b=pcall(R.TrackFX_GetFormattedParamValue,self.track,self.fx,param,'')
    local formatted=(type(b)=='string' and b) or (type(a)=='string' and a) or tostring(norm)
    local toggle=false
    if R.TrackFX_GetParameterStepSizes then
      local oks,retval,step,small,large,is_toggle=pcall(R.TrackFX_GetParameterStepSizes,self.track,self.fx,param)
      toggle=oks and is_toggle==true
    end
    return norm,(okf and formatted or tostring(norm)),toggle
  end
  function c:param_default(param)
    local R=self.R
    if R.TrackFX_GetParamEx then
      local ok,value,minv,maxv,mid=pcall(R.TrackFX_GetParamEx,self.track,self.fx,param)
      if ok and type(minv)=='number' and type(maxv)=='number' and maxv>minv and type(mid)=='number' then
        return math.max(0,math.min(1,(mid-minv)/(maxv-minv)))
      end
    end
    return 0.5
  end
  function c:set_param(param,norm)
    if not self.track or not self.fx then return false end
    norm=math.max(0,math.min(1,tonumber(norm) or 0))
    local ok=R.TrackFX_SetParamNormalized(self.track,self.fx,param,norm)
    if not ok then self.status='Could not set '..self:param_name(param)..'.'; return false end
    return true
  end
  function c:save()
    if not self.track or not self.fx then return false end
    local ok,err=pcall(Store.save,self.R,self:project(),self.track,self.fx,self.controls)
    if not ok then self.status='Configuration not saved: '..tostring(err); return false end
    self.status='Configuration saved in project.'
    return true
  end
  function c:visible_controls()
    local list,count={},self:param_count()
    for _,control in ipairs(self.controls or {}) do
      if control.param>=0 and control.param<count then list[#list+1]=control end
    end
    return list
  end
  function c:add_control(param)
    local count=self:param_count()
    if param<0 or param>=count then return false end
    local name=self:param_name(param)
    self.controls=Model.add(self.controls,param,name,self:is_toggle(param) and 'toggle' or 'slider')
    return self:save()
  end
  function c:remove_control(param)
    self.controls=Model.remove(self.controls,param)
    return self:save()
  end
  function c:move_control(param,delta)
    self.controls=Model.move(self.controls,param,delta)
    return self:save()
  end
  function c:is_toggle(param)
    local R=self.R
    if R.TrackFX_GetParameterStepSizes then
      local ok,retval,step,small,large,is_toggle=pcall(R.TrackFX_GetParameterStepSizes,self.track,self.fx,param)
      return ok and is_toggle==true
    end
    return false
  end
  function c:insert_lfo()
    if not self.track then self.status='Select a track first.'; return false end
    local R=self.R
    local before=R.TrackFX_GetCount(self.track)
    local project=self:project()
    R.Undo_BeginBlock2(project)
    local ok,index=pcall(R.TrackFX_AddByName,self.track,C.LFO_NAME,false,-1)
    R.Undo_EndBlock2(project,'ReaSkii Device Rack: add MIDI LFO',-1)
    if not ok or type(index)~='number' or index<0 then
      self.status='MIDI LFO insert refused. Is ReaSkii MIDI LFO installed in Effects?'
      return false
    end
    self.fx_count=R.TrackFX_GetCount(self.track)
    self:select_fx(index)
    self:apply_lfo_defaults()
    self.status='MIDI LFO added. Rate, Shape, Depth, Center and CC are ready in Previews.'
    return true
  end
  function c:apply_lfo_defaults()
    if #self.controls>0 then return end
    local wanted={['Free Rate (Hz)']=true,['Shape']=true,['Depth (%)']=true,['Center']=true,['CC']=true}
    local count=self:param_count()
    for param=0,count-1 do
      if wanted[self:param_name(param)] then
        self.controls=Model.add(self.controls,param,self:param_name(param),self:is_toggle(param) and 'toggle' or 'slider')
      end
    end
    if #self.controls>0 then self:save() end
  end
  function c:set_status(text) self.status=tostring(text) end
  return c
end
return C
