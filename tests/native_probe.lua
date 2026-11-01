-- Execute only in the dedicated portable QA installation.
local root = reaper.GetExePath()
assert(root:find('reaskii%-native'), 'Refusing to touch a non-QA REAPER instance')
local output=assert(io.open(root..'/native-probe.tsv','w'))
local function log(...) local t={...};for i,v in ipairs(t) do t[i]=tostring(v) end;output:write(table.concat(t,'\t')..'\n');output:flush() end
log('version',reaper.GetAppVersion(),reaper.GetResourcePath())
local ok=reaper.OpenColorThemeFile(root..'/ColorThemes/ReaSkii.ReaperThemeZip')
log('loaded',ok)
for i=0,300 do
 local name,desc,value,default,minimum,maximum=reaper.ThemeLayout_GetParameter(i)
 if not name or name=='' then break end
 log('parameter',i,name,value,default,minimum,maximum)
end
reaper.InsertTrackAtIndex(0,true)
local track=reaper.GetTrack(0,0)
reaper.GetSetMediaTrackInfo_String(track,'P_NAME','ReaSkii full-width track name - native geometry probe',true)
reaper.SetMediaTrackInfo_Value(track,'I_HEIGHTOVERRIDE',100)
reaper.TrackList_AdjustWindows(false)
reaper.ThemeLayout_RefreshAll()
local started=reaper.time_precise()
local function finish()
 if reaper.time_precise()-started<1 then reaper.defer(finish);return end
 for _,name in ipairs({'tcp.size','tcp.label','tcp.volume','tcp.pan','tcp.io','tcp.infoblock','tcp.recarm'}) do
  local found,rect=reaper.GetSetMediaTrackInfo_String(track,'P_UI_RECT:'..name,'',false)
  log('rect',name,found,rect)
 end
 output:close()
end
reaper.defer(finish)
