local root=reaper.GetExePath()
assert(root:find('reaskii%-native'))
assert(reaper.OpenColorThemeFile(root..'/ColorThemes/ReaSkii.ReaperThemeZip'))
reaper.Main_OnCommand(42234,0)
local start=reaper.time_precise()
local function tick()
 local open=reaper.GetExtState('ReaSkii','adjuster_open')=='1'
 local value
 for i=0,1000 do local n,_,v=reaper.ThemeLayout_GetParameter(i);if not n or n=='' then break end;if n=='tcp_name_full_row' then value=v;break end end
 if open and value==0 then
  local f=assert(io.open(root..'/adjuster-result.txt','w'));f:write('PASS: standard action opened own adjuster; real checkbox click changed full-row to 0');f:close()
 elseif reaper.time_precise()-start>10 then
  local f=assert(io.open(root..'/adjuster-result.txt','w'));f:write('FAIL: adjuster opened='..tostring(open)..', full-row='..tostring(value));f:close()
 else reaper.defer(tick) end
end
reaper.defer(tick)
