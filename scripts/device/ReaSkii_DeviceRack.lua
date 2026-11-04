-- ReaSkii Device Rack: bottom companion to REAPER, native track FX chain.
reaper.set_action_options(1)
local directory=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\\\])') or ''
local C=dofile(directory..'ReaSkii_DeviceRackController.lua')
local U=dofile(directory..'ReaSkii_DeviceRackUI.lua')
local controller=C.new(reaper)
controller:refresh()
gfx.init('ReaSkii Device Rack',1200,340,0,80,80)
gfx.setfont(1,'Arial',12)
local ui=U.new(controller)
local previous_right=false
local last_poll=0
local function close()
  gfx.quit()
end
reaper.atexit(close)
local function loop()
  local key=gfx.getchar()
  if key<0 then close(); return end
  local now=reaper.time_precise()
  if now-last_poll>.25 then controller:refresh(); last_poll=now end
  local right=(gfx.mouse_cap&2)~=0
  if right and not previous_right then
    gfx.x=gfx.mouse_x; gfx.y=gfx.mouse_y
    local choice=gfx.showmenu('Add MIDI LFO|Toggle dock|Close')
    if choice==1 then controller:insert_lfo(); controller:refresh()
    elseif choice==2 then gfx.dock(gfx.dock(-1)==0 and 1 or 0)
    elseif choice==3 then close(); return end
  end
  previous_right=right
  local ok,err=xpcall(function() ui:draw(); gfx.update() end,debug.traceback)
  if not ok then
    reaper.ShowConsoleMsg('ReaSkii Device Rack: '..tostring(err)..'\n')
    close(); return
  end
  reaper.defer(loop)
end
loop()
