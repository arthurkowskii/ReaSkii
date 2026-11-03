-- Standalone unit tests for scripts/midi/ReaSkii_MIDI_Generators.lua.
-- Runs with plain Lua 5.4, no REAPER and no gfx. Raises on the first failure.
-- Usage: lua5.4 tests/midi_generators_unit.lua
-- A successful run prints each test and returns {passed=N}.

local script_path = debug.getinfo(1, 'S').source:sub(2)
local directory = script_path:match('^(.*[/\\])') or './'
local G = dofile(directory .. '../scripts/midi/ReaSkii_MIDI_Generators.lua')

local passed = 0

local function ok(condition, message)
  assert(condition, message or 'assertion failed')
end

local function eq(actual, expected, message)
  if actual ~= expected then
    error(string.format('%s: expected %s, got %s', message or 'equality',
      tostring(expected), tostring(actual)), 2)
  end
end

local function near(actual, expected, message)
  if type(actual) ~= 'number' or math.abs(actual - expected) > 1e-6 then
    error(string.format('%s: expected %s, got %s', message or 'number',
      tostring(expected), tostring(actual)), 2)
  end
end

local function raises(fn, fragment, message)
  local success, err = pcall(fn)
  if success then error((message or 'error') .. ': expected an error', 2) end
  if fragment then
    if not tostring(err):find(fragment, 1, true) then
      error(string.format('%s: error %q does not contain %q',
        message or 'error', tostring(err), fragment), 2)
    end
  end
end

local function serialize(value, seen)
  if type(value) ~= 'table' then return tostring(value) .. ':' .. type(value) end
  seen = seen or {}
  if seen[value] then error('cycle in serialized table') end
  seen[value] = true
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return tostring(a) < tostring(b) end
    return type(a) < type(b)
  end)
  local parts = {}
  for _, key in ipairs(keys) do
    parts[#parts + 1] = tostring(key) .. '=' .. serialize(value[key], seen)
  end
  seen[value] = nil
  return '{' .. table.concat(parts, ',') .. '}'
end

local function starts(notes)
  local list = {}
  for index, note in ipairs(notes) do list[index] = note.startppq end
  return list
end

local function pitches(notes)
  local list = {}
  for index, note in ipairs(notes) do list[index] = note.pitch end
  return list
end

local function find_pitch(notes, pitch)
  for _, note in ipairs(notes) do
    if note.pitch == pitch then return note end
  end
  error('pitch ' .. tostring(pitch) .. ' not generated')
end

local function check_note_contract(notes, range_start, range_end, label)
  local ids = {}
  for index, note in ipairs(notes) do
    ok(type(note.startppq) == 'number', label .. ' start type')
    ok(type(note.endppq) == 'number', label .. ' end type')
    ok(note.endppq > note.startppq, label .. ' positive duration #' .. index)
    ok(note.startppq >= range_start - 1e-9, label .. ' starts before range')
    ok(note.startppq < range_end + 1e-9, label .. ' starts after range')
    ok(note.endppq <= range_end + 1e-9, label .. ' ends after range')
    ok(note.pitch % 1 == 0 and note.pitch >= 0 and note.pitch <= 127,
      label .. ' pitch bounds')
    ok(note.vel % 1 == 0 and note.vel >= 1 and note.vel <= 127,
      label .. ' velocity bounds')
    ok(note.channel % 1 == 0 and note.channel >= 0 and note.channel <= 15,
      label .. ' channel bounds')
    ok(note.release_velocity % 1 == 0
      and note.release_velocity >= 0 and note.release_velocity <= 127,
      label .. ' release velocity bounds')
    eq(note.selected, true, label .. ' selected')
    eq(type(note.muted), 'boolean', label .. ' muted type')
    ok(note.id ~= nil and ids[tostring(note.id)] == nil, label .. ' id unique')
    ids[tostring(note.id)] = true
  end
end

local function test(name, fn)
  fn()
  passed = passed + 1
  print('ok ' .. name)
end

-- Rhythm --------------------------------------------------------------------

test('rhythm fills one range with density steps', function()
  local options = {
    range_start = 0, range_end = 960, steps = 8, density = 8, seed = 1,
    note_length = 120, pitches = { 36, 38 }, vel = 90,
  }
  local before = serialize(options)
  local notes = G.generate('rhythm', options)
  eq(serialize(options), before, 'rhythm does not mutate options')
  eq(#notes, 8, 'rhythm note count')
  local expected_starts = { 0, 120, 240, 360, 480, 600, 720, 840 }
  for index, value in ipairs(expected_starts) do
    near(notes[index].startppq, value, 'rhythm start ' .. index)
    near(notes[index].endppq, value + 120, 'rhythm end ' .. index)
  end
  for index, note in ipairs(notes) do
    eq(note.pitch, index % 2 == 1 and 36 or 38, 'rhythm pitch cycle ' .. index)
    eq(note.vel, 90, 'rhythm velocity')
  end
  check_note_contract(notes, 0, 960, 'rhythm')
end)

test('rhythm density and seed control the pattern', function()
  local function run(seed)
    return G.generate('rhythm', {
      range_start = 0, range_end = 960, steps = 8, density = 3, seed = seed,
      note_length = 60, pitches = { 60 },
    })
  end
  local first = run(1)
  eq(#first, 3, 'rhythm density count')
  eq(serialize(run(1)), serialize(first), 'rhythm deterministic for a seed')
  local second = run(2)
  eq(#second, 3, 'rhythm density count for another seed')
  ok(serialize(second) ~= serialize(first), 'rhythm seeds differ')
  local empty = G.generate('rhythm', {
    range_start = 0, range_end = 960, steps = 8, density = 0, seed = 1,
    note_length = 60, pitches = { 60 },
  })
  eq(#empty, 0, 'rhythm density 0 is silent')
end)

test('rhythm repeats and clips at range_end', function()
  local notes = G.generate('rhythm', {
    range_start = 0, range_end = 500, steps = 4, density = 4, seed = 1,
    note_length = 100, pitches = { 60 }, step_ppq = 100,
  })
  eq(#notes, 5, 'rhythm repeat count')
  near(notes[1].startppq, 0, 'repeat first start')
  near(notes[5].startppq, 400, 'repeat last start')
  near(notes[5].endppq, 500, 'last note clipped')
  check_note_contract(notes, 0, 500, 'rhythm repeat')

  local clipped = G.generate('rhythm', {
    range_start = 0, range_end = 100, steps = 4, density = 4, seed = 1,
    note_length = 60, pitches = { 60 },
  })
  eq(#clipped, 4, 'short range note count')
  near(clipped[4].startppq, 75, 'short range last start')
  near(clipped[4].endppq, 100, 'short range last end clipped')
  check_note_contract(clipped, 0, 100, 'rhythm clipped')
end)

test('rhythm rejects invalid parameters', function()
  local base = {
    range_start = 0, range_end = 960, steps = 8, density = 3, seed = 1,
    note_length = 60, pitches = { 60 },
  }
  local function with(overrides)
    local copy = {}
    for key, value in pairs(base) do copy[key] = value end
    for key, value in pairs(overrides or {}) do copy[key] = value end
    return copy
  end
  raises(function() G.generate('rhythm', with({ density = 9 })) end, 'density')
  raises(function() G.generate('rhythm', with({ steps = 0 })) end, 'steps')
  raises(function() G.generate('rhythm', with({ note_length = 0 })) end, 'note_length')
  raises(function() G.generate('rhythm', with({ range_end = 0 })) end, 'range_end')
  raises(function() G.generate('rhythm', with({ pitches = {} })) end, 'pitches')
  raises(function() G.generate('rhythm', with({ pitches = { 128 } })) end, 'pitches')
  raises(function() G.generate('rhythm', with({ seed = 1.5 })) end, 'seed')
  raises(function()
    G.generate('rhythm', with({ step_ppq = 1, max_notes = 100 }))
  end, 'max_notes')
  raises(function() G.generate('rhythm', with({ max_notes = 2 })) end, 'max_notes')
end)

-- Euclidean ----------------------------------------------------------------

test('euclidean matches canonical E(3,8) and E(5,8)', function()
  local options = {
    range_start = 0, range_end = 960, steps = 8, pulses = 3, rotation = 0,
    pitch = 36, vel = 100, step_ppq = 120, note_length = 60,
  }
  local notes = G.generate('euclidean', options)
  eq(#notes, 3, 'E(3,8) pulses')
  local expected = { 0, 360, 720 }
  for index, value in ipairs(expected) do
    near(notes[index].startppq, value, 'E(3,8) hit ' .. index)
    near(notes[index].endppq, value + 60, 'E(3,8) length ' .. index)
    eq(notes[index].pitch, 36, 'E(3,8) pitch')
  end

  local five = G.generate('euclidean', {
    range_start = 0, range_end = 960, steps = 8, pulses = 5, rotation = 0,
    pitch = 60, step_ppq = 120, note_length = 60,
  })
  eq(#five, 5, 'E(5,8) pulses')
  local five_expected = { 0, 240, 480, 600, 840 }
  for index, value in ipairs(five_expected) do
    near(five[index].startppq, value, 'E(5,8) hit ' .. index)
  end
end)

test('euclidean rotation delays hits modulo steps', function()
  local function rotation_starts(rotation)
    return starts(G.generate('euclidean', {
      range_start = 0, range_end = 960, steps = 8, pulses = 3,
      rotation = rotation, pitch = 60, step_ppq = 120, note_length = 60,
    }))
  end
  local one = rotation_starts(1)
  eq(#one, 3, 'rotation 1 count')
  near(one[1], 120, 'rotation 1 hit 1')
  near(one[2], 480, 'rotation 1 hit 2')
  near(one[3], 840, 'rotation 1 hit 3')
  local minus = rotation_starts(-1)
  near(minus[1], 240, 'negative rotation wraps')
  near(minus[2], 600, 'negative rotation wraps middle')
  near(minus[3], 840, 'negative rotation wraps last')
  eq(serialize(rotation_starts(8)), serialize(rotation_starts(0)),
    'rotation by steps is identity')
  local five_rotated = starts(G.generate('euclidean', {
    range_start = 0, range_end = 960, steps = 8, pulses = 5, rotation = 2,
    pitch = 60, step_ppq = 120, note_length = 60,
  }))
  local expected = { 120, 240, 480, 720, 840 }
  for index, value in ipairs(expected) do
    near(five_rotated[index], value, 'E(5,8) rotation 2 hit ' .. index)
  end
end)

test('euclidean defaults and edge pulses', function()
  local notes = G.generate('euclidean', {
    range_start = 0, range_end = 480, steps = 8, pulses = 3, pitch = 60,
  })
  eq(#notes, 3, 'default step count')
  near(notes[1].startppq, 0, 'default first start')
  near(notes[1].endppq, 30, 'default half-step gate')
  near(notes[2].startppq, 180, 'default second start')
  local one = G.generate('euclidean', {
    range_start = 0, range_end = 480, steps = 4, pulses = 1, step_ppq = 120,
    note_length = 60,
  })
  eq(#one, 1, 'pulses 1')
  near(one[1].startppq, 0, 'pulses 1 starts on the first step')
  local all = G.generate('euclidean', {
    range_start = 0, range_end = 480, steps = 4, pulses = 4, step_ppq = 120,
    note_length = 60,
  })
  eq(#all, 4, 'pulses = steps')
  local none = G.generate('euclidean', {
    range_start = 0, range_end = 480, steps = 4, pulses = 0, step_ppq = 120,
    note_length = 60,
  })
  eq(#none, 0, 'pulses 0 is silent')
  local repeated = G.generate('euclidean', {
    range_start = 0, range_end = 1000, steps = 4, pulses = 1, step_ppq = 100,
    note_length = 50,
  })
  eq(#repeated, 3, 'euclidean repeats over a long range')
  near(repeated[3].startppq, 800, 'repeated hit position')
  check_note_contract(repeated, 0, 1000, 'euclidean repeated')
end)

test('euclidean rejects invalid parameters', function()
  local base = {
    range_start = 0, range_end = 960, steps = 8, pulses = 3,
    pitch = 60, step_ppq = 120, note_length = 60,
  }
  local function with(overrides)
    local copy = {}
    for key, value in pairs(base) do copy[key] = value end
    for key, value in pairs(overrides or {}) do copy[key] = value end
    return copy
  end
  raises(function() G.generate('euclidean', with({ pulses = 9 })) end, 'pulses')
  raises(function() G.generate('euclidean', with({ steps = 0 })) end, 'steps')
  raises(function() G.generate('euclidean', with({ rotation = 0.5 })) end, 'rotation')
  raises(function() G.generate('euclidean', with({ pitch = 128 })) end, 'pitch')
  raises(function() G.generate('euclidean', with({ vel = 0 })) end, 'vel')
  raises(function()
    G.generate('euclidean', with({ pulses = 8, step_ppq = 1, max_notes = 100 }))
  end, 'max_notes')
end)

-- Seed ---------------------------------------------------------------------

test('seed fills a grid deterministically', function()
  local options = {
    range_start = 0, range_end = 480, grid_ppq = 120, density = 1,
    pitch_min = 60, pitch_max = 60, vel_min = 80, vel_max = 80, seed = 7,
  }
  local before = serialize(options)
  local notes = G.generate('seed', options)
  eq(serialize(options), before, 'seed does not mutate options')
  eq(#notes, 4, 'full grid note count')
  local expected = { 0, 120, 240, 360 }
  for index, value in ipairs(expected) do
    near(notes[index].startppq, value, 'seed start ' .. index)
    near(notes[index].endppq, value + 120, 'seed end ' .. index)
    eq(notes[index].pitch, 60, 'seed fixed pitch')
    eq(notes[index].vel, 80, 'seed fixed velocity')
  end
  eq(serialize(G.generate('seed', options)), serialize(notes),
    'seed deterministic for a seed')
  check_note_contract(notes, 0, 480, 'seed')
end)

test('seed density and different seeds change the result', function()
  local function run(seed, density)
    return G.generate('seed', {
      range_start = 0, range_end = 960, grid_ppq = 120, density = density,
      pitch_min = 48, pitch_max = 84, vel_min = 20, vel_max = 120, seed = seed,
    })
  end
  eq(#run(1, 0.5), 4, 'density half of eight slots')
  eq(#run(1, 0), 0, 'density zero')
  eq(#run(1, 1), 8, 'density one')
  local first = run(1, 1)
  local second = run(2, 1)
  eq(#first, #second, 'same density keeps the count')
  ok(serialize(first) ~= serialize(second), 'seed values differ across seeds')
  for _, note in ipairs(first) do
    ok(note.pitch >= 48 and note.pitch <= 84, 'seed pitch range')
    ok(note.vel >= 20 and note.vel <= 120, 'seed velocity range')
  end
end)

test('seed honours the optional scale', function()
  local allowed = { [0] = true, [2] = true, [4] = true, [5] = true,
    [7] = true, [9] = true, [11] = true }
  local notes = G.generate('seed', {
    range_start = 0, range_end = 960, grid_ppq = 120, density = 1,
    pitch_min = 60, pitch_max = 72, vel_min = 1, vel_max = 127, seed = 3,
    root = 0, scale = 'major',
  })
  eq(#notes, 8, 'scale note count')
  for _, note in ipairs(notes) do
    ok(allowed[note.pitch % 12], 'pitch ' .. note.pitch .. ' outside C major')
  end
  local custom = G.generate('seed', {
    range_start = 0, range_end = 960, grid_ppq = 120, density = 1,
    pitch_min = 60, pitch_max = 72, vel_min = 1, vel_max = 127, seed = 3,
    root = 2, scale = { 0, 3, 7 },
  })
  for _, note in ipairs(custom) do
    local degree = (note.pitch - 2) % 12
    ok(degree == 0 or degree == 3 or degree == 7,
      'pitch ' .. note.pitch .. ' outside custom scale')
  end
  raises(function()
    G.generate('seed', {
      range_start = 0, range_end = 480, grid_ppq = 120, density = 1,
      pitch_min = 61, pitch_max = 61, vel_min = 1, vel_max = 1,
      root = 0, scale = 'major',
    })
  end, 'scale leaves no pitch')
end)

test('seed rejects invalid parameters', function()
  local base = {
    range_start = 0, range_end = 480, grid_ppq = 120, density = 1,
    pitch_min = 60, pitch_max = 72, vel_min = 1, vel_max = 100, seed = 1,
  }
  local function with(overrides)
    local copy = {}
    for key, value in pairs(base) do copy[key] = value end
    for key, value in pairs(overrides or {}) do copy[key] = value end
    return copy
  end
  raises(function() G.generate('seed', with({ density = 1.5 })) end, 'density')
  raises(function() G.generate('seed', with({ pitch_min = 73 })) end, 'pitch_max')
  raises(function() G.generate('seed', with({ vel_min = 120, vel_max = 100 })) end,
    'vel_max')
  raises(function() G.generate('seed', with({ grid_ppq = 600 })) end, 'grid_ppq')
  raises(function() G.generate('seed', with({ max_notes = 3 })) end, 'max_notes')
  raises(function() G.generate('seed', with({ pitch_max = 128 })) end, 'pitch_max')
  raises(function() G.generate('seed', with({ scale = 'nope' })) end, 'unknown scale')
end)

test('note_fields are copied and validated', function()
  local notes = G.generate('seed', {
    range_start = 0, range_end = 240, grid_ppq = 120, density = 1,
    pitch_min = 60, pitch_max = 60, vel_min = 1, vel_max = 1, seed = 1,
    channel = 4, release_velocity = 12,
    note_fields = { muted = true, color = 'blue', tag = 42 },
  })
  eq(#notes, 2, 'note_fields note count')
  for _, note in ipairs(notes) do
    eq(note.channel, 4, 'note_fields channel')
    eq(note.release_velocity, 12, 'note_fields release velocity')
    eq(note.muted, true, 'note_fields muted')
    eq(note.color, 'blue', 'note_fields extra string')
    eq(note.tag, 42, 'note_fields extra number')
  end
  raises(function()
    G.generate('seed', {
      range_start = 0, range_end = 120, grid_ppq = 120, density = 1,
      pitch_min = 60, pitch_max = 60, vel_min = 1, vel_max = 1, seed = 1,
      note_fields = { pitch = 61 },
    })
  end, 'cannot override pitch')
  raises(function()
    G.generate('seed', {
      range_start = 0, range_end = 120, grid_ppq = 120, density = 1,
      pitch_min = 60, pitch_max = 60, vel_min = 1, vel_max = 1, seed = 1,
      note_fields = { channel = 16 },
    })
  end, 'channel')
end)

-- Shape --------------------------------------------------------------------

test('shape line, sine and triangle follow documented levels', function()
  local line = G.generate('shape', { shape = 'line', range_start = 0,
    range_end = 480, steps = 5, pitch_min = 60, pitch_max = 72 })
  eq(serialize(pitches(line)), serialize({ 60, 63, 66, 69, 72 }), 'line pitches')
  local line_starts = starts(line)
  local expected_starts = { 0, 96, 192, 288, 384 }
  for index, value in ipairs(expected_starts) do
    near(line_starts[index], value, 'line start ' .. index)
  end
  for _, note in ipairs(line) do
    near(note.endppq, note.startppq + 96, 'line default length')
  end
  local sine = G.generate('shape', { shape = 'sine', range_start = 0,
    range_end = 480, steps = 5, pitch_min = 60, pitch_max = 72 })
  eq(serialize(pitches(sine)), serialize({ 60, 66, 72, 66, 60 }), 'sine pitches')
  local triangle = G.generate('shape', { shape = 'triangle', range_start = 0,
    range_end = 480, steps = 5, pitch_min = 60, pitch_max = 72 })
  eq(serialize(pitches(triangle)), serialize({ 60, 66, 72, 66, 60 }),
    'triangle midpoint pitches')
  local fine_sine = G.generate('shape', { shape = 'sine', range_start = 0,
    range_end = 480, steps = 9, pitch_min = 60, pitch_max = 72 })
  local fine_triangle = G.generate('shape', { shape = 'triangle', range_start = 0,
    range_end = 480, steps = 9, pitch_min = 60, pitch_max = 72 })
  eq(fine_sine[2].pitch, 62, 'sine off-midpoint level')
  eq(fine_triangle[2].pitch, 63, 'triangle off-midpoint level')
  check_note_contract(line, 0, 480, 'shape line')
  check_note_contract(sine, 0, 480, 'shape sine')
end)

test('shape quantizes to the scale and handles one step', function()
  local notes = G.generate('shape', {
    shape = 'line', range_start = 0, range_end = 480, steps = 5,
    pitch_min = 60, pitch_max = 67, root = 0, scale = { 0, 4, 7 },
  })
  eq(serialize(pitches(notes)), serialize({ 60, 60, 64, 64, 67 }),
    'scale-quantized line')
  for _, note in ipairs(notes) do
    local degree = note.pitch % 12
    ok(degree == 0 or degree == 4 or degree == 7, 'pitch outside custom scale')
  end
  local single = G.generate('shape', {
    shape = 'line', range_start = 0, range_end = 100, steps = 1,
    pitch_min = 64, pitch_max = 70,
  })
  eq(#single, 1, 'single step note count')
  eq(single[1].pitch, 64, 'single step uses pitch_min')
  near(single[1].endppq, 100, 'single step fills range')
  raises(function()
    G.generate('shape', {
      shape = 'line', range_start = 0, range_end = 100, steps = 1,
      pitch_min = 61, pitch_max = 61, root = 0, scale = 'major',
    })
  end, 'no playable pitch')
end)

test('shape rejects invalid parameters', function()
  raises(function()
    G.generate('shape', { shape = 'square', range_start = 0, range_end = 480,
      steps = 5, pitch_min = 60, pitch_max = 72 })
  end, 'shape must be')
  raises(function()
    G.generate('shape', { shape = 'line', range_start = 0, range_end = 480,
      steps = 0, pitch_min = 60, pitch_max = 72 })
  end, 'steps')
  raises(function()
    G.generate('shape', { shape = 'line', range_start = 0, range_end = 480,
      steps = 5, pitch_min = 73, pitch_max = 72 })
  end, 'pitch_max')
  raises(function()
    G.generate('shape', { shape = 'line', range_start = 0, range_end = 480,
      steps = 5, pitch_min = 60, pitch_max = 72, note_length = -1 })
  end, 'note_length')
  raises(function()
    G.generate('shape', { shape = 'line', range_start = 0, range_end = 480,
      steps = 5, pitch_min = 60, pitch_max = 72, scale = 'mode-inexistant' })
  end, 'unknown scale')
end)

-- Stacks -------------------------------------------------------------------

test('stacks lays chords end to end and preserves velocities', function()
  local chords = {
    { root = 60, intervals = { 0, 4, 7 }, duration_ppq = 240 },
    { root = 62, intervals = { 0, 3, 7 }, duration_ppq = 240, vel = 90 },
  }
  local options = { range_start = 0, range_end = 480, chords = chords, vel = 100 }
  local before = serialize(options)
  local notes = G.generate('stacks', options)
  eq(serialize(options), before, 'stacks does not mutate chords')
  eq(#notes, 6, 'stacks note count')
  local first = find_pitch(notes, 60)
  eq(first.startppq, 0, 'first chord start')
  eq(first.endppq, 240, 'first chord end')
  eq(first.vel, 100, 'first chord velocity')
  for _, pitch in ipairs({ 60, 64, 67 }) do
    local note = find_pitch(notes, pitch)
    eq(note.startppq, 0, 'first chord note start')
    eq(note.endppq, 240, 'first chord note end')
  end
  for _, pitch in ipairs({ 62, 65, 69 }) do
    local note = find_pitch(notes, pitch)
    eq(note.startppq, 240, 'second chord note start')
    eq(note.endppq, 480, 'second chord note end')
    eq(note.vel, 90, 'second chord velocity')
  end
  check_note_contract(notes, 0, 480, 'stacks')
end)

test('stacks clips, skips and copies extra fields', function()
  local notes = G.generate('stacks', {
    range_start = 0, range_end = 300, vel = 80,
    chords = {
      { root = 60, intervals = { 0, 7 }, duration_ppq = 240 },
      { root = 62, intervals = { 0, 5 }, duration_ppq = 240 },
      { root = 64, intervals = { 0, 4 }, duration_ppq = 240 },
    },
  })
  eq(#notes, 4, 'chord beyond range is skipped')
  for _, note in ipairs(notes) do
    ok(note.endppq <= 300, 'clipped chord end')
    ok(note.pitch ~= 64 and note.pitch ~= 68, 'third chord not generated')
  end
  eq(find_pitch(notes, 62).endppq, 300, 'second chord clipped at range end')

  local tagged = G.generate('stacks', {
    range_start = 0, range_end = 100, vel = 80,
    chords = { { root = 60, intervals = { 0, 7 }, duration_ppq = 100,
      channel = 3, muted = true, tag = 'custom', release_velocity = 9 } },
  })
  eq(#tagged, 2, 'tagged chord count')
  for _, note in ipairs(tagged) do
    eq(note.channel, 3, 'chord channel copied')
    eq(note.muted, true, 'chord muted copied')
    eq(note.tag, 'custom', 'chord user field copied')
    eq(note.release_velocity, 9, 'chord release velocity copied')
    eq(note.root, nil, 'chord root is not leaked onto notes')
    eq(note.intervals, nil, 'chord intervals are not leaked onto notes')
    eq(note.duration_ppq, nil, 'chord duration is not leaked onto notes')
  end
end)

test('stacks rejects invalid chords and limits expansion', function()
  local function run(overrides)
    local options = {
      range_start = 0, range_end = 480, chords = {
        { root = 60, intervals = { 0, 4, 7 }, duration_ppq = 240 },
      },
    }
    for key, value in pairs(overrides or {}) do options[key] = value end
    return G.generate('stacks', options)
  end
  raises(function() run({ chords = {} }) end, 'chords')
  raises(function()
    run({ chords = { { root = 60, intervals = {}, duration_ppq = 100 } } })
  end, 'intervals')
  raises(function()
    run({ chords = { { root = 127, intervals = { 0, 7 }, duration_ppq = 100 } } })
  end, 'outside 0..127')
  raises(function()
    run({ chords = { { root = 0, intervals = { -1 }, duration_ppq = 100 } } })
  end, 'outside 0..127')
  raises(function()
    run({ chords = { { root = 60, intervals = { 0, 0 }, duration_ppq = 100 } } })
  end, 'twice')
  raises(function()
    run({ chords = { { root = 60, intervals = { 0 }, duration_ppq = 0 } } })
  end, 'duration_ppq')
  raises(function()
    run({ max_notes = 2, chords = {
      { root = 60, intervals = { 0, 4, 7 }, duration_ppq = 100 },
    } })
  end, 'max_notes')
  raises(function()
    run({ chords = { { root = 60, intervals = { 0 }, duration_ppq = 100 },
      { root = 62, intervals = { 0, 4 }, duration_ppq = 100 } },
      max_notes = 2 })
  end, 'max_notes')
end)

-- Common contract ----------------------------------------------------------

test('all generators respect the note contract and isolation', function()
  local cases = {
    { 'rhythm', { range_start = 0, range_end = 960, steps = 8, density = 4,
      seed = 5, note_length = 60, pitches = { 40, 43 } } },
    { 'euclidean', { range_start = 0, range_end = 960, steps = 7, pulses = 4,
      rotation = 2, pitch = 55, step_ppq = 120, note_length = 60 } },
    { 'seed', { range_start = 0, range_end = 960, grid_ppq = 60, density = 0.5,
      pitch_min = 48, pitch_max = 72, vel_min = 10, vel_max = 110, seed = 9 } },
    { 'shape', { shape = 'triangle', range_start = 0, range_end = 960, steps = 6,
      pitch_min = 50, pitch_max = 70, vel = 77 } },
    { 'stacks', { range_start = 0, range_end = 480, vel = 66, chords = {
      { root = 57, intervals = { 0, 3, 7, 10 }, duration_ppq = 240,
        channel = 2, tag = 'x' },
      { root = 59, intervals = { 0, 4, 7 }, duration_ppq = 240 } } } },
  }
  for _, case in ipairs(cases) do
    local tool, options = case[1], case[2]
    local before = serialize(options)
    local notes = G.generate(tool, options)
    eq(serialize(options), before, tool .. ' leaves its input untouched')
    check_note_contract(notes, options.range_start, options.range_end, tool)
    ok(#notes > 0, tool .. ' should generate notes')
    eq(serialize(G.generate(tool, options)), serialize(notes),
      tool .. ' is deterministic')
  end
end)

test('generate rejects unknown tools and bad arguments', function()
  raises(function() G.generate('arp', {}) end, 'unknown generator')
  raises(function() G.generate(nil, {}) end, 'tool must be a string')
  raises(function() G.generate('rhythm', nil) end, 'options must be a table')
  raises(function() G.generate('rhythm', 'nope') end, 'options must be a table')
end)

print(string.format('%d tests passed', passed))
return { passed = passed }
