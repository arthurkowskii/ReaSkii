-- Standalone tests for scripts/midi/ReaSkii_MIDI_Adapter.lua.
-- Plain Lua 5.4, no REAPER, no gfx, no I/O beyond dofile.
-- Run: python3 .../lua54_run.py tests/midi_adapter_unit.lua
-- A successful run returns {passed=N}. Raises on the first failure.

local script_path = debug.getinfo(1, 'S').source:sub(2)
local directory = script_path:match('^(.*[/\\])') or './'
local C = assert(dofile(directory .. '../scripts/midi/ReaSkii_MIDI_Core.lua'))
local T = assert(dofile(directory .. '../scripts/midi/ReaSkii_MIDI_Transformations.lua'))
local G = assert(dofile(directory .. '../scripts/midi/ReaSkii_MIDI_Generators.lua'))
local A = assert(dofile(directory .. '../scripts/midi/ReaSkii_MIDI_Adapter.lua'))
A.configure({ C = C, T = T, G = G, ppq = 960 })

local passed = 0
local function check(condition, name)
  if not condition then error('FAIL: ' .. name, 2) end
  passed = passed + 1
end
local function eq(actual, expected, name)
  if actual ~= expected then
    error(string.format('FAIL: %s (expected %s, got %s)', name,
      tostring(expected), tostring(actual)), 2)
  end
  passed = passed + 1
end
local function expect_error(fn, fragment, name)
  local ok, err = pcall(fn)
  if ok then error('FAIL: ' .. name .. ' did not raise', 2) end
  if fragment and not tostring(err):find(fragment, 1, true) then
    error(string.format('FAIL: %s (error %q lacks %q)', name,
      tostring(err), fragment), 2)
  end
  passed = passed + 1
end
local function event(delta, flags, message)
  return string.pack('i4Bs4', delta, flags, message)
end
local function note_on(flags, pitch, velocity)
  return event(0, flags, string.char(0x90, pitch, velocity))
end
local function note_off(delta, pitch, velocity)
  return event(delta, 0, string.char(0x80, pitch, velocity))
end
local function decode(raw)
  return C.decode(raw)
end
local function concat(events)
  local parts = {}
  for index, item in ipairs(events) do
    parts[index] = string.pack('i4Bs4', item.pos, item.flags, item.msg)
  end
  return table.concat(parts)
end
local function find_message(events, status, data1)
  local found = {}
  for _, item in ipairs(events) do
    if #item.msg >= 2 and item.msg:byte(1) == status
        and (data1 == nil or item.msg:byte(2) == data1) then
      found[#found + 1] = item
    end
  end
  return found
end
local function last_event(raw)
  local events = decode(raw)
  return events[#events]
end

-- Deterministic fixture:
--   CC7 at 0 (expression), selected C4 on/off release 37,
--   unselected E4 on/off release 20, CC1 at 120, SysEx at 120,
--   text/notation at 120, end-of-track at 480.
local function fixture(options)
  options = options or {}
  local selected = options.selected ~= false
  local with_expression = options.with_expression ~= false
  local with_unknown = options.with_unknown ~= false
  local parts = {}
  if with_expression then
    parts[#parts + 1] = event(0, 0, string.char(0xB0, 7, 100))
  end
  parts[#parts + 1] = note_on(selected and 1 or 0, 60, 100)
  parts[#parts + 1] = note_on(0, 64, 90)
  if with_expression then
    parts[#parts + 1] = event(120, 0, string.char(0xB0, 1, 64))
  end
  if with_unknown then
    parts[#parts + 1] = event(0, 0, string.char(0xF0, 0x7D, 0x01, 0xF7))
    parts[#parts + 1] = event(0, 0, string.char(0xFF, 0x0F, 0x52, 0x65, 0x61))
  end
  parts[#parts + 1] = note_off(120, 60, 37)
  parts[#parts + 1] = note_off(0, 64, 20)
  parts[#parts + 1] = event(0, 0, '')
  return table.concat(parts)
end

-- 1. Legacy transpose preserves selection, release velocity, CC and SysEx.
do
  local input = fixture()
  local output = A.transform(input, 'transpose', { amount = 2 })
  local events = decode(output)
  local ons = find_message(events, 0x90, 62)
  local offs = find_message(events, 0x80, 62)
  eq(#ons, 1, 'transpose selected note-on')
  eq(#offs, 1, 'transpose selected note-off')
  eq(offs[1].msg:byte(3), 37, 'transpose keeps release velocity')
  eq(ons[1].flags & 1, 1, 'transpose keeps selected flag')
  local unselected_ons = find_message(events, 0x90, 64)
  local unselected_offs = find_message(events, 0x80, 64)
  eq(#unselected_ons, 1, 'transpose leaves unselected on')
  eq(unselected_offs[1].msg:byte(3), 20, 'transpose leaves unselected release')
  eq(unselected_ons[1].flags, 0, 'transpose leaves unselected flags')
  local cc7 = find_message(events, 0xB0, 7)
  local cc1 = find_message(events, 0xB0, 1)
  eq(cc7[1].msg, string.char(0xB0, 7, 100), 'CC7 bytes unchanged')
  eq(cc1[1].msg, string.char(0xB0, 1, 64), 'CC1 bytes unchanged')
  local sysex = find_message(events, 0xF0)
  eq(sysex[1].msg, string.char(0xF0, 0x7D, 0x01, 0xF7), 'SysEx bytes unchanged')
  local text = find_message(events, 0xFF)
  eq(text[1].msg, string.char(0xFF, 0x0F, 0x52, 0x65, 0x61), 'text bytes unchanged')
  local tail = events[#events]
  eq(tail.msg, '', 'terminator remains last')
  eq(tail.pos, 240, 'terminator position preserved')
end

-- 2. Velocity touches only the selected attack, never release velocity.
do
  local events = decode(A.transform(fixture(), 'velocity', { amount = 10 }))
  eq(find_message(events, 0x90, 60)[1].msg:byte(3), 110, 'selected velocity increased')
  eq(find_message(events, 0x90, 64)[1].msg:byte(3), 90, 'unselected velocity unchanged')
  eq(find_message(events, 0x80, 60)[1].msg:byte(3), 37, 'release velocity unchanged')
end

-- 3. Random velocity is deterministic and bounded, release untouched.
do
  local one = A.transform(fixture(), 'random_velocity', { amount = 20, seed = 123 })
  local two = A.transform(fixture(), 'random_velocity', { amount = 20, seed = 123 })
  eq(one, two, 'random velocity reproducible')
  local velocity = find_message(decode(one), 0x90, 60)[1].msg:byte(3)
  check(velocity >= 80 and velocity <= 120, 'random velocity within bounds')
  eq(find_message(decode(one), 0x80, 60)[1].msg:byte(3), 37,
    'random velocity keeps release velocity')
end

-- 4. New pitch tool: invert refuses an ambiguous landing and changes nothing.
do
  local input = fixture({ with_expression = false, with_unknown = false })
  local ok, err = pcall(A.transform, input, 'invert', { pivot = 62 })
  check(not ok, 'invert onto an unselected note refused')
  check(tostring(err):find('unselected', 1, true) ~= nil, 'collision message is honest')
  local changed = A.transform(input, 'invert', { pivot = 60 })
  local events = decode(changed)
  eq(find_message(events, 0x90, 60)[1].msg:byte(3), 100, 'invert identity keeps attack')
  eq(find_message(events, 0x80, 60)[1].msg:byte(3), 37, 'invert identity keeps release')
end

-- 5. Timing/pitch tools refuse CC/aftertouch/pitch-bend instead of deleting curves.
do
  local input = fixture()
  for _, tool in ipairs({ 'quantize', 'reverse', 'stretch', 'chop', 'legato',
    'arpeggiate', 'fit_scale' }) do
    local options = { grid_ppq = 120, strength = 1, range_start = 0,
      range_end = 480, parts = 2, factor = 2, anchor = 0, pivot = 60,
      root = 0, intervals = { 0, 2, 4, 5, 7, 9, 11 },
      low = 0, high = 100, onset_tolerance = 0 }
    expect_error(function() A.transform(input, tool, options) end, 'Blocked:',
      tool .. ' refuses expression data')
  end
  local touched = A.transform(input, 'velocity', { amount = 1 })
  check(#touched > 0, 'safe tool still works with expression present')
end

-- 6. Structural tools refuse SysEx/text/notation/CCBZ attachments.
do
  local input = fixture({ with_expression = false, with_unknown = true })
  expect_error(function() A.transform(input, 'chop', { parts = 2 }) end,
    'Blocked:', 'chop refuses SysEx/text attachments')
  -- Transpose is not structural and preserves those bytes.
  local output = A.transform(input, 'transpose', { amount = 1 })
  eq(find_message(decode(output), 0xF0)[1].msg,
    string.char(0xF0, 0x7D, 0x01, 0xF7), 'transpose keeps SysEx')
  eq(find_message(decode(output), 0xFF)[1].msg,
    string.char(0xFF, 0x0F, 0x52, 0x65, 0x61), 'transpose keeps notation text')
  local ccbz = event(0, 4, string.char(0xB0, 11, 90))
  local flagged = note_on(0, 60, 100) .. note_off(120, 60, 30) .. ccbz .. event(0, 0, '')
  expect_error(function() A.transform(flagged, 'chop', { parts = 2 }) end,
    'Blocked:', 'chop refuses CCBZ-flagged events')
end

-- 7. Chop splits the selected note only and preserves release velocity.
do
  local input = fixture({ with_expression = false, with_unknown = false })
  local output = A.transform(input, 'chop', { parts = 2 })
  local events = decode(output)
  local ons = find_message(events, 0x90, 60)
  local offs = find_message(events, 0x80, 60)
  eq(#ons, 2, 'chop creates two selected note-ons')
  eq(#offs, 2, 'chop creates two selected note-offs')
  eq(ons[1].pos, 0, 'chop part one starts at the source')
  eq(ons[2].pos, 60, 'chop part two starts halfway')
  eq(offs[1].pos, 60, 'chop part one ends halfway')
  eq(offs[2].pos, 120, 'chop part two ends at the source end')
  eq(offs[1].msg:byte(3), 37, 'chop keeps release velocity')
  eq(find_message(events, 0x90, 64)[1].msg:byte(3), 90, 'chop leaves unselected note')
  eq(events[#events].msg, '', 'chop keeps the terminator last')
end

-- 8. Contiguous same-pitch notes: note-off precedes the next note-on.
do
  local input = note_on(1, 60, 100) .. note_off(120, 60, 20)
    .. note_on(0, 60, 90) .. note_off(120, 60, 10) .. event(0, 0, '')
  local output = A.transform(input, 'legato', {})
  local events = decode(output)
  eq(events[1].msg:byte(1), 0x90, 'first note-on stays first')
  eq(events[2].pos, 120, 'legato extends the first note to the next start')
  eq(events[2].msg:byte(1), 0x80, 'first note-off at the boundary')
  eq(events[3].pos, 120, 'second note-on at the boundary')
  eq(events[3].msg:byte(1), 0x90, 'second note-on after the note-off')
  eq(events[4].msg:byte(3), 10, 'second release velocity preserved')
end

-- 9. Note-off encoded as 0x90 velocity 0 stays a real note-off.
do
  local input = note_on(1, 60, 100) .. event(60, 0, string.char(0x90, 60, 0))
    .. event(0, 0, '')
  local output = A.transform(input, 'transpose', { amount = 3 })
  local events = decode(output)
  eq(events[2].msg:byte(1), 0x90, 'zero-velocity note-off keeps 0x90 status')
  eq(events[2].msg:byte(2), 63, 'zero-velocity note-off transposes pitch')
  eq(events[2].msg:byte(3), 0, 'zero-velocity note-off keeps velocity 0')
end

-- 10. Malformed selected note (no note-off) is refused, not skipped.
do
  local input = note_on(1, 60, 100) .. event(0, 0, '')
  expect_error(function() A.transform(input, 'transpose', { amount = 2 }) end,
    'no note-off', 'unterminated selected note refused')
  local unselected = note_on(0, 60, 100) .. event(0, 0, '')
  local untouched = A.transform(unselected, 'transpose', { amount = 2 })
  eq(untouched, unselected, 'unselected malformed note is not touched')
end

-- 11. Ambiguous overlapping selected notes are refused.
do
  local input = note_on(1, 60, 100) .. note_on(0, 60, 90)
    .. note_off(120, 60, 10) .. note_off(0, 60, 5) .. event(0, 0, '')
  expect_error(function() A.transform(input, 'transpose', { amount = 1 }) end,
    'Ambiguous MIDI', 'overlapping same-pitch selected notes refused')
end

-- 12. Errors leave the input string untouched (Adapter is pure).
do
  local input = fixture()
  local copy = input
  pcall(A.transform, input, 'quantize', { grid_ppq = 120, strength = 1 })
  eq(input, copy, 'refused operation does not mutate input')
  eq(#decode(input), #decode(copy), 'refused operation does not rewrite events')
end

-- 13. Generation adds notes without erasing existing ones, terminator last.
do
  local input = fixture({ with_expression = false, with_unknown = false })
  local before = #decode(input)
  local output = A.generate(input, 'euclidean', {
    range_start = 240, range_end = 480,
    steps = 8, pulses = 4, step_ppq = 30, note_length = 15,
    pitch = 72, vel = 100, channel = 0, release_velocity = 0,
    mode = 'add',
  })
  local events = decode(output)
  local generated = find_message(events, 0x90, 72)
  eq(#generated, 4, 'euclidean generated four hits')
  eq(#find_message(events, 0x90, 60) + #find_message(events, 0x90, 64), 2,
    'generation keeps existing notes')
  eq(#events, before + 8, 'generation adds exactly its notes')
  local tail = events[#events]
  eq(tail.msg, '', 'generation keeps a final terminator')
  check(tail.pos >= events[#events - 1].pos,
    'terminator stays after generated events')
end

-- 14. Explicit replace removes only notes starting inside the range.
do
  local input = fixture({ with_expression = false, with_unknown = false })
  local output = A.generate(input, 'euclidean', {
    range_start = 0, range_end = 120,
    steps = 4, pulses = 2, step_ppq = 30, note_length = 15,
    pitch = 72, vel = 100, channel = 0, release_velocity = 0,
    mode = 'replace',
  })
  local events = decode(output)
  eq(#find_message(events, 0x90, 60), 0, 'replace removed the C4 note')
  eq(#find_message(events, 0x90, 64), 0, 'replace removed the E4 note in range')
  eq(#find_message(events, 0x90, 72), 2, 'replace installed generated notes')
  eq(events[#events].msg, '', 'replace keeps the terminator')
end

-- 15. Generation refuses expression data and requires an explicit range.
do
  local input = fixture()
  expect_error(function()
    A.generate(input, 'rhythm', {
      range_start = 0, range_end = 480, steps = 8, density = 4,
      note_length = 30, pitches = { 72 }, step_ppq = 60,
    })
  end, 'Blocked:', 'generation refuses expression data')
  expect_error(function()
    A.generate(input, 'rhythm', {
      steps = 8, density = 4, note_length = 30, pitches = { 72 },
    })
  end, 'explicit generation range', 'generation requires range')
  expect_error(function()
    A.generate(fixture({ with_expression = false, with_unknown = false }),
      'rhythm', {
        range_start = 0, range_end = 480, steps = 8, density = 4,
        note_length = 30, pitches = { 60 }, step_ppq = 60,
      })
  end, 'overlap', 'add mode refuses a collision instead of erasing')
end

-- 16. Core.transform interception delegates legacy tools without recursion.
do
  local input = fixture()
  local before = A.transform(input, 'transpose', { amount = 1 })
  A.install(C)
  local after = C.transform(input, 'transpose', { amount = 1 })
  eq(after, before, 'C.transform interception matches direct adapter call')
  local changed = C.transform(
    fixture({ with_expression = false, with_unknown = false }), 'chop', { parts = 2 })
  eq(#find_message(decode(changed), 0x90, 60), 2, 'interception routes new tools')
end

-- 17. QN <-> PPQ helpers use the configured resolution.
do
  eq(A.qn_to_ppq(0.25), 240, 'quarter of a quarter note is 240 PPQ at 960')
  eq(A.ppq_to_qn(480), 0.5, '480 PPQ is half a quarter note')
end

return { passed = passed }
