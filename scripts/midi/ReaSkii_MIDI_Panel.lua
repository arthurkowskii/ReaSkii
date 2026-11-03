-- ReaSkii narrow MIDI companion. Native piano roll stays native.
-- Load in the MIDI Editor action section. No installation or extension needed.
reaper.set_action_options(1)
local directory=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])') or ''
local C=dofile(directory..'ReaSkii_MIDI_Core.lua')
local A=dofile(directory..'ReaSkii_MIDI_Adapter.lua')
local T=dofile(directory..'ReaSkii_MIDI_Transformations.lua')
local P=dofile(directory..'ReaSkii_MIDI_PanelController.lua')
local U=dofile(directory..'ReaSkii_MIDI_PanelUI.lua')
local G=dofile(directory..'ReaSkii_MIDI_Generators.lua')
local O=dofile(directory..'ReaSkii_MIDI_PanelOperations.lua')
local H=dofile(directory..'ReaSkii_MIDI_PanelContext.lua')
A.configure({C=C,T=O.wrap(T),G=O.generators(G)}) -- private module instances, not LAB1 globals
local dispatch={transform=function(raw,tool,options) return O.transform(raw,tool,options,A) end}
C.transform=function(raw,tool,options) return P.transform(raw,tool,options,dispatch,C) end
local function target()
  local editor=reaper.MIDIEditor_GetActive()
  if not editor or reaper.MIDIEditor_GetMode(editor)==-1 then return nil end
  local take=reaper.MIDIEditor_GetTake(editor)
  local project=reaper.EnumProjects(-1,'')
  if not take or not reaper.ValidatePtr2(project,take,'MediaItem_Take*') or not reaper.TakeIsMIDI(take) then return nil end
  local context=H.context(reaper,take,project)
  A.set_ppq(context.ppq)
  return take,context
end
local c=P.new(C,target)
function c:clip_loop()
  if self.session then self:cancel() end
  local t,ctx=target(); assert(t,'Open a MIDI item')
  local project=reaper.EnumProjects(-1,'')
  assert(reaper.ValidatePtr2(project,ctx.item,'MediaItem*'),'Item no longer valid')
  local value=ctx.loop and 0 or 1
  reaper.Undo_BeginBlock2(project)
  local ok=reaper.SetMediaItemInfo_Value(ctx.item,'B_LOOPSRC',value)
  reaper.UpdateItemInProject(ctx.item)
  reaper.Undo_EndBlock2(project,'ReaSkii panel: MIDI item source loop',-1)
  assert(ok and reaper.GetMediaItemInfo_Value(ctx.item,'B_LOOPSRC')==value,'Loop update failed verification')
  self.status='REAPER source loop '..(value==1 and 'on' or 'off')..'. Not Ableton launch/loop-brace semantics.'
end
local u=U.new(c,P)
local take=target()
-- Recovery is explicit, before any preview. Never touch another project's take.
if take and C.recovery_pending(take) then
  c.status='Interrupted preview found. Right-click panel for Recover original.'
end
local stopped=false
local function close()
  if stopped then return end
  stopped=true; c:close()
  if c.session and not c.session.closed then reaper.ShowConsoleMsg('ReaSkii: '..c.status..'\n') end
  gfx.quit()
end
reaper.atexit(close)
gfx.init('ReaSkii MIDI Panel',224,790,0,35,70)
gfx.setfont(1,'Arial',12)
local previous_right=false
local last_poll=0
local function loop()
  local key=gfx.getchar()
  if key<0 then close(); return end
  if key==27 and not u.edit then c:close() end
  local now=reaper.time_precise()
  if now-last_poll>.2 then c:poll(); last_poll=now end
  local right=(gfx.mouse_cap & 2)~=0
  if right and not previous_right then
    gfx.x=gfx.mouse_x; gfx.y=gfx.mouse_y
    local n=gfx.showmenu('Recover interrupted original|Cancel preview|Toggle docker|Archive conflict and accept current MIDI')
    local ok,err=pcall(function()
      if n==1 then
        assert(not c.session,'Cancel current preview before recovery.')
        local t=assert(target(),'Open the target MIDI editor first.')
        local recovered,reason=C.recover(t); assert(recovered,reason); c.status='Interrupted original restored and verified.'
      elseif n==2 then c:cancel()
      elseif n==3 then gfx.dock(gfx.dock(-1)==0 and 1 or 0)
      elseif n==4 then
        local t=assert(target(),'Open the conflicted MIDI take first.')
        local probe=C.session(t) -- validates active-project GUID identity, no writes
        assert(not c.session or (c.session.take==t and c.session.project==probe.project),'Return to the original preview target/project first.')
        if reaper.ShowMessageBox('Keep the CURRENT MIDI, including any uncommitted preview and external edits? Recovery evidence will be archived, not deleted. This cannot be used to undo the preview.','ReaSkii: resolve recovery conflict',4)==6 then
          local R=dofile(directory..'ReaSkii_MIDI_PanelRecovery.lua')
          local paths=R.archive(probe.journal_path,string.format('%.0f',reaper.time_precise()*1000000))
          c.session=nil; c.active=nil; c.context=nil; c.blocked=nil
          c.status='Current MIDI accepted unchanged. Recovery archived: '..paths[1]
        end
      end
    end)
    if not ok then c.status=tostring(err) end
  end
  previous_right=right
  local ok,err=xpcall(function() u:draw(key); gfx.update() end,debug.traceback)
  if not ok then c.status=tostring(err); close(); reaper.ShowConsoleMsg(c.status..'\n'); return end
  reaper.defer(loop)
end
loop()
