-- Real-host fixture. Controller/UI capture is test-only; production has no hooks.
local root=assert(REASKII_ROOT)
reaper.InsertTrackAtIndex(0,true)
local track=reaper.GetTrack(0,0)
local item=reaper.CreateNewMIDIItemInProj(track,0,8,false)
local take=reaper.GetActiveTake(item)
reaper.GetSetMediaItemTakeInfo_String(take,'P_NAME','ReaSkii expansion fixture',true)
for i,pitch in ipairs({60,64,67}) do reaper.MIDI_InsertNote(take,true,false,960+(i-1)*720,1200+(i-1)*720,0,pitch,80+i*10,false) end
reaper.MIDI_Sort(take)
local _,baseline=reaper.MIDI_GetAllEvts(take,'')
reaper.Undo_OnStateChange2(0,'ReaSkii expansion fixture baseline')
reaper.SetMediaItemSelected(item,true); reaper.Main_OnCommand(40153,0)
local c,u,controls
local original=dofile
function dofile(path)
 local m=original(path)
 if path:match('PanelController.lua$') then
  local new=m.new; m.new=function(...) c=new(...); return c end
 elseif path:match('PanelUI.lua$') then
  local new=m.new; m.new=function(...)
   u=new(...); local button,number,draw=u.button,u.number,u.draw
   function u:button(x,y,w,label,...) controls['b:'..label]={x+w/2,y+9}; return button(self,x,y,w,label,...) end
   function u:number(key,x,y,w,...) controls['n:'..key]={x+w/2,y+9}; return number(self,key,x,y,w,...) end
   function u:draw(key) controls={}; return draw(self,key) end
   return u
  end
 end
 return m
end
local function launch()
 reaper.SetMIDIEditorGrid(0,.25)
 dofile(root..'/scripts/midi/ReaSkii_MIDI_Panel.lua')
 dofile=original
 local token,err='',nil
 local function raw() local _,r=reaper.MIDI_GetAllEvts(take,''); return r end
 local function reset(empty)
  if c.session then c:cancel() end
  if empty then
   local C=original(root..'/scripts/midi/ReaSkii_MIDI_Core.lua'); local events=C.decode(baseline); local e=events[#events]; reaper.MIDI_SetAllEvts(take,string.pack('i4Bs4',e.pos,e.flags,e.msg))
  else reaper.MIDI_SetAllEvts(take,baseline) end
  reaper.Undo_OnStateChange2(0,'ReaSkii expansion fixture reset')
  c.auto=false; c.replace=false; u.scroll=0
  u.sections.Clip=false; u.sections.Launch=false; u.sections['Pitch & Time']=false; u.sections.Transform=true; u.sections.Generate=false
 end
 local function configure(tool,generator,empty)
  reset(empty); c:choose(tool,generator); c:reset(tool)
  if generator then u.sections.Transform=false; u.sections.Generate=true end
  if tool=='connect' then c.values.density=100; c.values.grid=4 end
  if tool=='recombine' then c.values.mirror=1 end
  if tool=='strum' then c.values.high=50 end
 end
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
  local f=io.open(REASKII_STATE..'.cmd','r')
  if f then
   local code=f:read('*a'); f:close(); os.remove(REASKII_STATE..'.cmd')
   local fn,loaderr=load(code,'fixture command','t',setmetatable({c=c,u=u,take=take,item=item,configure=configure,reset=reset,raw=raw,baseline=baseline}, {__index=_G}))
   local ok,result=false,loaderr
   if fn then ok,result=pcall(fn) end
   token=token..'x'; err=not ok and tostring(result) or nil
  end
  local notes={}; local _,n=reaper.MIDI_CountEvts(take)
  for i=0,n-1 do local _,sel,_,s,e,ch,p,v=reaper.MIDI_GetNote(take,i); notes[#notes+1]={s,e,p,v,sel,ch} end
  local info=c:info()
  local state={token=token,error=err or '',notes=notes,status=c.status,session=c.session~=nil,blocked=c.blocked==true,controls=controls or {},auto=c.auto,tool=c.tool,generator=c.generator,info=info}
  state.info.item=nil
  local out=assert(io.open(REASKII_STATE..'.tmp','w')); out:write(json(state)); out:close(); os.rename(REASKII_STATE..'.tmp',REASKII_STATE)
  reaper.defer(observe)
 end
 observe()
end
reaper.defer(launch)
