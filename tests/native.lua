-- Native WALTER acceptance tests. Only for the dedicated portable QA instance.
local root=reaper.GetExePath()
assert(root:find('reaskii%-native'), 'Refusing a non-QA instance')
local cfg=dofile(root..'/native-config.lua')
local out=assert(io.open(root..'/native-results.tsv','w'))
local passed,failed=0,0
local function log(...) local t={...};for i,v in ipairs(t) do t[i]=tostring(v) end;out:write(table.concat(t,'\t')..'\n');out:flush() end
local function check(ok,label,details)
 if ok then passed=passed+1 else failed=failed+1 end
 log(ok and 'PASS' or 'FAIL',label,details or '')
end
assert(reaper.OpenColorThemeFile(root..'/ColorThemes/ReaSkii.ReaperThemeZip'))
local params={}
for i=0,1000 do
 local n,d,v,def,lo,hi=reaper.ThemeLayout_GetParameter(i)
 if not n or n=='' then break end
 params[n]={id=i,value=v,default=def}
end
local function set(name,value)
 assert(params[name], 'Missing parameter '..name)
 assert(reaper.ThemeLayout_SetParameter(params[name].id,value,false))
end
check(params.tcp_name_full_row.value==1,'full-row default ON')
check(params.smart_folder_indent.value==1,'smart-indent default ON')
for _,n in ipairs({'vol','pan','info','io'}) do check(params['tcp_name_keep_'..n].value==0,'keep '..n..' default OFF') end
local tracks={}
for i=0,6 do
 reaper.InsertTrackAtIndex(i,true)
 local tr=reaper.GetTrack(0,i);tracks[#tracks+1]=tr
 reaper.GetSetMediaTrackInfo_String(tr,'P_NAME','Depth '..i..' - ReaSkii long track name for testing',true)
 reaper.SetMediaTrackInfo_Value(tr,'I_FOLDERDEPTH',i<6 and 1 or -6)
 reaper.SetMediaTrackInfo_Value(tr,'I_HEIGHTOVERRIDE',65)
end
local target=tracks[1]
local function rect(tr,name)
 local ok,s=reaper.GetSetMediaTrackInfo_String(tr,'P_UI_RECT:'..name,'',false)
 assert(ok,'No native geometry for '..name)
 local t={};for n in s:gmatch('[-%d.]+') do t[#t+1]=tonumber(n) end
 assert(#t==4,'Unexpected geometry '..s)
 return {x=t[1],y=t[2],w=t[3],h=t[4],raw=s}
end
local function visible(r) return r.w>0 and r.h>0 end
local function sync() reaper.ThemeLayout_RefreshAll();reaper.TrackList_AdjustWindows(false);reaper.UpdateArrange() end
local names={'tcp.recarm','tcp.recmon','tcp.label','tcp.volume','tcp.pan','tcp.width','tcp.io','tcp.fx','tcp.fxbyp','tcp.env','tcp.recmode','tcp.fxin','tcp.recinput','tcp.infoblock'}
local function no_overlap(tag)
 local rs={}
 for _,n in ipairs(names) do
  local r=rect(target,n)
  if visible(r) then
   for _,other in ipairs(rs) do
    local a=other.r
    local iw=math.min(r.x+r.w,a.x+a.w)-math.max(r.x,a.x)
    local ih=math.min(r.y+r.h,a.y+a.h)-math.max(r.y,a.y)
    check(iw<=1 or ih<=1,tag..' no overlap '..n..' / '..other.n,r.raw..' | '..a.raw)
   end
   rs[#rs+1]={n=n,r=r}
  end
 end
end
local cases={}
local layouts={'','A','B','C','150%_A','150%_B','150%_C','200%_A','200%_B','200%_C'}
for _,layout in ipairs(layouts) do
 local scale=layout:find('150%%') and 1.5 or layout:find('200%%') and 2 or 1
 for mask=0,15 do
  -- The 960px run exercises every combination at every scale; narrower panels check the individual keep controls.
  if cfg.width>=900 or mask==0 or mask==1 or mask==2 or mask==4 or mask==8 then
   cases[#cases+1]={layout=layout,scale=scale,mask=mask,height=100*scale,arm=0,pan=0}
  end
 end
 for _,height in ipairs({25*scale,50*scale,150*scale}) do
  cases[#cases+1]={layout=layout,scale=scale,mask=0,height=height,arm=1,pan=5}
 end
 cases[#cases+1]={layout=layout,scale=scale,mask=0,height=100*scale,arm=0,pan=6}
 cases[#cases+1]={layout=layout,scale=scale,mask=0,height=100*scale,arm=0,pan=0,full=0}
end
local index,stage=1,0
local function configure(c)
 reaper.GetSetMediaTrackInfo_String(target,'P_TCP_LAYOUT',c.layout,true)
 reaper.SetMediaTrackInfo_Value(target,'I_HEIGHTOVERRIDE',c.height)
 reaper.SetMediaTrackInfo_Value(target,'I_RECARM',c.arm)
 reaper.SetMediaTrackInfo_Value(target,'I_PANMODE',c.pan)
 set('tcp_name_full_row',c.full==0 and 0 or 1);set('tcp_infoblock',c.full==0 and 0 or 1)
 for i,n in ipairs({'vol','pan','info','io'}) do set('tcp_name_keep_'..n,(c.mask & (1 << (i-1)))~=0 and 1 or 0) end
 -- Show the controls independent of inherited stock-layout hide conditions.
 for _,n in ipairs({'param5','param6','param7','param8','param9','param12','param33','param34','param35','param36','param37','param40','param56','param57','param58','param59','param60','param63'}) do set(n,0) end
 sync()
end
local function inspect(c)
 local label=rect(target,'tcp.label');local panel=rect(target,'tcp.size')
 local tag=('w%d %s mask%d h%.1f pan%d full%d'):format(cfg.width,c.layout,c.mask,c.height,c.pan,c.full==0 and 0 or 1)
 log('CASE',tag,panel.raw,label.raw)
 -- The original theme already hides this label at 640px/200%_C. Preserve it only when the new feature is OFF.
 local legacy_hidden=c.full==0 and ((cfg.width==640 and c.layout=='200%_C') or
  (cfg.width==320 and (c.layout=='150%_A' or c.layout=='200%_B')))
 check(visible(label)~=legacy_hidden,tag..' expected name visibility',label.raw)
 check(label.x>=panel.x-1 and label.x+label.w<=panel.x+panel.w+1,tag..' name inside TCP',label.raw)
 if c.full==0 then no_overlap(tag..' full-row OFF');return end
 local fields={'tcp.volume','tcp.pan','tcp.infoblock','tcp.io'}
 for i,n in ipairs(fields) do
  local r=rect(target,n);local keep=c.mask & (1 << (i-1))~=0
  if keep and cfg.width>=600 and label.h<=24*c.scale then
   check(visible(r),tag..' kept '..n..' visible',r.raw)
   if visible(r) then check(math.abs(r.y-label.y)<=1,tag..' kept '..n..' first row',r.raw..' | '..label.raw) end
  elseif keep and label.h>24*c.scale then
   log('FALLBACK',tag,'Original vertical-name layout: insufficient space for the configured meters')
  elseif not keep and visible(r) then
   check(r.y>=label.y+label.h-1,tag..' late '..n..' below name',r.raw..' | '..label.raw)
  end
 end
 no_overlap(tag)
end
local function finish_indent()
 set('tcp_name_full_row',1)
 set('tcp_infoblock',0)
 reaper.GetSetMediaTrackInfo_String(target,'P_TCP_LAYOUT','A',true)
 reaper.SetMediaTrackInfo_Value(target,'I_HEIGHTOVERRIDE',65)
 reaper.SetMediaTrackInfo_Value(target,'I_RECARM',0)
 reaper.SetMediaTrackInfo_Value(target,'I_PANMODE',0)
 for _,n in ipairs({'vol','pan','info','io'}) do set('tcp_name_keep_'..n,0) end
 set('param2',5);set('param79',1)
 for _,tr in ipairs(tracks) do reaper.GetSetMediaTrackInfo_String(tr,'P_TCP_LAYOUT','A',true) end
 local units={0,1,1.75,2.31,2.81,3.31,3.81}
 local smart=0
 local function finish_all()
  for cmd=40000,43000 do
   local desc=reaper.kbd_getTextFromCmd(cmd,0)
   if desc and desc:lower():find('theme adjuster',1,true) then log('ADJUSTER_ACTION',cmd,desc) end
  end
  log('DONE',passed,failed,#cases)
  out:close()
 end
 local mixer_layouts={'A','B','C','150%_A','150%_B','150%_C','200%_A','200%_B','200%_C'}
 local mixer_index=1
 local function mixer_scale()
  local l=mixer_layouts[mixer_index]
  return l:find('150%%') and 1.5 or l:find('200%%') and 2 or 1
 end
 local function inspect_mixer()
  local first=rect(tracks[1],'mcp.label')
  check(visible(first),'mixer reference visible',first.raw)
  for i,tr in ipairs(tracks) do
   local r=rect(tr,'mcp.label')
   local actual=first.y-r.y
   local expected=mixer_scale()*math.floor(10*(smart==1 and units[i] or i-1)+0.5)
   check(visible(r),'mixer label visible depth'..(i-1),r.raw)
   check(math.abs(actual-expected)<=1,'mixer smart'..smart..' depth'..(i-1),actual..' expected '..expected)
  end
  if smart==0 then smart=1;set('smart_folder_indent',1);sync();reaper.defer(inspect_mixer)
  elseif mixer_index<#mixer_layouts then
   mixer_index=mixer_index+1;smart=0;set('smart_folder_indent',0)
   for _,tr in ipairs(tracks) do reaper.GetSetMediaTrackInfo_String(tr,'P_MCP_LAYOUT',mixer_layouts[mixer_index],true) end
   sync();reaper.defer(inspect_mixer)
  else finish_all() end
 end
 local function start_mixer()
  smart=0;set('smart_folder_indent',0);set('param1',3);set('param78',1)
  for _,tr in ipairs(tracks) do reaper.GetSetMediaTrackInfo_String(tr,'P_MCP_LAYOUT','A',true) end
  assert(reaper.kbd_getTextFromCmd(40078,0):lower():find('mixer'))
  if reaper.GetToggleCommandState(40078)==0 then reaper.Main_OnCommand(40078,0) end
  sync();reaper.defer(inspect_mixer)
 end
 local function inspect_indent()
  local first=rect(tracks[1],'tcp.recarm')
  check(visible(first),'indent reference control visible',first.raw)
  for i,tr in ipairs(tracks) do
   local actual=rect(tr,'tcp.recarm').x-first.x
   log('INDENT_STATE',smart,i-1,reaper.GetTrackDepth(tr),reaper.GetMediaTrackInfo_Value(tr,'I_FOLDERDEPTH'),rect(tr,'tcp.recarm').raw)
   local expected=math.floor(18*(smart==1 and units[i] or i-1)+0.5)
   check(math.abs(actual-expected)<=1,'indent smart'..smart..' depth'..(i-1),actual..' expected '..expected)
  end
  if smart==0 then
   smart=1;set('smart_folder_indent',1);sync();reaper.defer(inspect_indent)
  else start_mixer() end
 end
 set('smart_folder_indent',0);sync();reaper.defer(inspect_indent)
end
local function step()
 local ok,err=xpcall(function()
  local c=cases[index]
  if not c then finish_indent();return end
  if stage==0 then configure(c);stage=1;reaper.defer(step)
  else inspect(c);index=index+1;stage=0;reaper.defer(step) end
 end,debug.traceback)
 if not ok then log('ERROR',err);out:close() end
end
reaper.defer(step)
