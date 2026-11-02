-- ReaSkii 0.2 parameter migration. No theme/config/project file is edited.
local M = {version='0.2.0'}
function M.is_theme()
  return reaper.GetLastColorThemeFile():lower():match('[/\\]reaskii%.reapertheme') ~= nil
end
function M.parameters()
  local found, ordered = {}, {}
  for i=0,2000 do
    local name,desc,value,default,minimum,maximum = reaper.ThemeLayout_GetParameter(i)
    if not name or name=='' then break end
    local p={id=i,name=name,desc=desc,value=value,default=default,minimum=minimum,maximum=maximum}
    found[name]=p;ordered[#ordered+1]=p
  end
  return found,ordered
end
function M.refresh()
  reaper.ThemeLayout_RefreshAll();reaper.TrackList_AdjustWindows(false);reaper.UpdateArrange()
end
function M.set(p,value)
  assert(reaper.ThemeLayout_SetParameter(p.id,value,true),'Cannot set '..p.name)
  local _,_,actual=reaper.ThemeLayout_GetParameter(p.id)
  assert(actual==value,'Read-back mismatch for '..p.name..': '..tostring(actual))
end
local function backup(ordered)
  local dir=reaper.GetResourcePath()..'/ReaSkii-backups'
  -- REAPER may return 0 when the directory already exists; opening the backup
  -- is the authoritative writability check, before any parameter is changed.
  reaper.RecursiveCreateDirectory(dir,0)
  local base=dir..'/Restore-before-defaults-'..os.date('%Y%m%d-%H%M%S')
  local path=base..'.lua';local n=0
  while true do
    local existing=io.open(path,'r');if not existing then break end
    existing:close();n=n+1;path=base..'-'..n..'.lua'
  end
  local file=assert(io.open(path,'w'))
  assert(file:write('-- Run from Actions with the ReaSkii 0.2 theme loaded to restore saved parameter values.\n'))
  assert(file:write("assert(reaper.GetLastColorThemeFile():lower():match('[/\\\\]reaskii%.reapertheme'), 'Select ReaSkii first')\nlocal values={\n"))
  for _,p in ipairs(ordered) do assert(file:write(string.format('[%q]=%s,\n',p.name,tostring(p.value)))) end
  assert(file:write("}\nfor i=0,2000 do\n local n=reaper.ThemeLayout_GetParameter(i);if not n or n=='' then break end\n if values[n]~=nil then assert(reaper.ThemeLayout_SetParameter(i,values[n],true)) end\nend\nreaper.ThemeLayout_RefreshAll();reaper.TrackList_AdjustWindows(false)\n"))
  assert(file:close())
  return path
end
function M.apply()
  assert(M.is_theme(),'Select ReaSkii before applying its defaults')
  local params,ordered=M.parameters()
  assert(params.tcp_side_fx and params.tcp_name_full_row and not params.tcp_fx_section_mode,
         'ReaSkii 0.2 theme required; reload the updated theme first')
  local path=backup(ordered)
  local ok,err=pcall(function() for _,p in ipairs(ordered) do M.set(p,p.default) end end)
  if not ok then
    for _,p in ipairs(ordered) do reaper.ThemeLayout_SetParameter(p.id,p.value,true) end
    M.refresh();error(tostring(err)..'\nPrevious values restored. Backup: '..path)
  end
  M.refresh()
  reaper.SetExtState('ReaSkii','defaults_engine',M.version,true)
  reaper.SetExtState('ReaSkii','defaults_backup',path,true)
  return path
end
function M.ensure()
  if reaper.GetExtState('ReaSkii','defaults_engine')~=M.version then return M.apply() end
end
return M
