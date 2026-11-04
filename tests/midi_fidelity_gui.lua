-- Isolated host fixture and read-only observer. Test command file alters fixture only.
local root=assert(REASKII_ROOT)
reaper.InsertTrackAtIndex(0,true)
local track=reaper.GetTrack(0,0)
local item=reaper.CreateNewMIDIItemInProj(track,0,5,false)
local take=reaper.GetActiveTake(item)
reaper.GetSetMediaItemTakeInfo_String(take,'P_NAME','ReaSkii fidelity chord',true)
for _,pitch in ipairs({60,64,67}) do reaper.MIDI_InsertNote(take,true,false,960,1920,0,pitch,100,false) end
reaper.MIDI_InsertNote(take,true,false,2880,3360,0,72,100,false)
reaper.MIDI_Sort(take)
reaper.SetMediaItemSelected(item,true)
reaper.Undo_OnStateChange2(0,'Fidelity fixture')
reaper.Main_OnCommand(40153,0)
local function launch()
  local editor=assert(reaper.MIDIEditor_GetActive())
  reaper.SetMIDIEditorGrid(0,.25)
  local action=reaper.AddRemoveReaScript(true,32060,root..'/scripts/midi/ReaSkii_MIDI_Panel.lua',true)
  assert(action>0)
  reaper.MIDIEditor_OnCommand(editor,action)
  local function observe()
    local cmd=io.open(REASKII_STATE..'.cmd','r')
    if cmd then
      local command=cmd:read('*a'); cmd:close(); os.remove(REASKII_STATE..'.cmd')
      if command=='external' then reaper.MIDI_SetNote(take,0,nil,nil,nil,nil,nil,nil,77,false)
      elseif command=='undo' then reaper.Undo_DoUndo2(0) end
    end
    local parts={}
    local _,count=reaper.MIDI_CountEvts(take)
    for i=0,count-1 do
      local _,_,_,s,e,_,pitch,vel=reaper.MIDI_GetNote(take,i)
      parts[#parts+1]=string.format('"%d":[%.3f,%.3f,%d]',pitch,s,e,vel)
    end
    local f=assert(io.open(REASKII_STATE..'.tmp','w')); f:write('{'..table.concat(parts,',')..'}'); f:close()
    os.rename(REASKII_STATE..'.tmp',REASKII_STATE)
    reaper.defer(observe)
  end
  observe()
end
reaper.defer(launch)
