local r=reaper.GetExePath();assert(r:find('reaskii%-native'))
assert(reaper.OpenColorThemeFile(r..'/ColorThemes/ReaSkii.ReaperThemeZip'))
for i=0,1000 do local n,_,_,default=reaper.ThemeLayout_GetParameter(i);if not n or n=='' then break end;reaper.ThemeLayout_SetParameter(i,default,false) end
local names={'WORLD AUDIO - full-width names','BAYOU - nested ambience folder','FAUNA - another folder level','INSECTS - long continuous beds','FROGS - close and distant calls','BIRDS - sparse distant phrases','LEAF TRACK - six folder levels deep'}
for i,name in ipairs(names) do
 reaper.InsertTrackAtIndex(i-1,true);local tr=reaper.GetTrack(0,i-1)
 reaper.GetSetMediaTrackInfo_String(tr,'P_NAME',name,true)
 reaper.GetSetMediaTrackInfo_String(tr,'P_TCP_LAYOUT','A',true)
 reaper.GetSetMediaTrackInfo_String(tr,'P_MCP_LAYOUT','A',true)
 reaper.SetMediaTrackInfo_Value(tr,'I_HEIGHTOVERRIDE',65)
 reaper.SetMediaTrackInfo_Value(tr,'I_FOLDERDEPTH',i<#names and 1 or -(#names-1))
 reaper.SetTrackColor(tr,reaper.ColorToNative(85+15*i,120+5*i,150))
end
if reaper.kbd_getTextFromCmd(40406,0):lower():find('volume') then
 reaper.SetOnlyTrackSelected(reaper.GetTrack(0,2));reaper.Main_OnCommand(40406,0)
end
if reaper.GetToggleCommandState(40078)==0 then reaper.Main_OnCommand(40078,0) end
reaper.ThemeLayout_RefreshAll();reaper.TrackList_AdjustWindows(false)
local start=reaper.time_precise();local ready=false
local function tick()
 local elapsed=reaper.time_precise()-start
 if elapsed>1 and not ready then local f=assert(io.open(r..'/fixture-ready.txt','w'));f:write('ready');f:close();ready=true end
 if elapsed>7 then reaper.Main_OnCommand(42234,0);return end
 reaper.defer(tick)
end
reaper.defer(tick)
