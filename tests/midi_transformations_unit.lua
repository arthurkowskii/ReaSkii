-- Standalone unit tests for ReaSkii_MIDI_Transformations.lua.
-- Pure Lua 5.4. Run from any directory:
--   lua5.4 tests/midi_transformations_unit.lua
-- Also executable under LuaJIT/nvim for local checking. Returns {passed=N}.
local source = debug.getinfo(1, 'S').source
local script_path = source:sub(1, 1) == '@' and source:sub(2) or source
local script_dir = script_path:match('^(.*)[/\\][^/\\]*$') or '.'
local module_path = script_dir
  .. '/../scripts/midi/ReaSkii_MIDI_Transformations.lua'
local T = assert(dofile(module_path))
local passed = 0

local function check(condition, name)
  if not condition then error('FAIL: ' .. name, 2) end
  passed = passed + 1
end

local function expect_error(fn, name)
  local ok = pcall(fn)
  check(not ok, name)
end

local function make(overrides)
  local note = {
    startppq = 0,
    endppq = 120,
    pitch = 60,
    vel = 100,
    channel = 0,
    selected = true,
    muted = false,
    id = 'id',
    release_velocity = 64,
  }
  for key, value in pairs(overrides or {}) do note[key] = value end
  return note
end

local function snapshot(note)
  local copy = {}
  for key, value in pairs(note) do copy[key] = value end
  return copy
end

local function same_fields(a, b)
  local keys_a, keys_b = {}, {}
  for key in pairs(a) do keys_a[#keys_a + 1] = key end
  for key in pairs(b) do keys_b[#keys_b + 1] = key end
  table.sort(keys_a)
  table.sort(keys_b)
  if #keys_a ~= #keys_b then return false end
  for index = 1, #keys_a do
    if keys_a[index] ~= keys_b[index] then return false end
    if a[keys_a[index]] ~= b[keys_b[index]] then return false end
  end
  return true
end

local function by_pitch(list, pitch)
  for _, note in ipairs(list) do
    if note.pitch == pitch then return note end
  end
  return nil
end

local function near(a, b, epsilon)
  return math.abs(a - b) <= (epsilon or 1e-9)
end

local function signature(list)
  local parts = {}
  for _, note in ipairs(list) do
    parts[#parts + 1] = table.concat({
      string.format('%.9f', note.startppq),
      string.format('%.9f', note.endppq),
      tostring(note.pitch),
      tostring(note.vel),
      tostring(note.channel),
      tostring(note.selected),
      tostring(note.muted),
      tostring(note.id),
      tostring(note.release_velocity),
    }, '|')
  end
  return table.concat(parts, ';')
end

-- Empty input.
do
  local out = T.apply({}, 'quantize', { grid_ppq = 120, strength = 1 })
  check(#out == 0, 'empty input returns an empty list')
  out = T.apply({}, 'arpeggiate', {
    mode = 'up', rate_ppq = 120, gate = 1, octaves = 1,
    range_start = 0, range_end = 480,
  })
  check(#out == 0, 'empty input works for arpeggiate too')
end

-- Unselected notes are copied, not mutated; selected notes change.
do
  local a = make({ startppq = 0, endppq = 100, pitch = 60,
    selected = false, id = 'a', extra = { x = 1 } })
  local b = make({ startppq = 200, endppq = 300, pitch = 64,
    selected = true, id = 'b' })
  local before_a, before_b = snapshot(a), snapshot(b)
  local out = T.apply({ a, b }, 'invert', { pivot = 60 })
  check(#out == 2, 'invert keeps the note count')
  check(out[1] ~= a and same_fields(out[1], a),
    'unselected note is copied with identical fields')
  check(out[1].extra == a.extra, 'extra fields are copied shallowly')
  check(out[2].pitch == 56, 'selected note is inverted')
  check(same_fields(a, before_a) and same_fields(b, before_b),
    'input tables are never mutated')
end

-- Quantize: nearest grid, strength, duration, ternary grid, collision.
do
  local note = make({ startppq = 70, endppq = 190, pitch = 62 })
  local out = T.apply({ note }, 'quantize', { grid_ppq = 120, strength = 1 })
  check(out[1].startppq == 120 and out[1].endppq == 240,
    'quantize moves to nearest grid and preserves duration')

  local tie = make({ startppq = 60, endppq = 120, pitch = 62 })
  out = T.apply({ tie }, 'quantize', { grid_ppq = 120, strength = 1 })
  check(out[1].startppq == 0 and out[1].endppq == 60,
    'quantize tie goes to the lower grid point')

  local half = make({ startppq = 30, endppq = 90, pitch = 62 })
  out = T.apply({ half }, 'quantize', { grid_ppq = 120, strength = 0.5 })
  check(out[1].startppq == 15 and out[1].endppq == 75,
    'quantize strength only moves partway')

  local ternary = make({ startppq = 79, endppq = 159, pitch = 62 })
  out = T.apply({ ternary }, 'quantize', { grid_ppq = 80, strength = 1 })
  check(out[1].startppq == 80 and out[1].endppq == 160,
    'ternary grid is supported')

  local unselected = make({ startppq = 70, endppq = 190, pitch = 60,
    selected = false })
  local selected = make({ startppq = 70, endppq = 190, pitch = 62 })
  out = T.apply({ unselected, selected }, 'quantize',
    { grid_ppq = 120, strength = 1 })
  check(out[1].startppq == 70 and out[2].startppq == 120,
    'quantize only touches the selection')

  local blocker = make({ startppq = 120, endppq = 200, pitch = 60,
    selected = false, id = 'quantize-blocker' })
  expect_error(function()
    T.apply({ make({ startppq = 110, endppq = 160, pitch = 60 }),
      blocker }, 'quantize', { grid_ppq = 120, strength = 1 })
  end, 'quantize rejects a collision with an unselected note')

  expect_error(function()
    T.apply({ make({}) }, 'quantize', { grid_ppq = 0, strength = 1 })
  end, 'quantize rejects a zero grid')
  expect_error(function()
    T.apply({ make({}) }, 'quantize', { grid_ppq = 120, strength = 1.1 })
  end, 'quantize rejects strength above one')
end

-- Reverse inside an explicit range.
do
  local note = make({ startppq = 100, endppq = 220, pitch = 60 })
  local out = T.apply({ note }, 'reverse',
    { range_start = 0, range_end = 480 })
  check(out[1].startppq == 260 and out[1].endppq == 380,
    'reverse mirrors start and end in the range')
  check(out[1].release_velocity == 64, 'reverse preserves release velocity')

  local full = make({ startppq = 0, endppq = 480, pitch = 62 })
  out = T.apply({ full }, 'reverse', { range_start = 0, range_end = 480 })
  check(out[1].startppq == 0 and out[1].endppq == 480,
    'a note filling the range is unchanged')

  expect_error(function()
    T.apply({ make({ startppq = 10, endppq = 500 }) }, 'reverse',
      { range_start = 0, range_end = 480 })
  end, 'reverse rejects a note crossing the range end')
  expect_error(function()
    T.apply({ make({}) }, 'reverse',
      { range_start = 480, range_end = 0 })
  end, 'reverse rejects an inverted range')
end

-- Stretch around an explicit anchor.
do
  local note = make({ startppq = 60, endppq = 120, pitch = 60 })
  local out = T.apply({ note }, 'stretch', { factor = 2, anchor = 0 })
  check(out[1].startppq == 120 and out[1].endppq == 240,
    'stretch scales around zero')
  out = T.apply({ note }, 'stretch', { factor = 0.5, anchor = 100 })
  check(out[1].startppq == 80 and out[1].endppq == 110,
    'stretch scales around a non-zero anchor')
  expect_error(function()
    T.apply({ note }, 'stretch', { factor = 0, anchor = 0 })
  end, 'stretch rejects a zero factor')
  expect_error(function()
    T.apply({ note }, 'stretch', { factor = 1, anchor = -1 })
  end, 'stretch rejects a negative anchor')
end

-- Chop: equal contiguous parts, field preservation, unique ids.
do
  local note = make({ startppq = 10, endppq = 310, pitch = 60,
    vel = 90, channel = 3, release_velocity = 37, id = 'chop-source' })
  local before = snapshot(note)
  local out = T.apply({ note }, 'chop', { parts = 3 })
  check(#out == 3, 'chop produces the requested number of parts')
  check(out[1].startppq == 10 and out[1].endppq == 110,
    'chop part one bounds')
  check(out[2].startppq == 110 and out[2].endppq == 210,
    'chop part two bounds')
  check(out[3].startppq == 210 and out[3].endppq == 310,
    'chop part three bounds')
  for _, part in ipairs(out) do
    check(part.pitch == 60 and part.vel == 90 and part.channel == 3,
      'chop preserves pitch, velocity and channel')
    check(part.release_velocity == 37,
      'chop preserves release velocity')
    check(part.selected == true, 'chop parts stay selected')
    check(part.id ~= 'chop-source', 'chop parts get deterministic new ids')
  end
  check(out[1].id ~= out[2].id and out[2].id ~= out[3].id,
    'chop ids are unique per part')
  check(same_fields(note, before), 'chop does not mutate its input')
  expect_error(function()
    T.apply({ make({}) }, 'chop', { parts = 1 })
  end, 'chop rejects one part')
  expect_error(function()
    T.apply({ make({}) }, 'chop', { parts = 65 })
  end, 'chop rejects more than 64 parts')
end

-- Arpeggiate: styles, octaves, gate, range, limits, collisions.
do
  local c = make({ startppq = 0, endppq = 480, pitch = 60, vel = 90,
    id = 'c' })
  local e = make({ startppq = 0, endppq = 480, pitch = 64, vel = 91,
    id = 'e' })
  local g = make({ startppq = 0, endppq = 480, pitch = 67, vel = 92,
    id = 'g' })
  local base = { mode = 'up', rate_ppq = 120, gate = 1, octaves = 1,
    range_start = 0, range_end = 480 }

  local out = T.apply({ c, e, g }, 'arpeggiate', base)
  check(#out == 4, 'arpeggiate replaces the chord with generated notes')
  check(out[1].pitch == 60 and out[2].pitch == 64
    and out[3].pitch == 67 and out[4].pitch == 60,
    'arpeggiate up cycles low to high')
  check(out[1].startppq == 0 and out[2].startppq == 120
    and out[3].startppq == 240 and out[4].startppq == 360,
    'arpeggiate uses the requested rate')
  check(out[4].endppq == 480 and out[4].vel == 90,
    'arpeggiate clamps the last gate and copies the source velocity')
  check(out[1].release_velocity == 64,
    'arpeggiate preserves release velocity')
  check(out[1].selected == true, 'arpeggiate output stays selected')

  local down = { mode = 'down', rate_ppq = 120, gate = 1, octaves = 1,
    range_start = 0, range_end = 480 }
  out = T.apply({ c, e, g }, 'arpeggiate', down)
  check(out[1].pitch == 67 and out[4].pitch == 67,
    'arpeggiate down starts high')

  local updown = { mode = 'updown', rate_ppq = 120, gate = 1, octaves = 1,
    range_start = 0, range_end = 480 }
  out = T.apply({ c, e, g }, 'arpeggiate', updown)
  check(#out == 4 and out[1].pitch == 60 and out[2].pitch == 64
    and out[3].pitch == 67 and out[4].pitch == 64,
    'arpeggiate updown omits the repeated endpoint')

  local octaves = { mode = 'up', rate_ppq = 120, gate = 1, octaves = 2,
    range_start = 0, range_end = 720 }
  out = T.apply({ c, e, g }, 'arpeggiate', octaves)
  check(#out == 6 and out[4].pitch == 72 and out[6].pitch == 79,
    'arpeggiate expands octave copies')

  local short = { mode = 'up', rate_ppq = 120, gate = 1, octaves = 1,
    range_start = 0, range_end = 50 }
  out = T.apply({ c }, 'arpeggiate', short)
  check(#out == 1 and out[1].startppq == 0 and out[1].endppq == 50,
    'arpeggiate clamps a short range to the range end')

  local half_gate = { mode = 'up', rate_ppq = 120, gate = 0.5,
    octaves = 1, range_start = 0, range_end = 480 }
  out = T.apply({ c, e, g }, 'arpeggiate', half_gate)
  check(out[1].endppq == 60 and out[4].endppq == 420,
    'arpeggiate gate shortens notes')

  local no_selection = { make({ selected = false, pitch = 60 }) }
  out = T.apply(no_selection, 'arpeggiate', base)
  check(#out == 1 and same_fields(out[1], no_selection[1]),
    'arpeggiate with no selection is a copy')

  local high = make({ startppq = 0, endppq = 480, pitch = 120 })
  expect_error(function()
    T.apply({ high }, 'arpeggiate', {
      mode = 'up', rate_ppq = 120, gate = 1, octaves = 2,
      range_start = 0, range_end = 480,
    })
  end, 'arpeggiate rejects an octave beyond pitch 127')

  expect_error(function()
    T.apply({ c }, 'arpeggiate', {
      mode = 'up', rate_ppq = 1, gate = 1, octaves = 1,
      range_start = 0, range_end = 100000,
    })
  end, 'arpeggiate rejects note explosion')

  local blocker = make({ startppq = 120, endppq = 240, pitch = 64,
    selected = false, id = 'blocker' })
  expect_error(function()
    T.apply({ c, e, g, blocker }, 'arpeggiate', base)
  end, 'arpeggiate rejects a collision with an unselected note')

  expect_error(function()
    T.apply({ c }, 'arpeggiate', {
      mode = 'sideways', rate_ppq = 120, gate = 1, octaves = 1,
      range_start = 0, range_end = 480,
    })
  end, 'arpeggiate rejects an unknown mode')
  expect_error(function()
    T.apply({ c }, 'arpeggiate', {
      mode = 'up', rate_ppq = 120, gate = 0, octaves = 1,
      range_start = 0, range_end = 480,
    })
  end, 'arpeggiate rejects a zero gate')
end

-- Legato: next strictly later onset, per channel, never shortens.
do
  local a = make({ startppq = 0, endppq = 100, pitch = 60, channel = 0,
    id = 'a' })
  local b = make({ startppq = 120, endppq = 200, pitch = 62, channel = 0,
    selected = false, id = 'b' })
  local same_time = make({ startppq = 0, endppq = 50, pitch = 72,
    channel = 0, selected = false, id = 'same' })
  local c = make({ startppq = 0, endppq = 130, pitch = 64, channel = 1,
    id = 'c' })
  local d = make({ startppq = 90, endppq = 150, pitch = 65, channel = 1,
    selected = false, id = 'd' })
  local e = make({ startppq = 0, endppq = 80, pitch = 67, channel = 1,
    id = 'e' })
  local f = make({ startppq = 0, endppq = 100, pitch = 69, channel = 2,
    id = 'f' })
  local out = T.apply({ a, b, same_time, c, d, e, f }, 'legato', {})
  check(out[1].endppq == 120, 'legato extends to the next channel onset')
  check(out[3].endppq == 50, 'unselected notes are untouched by legato')
  check(out[4].endppq == 130, 'legato never shortens an overlapping note')
  check(out[6].endppq == 90, 'legato extends a second note on the same channel')
  check(out[7].endppq == 100, 'legato leaves a note with no successor alone')
  check(out[1].pitch == 60 and out[1].channel == 0,
    'legato preserves pitch and channel')

  local sustained = make({ startppq = 0, endppq = 110, pitch = 60,
    channel = 0, selected = false, id = 'sustained' })
  local next_note = make({ startppq = 120, endppq = 200, pitch = 62,
    channel = 0, selected = false, id = 'next' })
  expect_error(function()
    T.apply({ make({ startppq = 0, endppq = 100, pitch = 60, channel = 0 }),
      sustained, next_note }, 'legato', {})
  end, 'legato rejects an extension over an unselected same-pitch note')
end

-- Fit to scale: nearest, tie to lower, boundaries, errors.
do
  local major = { 0, 2, 4, 5, 7, 9, 11 }
  local function fit(pitch)
    local out = T.apply({ make({ pitch = pitch }) }, 'fit_scale',
      { root = 0, intervals = major })
    return out[1].pitch
  end
  check(fit(61) == 60, 'fit_scale tie goes to the lower pitch')
  check(fit(66) == 65, 'fit_scale handles another lower tie')
  check(fit(63) == 62, 'fit_scale snaps a chromatic pitch downward')
  check(fit(71) == 71, 'fit_scale leaves an in-scale pitch alone')
  check(fit(127) == 127, 'fit_scale respects pitch 127')
  check(fit(0) == 0, 'fit_scale respects pitch 0')
  check(fit(1) == 0, 'fit_scale handles the low boundary')

  local out = T.apply({ make({ pitch = 61, vel = 90, channel = 5,
    release_velocity = 33 }) }, 'fit_scale',
    { root = 0, intervals = major })
  check(out[1].vel == 90 and out[1].channel == 5
    and out[1].release_velocity == 33,
    'fit_scale preserves non-pitch fields')

  local unselected = make({ pitch = 61, selected = false })
  out = T.apply({ unselected }, 'fit_scale', { root = 0, intervals = major })
  check(out[1].pitch == 61, 'fit_scale only changes selected notes')

  expect_error(function()
    T.apply({ make({ pitch = 61 }) }, 'fit_scale',
      { root = 0, intervals = { 0, 2, 2 } })
  end, 'fit_scale rejects duplicate intervals')
  expect_error(function()
    T.apply({ make({ pitch = 61 }) }, 'fit_scale',
      { root = 0, intervals = { 0, 12 } })
  end, 'fit_scale rejects an interval above 11')
  expect_error(function()
    T.apply({ make({ pitch = 61 }) }, 'fit_scale',
      { root = 12, intervals = { 0 } })
  end, 'fit_scale rejects root 12')
  expect_error(function()
    T.apply({ make({ pitch = 61 }) }, 'fit_scale',
      { root = 0, intervals = {} })
  end, 'fit_scale rejects an empty scale')

  local blocker = make({ startppq = 0, endppq = 120, pitch = 60,
    selected = false })
  expect_error(function()
    T.apply({ make({ pitch = 61 }), blocker }, 'fit_scale',
      { root = 0, intervals = major })
  end, 'fit_scale rejects a pitch collision')
end

-- Invert: melodic inversion and MIDI bounds.
do
  local out = T.apply({ make({ pitch = 64 }), make({ pitch = 56 }) },
    'invert', { pivot = 60 })
  check(out[1].pitch == 56 and out[2].pitch == 64,
    'invert mirrors around the pivot')
  out = T.apply({ make({ pitch = 0 }) }, 'invert', { pivot = 60 })
  check(out[1].pitch == 120, 'invert reaches pitch 120 from 0')
  out = T.apply({ make({ pitch = 120 }) }, 'invert', { pivot = 60 })
  check(out[1].pitch == 0, 'invert reaches pitch 0 from 120')
  expect_error(function()
    T.apply({ make({ pitch = 1 }) }, 'invert', { pivot = 0 })
  end, 'invert rejects a result below pitch 0')
  expect_error(function()
    T.apply({ make({ pitch = 0 }) }, 'invert', { pivot = 127 })
  end, 'invert rejects a result above pitch 127')
  expect_error(function()
    T.apply({ make({}) }, 'invert', { pivot = 128 })
  end, 'invert rejects pivot 128')
end

-- Strum: equal spacing, tension curve, grouping, start-only movement.
do
  local function chord()
    return {
      make({ startppq = 0, endppq = 480, pitch = 60, vel = 90,
        release_velocity = 40, id = 'n60' }),
      make({ startppq = 0, endppq = 480, pitch = 64, vel = 91,
        release_velocity = 41, id = 'n64' }),
      make({ startppq = 0, endppq = 480, pitch = 67, vel = 92,
        release_velocity = 42, id = 'n67' }),
      make({ startppq = 0, endppq = 480, pitch = 71, vel = 93,
        release_velocity = 43, id = 'n71' }),
    }
  end

  local out = T.apply(chord(), 'strum', {
    low = 100, high = 0, grid_ppq = 120, tension = 0, onset_tolerance = 0,
  })
  check(by_pitch(out, 60).startppq == 120, 'strum low moves the lowest last')
  check(near(by_pitch(out, 64).startppq, 80), 'strum low spacing is equal')
  check(near(by_pitch(out, 67).startppq, 40), 'strum low spacing stays equal')
  check(by_pitch(out, 71).startppq == 0, 'strum leaves the highest in place')
  check(by_pitch(out, 60).endppq == 480
    and by_pitch(out, 60).release_velocity == 40,
    'strum moves starts only, keeping ends and release velocity')

  out = T.apply(chord(), 'strum', {
    low = 0, high = 100, grid_ppq = 120, tension = 0, onset_tolerance = 0,
  })
  check(by_pitch(out, 60).startppq == 0, 'strum high leaves the lowest in place')
  check(near(by_pitch(out, 64).startppq, 40), 'strum high spacing is equal')
  check(by_pitch(out, 71).startppq == 120, 'strum high moves the highest last')

  out = T.apply(chord(), 'strum', {
    low = 100, high = 0, grid_ppq = 120, tension = 1, onset_tolerance = 0,
  })
  local middle = by_pitch(out, 64).startppq
  check(math.abs(middle - 1920 / 81) < 1e-9,
    'strum positive tension uses the documented curve')
  check(by_pitch(out, 60).startppq == 120
    and by_pitch(out, 71).startppq == 0,
    'strum tension keeps the endpoints')

  local pair = {
    make({ startppq = 0, endppq = 480, pitch = 60, id = 'p60' }),
    make({ startppq = 10, endppq = 480, pitch = 64, id = 'p64' }),
  }
  out = T.apply(pair, 'strum', {
    low = 100, high = 0, grid_ppq = 120, tension = 0, onset_tolerance = 10,
  })
  check(by_pitch(out, 60).startppq == 120,
    'strum groups onsets inside the tolerance')
  check(by_pitch(out, 64).startppq == 10,
    'strum keeps the high onset inside a grouped pair')

  out = T.apply(pair, 'strum', {
    low = 100, high = 0, grid_ppq = 120, tension = 0, onset_tolerance = 9,
  })
  check(by_pitch(out, 60).startppq == 0
    and by_pitch(out, 64).startppq == 10,
    'strum leaves separate groups alone')

  local single = make({ startppq = 0, endppq = 480, pitch = 60 })
  out = T.apply({ single }, 'strum', {
    low = 100, high = 0, grid_ppq = 120, tension = 0, onset_tolerance = 0,
  })
  check(out[1].startppq == 0, 'strum does not move a single-note group')

  out = T.apply(chord(), 'strum', {
    low = 0, high = 0, grid_ppq = 120, tension = 0, onset_tolerance = 0,
  })
  check(by_pitch(out, 60).startppq == 0 and by_pitch(out, 71).startppq == 0,
    'strum with both controls at zero is a no-op')

  expect_error(function()
    T.apply({
      make({ startppq = 0, endppq = 480, pitch = 60, id = 'neg60' }),
      make({ startppq = 0, endppq = 480, pitch = 64, id = 'neg64' }),
    }, 'strum', {
      low = -100, high = 0, grid_ppq = 120, tension = 0,
      onset_tolerance = 0,
    })
  end, 'strum rejects a start before zero')
  expect_error(function()
    T.apply(chord(), 'strum', {
      low = 100, high = 0, grid_ppq = 120, tension = 2,
      onset_tolerance = 0,
    })
  end, 'strum rejects tension above one')
  expect_error(function()
    T.apply(chord(), 'strum', {
      low = 101, high = 0, grid_ppq = 120, tension = 0,
      onset_tolerance = 0,
    })
  end, 'strum rejects low above 100')
  expect_error(function()
    T.apply(chord(), 'strum', {
      low = 100, high = 0, grid_ppq = 0, tension = 0,
      onset_tolerance = 0,
    })
  end, 'strum rejects a zero grid')
  expect_error(function()
    T.apply(chord(), 'strum', {
      low = 100, high = 0, grid_ppq = 120, tension = 0,
    })
  end, 'strum requires an explicit onset tolerance')

  local blocker = make({ startppq = 120, endppq = 480, pitch = 60,
    selected = false, id = 'blocker' })
  expect_error(function()
    local selected = chord()
    T.apply({ selected[1], selected[2], blocker }, 'strum', {
      low = 100, high = 0, grid_ppq = 120, tension = 0,
      onset_tolerance = 0,
    })
  end, 'strum rejects a collision with an unselected note')
end

-- Determinism, ids, extra fields, and input validation.
do
  local chord = {
    make({ startppq = 0, endppq = 480, pitch = 60, id = 'c' }),
    make({ startppq = 0, endppq = 480, pitch = 64, id = 'e' }),
    make({ startppq = 0, endppq = 480, pitch = 67, id = 'g' }),
  }
  local options = { mode = 'updown', rate_ppq = 120, gate = 1,
    octaves = 1, range_start = 0, range_end = 480 }
  local first = T.apply(chord, 'arpeggiate', options)
  local second = T.apply(chord, 'arpeggiate', options)
  check(signature(first) == signature(second),
    'transformations are deterministic without a global seed')
  check(first[1].id ~= first[2].id, 'generated ids are unique')

  local extra = { tag = 'x' }
  local note = make({ startppq = 0, endppq = 120, extra = extra })
  local out = T.apply({ note }, 'chop', { parts = 2 })
  check(out[1].extra == extra and out[2].extra == extra,
    'chop copies additional fields from the source')
  check(note.extra == extra, 'chop does not replace the input extra field')

  local lowest = make({ pitch = 0, vel = 1, channel = 0,
    release_velocity = 0 })
  local bounds = T.apply({ lowest }, 'chop', { parts = 2 })
  check(bounds[1].pitch == 0 and bounds[1].vel == 1
    and bounds[1].channel == 0 and bounds[1].release_velocity == 0,
    'minimum MIDI values survive a split')
  local highest = make({ pitch = 127, vel = 127, channel = 15 })
  bounds = T.apply({ highest }, 'chop', { parts = 2 })
  check(bounds[1].pitch == 127 and bounds[1].vel == 127
    and bounds[1].channel == 15,
    'maximum MIDI values survive a split')

  expect_error(function()
    T.apply({ make({ endppq = 1e9 + 1 }) }, 'legato', {})
  end, 'time above the PPQ limit is rejected')

  local missing_muted = make({})
  missing_muted.muted = nil
  expect_error(function()
    T.apply({ missing_muted }, 'legato', {})
  end, 'missing muted is rejected')
  expect_error(function()
    T.apply({ make({ pitch = 128 }) }, 'invert', { pivot = 60 })
  end, 'pitch 128 is rejected')
  expect_error(function()
    T.apply({ make({ vel = 0 }) }, 'invert', { pivot = 60 })
  end, 'velocity 0 is rejected')
  expect_error(function()
    T.apply({ make({ channel = 16 }) }, 'invert', { pivot = 60 })
  end, 'channel 16 is rejected')
  expect_error(function()
    T.apply({ make({ startppq = -1 }) }, 'invert', { pivot = 60 })
  end, 'negative start is rejected')
  expect_error(function()
    T.apply({ make({ endppq = 0 }) }, 'invert', { pivot = 60 })
  end, 'empty note duration is rejected')
  local missing_selected = make({})
  missing_selected.selected = nil
  expect_error(function()
    T.apply({ missing_selected }, 'legato', {})
  end, 'missing selected flag is rejected')
  expect_error(function()
    T.apply({ make({}) }, 'unknown_tool', {})
  end, 'unknown transformation is rejected')
end

local summary = { passed = passed }
print('PASS transformations: ' .. passed .. ' assertions')
return summary
