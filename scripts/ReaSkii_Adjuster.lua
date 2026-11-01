-- ReaSkii controls. Original reARK X controls remain available in the stock V6 adjuster.
local controls = {
  {'tcp_name_full_row', 'Track name takes the whole row'},
  {'tcp_name_keep_vol', '...but keep volume'},
  {'tcp_name_keep_pan', '...but keep pan'},
  {'tcp_name_keep_info', '...but keep infoblock (requires Use InfoBlock)'},
  {'tcp_name_keep_io', '...but keep routing button'},
  {'tcp_infoblock', 'Use InfoBlock'},
  {'smart_folder_indent', 'Smart folder indent'},
}
local function parameters()
  local found = {}
  for i = 0, 1000 do
    local name, desc, value, default, minimum, maximum = reaper.ThemeLayout_GetParameter(i)
    if not name or name == '' then break end
    found[name] = {id=i, value=value, default=default, minimum=minimum, maximum=maximum}
  end
  return found
end
local function is_reaskii()
  local path = reaper.GetLastColorThemeFile():lower()
  return path:match('[/\\]reaskii%.reapertheme') ~= nil
end
if not is_reaskii() then
  reaper.ShowMessageBox('Select the ReaSkii theme before opening these controls.', 'ReaSkii', 0)
  return
end
local function set(p, value)
  assert(reaper.ThemeLayout_SetParameter(p.id, value, true), 'Cannot set theme parameter')
  reaper.ThemeLayout_RefreshAll()
  reaper.TrackList_AdjustWindows(false)
end
local function text(x, y, label, bright)
  gfx.set(bright and 0.94 or 0.66, bright and 0.94 or 0.66, bright and 0.94 or 0.66)
  gfx.x, gfx.y = x, y
  gfx.drawstr(label)
end
local function inside(x,y,w,h)
  return gfx.mouse_x >= x and gfx.mouse_x < x+w and gfx.mouse_y >= y and gfx.mouse_y < y+h
end
local function button(x,y,w,label,click)
  gfx.set(0.25,0.25,0.25); gfx.rect(x,y,w,28)
  text(x+8,y+5,label,true)
  return click and inside(x,y,w,28)
end
local was_down = false
gfx.init('ReaSkii - Theme controls', 570, 455, 0)
gfx.setfont(1, 'Arial', 16)
-- Also used by the native smoke test to verify that the actual adjuster executed.
reaper.SetExtState('ReaSkii', 'adjuster_open', '1', false)
reaper.atexit(function() reaper.DeleteExtState('ReaSkii', 'adjuster_open', false); gfx.quit() end)
local function loop()
  if not is_reaskii() or gfx.getchar() < 0 then return end
  local params = parameters()
  local down = gfx.mouse_cap & 1 == 1
  local click = down and not was_down
  was_down = down
  gfx.set(0.12,0.12,0.12); gfx.rect(0,0,gfx.w,gfx.h)
  text(18,14,'ReaSkii: first-row controls and folder indentation',true)
  for i,entry in ipairs(controls) do
    local p = assert(params[entry[1]], 'Missing ReaSkii control: '..entry[1])
    local y = 48+(i-1)*34
    local enabled = not (i >= 2 and i <= 5) or params.tcp_name_full_row.value == 1
    gfx.set(0.7,0.7,0.7); gfx.rect(20,y,19,19,0)
    if p.value == 1 then
      gfx.line(23,y+9,28,y+14); gfx.line(28,y+14,36,y+4)
    end
    text(49,y,entry[2],enabled)
    if click and enabled and inside(18,y-3,530,27) then set(p,1-p.value) end
  end
  local width = params.tcp_infoblock_width
  text(20,294,'InfoBlock width: '..width.value..' px',true)
  if button(246,289,35,'-',click) then set(width,math.max(width.minimum,width.value-1)) end
  if button(289,289,35,'+',click) then set(width,math.min(width.maximum,width.value+1)) end
  if button(20,335,220,'Reset ReaSkii defaults',click) then
    for _,entry in ipairs(controls) do local p=params[entry[1]]; set(p,p.default) end
    set(width,width.default)
  end
  if button(20,375,295,'Original reARK X / V6 controls...',click) then
    local path=reaper.GetResourcePath()..'/Scripts/Cockos/Default_6.0_theme_adjuster.lua'
    local file=io.open(path,'r')
    if file then
      file:close()
      local action=reaper.AddRemoveReaScript(true,0,path,true)
      if action > 0 then reaper.Main_OnCommand(action,0) end
    else reaper.ShowMessageBox('The stock V6 adjuster was not found in Scripts/Cockos.', 'ReaSkii',0) end
  end
  text(20,421,'Controls not kept move down, or hide when the track is too short.',false)
  gfx.update()
  reaper.defer(loop)
end
loop()
