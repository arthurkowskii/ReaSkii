-- ReaSkii MIDI generators.
-- Pure Lua 5.4 module: no reaper.*, no gfx, no I/O. Independent implementation.
-- The tool names are functional equivalents of common generative tools.
-- No Ableton parity is claimed and no proprietary algorithm is reproduced.
--
-- generate(tool, options) returns a new array of notes:
--   { startppq=number, endppq=number, pitch=integer 0..127,
--     vel=integer 1..127, channel=integer 0..15, selected=true,
--     muted=boolean, id=opaque string, release_velocity=integer 0..127 }
-- Extra string keys supplied through options.note_fields (and, for stacks,
-- through each chord table) are copied onto the generated notes.
--
-- The module only builds note tables. It never mutates options, chords or any
-- input table, never reads a take and never deletes pre-existing notes.
-- Replacement/addition and MPE curves belong to the caller.
--
-- All times are explicit PPQ numbers. No REAPER tick conversion is guessed.
-- Positions are bounded to [0, 1e7] PPQ; grids, steps and note lengths are
-- bounded below by 1e-3 PPQ. Values outside those bounds raise errors.
-- Generated notes always start inside [range_start, range_end) and never end
-- after range_end. Parameter violations raise errors instead of being clamped.
-- ids are unique inside one returned list only; callers must not treat them
-- as stable identifiers across separate generate() calls.

local M = {}

local DEFAULT_MAX_NOTES = 4096
local HARD_MAX_NOTES = 16384
local MAX_STEPS = 1024
local MAX_CHORDS = 256
local MAX_INTERVALS = 32
local MAX_POSITION = 1e7
local MIN_DURATION = 1e-3

local SCALES = {
  major = { 0, 2, 4, 5, 7, 9, 11 },
  ionian = { 0, 2, 4, 5, 7, 9, 11 },
  minor = { 0, 2, 3, 5, 7, 8, 10 },
  natural_minor = { 0, 2, 3, 5, 7, 8, 10 },
  aeolian = { 0, 2, 3, 5, 7, 8, 10 },
  harmonic_minor = { 0, 2, 3, 5, 7, 8, 11 },
  melodic_minor = { 0, 2, 3, 5, 7, 9, 11 },
  dorian = { 0, 2, 3, 5, 7, 9, 10 },
  phrygian = { 0, 1, 3, 5, 7, 8, 10 },
  lydian = { 0, 2, 4, 6, 7, 9, 11 },
  mixolydian = { 0, 2, 4, 5, 7, 9, 10 },
  locrian = { 0, 1, 3, 5, 6, 8, 10 },
  pentatonic_major = { 0, 2, 4, 7, 9 },
  pentatonic_minor = { 0, 3, 5, 7, 10 },
  blues = { 0, 3, 5, 6, 7, 10 },
  chromatic = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 },
}

local function fail(message)
  error('ReaSkii_MIDI_Generators: ' .. message, 3)
end

local function is_finite(value)
  return type(value) == 'number' and value == value
    and value ~= math.huge and value ~= -math.huge
end

local function number_field(source, name, default, low, high)
  local value = source[name]
  if value == nil then value = default end
  if value == nil then fail(name .. ' is required') end
  if not is_finite(value) then fail(name .. ' must be a finite number') end
  if low ~= nil and value < low then
    fail(string.format('%s must be >= %s', name, tostring(low)))
  end
  if high ~= nil and value > high then
    fail(string.format('%s must be <= %s', name, tostring(high)))
  end
  return value
end

local function integer_field(source, name, default, low, high)
  local value = number_field(source, name, default, low, high)
  if value % 1 ~= 0 then fail(name .. ' must be an integer') end
  return math.tointeger(value) or value
end

local function check_integer(value, name, low, high)
  if not is_finite(value) or value % 1 ~= 0 then
    fail(name .. ' must be an integer')
  end
  if value < low or value > high then
    fail(string.format('%s must be between %d and %d', name, low, high))
  end
  return value
end

-- Rounded to 1e-6 PPQ to hide float noise from equal-step division.
-- MAX_POSITION keeps value * 1e6 inside the exact double range.
local function snap(value)
  local rounded = math.floor(value * 1e6 + 0.5) / 1e6
  if rounded % 1 == 0 then
    local exact = math.tointeger(rounded)
    if exact then return exact end
  end
  return rounded
end

local function range_fields(options)
  local startppq = number_field(options, 'range_start', nil, 0, MAX_POSITION)
  local endppq = number_field(options, 'range_end', nil, 0, MAX_POSITION)
  if not (endppq > startppq) then
    fail('range_end must be greater than range_start')
  end
  local span = endppq - startppq
  if span < MIN_DURATION then
    fail(string.format('range is shorter than the %.0e PPQ resolution', MIN_DURATION))
  end
  return startppq, endppq, span
end

local function max_notes_field(options)
  return integer_field(options, 'max_notes', DEFAULT_MAX_NOTES, 1, HARD_MAX_NOTES)
end

local function output_fields(options)
  return {
    channel = integer_field(options, 'channel', 0, 0, 15),
    release_velocity = integer_field(options, 'release_velocity', 0, 0, 127),
    note_fields = options.note_fields,
  }
end

local function pitch_list(options, name, default)
  local raw = options[name]
  if raw == nil then raw = default end
  local list = {}
  if type(raw) == 'number' then
    list[1] = raw
  elseif type(raw) == 'table' then
    for index = 1, #raw do list[index] = raw[index] end
  else
    fail(name .. ' must be a pitch or a list of pitches')
  end
  if #list == 0 then fail(name .. ' must not be empty') end
  if #list > 128 then fail(name .. ' must contain at most 128 pitches') end
  for index = 1, #list do
    list[index] = check_integer(list[index], name .. '[' .. index .. ']', 0, 127)
  end
  return list
end

-- Returns a predicate pitch -> boolean, or nil when no scale is requested.
local function scale_predicate(options)
  local scale = options.scale
  if scale == nil then return nil end
  local root = integer_field(options, 'root', 0, 0, 11)
  local degrees = {}
  if type(scale) == 'string' then
    local definition = SCALES[scale:lower()]
    if not definition then
      fail("unknown scale '" .. scale .. "'")
    end
    for _, degree in ipairs(definition) do degrees[degree % 12] = true end
  elseif type(scale) == 'table' then
    if #scale == 0 then fail('scale must not be empty') end
    for index = 1, #scale do
      local degree = check_integer(scale[index], 'scale[' .. index .. ']', 0, 11)
      degrees[degree] = true
    end
  else
    fail('scale must be a name or a list of semitone offsets')
  end
  return function(pitch)
    local relative = pitch - root
    return degrees[relative % 12] == true
  end
end

-- Deterministic local PRNG. Never touches math.random or math.randomseed.
-- LCG constants keep state * 1664525 below 2^53, so the arithmetic is exact
-- and identical across Lua 5.4 builds. Not suitable for cryptography.
local function new_rng(seed)
  local state = seed % 4294967296
  if state < 0 then state = state + 4294967296 end
  if state == 0 then state = 2463534242 end
  local rng = {}
  function rng.u32()
    state = (state * 1664525 + 1013904223) % 4294967296
    return state
  end
  function rng.int(low, high)
    local count = high - low + 1
    if count <= 0 then fail('empty random range') end
    return low + (rng.u32() % count)
  end
  return rng
end

local function shuffled_indices(count, rng)
  local order = {}
  for index = 1, count do order[index] = index end
  for index = count, 2, -1 do
    local other = rng.int(1, index)
    order[index], order[other] = order[other], order[index]
  end
  return order
end

local RESERVED_NOTE_FIELDS = {
  startppq = true, endppq = true, pitch = true, vel = true,
  id = true, selected = true,
}

local function copy_fields(target, source, label)
  if source == nil then return end
  if type(source) ~= 'table' then fail(label .. ' must be a table') end
  for key, value in pairs(source) do
    if type(key) ~= 'string' then fail(label .. ' keys must be strings') end
    if RESERVED_NOTE_FIELDS[key] then
      fail(label .. ' cannot override ' .. key)
    end
    target[key] = value
  end
end

local function make_note(tool, index, startppq, endppq, pitch, vel, fields, extras)
  local note = {
    startppq = snap(startppq),
    endppq = snap(endppq),
    pitch = pitch,
    vel = vel,
    channel = fields.channel,
    selected = true,
    muted = false,
    id = tool .. ':' .. tostring(index),
    release_velocity = fields.release_velocity,
  }
  copy_fields(note, fields.note_fields, 'note_fields')
  copy_fields(note, extras, 'extra fields')
  if not (is_finite(note.startppq) and is_finite(note.endppq)
      and note.endppq > note.startppq) then
    fail('generated note has a non-positive duration')
  end
  check_integer(note.pitch, 'generated pitch', 0, 127)
  check_integer(note.vel, 'generated vel', 1, 127)
  check_integer(note.channel, 'generated channel', 0, 15)
  check_integer(note.release_velocity, 'generated release_velocity', 0, 127)
  if type(note.muted) ~= 'boolean' then
    fail('generated muted must be a boolean')
  end
  return note
end

local function sort_notes(notes)
  table.sort(notes, function(a, b)
    if a.startppq ~= b.startppq then return a.startppq < b.startppq end
    if a.pitch ~= b.pitch then return a.pitch < b.pitch end
    return a.id < b.id
  end)
  return notes
end

-- Rhythm: a seeded step pattern with `density` hits, repeated to fill the range.
-- step_ppq defaults to span / steps (one point of the pattern per step).
-- When the range outlasts one pattern, hits repeat with the same pitches.
local function generate_rhythm(options)
  local startppq, endppq, span = range_fields(options)
  local steps = integer_field(options, 'steps', 8, 1, MAX_STEPS)
  local density = integer_field(options, 'density', steps, 0, steps)
  local seed = integer_field(options, 'seed', 1, -2147483648, 2147483647)
  local note_length = number_field(options, 'note_length', nil, MIN_DURATION, MAX_POSITION)
  local pitches = pitch_list(options, 'pitches', { 60 })
  local vel = integer_field(options, 'vel', 100, 1, 127)
  local step_ppq = number_field(options, 'step_ppq', span / steps, MIN_DURATION, MAX_POSITION)
  local limit = max_notes_field(options)
  local fields = output_fields(options)

  local pattern_ppq = steps * step_ppq
  local cycles = math.ceil(span / pattern_ppq - 1e-9)
  if cycles < 1 then cycles = 1 end
  if cycles * density > limit then
    fail(string.format('rhythm would generate up to %d notes, above max_notes %d',
      cycles * density, limit))
  end

  local rng = new_rng(seed)
  local order = shuffled_indices(steps, rng)
  local hits = {}
  for index = 1, density do hits[order[index]] = true end

  local notes = {}
  for cycle = 0, cycles - 1 do
    for step = 1, steps do
      local position = startppq + (cycle * steps + step - 1) * step_ppq
      if position >= endppq - 1e-9 then break end
      if hits[step] then
        local finish = math.min(position + note_length, endppq)
        if finish > position then
          local pitch = pitches[((step - 1) % #pitches) + 1]
          notes[#notes + 1] = make_note('rhythm', #notes + 1, position, finish,
            pitch, vel, fields, nil)
        end
      end
    end
  end
  if #notes > limit then
    fail(string.format('rhythm generated %d notes, above max_notes %d', #notes, limit))
  end
  return sort_notes(notes)
end

-- Euclidean: pattern[i] = ((i-1) * pulses) mod steps < pulses, standard E(k,n).
-- Positive rotation delays the pattern by that many steps (mod steps).
local function generate_euclidean(options)
  local startppq, endppq, span = range_fields(options)
  local steps = integer_field(options, 'steps', nil, 1, MAX_STEPS)
  local pulses = integer_field(options, 'pulses', nil, 0, steps)
  local rotation = integer_field(options, 'rotation', 0, -MAX_STEPS * 16, MAX_STEPS * 16)
  rotation = rotation % steps
  local pitch = integer_field(options, 'pitch', 60, 0, 127)
  local vel = integer_field(options, 'vel', 100, 1, 127)
  local step_ppq = number_field(options, 'step_ppq', span / steps, MIN_DURATION, MAX_POSITION)
  local note_length = number_field(options, 'note_length', step_ppq * 0.5,
    MIN_DURATION, MAX_POSITION)
  local limit = max_notes_field(options)
  local fields = output_fields(options)

  local pattern_ppq = steps * step_ppq
  local cycles = math.ceil(span / pattern_ppq - 1e-9)
  if cycles < 1 then cycles = 1 end
  if cycles * pulses > limit then
    fail(string.format('euclidean would generate up to %d notes, above max_notes %d',
      cycles * pulses, limit))
  end

  local rotated = {}
  for index = 1, steps do
    local source = ((index - 1 - rotation) % steps) + 1
    rotated[index] = (((source - 1) * pulses) % steps) < pulses
  end

  local notes = {}
  for cycle = 0, cycles - 1 do
    for step = 1, steps do
      local position = startppq + (cycle * steps + step - 1) * step_ppq
      if position >= endppq - 1e-9 then break end
      if rotated[step] then
        local finish = math.min(position + note_length, endppq)
        if finish > position then
          notes[#notes + 1] = make_note('euclidean', #notes + 1, position, finish,
            pitch, vel, fields, nil)
        end
      end
    end
  end
  if #notes > limit then
    fail(string.format('euclidean generated %d notes, above max_notes %d', #notes, limit))
  end
  return sort_notes(notes)
end

-- Seed: fills a grid with a seeded subset of slots (density 0..1), each slot
-- carrying one note of grid_ppq length (truncated by range_end). Pitches and
-- velocities are drawn uniformly from their ranges; an optional scale filters
-- the allowed pitches. Slot count is rounded half up from slots * density.
local function generate_seed(options)
  local startppq, endppq, span = range_fields(options)
  local grid_ppq = number_field(options, 'grid_ppq', nil, MIN_DURATION, MAX_POSITION)
  local density = number_field(options, 'density', nil, 0, 1)
  local pitch_min = integer_field(options, 'pitch_min', nil, 0, 127)
  local pitch_max = integer_field(options, 'pitch_max', nil, 0, 127)
  local vel_min = integer_field(options, 'vel_min', nil, 1, 127)
  local vel_max = integer_field(options, 'vel_max', nil, 1, 127)
  local seed = integer_field(options, 'seed', 1, -2147483648, 2147483647)
  local limit = max_notes_field(options)
  local fields = output_fields(options)
  if pitch_max < pitch_min then fail('pitch_max must be >= pitch_min') end
  if vel_max < vel_min then fail('vel_max must be >= vel_min') end

  local slots = math.floor(span / grid_ppq + 1e-9)
  if slots < 1 then fail('grid_ppq does not fit inside the range') end
  if slots > limit then
    fail(string.format('grid has %d slots, above max_notes %d', slots, limit))
  end

  local allowed = scale_predicate(options)
  local pitches
  if allowed then
    pitches = {}
    for pitch = pitch_min, pitch_max do
      if allowed(pitch) then pitches[#pitches + 1] = pitch end
    end
    if #pitches == 0 then
      fail('scale leaves no pitch between pitch_min and pitch_max')
    end
  end

  local selected_count = math.floor(slots * density + 0.5)
  local rng = new_rng(seed)
  local order = shuffled_indices(slots, rng)
  local chosen = {}
  for index = 1, selected_count do chosen[order[index]] = true end

  local notes = {}
  for slot = 1, slots do
    if chosen[slot] then
      local position = startppq + (slot - 1) * grid_ppq
      local finish = math.min(position + grid_ppq, endppq)
      if finish > position then
        local pitch
        if pitches then
          pitch = pitches[rng.int(1, #pitches)]
        else
          pitch = rng.int(pitch_min, pitch_max)
        end
        local vel = rng.int(vel_min, vel_max)
        notes[#notes + 1] = make_note('seed', #notes + 1, position, finish,
          pitch, vel, fields, nil)
      end
    end
  end
  return sort_notes(notes)
end

local function shape_value(kind, position)
  if kind == 'line' then
    return position
  elseif kind == 'sine' then
    return (1 - math.cos(2 * math.pi * position)) / 2
  else -- triangle
    return 1 - math.abs(2 * position - 1)
  end
end

-- Shape: `steps` notes spread evenly across the range. The normalized shape
-- (0..1) maps onto [pitch_min, pitch_max]; with a scale, each pitch is moved
-- to the nearest allowed pitch, preferring the lower one on a tie.
local function generate_shape(options)
  local startppq, endppq, span = range_fields(options)
  local kind = options.shape
  if kind ~= 'line' and kind ~= 'sine' and kind ~= 'triangle' then
    fail("shape must be 'line', 'sine' or 'triangle'")
  end
  local limit = max_notes_field(options)
  local steps = integer_field(options, 'steps', nil, 1, math.min(MAX_STEPS, limit))
  local pitch_min = integer_field(options, 'pitch_min', nil, 0, 127)
  local pitch_max = integer_field(options, 'pitch_max', nil, 0, 127)
  if pitch_max < pitch_min then fail('pitch_max must be >= pitch_min') end
  local vel = integer_field(options, 'vel', 100, 1, 127)
  local step_ppq = span / steps
  local note_length = number_field(options, 'note_length', step_ppq,
    MIN_DURATION, MAX_POSITION)
  local fields = output_fields(options)
  local allowed = scale_predicate(options)

  local function quantize(pitch)
    if not allowed or allowed(pitch) then return pitch end
    for distance = 1, 12 do
      local lower = pitch - distance
      if lower >= pitch_min and allowed(lower) then return lower end
      local upper = pitch + distance
      if upper <= pitch_max and allowed(upper) then return upper end
    end
    fail('scale and pitch range leave no playable pitch')
  end

  local notes = {}
  for index = 1, steps do
    local position = startppq + (index - 1) * step_ppq
    local normalized
    if steps == 1 then
      normalized = 0
    else
      normalized = shape_value(kind, (index - 1) / (steps - 1))
    end
    local target = math.floor(pitch_min + normalized * (pitch_max - pitch_min) + 0.5)
    if target < pitch_min then target = pitch_min end
    if target > pitch_max then target = pitch_max end
    local pitch = quantize(target)
    local finish = math.min(position + note_length, endppq)
    if finish > position then
      notes[#notes + 1] = make_note('shape', #notes + 1, position, finish,
        pitch, vel, fields, nil)
    end
  end
  return sort_notes(notes)
end

-- Stacks: chords laid end to end from range_start. Each chord is
-- { root=0..127, intervals={...}, duration_ppq=number, vel=optional }.
-- Any other string key on a chord (channel, muted, release_velocity, user
-- data) is copied to its notes. Chords that would start at or after
-- range_end are skipped; note ends are clipped to range_end.
local function generate_stacks(options)
  local startppq, endppq = range_fields(options)
  local chords = options.chords
  if type(chords) ~= 'table' then fail('chords must be a table') end
  if #chords == 0 then fail('chords must not be empty') end
  if #chords > MAX_CHORDS then
    fail(string.format('chords must contain at most %d entries', MAX_CHORDS))
  end
  local default_vel = integer_field(options, 'vel', 100, 1, 127)
  local limit = max_notes_field(options)
  local fields = output_fields(options)

  local cursor = startppq
  local notes = {}
  for chord_index = 1, #chords do
    local chord = chords[chord_index]
    if type(chord) ~= 'table' then
      fail('chord ' .. chord_index .. ' must be a table')
    end
    local root = integer_field(chord, 'root', nil, 0, 127)
    local duration = number_field(chord, 'duration_ppq', nil, MIN_DURATION, MAX_POSITION)
    local intervals = chord.intervals
    if type(intervals) ~= 'table' or #intervals == 0 then
      fail('chord ' .. chord_index .. ' needs a non-empty intervals list')
    end
    if #intervals > MAX_INTERVALS then
      fail('chord ' .. chord_index .. ' has more than ' .. MAX_INTERVALS .. ' intervals')
    end
    local chord_pitches, seen_pitches = {}, {}
    for interval_index = 1, #intervals do
      local interval = check_integer(intervals[interval_index],
        'chord ' .. chord_index .. ' interval', -127, 127)
      local pitch = root + interval
      if pitch < 0 or pitch > 127 then
        fail(string.format('chord %d interval %d gives pitch %d outside 0..127',
          chord_index, interval, pitch))
      end
      if seen_pitches[pitch] then
        fail(string.format('chord %d contains pitch %d twice', chord_index, pitch))
      end
      seen_pitches[pitch] = true
      chord_pitches[interval_index] = pitch
    end
    local vel = integer_field(chord, 'vel', default_vel, 1, 127)
    if cursor >= endppq - 1e-9 then break end
    if #notes + #intervals > limit then
      fail(string.format('stacks would exceed max_notes %d', limit))
    end
    local extras = {}
    for key, value in pairs(chord) do
      if key ~= 'root' and key ~= 'intervals' and key ~= 'duration_ppq'
          and key ~= 'vel' then
        extras[key] = value
      end
    end
    local finish = math.min(cursor + duration, endppq)
    if finish > cursor then
      for interval_index = 1, #chord_pitches do
        notes[#notes + 1] = make_note('stacks', #notes + 1, cursor, finish,
          chord_pitches[interval_index], vel, fields, extras)
      end
    end
    cursor = cursor + duration
  end
  return sort_notes(notes)
end

local GENERATORS = {
  rhythm = generate_rhythm,
  euclidean = generate_euclidean,
  seed = generate_seed,
  shape = generate_shape,
  stacks = generate_stacks,
}

function M.generate(tool, options)
  if type(tool) ~= 'string' then fail('tool must be a string') end
  local generator = GENERATORS[tool]
  if not generator then fail("unknown generator '" .. tostring(tool) .. "'") end
  if type(options) ~= 'table' then fail('options must be a table') end
  return generator(options)
end

M.generators = { 'rhythm', 'euclidean', 'seed', 'shape', 'stacks' }

return M
