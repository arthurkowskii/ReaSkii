-- Original gfx primitives and inline input. Reference layout, provisional gestures.
local U={}
function U.new(c,P)
  local u={c=c,P=P,scroll=0,sections={Clip=true,Launch=false,['Pitch & Time']=true,Transform=true,Generate=false},prev=false,parameter_tools={},accum={}}
  local F=P.features
  local function color(v) gfx.set(v,v,v,1) end
  local function text(x,y,s,v) color(v or .83); gfx.x=x; gfx.y=y; gfx.drawstr(s) end
  local function box(x,y,w,h,v,round)
    color(v); if round then gfx.roundrect(x,y,w,h,6,true) else gfx.rect(x,y,w,h,true) end
  end
  local function safe(fn)
    local ok,err=pcall(fn); if not ok then c.status=tostring(err):gsub('^.-:%d+: ','') end
  end
  function u:setvalue(key,value,tool) c:set(key,value,tool) end
  function u:hit(x,y,w,h)
    return self.mx>=x and self.mx<x+w and self.my>=y and self.my<y+h and (self.footer or self.my<self.viewport)
  end
  function u:button(x,y,w,label,fn,enabled)
    local over=self:hit(x,y,w,18)
    box(x,y,w,18,enabled==false and .19 or (over and .32 or .22),true)
    text(x+5,y+2,label,enabled==false and .46 or .84)
    if self.clicked and over then
      if enabled==false then c.status='Unavailable: '..label..'. No safe engine mapping in this milestone.' else safe(fn) end
    end
  end
  function u:number(key,x,y,w,suffix)
    local value=c.values[key]
    box(x,y,w,18,.12)
    local editing=self.edit and self.edit.key==key
    text(x+4,y+2,editing and (self.edit.buffer..'|') or (string.format(P.spec[key][4]<1 and '%.2f' or '%.0f',value)..(suffix or '')))
    self:control(key,x,y,w,18,false)
  end
  function u:control(key,x,y,w,h,knob)
    if self:hit(x,y,w,h) then
      if self.wheel~=0 then
        -- Fine wheel substeps accumulate instead of being rounded away on integers.
        local step=P.spec[key][4]
        if self.fine and step>=1 then
          self.accum[key]=(self.accum[key] or 0)+self.wheel/120*step*.1
          local delta=0
          if math.abs(self.accum[key])>=step*.5 then
            delta=(self.accum[key]>0 and 1 or -1)*step
            self.accum[key]=self.accum[key]-delta
          end
          if delta~=0 then safe(function() self:setvalue(key,c.values[key]+delta,self.parameter_tools[key]) end) end
        else
          safe(function() self:setvalue(key,P.adjust(key,c.values[key],self.wheel/120,self.fine),self.parameter_tools[key]) end)
        end
        self.wheel=0
      end
      if self.clicked then
        local now=reaper.time_precise()
        if self.last_key==key and now-(self.last_click or 0)<.32 then
          self.edit=nil; self.drag=nil; safe(function() self:setvalue(key,P.spec[key][3],self.parameter_tools[key]) end)
          self.last_key=nil
        else
          self.drag={key=key,x=self.mx,y=self.my,base=c.values[key],knob=knob,tool=self.parameter_tools[key]}
          self.last_key=key; self.last_click=now
        end
      end
    end
  end
  function u:header(name,y)
    box(0,y,self.width-8,20,.29)
    text(8,y+3,(self.sections[name] and 'v  ' or '>  ')..name,.9)
    if self.clicked and self:hit(0,y,self.width-8,20) then self.sections[name]=not self.sections[name]; self.edit=nil end
    return y+22,self.sections[name]
  end
  function u:key(key)
    if not self.edit then return end
    if key==27 then self.edit=nil
    elseif key==13 then
      local e=self.edit
      safe(function() local n=assert(tonumber(e.buffer),'Enter a number'); self:setvalue(e.key,n,e.tool); self.edit=nil end)
    elseif key==8 then
      if self.edit.selected then self.edit.buffer=''; self.edit.selected=false else self.edit.buffer=self.edit.buffer:sub(1,-2) end
    elseif key>=32 and key<127 and string.char(key):match('[%d%.%+%-]') then
      if self.edit.selected then self.edit.buffer=''; self.edit.selected=false end
      self.edit.buffer=self.edit.buffer..string.char(key)
    end
  end
  function u:chooser(list,current,x,y,w,fn)
    local menu,label={},current
    for _,entry in ipairs(list) do
      if entry[2]==current then label=entry[1] end
      menu[#menu+1]=(not entry[2] and '#' or entry[2]==current and '!' or '')..entry[1]
    end
    self:button(x,y,w,label..' v',function()
      self.edit=nil; self.drag=nil; gfx.x=x; gfx.y=y
      local n=gfx.showmenu(table.concat(menu,'|'))
      if n>0 and list[n][2] then fn(list[n][2]) end
    end)
  end
  function u:quantize(y)
    -- Original primitives following official MIDIToolQuantizeL12 control layout.
    local left,width=14,self.width-36
    local gap=5; local half=(width-gap)/2
    local function choice(x,yy,w,label,key,value,enabled)
      if c.values[key]==value and enabled~=false then
        gfx.set(.57,.40,.06,1); gfx.rect(x-1,yy-1,w+2,20,true)
      end
      self:button(x,yy,w,label,function() c:set(key,value,'quantize') end,enabled)
    end
    choice(left,y,width,'Grid','quantize_grid',0); y=y+24
    for i,label in ipairs({'1/4','1/8','1/16','1/32'}) do
      local column=(i-1)%2; local row=math.floor((i-1)/2)
      choice(left+column*(half+gap),y+row*23,half,label,'quantize_grid',i)
    end
    y=y+49
    local active=c.values.quantize_grid~=0
    if c.values.quantize_triplets==1 and active then text(left,y+2,'[x]',.95) else text(left,y+2,'[ ]',.65) end
    self:button(left+26,y,width-26,'Triplets',function() c:set('quantize_triplets',1-c.values.quantize_triplets,'quantize') end,active)
    y=y+26; color(.36); gfx.line(left,y,left+width,y); y=y+8
    text(left,y+3,'Adjust Note')
    local x=left+82; local w=(width-87)/2
    choice(x,y,w,'Start','quantize_start',1-c.values.quantize_start)
    choice(x+w+5,y,w,'End','quantize_end',1-c.values.quantize_end)
    -- Note flags are independent toggles. Their active outlines reflect current state.
    for i,key in ipairs({'quantize_start','quantize_end'}) do
      if c.values[key]==1 then color(.75); gfx.rect(x+(i-1)*(w+5)-1,y-1,w+2,20,false) end
    end
    y=y+26; color(.36); gfx.line(left,y,left+width,y); y=y+10
    text(left+width/2-22,y,'Amount'); y=y+23
    local cx,cy=left+width/2,y+23
    local angle=-math.pi*.75+c.values.strength/100*math.pi*1.5
    local px,py
    for i=0,36 do
      local a=-math.pi*.75+i/36*math.pi*1.5
      local xx,yy=cx+23*math.sin(a),cy-23*math.cos(a)
      color(a<=angle and .78 or .34); if px then gfx.line(px,py,xx,yy) end; px,py=xx,yy
    end
    gfx.set(.92,.69,.21,1); gfx.line(cx,cy,cx+18*math.sin(angle),cy-18*math.cos(angle))
    self.parameter_tools.strength='quantize'; self:control('strength',cx-28,cy-28,56,56,true)
    self:number('strength',cx-36,cy+31,72,' %')
    y=cy+59; color(.36); gfx.line(left,y,left+width,y)
    return y+10
  end
  function u:fields(tool,y)
    for _,key in ipairs(F.fields[tool] or {}) do
      self.parameter_tools[key]=tool
      text(12,y+3,F.labels[key] or key)
      local choices=F.choices[key]
      if key=='grid' then choices={}; for _,g in ipairs(F.grids) do choices[#choices+1]=g[1] end end
      if choices then
        self:button(113,y,self.width-129,choices[c.values[key]]..' v',function()
          gfx.x=113; gfx.y=y; local n=gfx.showmenu(table.concat(choices,'|')); if n>0 then self:setvalue(key,n,tool) end
        end)
      elseif key=='spread' or key=='density' or key=='tie' or key=='gate' or key=='offset' or key=='variation' then
        local cx=128; local cy=y+17; local s=P.spec[key]; local angle=-math.pi*.75+(c.values[key]-s[1])/(s[2]-s[1])*math.pi*1.5
        local px,py
        for i=0,24 do local a=-math.pi*.75+i/24*math.pi*1.5; local xx,yy=cx+13*math.sin(a),cy-13*math.cos(a); color(a<=angle and .75 or .35); if px then gfx.line(px,py,xx,yy) end; px,py=xx,yy end
        gfx.set(.92,.69,.21,1); gfx.line(cx,cy,cx+10*math.sin(angle),cy-10*math.cos(angle))
        self:control(key,cx-17,cy-17,34,34,true)
        self:number(key,150,y+8,self.width-166)
        y=y+16
      else self:number(key,113,y,self.width-129) end
      y=y+22
    end
    if tool=='velocity_shaper' then
      local left,top,width,height=16,y,self.width-40,80
      color(.12); gfx.rect(left,top,width,height,true)
      local keys={'first','middle','last'}
      for i,k in ipairs(keys) do
        local x=left+(i-1)*width/2; local yy=top+height-c.values[k]/100*height
        if i>1 then local prev=keys[i-1]; gfx.set(.25,.82,.78,1); gfx.line(x-width/2,top+height-c.values[prev]/100*height,x,yy) end
        gfx.set(1,.72,.12,1); gfx.circle(x,yy,4,true,true)
        if self.clicked and self:hit(x-9,yy-9,18,18) then self.drag={key=k,base=c.values[k],y=self.my,x=self.mx,knob=true,tool=tool} end
      end
      y=y+86
    elseif tool=='chop' or tool=='euclidean' or tool=='rhythm' then
      local steps=tool=='chop' and c.values.parts or c.values.steps
      for i=1,math.min(steps,32) do
        local hit=tool=='chop' or ((i-1)*math.min(c.values.hits,steps))%steps<math.min(c.values.hits,steps)
        box(12+(i-1)*(self.width-30)/math.min(steps,32),y,(self.width-30)/math.min(steps,32)-2,12,hit and .72 or .3)
      end
      y=y+19
    end
    return y
  end
  function u:draw(key)
    self.width=math.max(180,gfx.w); self.viewport=math.max(70,gfx.h-126)
    self.mx=gfx.mouse_x; self.my=gfx.mouse_y
    local down=(gfx.mouse_cap & 1)~=0
    self.clicked=down and not self.prev; self.fine=(gfx.mouse_cap & 8)~=0
    self.wheel=gfx.mouse_wheel; gfx.mouse_wheel=0
    if self.drag then
      local d=self.drag
      if down then
        if d.graph then
          local delta=(self.mx-d.x)*200/d.width*(self.fine and .1 or 1)
          safe(function() self:setvalue(d.key,P.limit(d.key,d.base+delta)) end)
        elseif math.abs(self.my-d.y)>2 then
          d.moved=true
          safe(function() self:setvalue(d.key,P.adjust(d.key,d.base,d.y-self.my,self.fine),d.tool) end)
        end
      else
        if not d.graph and not d.knob and not d.moved then self.edit={key=d.key,buffer=tostring(c.values[d.key]),selected=true,tool=d.tool} end
        self.drag=nil
      end
    end
    self:key(key)
    self.parameter_tools={}
    gfx.setimgdim(1,gfx.w,self.viewport); gfx.dest=1
    box(0,0,gfx.w,self.viewport,.205)
    self.footer=false
    local y=-self.scroll
    local open
    y,open=self:header('Clip',y)
    if open then
      local info=c:info()
      text(10,y,(info.name or 'No native MIDI item'):sub(1,30),.76); y=y+18
      text(10,y,string.format('Start %.3fs   Length %.3fs',info.position or 0,info.length or 0),.65); y=y+17
      text(10,y,string.format('Offset %.3fs   Rate %.3f',info.offset or 0,info.playrate or 1),.65); y=y+17
      self:button(10,y,self.width-26,info.loop and 'Source loop ON' or 'Source loop OFF',function() c:clip_loop() end); y=y+23
      text(10,y,'Scale'); y=y+16
      local roots={'C','C#','D','D#','E','F','F#','G','G#','A','A#','B'}
      self:button(10,y,55,roots[c.root+1]..' v',function()
        gfx.x=10; gfx.y=y; local n=gfx.showmenu(table.concat(roots,'|')); if n>0 then c.root=n-1 end
      end)
      self:button(70,y,self.width-86,P.scales[c.scale][1]..' v',function()
        gfx.x=70; gfx.y=y; local n=gfx.showmenu('Major|Minor|Dorian|Chromatic'); if n>0 then c.scale=n end
      end); y=y+24
    end
    y,open=self:header('Launch',y)
    if open then text(10,y,'Unavailable: native clip launch'); y=y+24 end
    y,open=self:header('Pitch & Time',y)
    if open then
      local col=(self.width-28)/2; local right=col+18
      local info=c:info()
      local function pitch(n) return n and (({'C','C#','D','D#','E','F','F#','G','G#','A','A#','B'})[n%12+1]..tostring(math.floor(n/12)-1)) or '--' end
      box(10,y,col,40,.14); text(15,y+7,pitch(info.pitch_low)..' - '..pitch(info.pitch_high),.75)
      self:button(right,y,col,'Fit to Scale',function() c:action('fit_scale') end)
      self:button(right,y+21,col,'Invert',function() c:action('invert') end); y=y+44
      self:number('transpose',10,y,col,' st'); self:button(right,y,col,'Transpose',function() c:action('transpose') end); y=y+22
      self:number('interval',10,y,col,' st'); self:button(right,y,col,'Add Interval',function() c:action('add_interval') end); y=y+25
      text(18,y,'Stretch'); y=y+16
      local cx=10+col/2; local cy=y+16
      local angle=math.log(c.values.stretch)/math.log(100)*math.pi*.75
      local px,py
      for i=0,32 do
        local a=-math.pi*.75+i/32*math.pi*1.5
        local xx,yy=cx+13*math.sin(a),cy-13*math.cos(a)
        color(a<=angle and .74 or .38)
        if px then gfx.line(px,py,xx,yy) end
        px,py=xx,yy
      end
      gfx.set(.92,.69,.21,1); gfx.line(cx,cy,cx+10*math.sin(angle),cy-10*math.cos(angle))
      self:control('stretch',cx-18,cy-17,36,33,true)
      self:button(right,y,col,'x2',function() self:setvalue('stretch',c.values.stretch*2) end)
      self:button(right,y+21,col,'/2',function() self:setvalue('stretch',c.values.stretch/2) end)
      y=y+38; self:number('stretch',10,y,col,' x'); self:button(right,y,col,'Apply Stretch',function() c:action('stretch') end); y=y+24
      self:button(10,y,col,F.grids[c.values.grid][1]..' v',function()
        local menu={}; for _,g in ipairs(F.grids) do menu[#menu+1]=g[1] end
        gfx.x=10; gfx.y=y; local n=gfx.showmenu(table.concat(menu,'|')); if n>0 then c.values.grid=n end
      end)
      self:button(right,y,col,'Set Length',function() c:action('set_length') end); y=y+22
      self:number('humanize',10,y,col,' %'); self:button(right,y,col,'Humanize',function() c:action('humanize') end); y=y+23
      self:button(10,y,col,'Reverse',function() c:action('reverse') end)
      self:button(right,y,col,'Legato',function() c:action('legato') end); y=y+25
    end
    y,open=self:header('Transform',y)
    if open then
      self:button(10,y,23,'R',function() c:reset() end)
      self:chooser(F.transforms,c.tool,38,y,self.width-54,function(tool) c:choose(tool,false) end); y=y+23
      if c.tool=='strum' then
      local panel_y=y
      box(10,y,self.width-26,199,.12)
      text(16,y+5,'Low'); self:number('low',43,y+3,57,' %')
      text(self.width-116,y+5,'High'); self:number('high',self.width-81,y+3,57,' %')
      local left,top,width,height=19,y+30,self.width-44,133
      color(.37); gfx.rect(left,top,width,height,false); gfx.line(left,top+height/2,left+width,top+height/2)
      local function gx(v) return left+(v+100)/200*width end
      local px,py
      for i=0,60 do
        local t=i/60; local a=P.curve(t,c.values.tension)
        local x=gx(c.values.low*(1-a)+c.values.high*a); local yy=top+height-7-t*(height-14)
        if px then gfx.set(.25,.82,.78,1); gfx.line(px,py,x,yy) end
        px,py=x,yy
      end
      for _,point in ipairs({{'high',top+7},{'low',top+height-7}}) do
        local k,yy=point[1],point[2]; local x=gx(c.values[k])
        gfx.set(1,.72,.12,1); gfx.circle(x,yy,5,k=='low',true)
        if self.clicked and self:hit(x-9,yy-10,18,20) then self.drag={key=k,base=c.values[k],x=self.mx,width=width,graph=true}; self.edit=nil end
      end
      text(16,y+176,'Tension'); self:number('tension',83,y+173,75,' %')
      y=panel_y+205
      elseif c.tool=='quantize' then y=self:quantize(y)
      else y=self:fields(c.tool,y) end
      if c.auto then gfx.set(.57,.40,.06,1); gfx.rect(9,y-1,63,20,true) end
      self:button(10,y,61,c.auto and 'Auto ON' or 'Auto OFF',function() c:toggle_auto() end)
      self:button(80,y,self.width-96,'Transform',function() c:transform() end); y=y+23
      text(10,y,'Independent / partial controls',.58); y=y+18
    end
    y,open=self:header('Generate',y)
    if open then
      self:button(10,y,23,'R',function() c:reset(c.generator) end)
      self:chooser(F.generators,c.generator,38,y,self.width-54,function(tool) c:choose(tool,true) end); y=y+23
      local info=c:info()
      text(10,y,string.format('%s: %.0f .. %.0f PPQ',info.range_label or 'range',info.generate_start or 0,info.generate_end or 0),.7); y=y+18
      self:button(10,y,self.width-26,c.replace and 'REPLACE range (armed)' or 'ADD (collision-safe)',function() c:mode() end); y=y+23
      y=self:fields(c.generator,y)
      self:button(10,y,61,c.auto and 'Auto ON' or 'Auto OFF',function() c:toggle_auto() end)
      self:button(80,y,self.width-96,'Generate',function() c:generate() end); y=y+23
    end
    self.total=y+self.scroll+5
    if self.wheel~=0 and self.my<self.viewport then self.scroll=math.max(0,math.min(math.max(0,self.total-self.viewport),self.scroll-self.wheel/120*35)) end
    self.scroll=math.max(0,math.min(math.max(0,self.total-self.viewport),self.scroll))
    color(.46); gfx.rect(gfx.w-5,self.scroll/math.max(1,self.total)*self.viewport,3,math.max(8,self.viewport*self.viewport/math.max(self.viewport,self.total)),true)
    gfx.dest=-1; gfx.x=0; gfx.y=0; gfx.blit(1,1,0)
    self.footer=true
    local fy=self.viewport
    box(0,fy,gfx.w,126,.155)
    self:button(8,fy+5,70,'Keep pitch',function() assert(c.active=='stretch','Stretch preview required'); c:commit() end)
    self:button(83,fy+5,58,'Cancel',function() c:cancel() end)
    self:button(146,fy+5,self.width-153,'Dock',function() gfx.dock(gfx.dock(-1)==0 and 1 or 0) end)
    text(8,fy+28,'MILESTONE / Live parity unmeasured',.68)
    local line,yy='',fy+46
    for word in c.status:gmatch('%S+') do
      if gfx.measurestr(line..word)>gfx.w-17 then text(8,yy,line); line=''; yy=yy+14 end
      if yy<gfx.h-12 then line=line..word..' ' end
    end
    text(8,yy,line,.83)
    self.prev=down
  end
  return u
end
return U
