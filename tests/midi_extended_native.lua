-- tests/midi_extended_native.lua
-- Integration of Adapter+Transformations+Generators inside a real REAPER take.
-- Run from an isolated REAPER instance; writes PASS/FAIL TSV lines to REASKII_OUT.
local ROOT = assert(REASKII_ROOT, 'REASKII_ROOT is required')
local OUT = assert(REASKII_OUT, 'REASKII_OUT is required')
local results = {}

local function clean(value)
  return (tostring(value):gsub('[\t\r\n]+', ' '):sub(1, 500))
end
local function run(name, fn)
  local ok, detail = xpcall(fn, debug.traceback)
  if ok then
    results[#results + 1] = 'PASS\t' .. name .. (detail and ('\t' .. clean(detail)) or '')
  else
    results[#results + 1] = 'FAIL\t' .. name .. '\t' .. clean(detail)
  end
end

local function main()
  local C = assert(loadfile(ROOT .. '/scripts/midi/ReaSkii_MIDI_Core.lua'))()
  local T = assert(loadfile(ROOT .. '/scripts/midi/ReaSkii_MIDI_Transformations.lua'))()
  local G = assert(loadfile(ROOT .. '/scripts/midi/ReaSkii_MIDI_Generators.lua'))()
  local A = assert(loadfile(ROOT .. '/scripts/midi/ReaSkii_MIDI_Adapter.lua'))()
  A.configure({ C = C, T = T, G = G })
  A.install(C)
  results[#results + 1] = 'INFO\tmodules\tAdapter.configure(C,T,G) and Adapter.install(C) loaded'

  local function bytes(take) return select(1, reaper.MIDI_GetAllEvts(take)) end
  local function note_count(take) return select(2, reaper.MIDI_CountEvts(take)) end
  local function cc_count(take) return select(3, reaper.MIDI_CountEvts(take)) end
  local function reset(take, raw)
    reaper.MIDI_SetAllEvts(take, raw)
    reaper.MIDI_Sort(take)
    assert(bytes(take) == raw, 'take reset is not byte exact')
  end
  local function cycle(take, raw, tool, options, expected)
    reset(take, raw)
    local before = bytes(take)
    local session = C.session(take)
    session:preview(tool, options)
    assert(bytes(take) ~= before, tool .. ': preview did not modify the take')
    local count = note_count(take)
    if expected then
      assert(count == expected, tool .. ': expected ' .. expected .. ' notes, got ' .. count)
    end
    session:cancel()
    assert(bytes(take) == before, tool .. ': cancel is not byte exact')
    assert(not C.recovery_pending(take), tool .. ': recovery file left after cancel')
    return count .. ' notes, cancel byte-exact'
  end

  reaper.Undo_BeginBlock()
  reaper.InsertTrackAtIndex(0, true)
  local track = reaper.GetTrack(0, 0)
  local item = reaper.CreateNewMIDIItemInProj(track, 0, 4, false)
  local take = reaper.GetActiveTake(item)
  for _, note in ipairs({
    { 0, 240, 60 }, { 500, 740, 61 }, { 1000, 1240, 64 }, { 1500, 1740, 67 },
  }) do
    reaper.MIDI_InsertNote(take, true, false, note[1], note[2], 0, note[3], 100, false)
  end
  reaper.MIDI_InsertCC(take, true, false, 0, 0xB0, 0, 7, 64)
  reaper.MIDI_Sort(take)
  local base = bytes(take)
  assert(note_count(take) == 4, 'fixture chord has four notes')

  local item2 = reaper.CreateNewMIDIItemInProj(track, 4, 4, false)
  local take2 = reaper.GetActiveTake(item2)
  reaper.MIDI_Sort(take2)
  local empty = bytes(take2)
  reaper.Undo_EndBlock('ReaSkii extended native fixture', -1)
  reaper.UpdateArrange()

  run('native fixture in real take', function()
    assert(reaper.TakeIsMIDI(take) and reaper.TakeIsMIDI(take2))
    assert(note_count(take) == 4 and note_count(take2) == 0)
    assert(cc_count(take) == 1)
    return '4 selected notes + CC7, empty take ready'
  end)

  local ppq = reaper.MIDI_GetPPQPosFromProjQN(take, 1)
    - reaper.MIDI_GetPPQPosFromProjQN(take, 0)
  assert(ppq and ppq > 0, 'Cannot read take PPQ')
  A.set_ppq(ppq)
  results[#results + 1] = 'INFO\tppq\t' .. tostring(ppq)

  local transforms = {
    { 'arpeggiate', { mode = 'up', rate_ppq = 480, gate = 0.5, octaves = 1,
      range_start = 0, range_end = 3840 }, nil },
    { 'chop', { parts = 3 }, 12 },
    { 'fit_scale', { root = 0, intervals = { 0, 2, 4, 5, 7, 9, 11 } }, 4 },
    { 'invert', { pivot = 60 }, 4 },
    { 'legato', {}, 4 },
    { 'quantize', { grid_ppq = 480, strength = 1 }, 4 },
    { 'reverse', { range_start = 0, range_end = 3840 }, 4 },
    { 'stretch', { factor = 2, anchor = 0 }, 4 },
    { 'strum', { low = -20, high = 20, grid_ppq = 480, tension = 0,
      onset_tolerance = 48 }, 4 },
  }
  for _, entry in ipairs(transforms) do
    run('transform ' .. entry[1], function()
      return cycle(take, base, entry[1], entry[2], entry[3])
    end)
  end

  local generators = {
    { 'rhythm', { range_start = 0, range_end = 3840, steps = 4, density = 2,
      seed = 7, note_length = 480, step_ppq = 960, pitches = { 60, 64 },
      vel = 100, channel = 0, release_velocity = 0, mode = 'add' }, 2 },
    { 'euclidean', { range_start = 0, range_end = 3840, steps = 4, pulses = 2,
      rotation = 0, pitch = 72, vel = 100, step_ppq = 960, note_length = 480,
      channel = 0, release_velocity = 0, mode = 'add' }, 2 },
    { 'seed', { range_start = 0, range_end = 3840, grid_ppq = 960, density = 0.5,
      pitch_min = 60, pitch_max = 60, vel_min = 100, vel_max = 100, seed = 5,
      channel = 0, release_velocity = 0, mode = 'add' }, 2 },
    { 'shape', { range_start = 0, range_end = 3840, shape = 'line', steps = 4,
      pitch_min = 60, pitch_max = 72, vel = 100, channel = 0,
      release_velocity = 0, mode = 'add' }, 4 },
    { 'stacks', { range_start = 0, range_end = 3840, vel = 100, channel = 0,
      release_velocity = 0, mode = 'add', chords = {
        { root = 60, intervals = { 0, 4, 7 }, duration_ppq = 960 },
        { root = 65, intervals = { 0, 4, 7 }, duration_ppq = 960 },
      } }, 6 },
  }
  for _, entry in ipairs(generators) do
    run('generator ' .. entry[1], function()
      return cycle(take2, empty, entry[1], entry[2], entry[3])
    end)
  end

  run('chop apply then REAPER undo', function()
    reset(take, base)
    local session = C.session(take)
    session:preview('chop', { parts = 2 })
    local applied = session:apply('ReaSkii native QA chop')
    assert(applied, 'chop apply reported no change')
    assert(note_count(take) == 8, 'chop apply expected 8 notes')
    assert(reaper.Undo_DoUndo2(0), 'REAPER undo failed')
    reaper.UpdateArrange()
    assert(bytes(take) == base, 'undo did not restore the byte-exact take')
    return '8 notes committed, undo restored 4 notes'
  end)

  run('euclidean apply then REAPER undo', function()
    reset(take2, empty)
    local session = C.session(take2)
    session:preview('euclidean', { range_start = 0, range_end = 3840, steps = 4,
      pulses = 2, rotation = 0, pitch = 72, vel = 100, step_ppq = 960,
      note_length = 480, channel = 0, release_velocity = 0, mode = 'add' })
    local applied = session:apply('ReaSkii native QA euclidean')
    assert(applied, 'euclidean apply reported no change')
    assert(note_count(take2) == 2, 'euclidean apply expected 2 notes')
    assert(reaper.Undo_DoUndo2(0), 'REAPER undo failed')
    reaper.UpdateArrange()
    assert(bytes(take2) == empty, 'undo did not restore the empty take')
    return '2 notes committed, undo restored empty take'
  end)

  run('CC curve preserved by chop apply', function()
    reset(take, base)
    local session = C.session(take)
    session:preview('chop', { parts = 2 })
    assert(session:apply('ReaSkii native QA CC'), 'chop apply failed')
    assert(cc_count(take) >= 1, 'chop apply lost all CC events')
    local found = false
    for index = 0, cc_count(take) - 1 do
      local _, _, _, _, chanmsg, chan, msg2, msg3 = reaper.MIDI_GetCC(take, index)
      if chanmsg == 0xB0 and chan == 0 and msg2 == 7 and msg3 == 64 then found = true end
    end
    assert(found, 'CC7 value 64 disappeared after chop apply')
    assert(reaper.Undo_DoUndo2(0), 'undo failed after CC check')
    return 'CC7=64 still present after apply'
  end)

  run('invalid parameter writes nothing', function()
    reset(take, base)
    local before = bytes(take)
    local session = C.session(take)
    local ok = pcall(function() session:preview('chop', { parts = 1 }) end)
    assert(not ok, 'chop accepted parts=1')
    assert(bytes(take) == before, 'failed preview modified the take')
    session:abandon()
    assert(not C.recovery_pending(take), 'failed preview left a recovery file')
    return 'parts=1 rejected, take untouched'
  end)

  run('collision with unselected note is refused', function()
    reset(take2, empty)
    reaper.MIDI_InsertNote(take2, false, false, 0, 960, 0, 72, 100, false)
    reaper.MIDI_Sort(take2)
    local collision = bytes(take2)
    local session = C.session(take2)
    local ok = pcall(function()
      session:preview('euclidean', { range_start = 0, range_end = 3840, steps = 4,
        pulses = 2, rotation = 0, pitch = 72, vel = 100, step_ppq = 960,
        note_length = 480, channel = 0, release_velocity = 0, mode = 'add' })
    end)
    assert(not ok, 'euclidean overwrote an unselected note of the same pitch')
    assert(bytes(take2) == collision, 'refused preview modified the take')
    session:abandon()
    return 'unselected target note protected'
  end)

  run('generator end clipped to range_end', function()
    reset(take2, empty)
    local session = C.session(take2)
    session:preview('euclidean', { range_start = 0, range_end = 500, steps = 4,
      pulses = 2, rotation = 0, pitch = 72, vel = 100, step_ppq = 960,
      note_length = 960, channel = 0, release_velocity = 0, mode = 'add' })
    assert(note_count(take2) == 1, 'expected one note inside the short range')
    local _, _, _, startppq, endppq = reaper.MIDI_GetNote(take2, 0)
    assert(startppq == 0 and endppq == 500,
      'note was not clipped to range_end: ' .. tostring(startppq) .. '..' .. tostring(endppq))
    session:cancel()
    assert(bytes(take2) == empty, 'cancel after clipped generator is not byte exact')
    return 'note 0..500 clipped exactly at range_end'
  end)
end

local ok, err = xpcall(main, debug.traceback)
if not ok then
  results[#results + 1] = 'FAIL\tfatal\t' .. clean(err)
end
results[#results + 1] = 'DONE\t' .. tostring(#results)
local handle = assert(io.open(OUT, 'w'))
handle:write(table.concat(results, '\n') .. '\n')
handle:close()
