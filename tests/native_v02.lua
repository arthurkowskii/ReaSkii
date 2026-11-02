-- ReaSkii 0.2 native acceptance; only isolated portable REAPER.
local root=reaper.GetExePath();assert(root:find('reaskii%-native'))
local cfg=dofile(root..'/native-config.lua')
local out=assert(io.open(root..'/native-results.tsv','w'))
local passed,failed=0,0
local function log(...) local t={...};for i,v in ipairs(t) do t[i]=tostring(v) end;out:write(table.concat(t,'\t')..'\n');out:flush() end
local function check(ok,label,details) if ok then passed=passed+1 else failed=failed+1 end;log(ok and 'PASS' or 'FAIL',label,details or '') end
local function refresh() reaper.ThemeLayout_RefreshAll();reaper.TrackList_AdjustWindows(false);reaper.UpdateArrange() end
assert(reaper.OpenColorThemeFile(root..'/ColorThemes/ReaSkii.ReaperThemeZip'))
local D=dofile(root..'/Scripts/Cockos/ReaSkii_Defaults.lua')
local params,ordered=D.parameters()
local function set(name,value) assert(params[name],name);assert(reaper.ThemeLayout_SetParameter(params[name].id,value,false)) end
for _,p in ipairs(ordered) do check(p.value==p.default,'factory '..p.name,tostring(p.value)..' / '..p.default) end
for name,expected in pairs({tcp_name_full_row=1,smart_folder_indent=1,tcp_name_keep_vol=0,tcp_name_keep_pan=0,
 tcp_name_keep_info=0,tcp_name_keep_io=0,reark_tcp_fx_sidebar=1,reark_tcp_fx_size=3,reark_tcp_fx_columns=2,reark_tcp_fx_height=2,param12=0,param14=0}) do
 check(params[name].value==expected,'explicit requested default '..name,tostring(params[name].value)..' / '..expected)
end
set('param12',1);set('tcp_side_fx',0);set('reark_tcp_fx_size',1)
local backup=D.apply();check(io.open(backup,'r')~=nil,'migration creates restore script',backup)
params,ordered=D.parameters()
for _,p in ipairs(ordered) do check(p.value==p.default,'migrated '..p.name,tostring(p.value)..' / '..p.default) end
set('tcp_name_keep_pan',1);D.ensure()
check(select(3,reaper.ThemeLayout_GetParameter(params.tcp_name_keep_pan.id))==1,'migration once preserves later customization')
dofile(backup)
check(select(3,reaper.ThemeLayout_GetParameter(params.param12.id))==1,'restore script restores seeded pan mask')
D.apply();params,ordered=D.parameters()
local tracks={}
for i=0,6 do
 reaper.InsertTrackAtIndex(i,true);local tr=reaper.GetTrack(0,i);tracks[#tracks+1]=tr
 reaper.GetSetMediaTrackInfo_String(tr,'P_NAME','Depth '..i..' - ReaSkii native acceptance',true)
 reaper.SetMediaTrackInfo_Value(tr,'I_FOLDERDEPTH',i<6 and 1 or -6)
 reaper.SetMediaTrackInfo_Value(tr,'I_HEIGHTOVERRIDE',70)
end
local target=tracks[1]
for i=1,3 do local fx=reaper.TrackFX_AddByName(target,'JS: utility/volume',false,-1);check(fx>=0,'real JS insert '..i,fx) end
local inserts_action=40302
check(reaper.kbd_getTextFromCmd(inserts_action,0):lower():find('show fx inserts in tcp',1,true)~=nil,'verified native TCP inserts action')
if reaper.GetToggleCommandState(inserts_action)==0 then reaper.Main_OnCommand(inserts_action,0) end
local function rect(tr,name)
 local ok,s=reaper.GetSetMediaTrackInfo_String(tr,'P_UI_RECT:'..name,'',false)
 if not ok and (name=='tcp.fxparm' or name=='tcp.fxlist' or name=='tcp.sendlist') then return {x=0,y=0,w=0,h=0,raw='unavailable'} end
 assert(ok,name)
 local t={};for n in s:gmatch('[-%d.]+') do t[#t+1]=tonumber(n) end;assert(#t==4,s)
 return {x=t[1],y=t[2],w=t[3],h=t[4],raw=s}
end
local function visible(r) return r.w>0 and r.h>0 end
local names={'tcp.recarm','tcp.recmon','tcp.label','tcp.volume','tcp.pan','tcp.width','tcp.io','tcp.fx','tcp.env','tcp.recmode','tcp.fxin','tcp.recinput','tcp.infoblock'}
local cases={}
for _,layout in ipairs({'A','B','C','150%_A','150%_B','150%_C','200%_A','200%_B','200%_C'}) do
 local scale=layout:find('150%%') and 1.5 or layout:find('200%%') and 2 or 1
 for mask=0,15 do
  if cfg.width>=900 or mask==0 or mask==1 or mask==2 or mask==4 or mask==8 then
   cases[#cases+1]={layout=layout,scale=scale,height=100*scale,mask=mask,arm=0,pan=0,side=1}
  end
 end
 for _,height in ipairs({50,58,61,65}) do
  cases[#cases+1]={layout=layout,scale=scale,height=height*scale,mask=0,arm=0,pan=0,side=1,required=scale==1 and cfg.width>=540}
 end
 for _,pan in ipairs({5,6}) do cases[#cases+1]={layout=layout,scale=scale,height=130*scale,mask=3,arm=1,pan=pan,side=1} end
 cases[#cases+1]={layout=layout,scale=scale,height=100*scale,mask=0,arm=0,pan=0,side=0}
end
local index,stage=1,0
local function configure(c)
 for _,p in ipairs(ordered) do reaper.ThemeLayout_SetParameter(p.id,p.default,false) end
 set('reark_tcp_fx_sidebar',c.side)
 set('tcp_infoblock',c.required and 0 or 1)
 for i,n in ipairs({'vol','pan','info','io'}) do set('tcp_name_keep_'..n,(c.mask & (1 << (i-1)))~=0 and 1 or 0) end
 -- Geometry tests request visible controls; factory masks were checked separately above.
 for _,idx in ipairs({5,6,7,8,9,10,11,12,13,14,33,34,35,36,37,38,39,40,41,42,56,57,58,59,60,61,62,63,64,65}) do set('param'..idx,0) end
 reaper.GetSetMediaTrackInfo_String(target,'P_TCP_LAYOUT',c.layout,true)
 reaper.SetMediaTrackInfo_Value(target,'I_HEIGHTOVERRIDE',c.height)
 reaper.SetMediaTrackInfo_Value(target,'I_RECARM',c.arm)
 reaper.SetMediaTrackInfo_Value(target,'I_PANMODE',c.pan)
 refresh()
end
local function inspect(c)
 local tag=c.layout..' h='..c.height..' keep='..c.mask..' pan='..c.pan..' sidebar='..c.side
 local panel=rect(target,'tcp.size');log('CASE',tag,panel.raw)
 local label=rect(target,'tcp.label');check(visible(label),tag..' name visible',label.raw)
 local rs={}
 for _,name in ipairs(names) do
  local r=rect(target,name)
  if visible(r) then
   check(r.x>=panel.x-1 and r.y>=panel.y-1 and r.x+r.w<=panel.x+panel.w+1 and r.y+r.h<=panel.y+panel.h+1,tag..' contained '..name,r.raw)
   for _,other in ipairs(rs) do
    local a=other.r;local iw=math.min(r.x+r.w,a.x+a.w)-math.max(r.x,a.x);local ih=math.min(r.y+r.h,a.y+a.h)-math.max(r.y,a.y)
    check(iw<=2*c.scale or ih<=1,tag..' no overlap '..name..' / '..other.name,r.raw..' | '..a.raw)
   end
   rs[#rs+1]={r=r,name=name}
  end
 end
 if c.required then
  for _,name in ipairs({'tcp.volume','tcp.pan','tcp.io','tcp.fx','tcp.env'}) do local r=rect(target,name);check(visible(r),tag..' required two-row '..name,r.raw) end
 end
 if c.side==1 then
  local r=rect(target,'tcp.fxparm')
  if c.scale==1 and cfg.width>=540 then check(visible(r),tag..' reARK sidebar must be visible with room',r.raw) end
  if visible(r) then
   check(r.y>=panel.y-1 and r.y+r.h<=panel.y+panel.h+1,tag..' reARK sidebar vertically bounded',r.raw)
   for _,other in ipairs(rs) do
    local a=other.r;local iw=math.min(r.x+r.w,a.x+a.w)-math.max(r.x,a.x);local ih=math.min(r.y+r.h,a.y+a.h)-math.max(r.y,a.y)
    check(iw<=1 or ih<=1,tag..' reARK sidebar does not cover '..other.name,r.raw..' | '..a.raw)
   end
   check(math.abs(r.w-(130-7)*c.scale)<=1,tag..' reARK sidebar expected 130px minus 7px right margin',r.raw)
   check(r.x+r.w<=panel.x+panel.w+1,tag..' reARK sidebar bounded',r.raw)
   check(r.x>=label.x+label.w-1,tag..' reARK sidebar right of name',r.raw..' | '..label.raw)
   check(not visible(rect(target,'tcp.fxlist')),tag..' reARK combined list, no separate FX list')
  end
 end
end
local mcp_index=1
local tick
local function step()
 local c=cases[index]
 if not c then
  local layouts={'A','B','C','150%_A','150%_B','150%_C','200%_A','200%_B','200%_C'}
  if layouts[mcp_index] then
   if stage==0 then
    for _,tr in ipairs(tracks) do reaper.GetSetMediaTrackInfo_String(tr,'P_MCP_LAYOUT',layouts[mcp_index],true) end
    if reaper.GetToggleCommandState(40078)==0 then reaper.Main_OnCommand(40078,0) end
    refresh();stage=1;reaper.defer(tick);return
   end
   for depth,tr in ipairs(tracks) do
    local layout=layouts[mcp_index]
    local r=rect(tr,'mcp.label');check(visible(r),'MCP '..layout..' depth '..depth..' label visible',r.raw)
    local value=rect(tr,'mcp.volume.label');check(visible(value),'MCP '..layout..' depth '..depth..' volume readout visible',value.raw)
    if layout=='A' or layout=='B' or layout=='C' then
     local fader=rect(tr,'mcp.volume');check(visible(fader),'MCP '..layout..' depth '..depth..' volume control visible',fader.raw)
    end
   end
   mcp_index=mcp_index+1;stage=0;reaper.defer(tick);return
  end
  log('DONE',passed,failed,#cases);out:close();return
 end
 if stage==0 then configure(c);stage=1;reaper.defer(tick);return end
 inspect(c);index=index+1;stage=0;reaper.defer(tick)
end
tick=function() local ok,err=xpcall(step,debug.traceback);if not ok then log('ERROR',err);out:close() end end
reaper.defer(tick)
