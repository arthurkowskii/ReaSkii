-- Pure independent panel algorithms. Manual semantics, NOT measured Live parity.
-- Run through Adapter's structural guard/render path, never raw host writes.
local O={}
O.tools={add_interval=true,set_length=true,humanize=true,connect=true,ornament=true,recombine=true,span=true,velocity_shaper=true,quantize=true}
local function copy(n) local r={}; for k,v in pairs(n) do r[k]=v end; return r end
local function round(x) return math.floor(x+.5) end
local function rng(seed)
 local state=seed or 1
 return function() state=(state*1664525+1013904223)%4294967296; return state/4294967296 end
end
function O.apply(notes,tool,p)
 local selected,out={},{}
 for _,n in ipairs(notes) do
  local v=copy(n); out[#out+1]=v; if v.selected then selected[#selected+1]=v end
 end
 table.sort(selected,function(a,b) return a.startppq<b.startppq or (a.startppq==b.startppq and a.pitch<b.pitch) end)
 local random=rng(p.seed)
 local function extra(n,s,e,pitch,velocity)
  local r=copy(n); r.startppq=s; r.endppq=e; r.pitch=pitch or n.pitch; r.vel=velocity or n.vel
  out[#out+1]=r; assert(#out<=16384,'Too many generated notes'); return r
 end
 if tool=='add_interval' then
  assert(p.amount~=0,'Choose a nonzero interval')
  for _,n in ipairs(selected) do extra(n,n.startppq,n.endppq,n.pitch+p.amount) end
 elseif tool=='set_length' then
  for _,n in ipairs(selected) do n.endppq=n.startppq+p.length end
 elseif tool=='quantize' then
  assert(type(p.grid_ppq)=='number' and p.grid_ppq==p.grid_ppq and p.grid_ppq>0 and p.grid_ppq<math.huge,'Invalid quantize grid')
  assert(type(p.strength)=='number' and p.strength>=0 and p.strength<=1,'Invalid quantize amount')
  assert(type(p.adjust_start)=='boolean' and type(p.adjust_end)=='boolean','Invalid quantize note edge flags')
  local function snap(value)
   local q=value/p.grid_ppq; local lower=math.floor(q)
   if q-lower>.5 then lower=lower+1 end -- provisional tie-down policy
   return value+(lower*p.grid_ppq-value)*p.strength
  end
  for _,n in ipairs(selected) do
   local start,finish=n.startppq,n.endppq
   if p.adjust_start then
    n.startppq=snap(start)
    if not p.adjust_end then n.endppq=finish+n.startppq-start end
   end
   if p.adjust_end then n.endppq=snap(finish) end
  end
 elseif tool=='humanize' then
  for _,n in ipairs(selected) do
   local delta=round((random()*2-1)*p.grid_ppq*p.amount/100)
   n.startppq=n.startppq+delta; n.endppq=n.endppq+delta
  end
 elseif tool=='connect' then
  for i=1,#selected-1 do
   local n,nextn=selected[i],selected[i+1]
   assert(nextn.startppq>=n.endppq,'Connect currently requires nonoverlapping sequential notes')
   local gap=nextn.startppq-n.endppq
   local slots=math.floor(gap/p.rate_ppq)
   assert(slots<=4096,'Connect rate produces too many slots')
   for j=0,slots-1 do
    if random()*100<p.density then
     local s=n.endppq+j*p.rate_ppq
     local pitch=n.pitch+math.floor(random()*(2*p.spread+1))-p.spread
     local e=math.min(nextn.startppq,s+p.rate_ppq)
     if random()*100<p.tie then e=nextn.startppq end
     extra(n,s,e,pitch)
     -- A tied note consumes the remaining gap; no ambiguous overlapping copies.
     if e==nextn.startppq then break end
    end
   end
  end
 elseif tool=='ornament' then
  local length=round(math.abs(p.position)/100*p.grid_ppq)
  assert(length>=1,'Ornament Position must produce at least one tick')
  for _,n in ipairs(selected) do
   local start=n.startppq
   local count=p.kind=='flam' and 1 or p.count
   local s=p.position<0 and start-length or start
   if p.position>0 then n.startppq=start+length end
   for j=1,count do
    local pitch=n.pitch
    if p.kind=='grace' and j%2==1 then pitch=pitch+p.pitch_delta end
    extra(n,round(s+(j-1)*length/count),round(s+j*length/count),pitch,math.max(1,round(n.vel*p.velocity/100)))
   end
  end
 elseif tool=='recombine' then
  local values={}
  for i,n in ipairs(selected) do
   values[i]=p.dimension=='position' and n.startppq or p.dimension=='duration' and (n.endppq-n.startppq) or p.dimension=='pitch' and n.pitch or n.vel
  end
  if p.shuffle then for i=#values,2,-1 do local j=math.floor(random()*i)+1; values[i],values[j]=values[j],values[i] end end
  if p.mirror then for i=1,math.floor(#values/2) do local j=#values-i+1; values[i],values[j]=values[j],values[i] end end
  for i,n in ipairs(selected) do
   local value=values[(i-1-p.rotate)%#values+1]
   if p.dimension=='position' then local duration=n.endppq-n.startppq; n.startppq=value; n.endppq=value+duration
   elseif p.dimension=='duration' then n.endppq=n.startppq+value
   elseif p.dimension=='pitch' then n.pitch=value else n.vel=value end
  end
 elseif tool=='span' then
  local shortest
  for i=2,#selected do local d=selected[i].startppq-selected[i-1].startppq; if d>0 then shortest=math.min(shortest or d,d) end end
  if p.articulation=='staccato' then assert(shortest,'Staccato needs distinct note starts') end
  for i,n in ipairs(selected) do
   local e=n.endppq
   if p.articulation=='legato' then
    e=p.range_end
    for j=i+1,#selected do if selected[j].startppq>n.startppq then e=selected[j].startppq; break end end
   elseif p.articulation=='staccato' then e=n.startppq+shortest/2 end
   n.endppq=e+p.grid_ppq*(p.offset-random()*p.variation)/100
  end
 elseif tool=='velocity_shaper' then
  local span=p.range_end-p.range_start; assert(span>0,'Empty envelope range')
  for _,n in ipairs(selected) do
   local t=((n.startppq-p.range_start)/span*p.loops-p.rotate*p.grid_ppq/span)%1
   local v=t<=.5 and (p.first+(p.middle-p.first)*t*2) or (p.middle+(p.last-p.middle)*(t-.5)*2)
   n.vel=round(p.minimum+(p.maximum-p.minimum)*v/100)
  end
 else error('Unknown panel operation: '..tostring(tool)) end
 -- Refuse ALL ambiguous result collisions, including selected-selected.
 O.validate(out)
 return out
end
function O.validate(out)
 for i,n in ipairs(out) do
  n.startppq=round(n.startppq); n.endppq=round(n.endppq)
  assert(n.startppq>=0 and n.endppq>n.startppq,'Result has negative start or empty duration')
  assert(n.pitch>=0 and n.pitch<=127 and n.pitch%1==0,'Pitch outside MIDI range')
  assert(n.vel>=1 and n.vel<=127,'Velocity outside MIDI range')
  for j=1,i-1 do local b=out[j]
   assert(not ((n.selected or b.selected) and n.pitch==b.pitch and n.channel==b.channel and n.startppq<b.endppq and b.startppq<n.endppq),'Result contains overlapping same-pitch/channel notes')
  end
 end
 return out
end
function O.generators(G)
 return {generate=function(tool,p)
  local notes=G.generate(tool,p)
  assert(#notes>0,'Generator produced no notes; refusing an empty replacement.')
  return O.validate(notes)
 end}
end
function O.wrap(T)
 return {apply=function(notes,tool,p)
  if p.panel_tool then return O.apply(notes,p.panel_tool,p) end
  return T.apply(notes,tool,p)
 end}
end
function O.transform(raw,tool,p,A)
 if O.tools[tool] then
  local options=copy(p); options.panel_tool=tool
  return A.transform(raw,'chop',options) -- strict structural + expression refusals
 end
 return A.transform(raw,tool,p)
end
return O
