-- Companion-panel state; local semantics, NOT measured Ableton parity.
local P={}
local directory=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\\\])') or ''
local F=dofile(directory..'ReaSkii_MIDI_PanelFeatures.lua')
P.features=F
P.spec={stretch={.01,100,1,.01},low={-100,100,0,1},high={-100,100,0,1},
  tension={-100,100,0,1},interval={-127,127,0,1},humanize={0,100,10,1}}
for k,v in pairs(F.spec) do P.spec[k]=v end
function P.limit(key,value)
  local s=assert(P.spec[key],'Unknown parameter')
  assert(type(value)=='number' and value==value and math.abs(value)<math.huge,'Enter a finite number')
  value=math.max(s[1],math.min(s[2],value))
  return math.floor(value/s[4]+.5)*s[4]
end
function P.adjust(key,base,delta,fine)
  return P.limit(key,base+delta*P.spec[key][4]*(fine and .1 or 1))
end
function P.graph_value(x,left,width) return P.limit('high',(x-left)/width*200-100) end
function P.curve(t,tension) return 1-(1-t)^(2^(2*tension/100)) end
P.scales={{'Major',{0,2,4,5,7,9,11}},{'Minor',{0,2,3,5,7,8,10}},
  {'Dorian',{0,2,3,5,7,9,10}},{'Chromatic',{0,1,2,3,4,5,6,7,8,9,10,11}}}
function P.new(engine,target)
  local c={auto=true,tool='strum',generator='rhythm',replace=false,values={},root=0,scale=1,status='Open a MIDI item; select notes in the native editor.',engine=engine}
  function c:info() local _,ctx=target(); return ctx or {} end
  function c:choose(tool,generator)
    if self.session then self:cancel() end
    if generator then self.generator=tool else self.tool=tool end
    self.status='Selected '..tool..'. Independent provisional implementation.'
  end
  function c:mode()
    if self.session then self:cancel() end
    self.replace=not self.replace
    self.status=self.replace and 'REPLACE armed: removes notes starting inside displayed range only when previewed/generated.' or 'ADD mode: existing notes preserved; collisions refused.'
  end
  for key,s in pairs(P.spec) do c.values[key]=s[3] end
  function c:options(tool)
    local take,context
    if self.session then take,context=self.session.take,self.context else take,context=target() end
    assert(take,'Open a MIDI item in the native editor and select notes.')
    context=context or {}
    if tool=='strum' then
      assert(context.grid_ppq and context.grid_ppq>0,'Choose a native MIDI grid first.')
      return {low=self.values.low,high=self.values.high,tension=self.values.tension/100,
        grid_ppq=context.grid_ppq,onset_tolerance=0},take
    elseif tool=='stretch' then return {factor=self.values.stretch,anchor=context.anchor or 0},take
    elseif tool=='fit_scale' then return {root=self.root,intervals=P.scales[self.scale][2]},take
    elseif tool=='invert' then return {pivot=assert(context.pivot,'Select notes for inversion pivot.')},take
    elseif tool=='reverse' then return {range_start=assert(context.range_start),range_end=assert(context.range_end)},take
    elseif tool=='legato' then return {},take end
    local extra=F.options(tool,self.values,context,self)
    if extra then return extra,take end
    error('Unavailable: no safe adapter mapping for '..tostring(tool),0)
  end
  function c:cancel()
    if self.session then
      self.session:cancel(); self.session=nil; self.active=nil; self.context=nil; self.blocked=nil
    end
    self.status='Original restored. Committed MIDI is unchanged.'
  end
  function c:check_context(context)
    for _,key in ipairs({'position','length','offset','playrate','generate_start','generate_end'}) do
      assert((context or {})[key]==(self.context or {})[key],'Item or time-selection context changed; cancel preview before retrying.')
    end
  end
  function c:preview(tool)
    assert(not self.blocked,'Preview blocked; resolve recovery or cancel before editing.')
    local take,context=target()
    if self.session then
      if self.session.take~=take then
        self:cancel()
        error('Native target changed; previous preview restored. Retry on the new target.',0)
      end
      self.session:check() -- selection changes are raw MIDI edits too
      self:check_context(context)
      if self.active and self.active~=tool then self:cancel(); take,context=target() end
    end
    assert(take,'Open a MIDI item in the native editor.')
    if not self.session then
      self.context={}; for k,v in pairs(context or {}) do self.context[k]=v end
      self.session=engine.session(take)
    end
    local options=self:options(tool)
    self.session:preview(tool,options); self.active=tool
    self.status='Preview: '..tool..' from snapshot. Not committed.'
  end
  function c:set(key,value,tool)
    value=P.limit(key,value)
    if self.values[key]==value then return end
    local previous=self.values[key]
    self.values[key]=value
    local ok,err=pcall(function()
      if tool then
        if self.auto then self:preview(tool) end
      elseif key=='stretch' or key=='low' or key=='high' or key=='tension' then
        if self.auto then self:preview(key=='stretch' and 'stretch' or 'strum') end
      end
    end)
    if not ok then self.values[key]=previous; self.status='Update failed: '..tostring(err); error(err,0) end
  end
  function c:toggle_auto()
    if self.auto then self:cancel(); self.auto=false
    else self.auto=true end -- enabling arms the next adjustment, no hidden reapplication
    self.status=self.auto and 'Auto on: next adjustment previews from snapshot.' or 'Auto off: original restored; Apply/Transform/Generate uses staged values.'
  end
  function c:commit()
    assert(self.session,'No pending preview to keep.')
    assert(not self.blocked,'Preview blocked; cannot commit.')
    local take,ctx=target()
    assert(take==self.session.take,'Native target changed; cannot commit.')
    self:check_context(ctx)
    local changed=self.session:apply('ReaSkii panel: '..tostring(self.active))
    self.session=nil; self.active=nil; self.context=nil
    self.status=changed==false and 'No MIDI change; no undo point created.' or 'Committed. Native REAPER Undo is available.'
  end
  function c:transform() self:preview(self.tool); self:commit() end
  function c:generate() self:preview(self.generator); self:commit() end
  function c:action(tool) self:preview(tool); self:commit() end
  function c:reset(tool)
    tool=tool or self.tool
    for _,key in ipairs(F.fields[tool] or {}) do self.values[key]=P.spec[key][3] end
    self.status=tool..' parameters staged/reset only; '..(self.session and 'OLD PREVIEW STILL AUDIBLE. Apply to update, or Cancel.' or 'MIDI unchanged. Adjust or apply to use.')
  end
  function c:poll()
    if not self.session then return true end
    local ok,err=pcall(function()
      local take,ctx=target()
      assert(take==self.session.take,'Native target changed; preview stopped')
      self:check_context(ctx)
      self.session:check()
    end)
    if not ok then
      local restored=pcall(function() self:cancel() end)
      self.blocked=not restored
      self.status=tostring(err)..(restored and ' Original restored.' or ' Restore refused; session and recovery retained. MIDI untouched.')
    end
    return ok
  end
  function c:close()
    if self.session then
      local ok,err=pcall(function() self:cancel() end)
      if not ok then self.status='Restore refused: '..tostring(err)..'; recovery retained.' end
    end
  end
  return c
end
-- REAPER's final unselected all-notes-off is a source boundary, not a
-- note-owned expression curve. Exclude ONLY that exact terminal marker from
-- analysis, restore it unchanged, and refuse any result crossing its boundary.
-- All other CC/pressure/bend events still go through the adapter's refusals.
function P.transform(raw,tool,options,A,C)
  local events=C.decode(raw)
  local last
  for i,e in ipairs(events) do if #e.msg>0 then last=i end end
  local terminal=last and events[last]
  if not terminal or terminal.msg~=string.char(0xB0,123,0) or terminal.flags~=0 then
    return A.transform(raw,tool,options)
  end
  local function pack(list)
    local parts,previous={},0
    for _,e in ipairs(list) do
      parts[#parts+1]=string.pack('i4Bs4',e.pos-previous,e.flags,e.msg); previous=e.pos
    end
    return table.concat(parts)
  end
  local boundary=terminal.pos
  table.remove(events,last)
  local transformed=C.decode(A.transform(pack(events),tool,options))
  for _,e in ipairs(transformed) do
    assert(#e.msg==0 or e.pos<=boundary,'Result crosses the native all-notes-off source boundary')
  end
  local restored={}
  local inserted=false
  for _,e in ipairs(transformed) do
    if not inserted and (e.pos>boundary or (e.pos==boundary and #e.msg==0)) then
      restored[#restored+1]={pos=boundary,flags=0,msg=string.char(0xB0,123,0)}; inserted=true
    end
    restored[#restored+1]=e
  end
  if not inserted then restored[#restored+1]={pos=boundary,flags=0,msg=string.char(0xB0,123,0)} end
  return pack(restored)
end
return P
