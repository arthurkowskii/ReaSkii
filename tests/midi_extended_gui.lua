-- tests/midi_extended_gui.lua
-- Fixture/observer for real X11 clicks on the Transform/Generate panel views.
-- REASKII_SCENARIO is chord, empty or offset. State is "count|start:end:pitch:vel:sel;...".
local root = assert(REASKII_ROOT, 'REASKII_ROOT is required')
local state = assert(REASKII_STATE, 'REASKII_STATE is required')
local scenario = REASKII_SCENARIO or 'chord'

reaper.InsertTrackAtIndex(0, true)
local track = reaper.GetTrack(0, 0)
reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', 'ReaSkii extended GUI fixture', true)
local item, take
if scenario == 'offset' then
  reaper.SetCurrentBPM(0, 90, true)
  item = reaper.CreateNewMIDIItemInProj(track, 1.0, 2.0, false)
  take = reaper.GetActiveTake(item)
  reaper.SetMediaItemInfo_Value(item, 'D_PLAYRATE', 2.0)
  reaper.SetMediaItemInfo_Value(item, 'D_LENGTH', 2.0)
  reaper.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', 0.5)
  reaper.MIDI_InsertNote(take, true, false, 1440, 1920, 0, 60, 100, false)
else
  item = reaper.CreateNewMIDIItemInProj(track, 0, 4, false)
  take = reaper.GetActiveTake(item)
  if scenario == 'chord' then
    for _, pitch in ipairs({ 60, 61, 64, 67 }) do
      reaper.MIDI_InsertNote(take, true, false, (pitch == 60 and 0 or
        (pitch == 61 and 480 or (pitch == 64 and 960 or 1440))),
        (pitch == 60 and 240 or (pitch == 61 and 720 or
        (pitch == 64 and 1200 or 1680))), 0, pitch, 100, false)
    end
  end
end
reaper.MIDI_Sort(take)
reaper.GetSetMediaItemTakeInfo_String(take, 'P_NAME',
  'ReaSkii extended ' .. scenario .. ' take', true)
reaper.SetMediaItemSelected(item, true)
reaper.Undo_OnStateChange2(0, 'extended GUI fixture ' .. scenario)

local function dump()
  local count = select(2, reaper.MIDI_CountEvts(take))
  local parts = {}
  for index = 0, count - 1 do
    local _, selected, _, startppq, endppq, pitch, vel = reaper.MIDI_GetNote(take, index)
    parts[#parts + 1] = string.format('%d:%d:%d:%d:%d', startppq, endppq, pitch, vel,
      selected and 1 or 0)
  end
  return count .. '|' .. table.concat(parts, ';')
end

local function publish()
  local handle = assert(io.open(state .. '.tmp', 'w'))
  handle:write(dump())
  handle:close()
  os.rename(state .. '.tmp', state)
end

reaper.Main_OnCommand(40153, 0)
local function launch()
  assert(reaper.MIDIEditor_GetActive(), 'Native MIDI editor did not open')
  local action = reaper.AddRemoveReaScript(true, 32060,
    root .. '/scripts/midi/ReaSkii_MIDI_Tools.lua', true)
  assert(action > 0, 'Panel action registration failed')
  reaper.MIDIEditor_OnCommand(reaper.MIDIEditor_GetActive(), action)
  local function observe()
    publish()
    reaper.defer(observe)
  end
  observe()
end
reaper.defer(launch)
