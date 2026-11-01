local r=reaper.GetExePath();assert(r:find('reaskii%-native'))
assert(reaper.OpenColorThemeFile(r..'/ColorThemes/Baseline.ReaperThemeZip'))
local params={}
for i=0,1000 do local n=reaper.ThemeLayout_GetParameter(i);if not n or n=='' then break end;params[n]=i end
for _,n in ipairs({'param5','param6','param7','param8','param9','param12','param56','param57','param58','param59','param60','param63'}) do reaper.ThemeLayout_SetParameter(params[n],0,false) end
for i=0,6 do
 reaper.InsertTrackAtIndex(i,true);local tr=reaper.GetTrack(0,i)
 reaper.SetMediaTrackInfo_Value(tr,'I_FOLDERDEPTH',i<6 and 1 or -6)
 reaper.SetMediaTrackInfo_Value(tr,'I_HEIGHTOVERRIDE',i==0 and 200 or 65)
end
local tr=reaper.GetTrack(0,0)
local cfg=dofile(r..'/native-config.lua')
local layouts=cfg.width==320 and {'150%_A','200%_B'} or {'200%_C'}
local f=assert(io.open(r..'/baseline-result.txt','w'))
local index=1
local function inspect()
 f:write('layout '..layouts[index]..'\n')
 for _,n in ipairs({'tcp.size','tcp.label','tcp.recarm'}) do local ok,s=reaper.GetSetMediaTrackInfo_String(tr,'P_UI_RECT:'..n,'',false);f:write(n..' '..s..'\n') end
 f:flush();index=index+1
 if index>#layouts then f:close();return end
 local scale=layouts[index]:find('150%%') and 1.5 or 2
 reaper.SetMediaTrackInfo_Value(tr,'I_HEIGHTOVERRIDE',100*scale)
 reaper.GetSetMediaTrackInfo_String(tr,'P_TCP_LAYOUT',layouts[index],true)
 reaper.ThemeLayout_RefreshAll();reaper.TrackList_AdjustWindows(false);reaper.defer(inspect)
end
reaper.SetMediaTrackInfo_Value(tr,'I_HEIGHTOVERRIDE',layouts[1]:find('150%%') and 150 or 200)
reaper.GetSetMediaTrackInfo_String(tr,'P_TCP_LAYOUT',layouts[1],true)
reaper.ThemeLayout_RefreshAll();reaper.TrackList_AdjustWindows(false);reaper.defer(inspect)
