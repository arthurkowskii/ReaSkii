-- Standalone tests for scripts/midi/ReaSkii_MIDI_Expression.lua.
-- Pure Lua 5.4. No host API, no gfx, no I/O beyond dofile.
-- Run: python3 /home/randomaccessmemories/.hermes/cache/scratch/lua54_run.py \
--        tests/midi_expression_unit.lua
-- Prints ASSERTIONS=<count> and returns {passed=<count>}.

local script_path = debug.getinfo(1, 'S').source:sub(2)
local directory = script_path:match('^(.*[/\\])') or './'
local E = assert(dofile(directory .. '../scripts/midi/ReaSkii_MIDI_Expression.lua'))

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
local function decode(raw)
  local events, offset, pos = {}, 1, 0
  while offset <= #raw do
    local delta, flags, message
    delta, flags, message, offset = string.unpack('i4Bs4', raw, offset)
    pos = pos + delta
    events[#events + 1] = {
      pos = pos, flags = flags, msg = message, id = #events + 1,
    }
  end
  return events
end
local function raw_of(list)
  local sorted = {}
  for index, item in ipairs(list) do
    sorted[index] = {
      pos = item.pos, flags = item.flags, msg = item.msg, order = index,
    }
  end
  table.sort(sorted, function(a, b)
    if a.pos ~= b.pos then return a.pos < b.pos end
    return a.order < b.order
  end)
  local parts, previous = {}, 0
  for _, item in ipairs(sorted) do
    parts[#parts + 1] = event(item.pos - previous, item.flags, item.msg)
    previous = item.pos
  end
  return table.concat(parts)
end
local function note_on(channel, pitch, velocity)
  return string.char(0x90 | channel, pitch, velocity)
end
local function note_off(channel, pitch, release)
  return string.char(0x80 | channel, pitch, release)
end
local function cc(channel, controller, value)
  return string.char(0xB0 | channel, controller, value)
end
local function pressure(channel, value)
  return string.char(0xD0 | channel, value)
end
local function bend(channel, value)
  return string.char(0xE0 | channel, value & 0x7F, (value >> 7) & 0x7F)
end
local function bend_value(message)
  return message:byte(2) | (message:byte(3) << 7)
end
local function find(events, predicate)
  local found = {}
  for _, item in ipairs(events) do
    if predicate(item) then found[#found + 1] = item end
  end
  return found
end
local function by_message(events, message)
  return find(events, function(item) return item.msg == message end)
end
local function by_channel_dimension(events, channel, dimension)
  return find(events, function(item)
    if #item.msg < 2 then return false end
    local status = item.msg:byte(1)
    if (status & 15) ~= channel then return false end
    local kind = status & 0xF0
    if dimension == 'pitch' then return kind == 0xE0 end
    if dimension == 'slide' then
      return kind == 0xB0 and item.msg:byte(2) == 74
    end
    return kind == 0xD0
  end)
end
local function is_integral(events)
  for _, item in ipairs(events) do
    if item.pos % 1 ~= 0 then return false end
  end
  return true
end
local function terminator_is_last(events)
  local last = events[#events]
  if last.msg ~= '' then return false end
  for index = 1, #events - 1 do
    if events[index].pos > last.pos then return false end
  end
  return true
end

-- Three notes on separate channels. Only channel 1 carries the selected flag.
-- Existing expression on channels 2 and 3 must remain byte-identical.
local function chord_fixture()
  return raw_of({
    { pos = 0, flags = 1, msg = note_on(1, 60, 100) },
    { pos = 0, flags = 0, msg = note_on(2, 64, 90) },
    { pos = 0, flags = 0, msg = note_on(3, 67, 80) },
    { pos = 10, flags = 0, msg = bend(2, 8192) },
    { pos = 20, flags = 0, msg = cc(3, 74, 22) },
    { pos = 30, flags = 0, msg = pressure(2, 33) },
    { pos = 60, flags = 0, msg = cc(1, 74, 55) },
    { pos = 61, flags = 0, msg = bend(3, 8192) },
    { pos = 62, flags = 0, msg = cc(1, 7, 77) },
    { pos = 63, flags = 0, msg = string.char(0xF0, 0x7D, 0x01, 0xF7) },
    { pos = 64, flags = 0, msg = string.char(0xFF, 0x0F, 0x52, 0x65, 0x61) },
    { pos = 100, flags = 0, msg = note_off(1, 60, 37) },
    { pos = 100, flags = 0, msg = note_off(2, 64, 20) },
    { pos = 100, flags = 0, msg = note_off(3, 67, 21) },
    { pos = 480, flags = 0, msg = '' },
  })
end

-- 1. Pitch on the selected channel only.
do
  local input = chord_fixture()
  local output = E.transform(input, 'pitch', {
    points = { { t = 0, value = 8192 }, { t = 1, value = 12000 } },
    steps = 5,
  })
  local events = decode(output)
  local selected_pitch = by_channel_dimension(events, 1, 'pitch')
  eq(#selected_pitch, 5, 'pitch writes five points on the selected channel')
  eq(bend_value(selected_pitch[1].msg), 8192, 'pitch starts at the centre')
  eq(bend_value(selected_pitch[#selected_pitch].msg), 12000, 'pitch reaches the end value')
  eq(#by_channel_dimension(events, 2, 'pitch'), 1, 'pitch leaves channel 2 bend count')
  eq(by_channel_dimension(events, 2, 'pitch')[1].msg, bend(2, 8192),
    'pitch leaves channel 2 bend bytes')
  eq(#by_channel_dimension(events, 3, 'pitch'), 1, 'pitch leaves channel 3 bend count')
  eq(by_channel_dimension(events, 3, 'pitch')[1].msg, bend(3, 8192),
    'pitch leaves channel 3 bend bytes')
  eq(by_message(events, cc(3, 74, 22))[1].msg, cc(3, 74, 22),
    'pitch leaves unrelated CC74 bytes')
  eq(by_message(events, pressure(2, 33))[1].msg, pressure(2, 33),
    'pitch leaves unrelated pressure bytes')
  eq(by_message(events, cc(1, 7, 77))[1].msg, cc(1, 7, 77),
    'pitch leaves unrelated CC7 bytes')
  eq(by_message(events, string.char(0xF0, 0x7D, 0x01, 0xF7))[1].msg,
    string.char(0xF0, 0x7D, 0x01, 0xF7), 'pitch leaves SysEx bytes')
  eq(by_message(events, string.char(0xFF, 0x0F, 0x52, 0x65, 0x61))[1].msg,
    string.char(0xFF, 0x0F, 0x52, 0x65, 0x61), 'pitch leaves text bytes')
  eq(by_message(events, note_off(1, 60, 37))[1].msg:byte(3), 37,
    'pitch preserves release velocity')
  eq(by_message(events, note_on(1, 60, 100))[1].flags & 1, 1,
    'pitch preserves the selected note flag')
  check(terminator_is_last(events), 'pitch keeps the final terminator last')
  check(is_integral(events), 'pitch emits integer PPQ positions')
  local first_on, first_bend
  for index, item in ipairs(events) do
    if item.pos == 0 and item.msg == note_on(1, 60, 100) then first_on = index end
    if item.pos == 0 and item.msg == bend(1, 8192) then first_bend = index end
  end
  check(first_on and first_bend and first_on < first_bend,
    'note-on sorts before generated expression at the same tick')
end

-- 2. Slide on the selected channel only; replace removes its CC74 in-window.
do
  local input = chord_fixture()
  local output = E.transform(input, 'slide', {
    points = { { t = 0, value = 0 }, { t = 1, value = 127 } },
    steps = 3,
  })
  local events = decode(output)
  local selected_slide = by_channel_dimension(events, 1, 'slide')
  eq(#selected_slide, 3, 'slide writes three points on the selected channel')
  eq(selected_slide[1].msg:byte(3), 0, 'slide starts at zero')
  eq(selected_slide[#selected_slide].msg:byte(3), 127, 'slide reaches 127')
  eq(#by_channel_dimension(events, 3, 'slide'), 1, 'slide leaves channel 3 CC74 count')
  eq(by_channel_dimension(events, 3, 'slide')[1].msg, cc(3, 74, 22),
    'slide leaves channel 3 CC74 bytes')
  eq(#by_channel_dimension(events, 2, 'pitch'), 1, 'slide leaves channel 2 bend intact')
  eq(by_channel_dimension(events, 2, 'pitch')[1].msg, bend(2, 8192),
    'slide leaves channel 2 bend bytes')
  eq(by_message(events, cc(1, 7, 77))[1].msg, cc(1, 7, 77),
    'slide leaves other CC bytes')
  eq(by_message(events, note_off(1, 60, 37))[1].msg:byte(3), 37,
    'slide preserves release velocity')
  check(terminator_is_last(events), 'slide keeps the final terminator last')
end

-- 3. Channel pressure on the selected channel only.
do
  local input = chord_fixture()
  local output = E.transform(input, 'pressure', {
    points = { { t = 0, value = 10 }, { t = 1, value = 100 } },
    steps = 3,
  })
  local events = decode(output)
  local selected_pressure = by_channel_dimension(events, 1, 'pressure')
  eq(#selected_pressure, 3, 'pressure writes three points on the selected channel')
  eq(selected_pressure[1].msg:byte(2), 10, 'pressure starts at 10')
  eq(selected_pressure[#selected_pressure].msg:byte(2), 100, 'pressure reaches 100')
  eq(#by_channel_dimension(events, 2, 'pressure'), 1,
    'pressure leaves channel 2 pressure count')
  eq(by_channel_dimension(events, 2, 'pressure')[1].msg, pressure(2, 33),
    'pressure leaves channel 2 pressure bytes')
  eq(#by_channel_dimension(events, 1, 'pitch'), 0,
    'pressure does not create pitch events')
  eq(#by_channel_dimension(events, 1, 'slide'), 1,
    'pressure leaves the existing in-window CC74 alone')
  eq(by_message(events, note_off(1, 60, 37))[1].msg:byte(3), 37,
    'pressure preserves release velocity')
  check(terminator_is_last(events), 'pressure keeps the final terminator last')
end

-- 4. Same-channel overlap is refused before any output can be produced.
do
  local input = raw_of({
    { pos = 0, flags = 1, msg = note_on(1, 60, 100) },
    { pos = 50, flags = 0, msg = note_on(1, 64, 90) },
    { pos = 100, flags = 0, msg = note_off(1, 60, 37) },
    { pos = 150, flags = 0, msg = note_off(1, 64, 20) },
    { pos = 480, flags = 0, msg = '' },
  })
  local snapshot = input
  expect_error(function()
    E.transform(input, 'pitch', {
      points = { { t = 0, value = 8192 }, { t = 1, value = 9000 } },
    })
  end, 'ambiguous', 'same-channel overlap is refused')
  eq(input, snapshot, 'overlap refusal leaves the source string unchanged')
  eq(#decode(input), 5, 'overlap refusal does not truncate the source')
end

-- 5. A contiguous same-channel boundary is refused, a one-tick gap is allowed.
do
  local function boundary(second_start)
    return raw_of({
      { pos = 0, flags = 1, msg = note_on(1, 60, 100) },
      { pos = second_start, flags = 0, msg = note_on(1, 64, 90) },
      { pos = 100, flags = 0, msg = note_off(1, 60, 37) },
      { pos = 200, flags = 0, msg = note_off(1, 64, 20) },
      { pos = 480, flags = 0, msg = '' },
    })
  end
  expect_error(function()
    E.transform(boundary(100), 'pitch', {
      points = { { t = 0, value = 8192 }, { t = 1, value = 9000 } },
    })
  end, 'contiguous', 'contiguous same-channel boundary is refused')
  local output = E.transform(boundary(101), 'pitch', {
    points = { { t = 0, value = 8192 }, { t = 1, value = 9000 } },
    steps = 3,
  })
  eq(#by_channel_dimension(decode(output), 1, 'pitch'), 3,
    'a one-tick gap permits the expression curve')
end

-- 6. Master channel and out-of-zone selections are refused.
do
  local master = raw_of({
    { pos = 0, flags = 1, msg = note_on(0, 60, 100) },
    { pos = 100, flags = 0, msg = note_off(0, 60, 37) },
    { pos = 480, flags = 0, msg = '' },
  })
  expect_error(function()
    E.transform(master, 'pitch', {
      points = { { t = 0, value = 8192 }, { t = 1, value = 9000 } },
    })
  end, 'master channel', 'selected master-channel note is refused')
  expect_error(function()
    E.transform(master, 'pitch', {
      points = { { t = 0, value = 8192 }, { t = 1, value = 9000 } },
      member_channels = { 0, 1 },
    })
  end, 'master channel', 'master channel in member_channels is refused')

  local on_two = raw_of({
    { pos = 0, flags = 1, msg = note_on(2, 60, 100) },
    { pos = 100, flags = 0, msg = note_off(2, 60, 37) },
    { pos = 480, flags = 0, msg = '' },
  })
  expect_error(function()
    E.transform(on_two, 'pitch', {
      points = { { t = 0, value = 8192 }, { t = 1, value = 9000 } },
      member_channels = { 1, 3 },
    })
  end, 'outside options.member_channels', 'selected note outside the zone is refused')
  expect_error(function()
    E.transform(on_two, 'pitch', {
      points = { { t = 0, value = 8192 }, { t = 1, value = 9000 } },
      member_channels = { 1, 1, 2 },
    })
  end, 'Duplicate member channel', 'duplicate member channels are refused')
end

-- 7. Integer PPQ rounding, exact linear values, release velocity and flags.
do
  local input = raw_of({
    { pos = 0, flags = 1, msg = note_on(1, 60, 100) },
    { pos = 10, flags = 0, msg = note_off(1, 60, 37) },
    { pos = 100, flags = 0, msg = '' },
  })
  local output = E.transform(input, 'pitch', {
    points = { { t = 0, value = 8192 }, { t = 1, value = 9000 } },
    steps = 4,
  })
  local events = decode(output)
  local generated = by_channel_dimension(events, 1, 'pitch')
  eq(#generated, 4, 'four rounded samples are emitted')
  local positions, values = {}, {}
  for index, item in ipairs(generated) do
    positions[index] = item.pos
    values[index] = bend_value(item.msg)
  end
  eq(table.concat(positions, ','), '0,3,6,9', 'PPQ samples round to whole ticks')
  eq(values[1], 8192, 'first rounded sample is exact')
  eq(values[2], 8461, 'second rounded sample uses half-up rounding')
  eq(values[3], 8731, 'third rounded sample uses half-up rounding')
  eq(values[4], 9000, 'last rounded sample is exact')
  local off = by_message(events, note_off(1, 60, 37))[1]
  eq(off.msg:byte(3), 37, 'note-off release velocity is preserved after rounding')
  eq(by_message(events, note_on(1, 60, 100))[1].flags & 1, 1,
    'note-on selected flag is preserved after rounding')
  check(terminator_is_last(events), 'rounded curve keeps the terminator last')
end

-- 8. Stable deduplication on a short note: later samples win, ticks stay unique.
do
  local input = raw_of({
    { pos = 0, flags = 1, msg = note_on(1, 60, 100) },
    { pos = 3, flags = 0, msg = note_off(1, 60, 37) },
    { pos = 100, flags = 0, msg = '' },
  })
  local output = E.transform(input, 'slide', {
    points = { { t = 0, value = 0 }, { t = 1, value = 127 } },
    steps = 10,
  })
  local generated = by_channel_dimension(decode(output), 1, 'slide')
  eq(#generated, 3, 'dedup keeps one event per rounded tick')
  eq(generated[1].pos, 0, 'dedup first tick is the note start')
  eq(generated[2].pos, 1, 'dedup second tick is unique')
  eq(generated[3].pos, 2, 'dedup stays before the note-off')
  eq(generated[#generated].msg:byte(3), 127, 'dedup keeps the final sample value')
end

-- 9. Invalid points, NaN/inf, invalid options and bounded values.
do
  local input = chord_fixture()
  local snapshot = input
  expect_error(function()
    E.transform(input, 'pitch', {
      points = { { t = 0, value = 8192 }, { t = 1, value = 20000 } },
    })
  end, 'outside pitch range', 'pitch value above range is refused')
  eq(input, snapshot, 'invalid pitch leaves the source unchanged')
  expect_error(function()
    E.transform(input, 'slide', {
      points = { { t = 0, value = 0 }, { t = 1, value = 128 } },
    })
  end, 'outside slide range', 'slide value above range is refused')
  expect_error(function()
    E.transform(input, 'pressure', {
      points = { { t = 0, value = -1 }, { t = 1, value = 10 } },
    })
  end, 'outside pressure range', 'negative pressure is refused')
  expect_error(function()
    E.transform(input, 'pitch', {
      points = { { t = 0, value = 8192 }, { t = 0, value = 9000 } },
    })
  end, 'strictly increase', 'non-increasing point times are refused')
  expect_error(function()
    E.transform(input, 'pitch', {
      points = { { t = 0, value = 8192 }, { t = 1.1, value = 9000 } },
    })
  end, 'Invalid point time', 'point time above one is refused')
  expect_error(function()
    E.transform(input, 'pitch', {
      points = { { t = 0, value = 8192 }, { t = 1, value = 0 / 0 } },
    })
  end, 'Point value', 'NaN point value is refused')
  expect_error(function()
    E.transform(input, 'pitch', {
      points = { { t = 0, value = 8192 }, { t = 1, value = math.huge } },
    })
  end, 'Point value', 'infinite point value is refused')
  expect_error(function()
    E.transform(input, 'pitch', {
      points = { { t = 0, value = 8192 }, { t = 1, value = 9000 } },
      steps = 1,
    })
  end, 'Invalid expression steps', 'steps below two are refused')
  expect_error(function()
    E.transform(input, 'pitch', {
      points = { { t = 0, value = 8192 }, { t = 1, value = 9000 } },
      steps = 1025,
    })
  end, 'Invalid expression steps', 'steps above 1024 are refused')
  expect_error(function()
    E.transform(input, 'pitch', {
      points = { { t = 0, value = 8192 }, { t = 1, value = 9000 } },
      steps = 2.5,
    })
  end, 'Invalid expression steps', 'fractional steps are refused')
  expect_error(function()
    E.transform(input, 'pitch', {
      points = { { t = 0, value = 8192 }, { t = 1, value = 9000 } },
      shape = 'bogus',
    })
  end, 'Invalid expression shape', 'unknown shape is refused')
  expect_error(function()
    E.transform(input, 'pitch', {
      points = { { t = 0, value = 8192 } },
    })
  end, 'at least two points', 'a single point is refused')
  expect_error(function()
    E.transform(input, 'pitch', { points = {}, steps = 2 })
  end, 'at least two points', 'an empty point list is refused')
  expect_error(function()
    E.transform(input, 'pitch', { points = 'x' })
  end, 'explicit point list', 'a non-table point list is refused')
  local bounded = E.transform(input, 'pitch', {
    points = { { t = 0, value = 0 }, { t = 1, value = 16383 } },
    steps = 7,
  })
  local values_ok = true
  for _, item in ipairs(by_channel_dimension(decode(bounded), 1, 'pitch')) do
    local value = bend_value(item.msg)
    if value < 0 or value > 16383 then values_ok = false end
  end
  check(values_ok, 'generated pitch values stay within 0..16383')
end

-- 10. An event-budget explosion is refused and the source is untouched.
do
  local fixture = {}
  for index = 0, 127 do
    local start_pos = index * 200
    fixture[#fixture + 1] = {
      pos = start_pos, flags = 1, msg = note_on(1, 60, 100),
    }
    fixture[#fixture + 1] = {
      pos = start_pos + 100, flags = 0, msg = note_off(1, 60, 37),
    }
  end
  fixture[#fixture + 1] = { pos = 128 * 200, flags = 0, msg = '' }
  local input = raw_of(fixture)
  local snapshot = input
  expect_error(function()
    E.transform(input, 'pitch', {
      points = { { t = 0, value = 8192 }, { t = 1, value = 9000 } },
      steps = 1024,
    })
  end, 'event budget exceeded', 'event explosion is refused before generation')
  eq(input, snapshot, 'event explosion leaves the source string unchanged')
end

-- 11. Repeated replace calls do not accumulate.
do
  local input = raw_of({
    { pos = 0, flags = 1, msg = note_on(1, 60, 100) },
    { pos = 0, flags = 0, msg = bend(1, 8192) },
    { pos = 50, flags = 0, msg = bend(1, 10000) },
    { pos = 99, flags = 0, msg = bend(1, 12000) },
    { pos = 100, flags = 0, msg = note_off(1, 60, 37) },
    { pos = 200, flags = 0, msg = '' },
  })
  local options = {
    points = { { t = 0, value = 8192 }, { t = 1, value = 4000 } },
    steps = 5,
  }
  local first = E.transform(input, 'pitch', options)
  local second = E.transform(first, 'pitch', options)
  eq(first, second, 'repeated replace is byte-identical')
  local generated = by_channel_dimension(decode(second), 1, 'pitch')
  eq(#generated, 5, 'repeated replace keeps exactly five points')
  eq(bend_value(generated[1].msg), 8192, 'repeated replace keeps the first value')
  eq(bend_value(generated[#generated].msg), 4000, 'repeated replace does not accumulate')
end

-- 12. Add mode uses the explicit offset contract.
do
  local input = raw_of({
    { pos = 0, flags = 1, msg = note_on(1, 60, 100) },
    { pos = 0, flags = 0, msg = bend(1, 8192) },
    { pos = 10, flags = 0, msg = note_off(1, 60, 37) },
    { pos = 100, flags = 0, msg = '' },
  })
  local output = E.transform(input, 'pitch', {
    points = { { t = 0, value = 8192 }, { t = 1, value = 8500 } },
    steps = 2, mode = 'add',
  })
  local generated = by_channel_dimension(decode(output), 1, 'pitch')
  eq(#generated, 2, 'add mode merges with the existing event and adds one')
  eq(bend_value(generated[1].msg), 8192, 'add mode zero offset keeps the baseline')
  eq(bend_value(generated[2].msg), 8500, 'add mode adds the explicit pitch offset')
end

-- 13. Glissando and LFO helpers build points and reuse transform.
do
  local input = raw_of({
    { pos = 0, flags = 1, msg = note_on(1, 60, 100) },
    { pos = 10, flags = 0, msg = note_off(1, 60, 37) },
    { pos = 100, flags = 0, msg = '' },
  })
  local glide = E.glissando(input, 'pitch', { from = 8192, to = 9000, steps = 3 })
  local glide_points = by_channel_dimension(decode(glide), 1, 'pitch')
  eq(#glide_points, 3, 'glissando emits three points')
  eq(bend_value(glide_points[#glide_points].msg), 9000,
    'glissando reaches its end value')

  local lfo = E.lfo(input, 'pitch', {
    center = 8192, amplitude = 100, cycles = 1, samples = 5,
  })
  local lfo_points = by_channel_dimension(decode(lfo), 1, 'pitch')
  eq(#lfo_points, 5, 'LFO emits one point per sample')
  eq(bend_value(lfo_points[1].msg), 8192, 'LFO starts at its centre')
  eq(bend_value(lfo_points[2].msg), 8292, 'LFO reaches its positive peak')
  eq(bend_value(lfo_points[4].msg), 8092, 'LFO reaches its negative peak')
  check(terminator_is_last(decode(lfo)), 'LFO keeps the terminator last')
end

-- 14. No selected note returns the exact input string, even with bad options.
do
  local input = raw_of({
    { pos = 0, flags = 0, msg = note_on(1, 60, 100) },
    { pos = 100, flags = 0, msg = note_off(1, 60, 37) },
    { pos = 480, flags = 0, msg = '' },
  })
  eq(E.transform(input, 'pitch', { points = 'invalid' }), input,
    'empty selection returns the exact raw string')
  eq(E.transform(input, 'pitch', { steps = 0 }), input,
    'empty selection ignores invalid options')
end

print('ASSERTIONS=' .. passed)
return { passed = passed }
