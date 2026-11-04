-- Independent, conservative lower-zone MPE raw adapter. No host calls or I/O.
-- Inject Expression with configure({E=Expression}); see docs/MIDI-MPE-INTEGRATION.md.
-- This is a provisional implementation, NOT measured Ableton Live parity.
local M = {}
local E
local function fail(s) error('MPE: '..s,0) end
local function finite(v) return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
local function number(v,lo,hi,name,whole)
  if not finite(v) or v<lo or v>hi or (whole and v%1~=0) then fail('invalid '..name) end
  return v
end
local function default(v,d) if v==nil then return d end return v end
local function keys(t,allowed)
  if type(t)~='table' then fail('options must be a table') end
  for k in pairs(t) do if not allowed[k] then fail('unsupported option '..tostring(k)) end end
end
function M.configure(o)
  keys(o,{E=true})
  if type(o.E)~='table' or type(o.E.decode)~='function' or type(o.E.transform)~='function' then
    fail('configure requires Expression.decode and Expression.transform')
  end
  E=o.E
  return M
end
local common={mpe=true,member_channels=true,pitchbend_range=true,dimension=true,mode=true}
local function options(tool,o)
  local allowed={} for k,v in pairs(common) do allowed[k]=v end
  local extra=tool=='glissando_mpe' and {'start_percent','curve','steps'}
    or {'ppq','rate','amount','base','samples','shape','attack','decay','time_shift'}
  for _,k in ipairs(extra) do allowed[k]=true end
  keys(o,allowed)
  if o.mpe~=true then fail('mpe=true must explicitly confirm a configured MPE receiver') end
  if o.mode~=nil and o.mode~='replace' then fail('only replace mode is supported') end
  local zone=o.member_channels
  if type(zone)~='table' or #zone<1 or #zone>15 then fail('explicit member_channels lower zone required') end
  local count=0
  for k,v in pairs(zone) do
    count=count+1
    if type(k)~='number' or k%1~=0 or k<1 or k>#zone or v~=k then
      fail('member_channels must be the dense lower-zone list {1,...,N} (zero-based)')
    end
  end
  if count~=#zone then fail('invalid member_channels') end
  local dim=default(o.dimension,'pitch')
  if dim~='pitch' and dim~='slide' and dim~='pressure' then fail('unsupported dimension') end
  if tool=='glissando_mpe' and dim~='pitch' then fail('Glissando supports pitch only') end
  local range=o.pitchbend_range
  if dim=='pitch' or range~=nil then number(range,1,96,'pitchbend_range semitones') end
  local p={dimension=dim,range=range,members=zone}
  if tool=='glissando_mpe' then
    p.start=number(default(o.start_percent,50),0,100,'start_percent')/100
    p.curve=number(default(o.curve,0),-100,100,'curve')
    p.samples=number(default(o.steps,32),2,1024,'steps',true)
  else
    p.ppq=number(o.ppq,1,1000000,'ppq')
    p.rate=number(default(o.rate,1/4),1/128,1,'rate whole notes')
    p.samples=number(default(o.samples,64),2,1024,'samples',true)
    p.shape=default(o.shape,'sine')
    if p.shape~='sine' and p.shape~='triangle' and p.shape~='square' then fail('unsupported LFO shape') end
    local max=dim=='pitch' and range*2 or 127
    p.amount=number(default(o.amount,1),-max,max,'amount')
    max=dim=='pitch' and range or 127
    p.base=number(default(o.base,0),-max,max,'base')
    p.attack=number(default(o.attack,0),0,100,'attack')/100
    p.decay=number(default(o.decay,0),0,100,'decay')/100
    if p.attack+p.decay>1 then fail('attack + decay must not exceed 100 percent') end
    p.shift=number(default(o.time_shift,0),-100,100,'time_shift')/100
  end
  return p
end
local function dimension_event(e,dim,ch)
  local s=e.msg:byte(1)
  if not s or s&15~=ch then return false end
  local kind=s&0xF0
  return dim=='pitch' and kind==0xE0 or dim=='pressure' and kind==0xD0
    or dim=='slide' and kind==0xB0 and e.msg:byte(2)==74
end
local function analyse(raw,p)
  local events=E.decode(raw) -- bounded decoder, rejects truncation/negative deltas
  if #events==0 then fail('missing terminal source marker') end
  local marker=events[#events]
  if marker.msg~='' and marker.msg~=string.char(0xB0,123,0) then
    fail('terminal source marker must be empty or native channel-0 CC123=0')
  end
  -- Setup changes on the master can redefine the entire member zone/range.
  for _,e in ipairs(events) do
    local s=e.msg:byte(1)
    if s and (s&0xF0)==0xB0 then
      local cc=e.msg:byte(2)
      if cc and (cc==6 or cc==38 or cc>=96 and cc<=101) then
        fail('RPN/NRPN receiver setup is unsupported on master or member channels')
      end
    end
  end
  local active,notes,selected={},{},{}
  local note_count=0
  for i,e in ipairs(events) do
    if e.msg=='' and i~=#events then fail('nonterminal empty event is unsupported') end
    local s=e.msg:byte(1)
    if s and s<0xF0 then
      if s<0x80 then fail('running status is unsupported') end
      local kind=s&0xF0
      local length=(kind==0xC0 or kind==0xD0) and 2 or 3
      if #e.msg~=length then fail('malformed channel event') end
      for j=2,length do if e.msg:byte(j)>127 then fail('invalid MIDI data byte') end end
      local ch=s&15
      if kind==0x90 and e.msg:byte(3)>0 then
        note_count=note_count+1
        if note_count>4096 then fail('note budget exceeded') end
        local key=ch*128+e.msg:byte(2)
        active[key]=active[key] or {}
        local n={on=e,ch=ch,pitch=e.msg:byte(2),selected=(e.flags&1)~=0}
        notes[#notes+1]=n
        active[key][#active[key]+1]=n
        if n.selected then selected[#selected+1]=n end
      elseif kind==0x80 or kind==0x90 then
        local key=ch*128+e.msg:byte(2)
        if not active[key] or #active[key]==0 then fail('unmatched note-off') end
        local n=table.remove(active[key],1); n.off=e
      end
    end
  end
  for _,a in ipairs(selected) do
    if not a.off or a.off.pos<=a.on.pos then fail('selected note must have positive duration and note-off') end
    if a.ch<1 or a.ch>#p.members then fail('selected note outside declared member zone (master channel refused)') end
    if a.off.pos>marker.pos then fail('note exceeds terminal source boundary') end
    for _,b in ipairs(notes) do
      if a~=b and a.ch==b.ch and a.on.pos<=(b.off and b.off.pos or math.huge)
          and b.on.pos<=a.off.pos then
        fail('unsafe channel sharing: overlapping, touching or unterminated note')
      end
    end
    for i,e in ipairs(events) do
      local s=e.msg:byte(1)
      -- CCBZ companions can be opaque system messages: never orphan one.
      if e.msg:find('CCBZ',1,true) then fail('CCBZ curve attachments are unsupported') end
      if s and s<0xF0 and ((s&15)==a.ch or (s&15)==0 and (s&0xF0)==0xB0) then
        local kind=s&0xF0
        local cc=e.msg:byte(2)
        if kind==0xA0 then fail('polyphonic key pressure is not MPE channel pressure') end
        if kind==0xB0 then
          if cc==64 or cc==66 or cc==69 then fail('pedal-held note attribution is unsupported') end
          if cc==6 or cc==38 or cc>=96 and cc<=101 then fail('RPN/NRPN receiver setup is unsupported') end
          if cc>=120 and i~=#events and e.pos>=a.on.pos and e.pos<a.off.pos then
            fail('channel mode message inside selected note')
          end
        end
        if dimension_event(e,p.dimension,a.ch) and e.pos>=a.on.pos and e.pos<a.off.pos
            and e.flags&0xF4~=0 then fail('shaped target expression events are unsupported') end
      end
    end
  end
  return events,selected,marker
end
local function value(v,p)
  if p.dimension=='pitch' then
    -- Asymmetric 14-bit endpoints: -range=0, neutral=8192, +range=16383.
    v=math.max(-p.range,math.min(p.range,v))
    return 8192+v/p.range*(v<0 and 8192 or 8191)
  end
  return math.max(0,math.min(127,v))
end
local function points_for(n,next_note,p,tool)
  local points={}
  for i=1,p.samples do
    local t=(i-1)/(p.samples-1)
    local v
    if tool=='glissando_mpe' then
      local u=p.start==1 and (t==1 and 1 or 0) or math.max(0,(t-p.start)/(1-p.start))
      -- Locally chosen power curve, NOT Ableton's unmeasured transfer function.
      local exponent=2^(math.abs(p.curve)/25)
      if p.curve<0 then u=u^exponent else u=1-(1-u)^exponent end
      v=(next_note.pitch-n.pitch)*u
    else
      local period=p.ppq*4*p.rate
      local elapsed=t*(n.off.pos-n.on.pos-1)/period-p.shift
      local wave=0
      if not (p.shift>0 and elapsed<0) then
        if p.shape=='sine' then wave=math.sin(2*math.pi*elapsed)
        elseif p.shape=='square' then wave=(elapsed%1)<0.5 and 1 or -1
        else wave=2/math.pi*math.asin(math.sin(2*math.pi*elapsed)) end
      end
      local envelope=1
      if p.attack>0 then envelope=math.min(envelope,t/p.attack) end
      if p.decay>0 then envelope=math.min(envelope,(1-t)/p.decay) end
      v=p.base+p.amount*wave*envelope
    end
    points[i]={t=t,value=value(v,p)}
  end
  return points
end
local function pack(events)
  local parts,last={},0
  for _,e in ipairs(events) do
    parts[#parts+1]=string.pack('i4Bs4',e.pos-last,e.flags,e.msg); last=e.pos
  end
  return table.concat(parts)
end
function M.transform(raw,tool,o)
  if not E then fail('configure({E=Expression}) must run first') end
  if tool~='glissando_mpe' and tool~='lfo_mpe' then fail('unsupported tool '..tostring(tool)) end
  local p=options(tool,o or {})
  local events,selected,marker=analyse(raw,p)
  if #selected==0 then return raw end
  if tool=='glissando_mpe' then
    if #selected<2 then fail('Glissando requires at least two successive selected notes') end
    for i=1,#selected-1 do
      if selected[i+1].on.pos<selected[i].off.pos then
        fail('Glissando requires successive nonoverlapping selected notes, not chords')
      end
      if math.abs(selected[i+1].pitch-selected[i].pitch)>p.range then
        fail('successive pitch interval exceeds declared pitchbend_range')
      end
    end
  end
  local edited_count=#selected-(tool=='glissando_mpe' and 1 or 0)
  if #events+edited_count*(p.samples+1)>100000 then fail('expression event budget exceeded') end
  local removed,generated={},{}
  for i=1,edited_count do
    local n=selected[i]
    -- Only synthetic note/empty marker scaffolding goes through the engine.
    -- Merge its generated dimension back into originals to retain ALL opaque
    -- bytes, flags, stable unrelated order and the actual native source marker.
    local scaffold=pack({{pos=n.on.pos,flags=1,msg=n.on.msg},
      {pos=n.off.pos,flags=0,msg=n.off.msg},{pos=marker.pos,flags=0,msg=''}})
    local output=E.transform(scaffold,p.dimension,{points=points_for(n,selected[i+1],p,tool),
      steps=p.samples,shape='linear',mode='replace',member_channels=p.members})
    local last_generated
    for _,e in ipairs(E.decode(output)) do
      if dimension_event(e,p.dimension,n.ch) then
        e.flags=n.on.flags&2 -- expression belonging to a muted note stays muted
        e.seq=#events+#generated+1; generated[#generated+1]=e
        last_generated=e.msg
      end
    end
    -- Restore the source channel state at release. This prevents the last
    -- generated value leaking into a later unselected note using this member.
    -- An existing release-tick event already performs the source transition.
    local baseline=p.dimension=='pitch' and string.char(0xE0|n.ch,0,64)
      or p.dimension=='slide' and string.char(0xB0|n.ch,74,0) or string.char(0xD0|n.ch,0)
    local at_release=false
    for _,e in ipairs(events) do
      if e.pos<=n.off.pos and dimension_event(e,p.dimension,n.ch) and e.flags&2==0 then
        baseline=e.msg
        if e.pos==n.off.pos then at_release=true end
      end
    end
    if not at_release and baseline~=last_generated then
      generated[#generated+1]={pos=n.off.pos,flags=n.on.flags&2,msg=baseline,
        seq=#events+#generated+1}
    end
    for id,e in ipairs(events) do
      if e.pos>=n.on.pos and e.pos<n.off.pos and dimension_event(e,p.dimension,n.ch) then removed[id]=true end
    end
  end
  local merged={}
  for id,e in ipairs(events) do if not removed[id] then e.seq=id; merged[#merged+1]=e end end
  for _,e in ipairs(generated) do merged[#merged+1]=e end
  table.sort(merged,function(a,b)
    if a.pos~=b.pos then return a.pos<b.pos end
    if a==marker then return false end
    if b==marker then return true end
    return a.seq<b.seq
  end)
  -- A pre-existing neutral bend at a release tick must follow that channel's
  -- note-off. Only move that reset; other original events retain relative order.
  local i=1
  while i<=#merged do
    local e=merged[i]
    if #e.msg==3 and e.msg:byte(1)&0xF0==0xE0 and e.msg:byte(2)==0 and e.msg:byte(3)==64 then
      local last=i
      for j=i+1,#merged do
        local b=merged[j]; if b.pos~=e.pos then break end
        local s=b.msg:byte(1)
        if s and (s&15)==(e.msg:byte(1)&15) and #b.msg==3
            and (s&0xF0==0x80 or s&0xF0==0x90 and b.msg:byte(3)==0) then last=j end
      end
      if last>i then table.remove(merged,i); table.insert(merged,last,e); i=i-1 end
    end
    i=i+1
  end
  local result=pack(merged)
  if #result>64*1024*1024 then fail('output byte budget exceeded') end
  return result
end
function M.describe()
  -- Fresh tables on every call. Defaults are ours; screenshots are NOT fixtures.
  return {version=1,provisional=true,reference='https://www.ableton.com/en/live-manual/12/midi-tools/',
    setup={mpe={required=true},member_channels={required=true,unit='zero-based channels',zone='lower {1,...,N}; master 0'},
      pitchbend_range={required_for='pitch',min=1,max=96,unit='semitones; receiver assumption, no RPN sent'}},
    tools={
      glissando_mpe={dimension='pitch',minimum_selected=2,
        start_percent={default=50,min=0,max=100,unit='percent of note length',reference='manual + screenshot 50%'},
        curve={default=0,min=-100,max=100,unit='percent',reference='screenshot 0%; transfer provisional'},
        steps={default=32,min=2,max=1024,unit='samples per edited note',reference='implementation budget'}},
      lfo_mpe={dimension={default='pitch',values={'pitch','slide','pressure'},reference='manual'},
        ppq={required=true,min=1,max=1000000,unit='ticks per quarter note'},
        rate={default=1/4,min=1/128,max=1,unit='whole notes',reference='manual; screenshot 1/4'},
        amount={default=1,range_pitch='-2*range .. 2*range semitones',min_other=-127,max_other=127,reference='manual; transfer provisional'},
        base={default=0,range_pitch='-range .. range semitones',min_other=-127,max_other=127,reference='manual'},
        shape={default='sine',values={'sine','triangle','square'},unsupported={'random','shape morph'},reference='manual: four types; restricted subset'},
        attack={default=0,min=0,max=100,unit='percent of note',reference='manual relative envelope; mapping provisional'},
        decay={default=0,min=0,max=100,unit='percent of note; attack+decay <=100'},
        time_shift={default=0,min=-100,max=100,unit='percent of oscillator period',reference='manual delay/phase; mapping provisional'},
        samples={default=64,min=2,max=1024,unit='samples per note',reference='implementation budget'}}}}
end
return M
