-- Fixture and passive observer for real mouse interaction in the isolated display.
local root=assert(REASKII_ROOT)
local state=assert(REASKII_STATE)
reaper.InsertTrackAtIndex(0,true)
local track=reaper.GetTrack(0,0)
reaper.GetSetMediaTrackInfo_String(track,'P_NAME','ReaSkii native MIDI fixture',true)
local item=reaper.CreateNewMIDIItemInProj(track,0,4,false)
local take=reaper.GetActiveTake(item)
reaper.GetSetMediaItemTakeInfo_String(take,'P_NAME','ReaSkii MIDI test chord',true)
for _,pitch in ipairs({60,64,67}) do
  reaper.MIDI_InsertNote(take,true,false,0,960,0,pitch,100,false)
end
reaper.SetMediaItemSelected(item,true)
reaper.Undo_OnStateChange2(0,'GUI fixture')
reaper.Main_OnCommand(40153,0)
local function launch()
  assert(reaper.MIDIEditor_GetActive(),'Native MIDI editor did not open')
  local action=reaper.AddRemoveReaScript(true,32060,root..'/scripts/midi/ReaSkii_MIDI_Tools.lua',true)
  assert(action>0,'Panel action registration failed')
  reaper.MIDIEditor_OnCommand(reaper.MIDIEditor_GetActive(),action)
  local function observe()
    local _,_,_,_,_,_,pitch=reaper.MIDI_GetNote(take,0)
    local f=assert(io.open(state,'w')); f:write(tostring(pitch)); f:close()
    reaper.defer(observe)
  end
  observe()
end
reaper.defer(launch)
