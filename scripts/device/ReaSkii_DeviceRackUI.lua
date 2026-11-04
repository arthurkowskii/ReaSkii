-- Original vector UI for the ReaSkii Device Rack. Reference layout, local gestures.
local U={}
function U.new(controller)
  local c=controller
  local u={c=controller,drag=nil,prev=false,chain_scroll=0,param_scroll=0,body_scroll=0,last_param=nil,last_click=0,consumed=false}
  local function color(v) gfx.set(v,v,v,1) end
  local function text(x,y,s,v) color(v or .84); gfx.x=x; gfx.y=y; gfx.drawstr(s) end
  local function box(x,y,w,h,v,round)
    color(v); if round then gfx.roundrect(x,y,w,h,5,true) else gfx.rect(x,y,w,h,true) end
  end
  local function fit(s,w)
    s=tostring(s or '')
    if gfx.measurestr(s)<=w then return s end
    while #s>1 and gfx.measurestr(s..'...')>w do s=s:sub(1,-2) end
    return s..'...'
  end
  local function safe(fn)
    local ok,err=pcall(fn)
    if not ok then controller:set_status(tostring(err):gsub('^.-:%d+: ','')) end
  end
  function u:hit(x,y,w,h)
    return self.mx>=x and self.mx<x+w and self.my>=y and self.my<y+h
  end
  function u:button(x,y,w,label,fn,enabled,active)
    local over=self:hit(x,y,w,18)
    box(x,y,w,18,enabled==false and .17 or (active and .34 or (over and .30 or .21)),true)
    text(x+5,y+2,fit(label,w-8),enabled==false and .45 or .86)
    if self.clicked and over then
      self.consumed=true
      if enabled==false then controller:set_status('Unavailable: '..label) else safe(fn) end
    end
  end
  function u:small(x,y,w,label,fn)
    local over=self:hit(x,y,w,16)
    box(x,y,w,16,over and .33 or .22)
    text(x+3,y+1,label,.86)
    if self.clicked and over then self.consumed=true; safe(fn) end
  end
  function u:slider_cell(control,x,y,w,h)
    local param=control.param
    local norm,formatted=c:param_value(param)
    local shown=control.label and control.label~='' and control.label or c:param_name(param)
    text(x,y,fit(shown,w-70),.86)
    local value=fit(formatted,64)
    text(x+w-gfx.measurestr(value),y,value,.64)
    local tx,ty,tw= x,y+28,w-4
    color(.18); gfx.rect(tx,ty,tw,4,true)
    color(.64); gfx.rect(tx,ty,tw*norm,4,true)
    local hx=tx+tw*norm
    gfx.set(.96,.74,.24,1); gfx.circle(hx,ty+2,5,true,true)
    local hitx, hity, hitw, hith=tx-6,ty-8,tw+12,20
    if self:hit(hitx,hity,hitw,hith) then
      if self.wheel~=0 then
        local delta=(self.fine and .001 or .01)*(self.wheel>0 and 1 or -1)
        safe(function() c:set_param(param,norm+delta) end)
        controller:set_status(shown..': '..c:param_value(param))
        self.wheel=0; self.consumed=true
      end
      if self.clicked and not self.consumed then
        self.consumed=true
        local now=reaper.time_precise()
        if self.last_param==param and now-(self.last_click or 0)<.32 then
          c:set_param(param,c:param_default(param)); self.drag=nil; self.last_param=nil
          controller:set_status(shown..' set to midpoint')
        else
          local value_at=function(px) return math.max(0,math.min(1,(px-tx)/tw)) end
          local target=value_at(self.mx)
          c:set_param(param,target)
          self.drag={param=param,x=self.mx,base=target,shown=shown}
          self.last_param=param; self.last_click=now
        end
      end
    end
    if self.drag and self.drag.param==param then
      if self.down then
        local d=self.drag
        local target
        if self.fine then target=d.base+(self.mx-d.x)/tw*.1
        else target=(self.mx-tx)/tw end
        safe(function() c:set_param(param,target) end)
      else self.drag=nil end
    end
    return h
  end
  function u:toggle_cell(control,x,y,w,h)
    local param=control.param
    local norm,formatted,toggle=c:param_value(param)
    local shown=control.label and control.label~='' and control.label or c:param_name(param)
    text(x,y,fit(shown,w-76),.86)
    text(x+w-64,y,fit(formatted,62),.64)
    local bx,by,bw,bh=x,y+26,w-4,20
    box(bx,by,bw,bh,norm>=.5 and .34 or .18)
    text(bx+5,by+2,norm>=.5 and 'ON' or 'OFF',norm>=.5 and .95 or .55)
    if self.clicked and self:hit(bx,by,bw,bh) then
      self.consumed=true
      c:set_param(param,norm>=.5 and 0 or 1)
      controller:set_status(shown..': '..c:param_value(param))
    end
    return h
  end
  function u:chain(y,height)
    local R=c.R
    local track=c.track
    local count=c.fx_count or 0
    local cardw=164
    local visible=math.max(1,math.floor((self.width-16)/(cardw+6)))
    local maxscroll=math.max(0,count-visible)
    self.chain_scroll=math.max(0,math.min(maxscroll,self.chain_scroll or 0))
    local x=8
    if count==0 then text(12,y+14,'No devices on the selected track.',.55); return end
    if self.wheel~=0 and self:hit(0,y,self.width,height) then
      self.chain_scroll=math.max(0,math.min(maxscroll,self.chain_scroll+(self.wheel>0 and -1 or 1)))
      self.wheel=0; self.consumed=true
    end
    local basex=8
    for index=self.chain_scroll,math.min(count-1,self.chain_scroll+visible-1) do
      local selected=index==c.fx
      local enabled=c:fx_enabled(index)
      local cx=basex+(index-self.chain_scroll)*(cardw+6)
      box(cx,y,cardw,height-6,selected and .31 or .19,true)
      if selected then color(.92); gfx.rect(cx,y,2,height-6,true) end
      local pw=16
      box(cx+7,y+7,pw,16,enabled and .45 or .20)
      text(cx+10,y+8,enabled and 'I' or 'O',enabled and .95 or .55)
      if self.clicked and self:hit(cx+7,y+7,pw,16) then
        self.consumed=true; c:set_fx_enabled(index,not enabled)
      elseif self.clicked and self:hit(cx,y,cardw,height-6) then
        self.consumed=true; c:select_fx(index)
      end
      text(cx+29,y+7,fit(c:device_name(index),cardw-34),selected and .98 or .78)
      text(cx+8,y+28,string.format('%02d',index+1),.52)
      local pcount=(function() local ok,n=pcall(R.TrackFX_GetNumParams,track,index); return ok and n or 0 end)()
      text(cx+29,y+28,string.format('%d params',pcount),.52)
    end
    if count>visible then
      if self.chain_scroll>0 then self:small(self.width-44,y+height-26,16,'<',function() self.chain_scroll=self.chain_scroll-1 end) end
      if self.chain_scroll<maxscroll then self:small(self.width-24,y+height-26,16,'>',function() self.chain_scroll=self.chain_scroll+1 end) end
    end
  end
  function u:controls_body(y,height)
    local controls=c:visible_controls()
    if #controls==0 then
      text(12,y+16,'No preview controls for this device.',.64)
      text(12,y+34,'Open Configure to choose parameters, or add the MIDI LFO.',.52)
      return
    end
    local colw=(self.width-34)/2
    local rowh=54
    local rows=math.ceil(#controls/2)
    local maxscroll=math.max(0,rows*rowh-height+12)
    self.body_scroll=math.max(0,math.min(maxscroll,self.body_scroll or 0))
    for i,control in ipairs(controls) do
      local col=(i-1)%2; local row=math.floor((i-1)/2)
      local cx=12+col*(colw+10)
      local cy=y+row*rowh-self.body_scroll
      if cy+rowh>y-2 and cy<y+height then
        box(cx,cy,colw,rowh-8,.145,true)
        if control.kind=='toggle' then self:toggle_cell(control,cx+8,cy+7,colw-16,rowh-14)
        else self:slider_cell(control,cx+8,cy+7,colw-16,rowh-14) end
      end
    end
    if #controls>0 then
      text(12,y+height-14,string.format('%d preview controls / %d parameters',#controls,c:param_count()),.46)
    end
    if self.wheel~=0 and self:hit(0,y,self.width,height) then
      self.body_scroll=math.max(0,math.min(maxscroll,self.body_scroll+(self.wheel>0 and -2 or 2)))
      self.wheel=0; self.consumed=true
    end
  end
  function u:configure_body(y,height)
    local controls=c.controls or {}
    local count=c:param_count()
    local leftw=math.floor((self.width-30)*.48)
    local rightx=12+leftw+10
    local rightw=self.width-rightx-12
    text(12,y,'PANEL',.62); text(rightx,y,'PARAMETERS',.62)
    local listy=y+18
    local rowh=22
    local maxrows=math.max(1,math.floor((height-24)/rowh))
    box(12,listy,leftw,height-26,.12)
    if #controls==0 then text(18,listy+8,'Empty. Add from the parameter list.',.50) end
    for i,control in ipairs(controls) do
      local ry=listy+4+(i-1)*rowh
      if ry+rowh>listy and ry<listy+height-26 then
        text(18,ry,fit(control.label or c:param_name(control.param),leftw-96),.84)
        text(18+leftw-88,ry,string.format('%02d',control.param),.46)
        self:small(18+leftw-58,ry-1,16,'<',function() c:move_control(control.param,-1); c:refresh() end)
        self:small(18+leftw-40,ry-1,16,'>',function() c:move_control(control.param,1); c:refresh() end)
        self:small(18+leftw-22,ry-1,16,'x',function() c:remove_control(control.param); c:refresh() end)
      end
    end
    box(rightx,listy,rightw,height-26,.12)
    self.param_scroll=math.max(0,math.min(math.max(0,count-maxrows),self.param_scroll or 0))
    if self.wheel~=0 and self:hit(rightx,listy,rightw,height-26) then
      self.param_scroll=math.max(0,math.min(math.max(0,count-maxrows),self.param_scroll+(self.wheel>0 and -1 or 1)))
      self.wheel=0; self.consumed=true
    end
    local selected={}
    for _,control in ipairs(controls) do selected[control.param]=true end
    for row=0,maxrows-1 do
      local param=self.param_scroll+row
      if param>=count then break end
      local ry=listy+4+row*rowh
      local on=selected[param]
      box(rightx+4,ry,rightw-8,rowh-3,on and .25 or .16)
      text(rightx+9,ry+3,on and '-' or '+',on and .95 or .62)
      text(rightx+27,ry+3,fit(c:param_name(param),rightw-52),.82)
      if self.clicked and self:hit(rightx+4,ry,rightw-8,rowh-3) then
        self.consumed=true
        if on then c:remove_control(param) else c:add_control(param) end
        c:refresh()
      end
    end
    text(12,y+height-8,string.format('%d configured / %d available',#controls,count),.46)
  end
  function u:draw()
    self.width=math.max(640,gfx.w); self.height=math.max(220,gfx.h)
    self.mx=gfx.mouse_x; self.my=gfx.mouse_y
    self.down=(gfx.mouse_cap&1)~=0
    self.clicked=self.down and not self.prev
    self.fine=(gfx.mouse_cap&8)~=0
    self.wheel=gfx.mouse_wheel; gfx.mouse_wheel=0
    self.consumed=false
    color(.13); gfx.rect(0,0,self.width,self.height,true)
    box(0,0,self.width,24,.22)
    text(8,6,'DEVICE RACK',.92)
    local trackName='no track'
    if c.track then local _,name=c.R.GetTrackName(c.track,''); trackName=name or 'track' end
    text(112,6,fit(trackName,self.width-360),.62)
    if c.track and c.fx then
      self:button(self.width-250,3,100,c.configure and 'Done' or 'Configure',function() c.configure=not c.configure end)
      self:button(self.width-144,3,136,'Add MIDI LFO',function() c:insert_lfo(); c:refresh() end)
    end
    local chainy=30
    if c.track then self:chain(chainy,58) end
    local bodyy=94
    local bodyh=self.height-bodyy-40
    if c.track and c.fx then
      local name=c:device_name(c.fx)
      box(0,bodyy-2,self.width,22,.17)
      text(10,bodyy+2,fit(name,self.width-180),.94)
      text(self.width-168,bodyy+2,string.format('%d params',c:param_count()),.52)
      if c.configure then self:configure_body(bodyy+24,bodyh-24)
      else self:controls_body(bodyy+24,bodyh-24) end
    elseif c.track then
      text(12,bodyy+20,'Select a device in the chain.',.55)
    end
    box(0,self.height-22,self.width,22,.18)
    text(8,self.height-18,fit(c.status or '',self.width-16),.72)
    self.prev=self.down
  end
  return u
end
return U
