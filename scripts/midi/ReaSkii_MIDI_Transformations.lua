-- ReaSkii MIDI Transformations: independent pure-Lua implementation.
-- Lua 5.4, no reaper/gfx/io calls. Behaviour is specified locally; it is NOT
-- an Ableton-parity port and has not been compared with real Live exports.
--
-- Contract:
--   notes = { {startppq=number, endppq=number, pitch=0..127, vel=1..127,
--              channel=0..15, selected=boolean, muted=boolean, id=opaque,
--              release_velocity=0..127, ...extra fields } }
--   M.apply(notes, tool, options) -> a new list. Input tables are never
--   mutated. Every field, including unknown extras, is copied shallowly.
--   Unselected notes are copied unchanged (values identical, new objects).
--   Generated notes receive deterministic ids "reaskii:<tool>:<ordinal>:<n>".
--
-- Common semantics:
--   * PPQ times, half-open intervals [startppq, endppq).
--   * No randomness and no global seed: every call is deterministic.
--   * Tools act on selected notes only; selected notes are removed and their
--     replacements are emitted at the source position, preserving input order.
--   * A transformed/generated note that would overlap an unselected note on
--     the same pitch+channel is rejected with an error (no silent clamping).
--   * Limits: 100000 input notes, 65536 generated notes per call,
--     0 <= time <= 1e9 PPQ. Invalid parameters and results raise an error.
--   * MPE curves are out of scope. Channels, muted, extra fields and
--     release_velocity are preserved; the parent adapter must block unsafe
--     MPE operations.
--
-- Tools and options (all times in PPQ, all options explicit):
--   arpeggiate {mode="up"|"down"|"updown", rate_ppq>0, gate>0,
--               octaves=1..8, range_start>=0, range_end>range_start}
--     Uses the distinct selected pitches (first occurrence in input order),
--     expands them by octaves, then cycles the pattern on every rate step in
--     [range_start, range_end). Note length = min(rate*gate, range_end-start).
--     "updown" does not repeat the lowest/highest endpoint. Pitches outside
--     0..127 are rejected.
--   chop {parts=2..64}
--     Splits each selected note into equal contiguous parts sharing the same
--     pitch, channel, velocity and release_velocity.
--   quantize {grid_ppq>0, strength=0..1}
--     Moves the start toward the nearest grid point with the given strength,
--     preserving duration. Exact halfway points go to the lower grid point.
--   reverse {range_start>=0, range_end>range_start}
--     Mirrors selected notes inside the range: new_start = range_start +
--     (range_end - end). Every selected note must lie fully inside the range.
--   stretch {factor=0.01..100, anchor>=0}
--     new_time = anchor + (old_time - anchor) * factor, starts and ends.
--   legato {}
--     Extends a selected note to the next strictly later start on the same
--     channel (selected or not). It never shortens: end = max(end, next
--     start). No next start means no change.
--   fit_scale {root=0..11, intervals={semitone offsets 0..11}}
--     Snaps each selected pitch to the nearest pitch of the scale; an exact
--     tie goes to the lower pitch. Intervals must be unique and non-empty.
--   invert {pivot=0..127}
--     Melodic inversion: new_pitch = 2*pivot - pitch. Out-of-range results
--     are rejected.
--   strum {low=-100..100, high=-100..100, grid_ppq>0, tension=-1..1,
--          onset_tolerance>=0}
--     Groups selected notes whose start differs from the group's first start
--     by at most onset_tolerance. Within a group sorted low to high, the
--     normalized position t in [0,1] gives shaped(t) =
--     1-(1-t)^(2^(2*tension)). Offset = (low/100)*grid*(1-shaped) +
--     (high/100)*grid*shaped. Only starts move; ends and release velocities
--     stay fixed. Single-note groups do not move. This curve is documented
--     locally and is not measured against Ableton's Strum display.

local M = {}

local MAX_NOTES = 100000
local MAX_GENERATED = 65536
local MAX_PPQ = 1e9

local function fail(message)
  error(message, 0)
end

local function finite(value)
  return type(value) == 'number' and value == value
    and value > -math.huge and value < math.huge
end

local function integer(value, low, high, name)
  if type(value) ~= 'number' or not finite(value) or value % 1 ~= 0
      or value < low or value > high then
    fail('Invalid ' .. name)
  end
  return value
end

local function check_times(startppq, endppq)
  if not finite(startppq) or startppq < 0 or startppq > MAX_PPQ then
    fail('Transformation produced an invalid start time')
  end
  if not finite(endppq) or endppq <= startppq or endppq > MAX_PPQ then
    fail('Transformation produced an invalid end time')
  end
  return startppq, endppq
end

local function copy_note(note)
  local out = {}
  for key, value in pairs(note) do out[key] = value end
  return out
end

local function generated_note(source, ordinal, tool, part, startppq, endppq)
  check_times(startppq, endppq)
  local out = copy_note(source)
  out.startppq = startppq
  out.endppq = endppq
  out.selected = true
  out.id = 'reaskii:' .. tool .. ':' .. ordinal .. ':' .. part
  return out
end

local function validate_notes(notes)
  if type(notes) ~= 'table' then fail('Notes must be a list') end
  if #notes > MAX_NOTES then fail('Too many input notes') end
  for index = 1, #notes do
    local note = notes[index]
    if type(note) ~= 'table' then fail('Invalid note at index ' .. index) end
    if not finite(note.startppq) or note.startppq < 0
        or note.startppq > MAX_PPQ then
      fail('Invalid startppq at index ' .. index)
    end
    if not finite(note.endppq) or note.endppq <= note.startppq
        or note.endppq > MAX_PPQ then
      fail('Invalid endppq at index ' .. index)
    end
    integer(note.pitch, 0, 127, 'pitch at index ' .. index)
    integer(note.vel, 1, 127, 'vel at index ' .. index)
    integer(note.channel, 0, 15, 'channel at index ' .. index)
    if type(note.selected) ~= 'boolean' then
      fail('Invalid selected at index ' .. index)
    end
    if type(note.muted) ~= 'boolean' then
      fail('Invalid muted at index ' .. index)
    end
    if note.release_velocity ~= nil then
      integer(note.release_velocity, 0, 127,
        'release_velocity at index ' .. index)
    end
  end
end

local function option_number(options, name, default, low, high)
  local value = options[name]
  if value == nil then
    if default == nil then fail('Missing option: ' .. name) end
    value = default
  end
  if not finite(value) or value < low or value > high then
    fail('Invalid option: ' .. name)
  end
  return value
end

local function option_integer(options, name, default, low, high)
  local value = option_number(options, name, default, low, high)
  if value % 1 ~= 0 then fail('Option must be an integer: ' .. name) end
  return value
end

local function assemble(notes, replacements)
  local out = {}
  for index = 1, #notes do
    local replacement = replacements[index]
    if replacement then
      for _, note in ipairs(replacement) do out[#out + 1] = note end
    else
      out[#out + 1] = copy_note(notes[index])
    end
  end
  if #out > MAX_NOTES then fail('Result would exceed the note limit') end
  return out
end

-- A transformed note must not cover an unselected note of the same pitch on
-- the same channel. Selected/selected overlaps are left to the caller.
local function assert_no_external_collision(candidates, notes)
  local by_pitch_channel = {}
  for index = 1, #notes do
    local other = notes[index]
    if not other.selected then
      local key = other.pitch * 16 + other.channel
      local bucket = by_pitch_channel[key]
      if not bucket then
        bucket = {}
        by_pitch_channel[key] = bucket
      end
      bucket[#bucket + 1] = other
    end
  end
  for _, candidate in ipairs(candidates) do
    local bucket = by_pitch_channel[candidate.pitch * 16 + candidate.channel]
    if bucket then
      for _, other in ipairs(bucket) do
        if candidate.startppq < other.endppq
            and other.startppq < candidate.endppq then
          fail('Transformation would overlap an unselected note (pitch '
            .. candidate.pitch .. ', channel ' .. candidate.channel .. ')')
        end
      end
    end
  end
end

local function selected_count(notes)
  local count = 0
  for index = 1, #notes do
    if notes[index].selected then count = count + 1 end
  end
  return count
end

local function tool_chop(notes, options)
  local parts = option_integer(options, 'parts', nil, 2, 64)
  local selected = selected_count(notes)
  if selected * parts + (#notes - selected) > MAX_NOTES then
    fail('Chop would exceed the note limit')
  end
  local replacements = {}
  for index = 1, #notes do
    local note = notes[index]
    if note.selected then
      local list = {}
      local duration = note.endppq - note.startppq
      local step = duration / parts
      for part = 1, parts do
        local startppq = note.startppq + (part - 1) * step
        local endppq = (part == parts) and note.endppq
          or (note.startppq + part * step)
        list[#list + 1] = generated_note(note, index, 'chop', part,
          startppq, endppq)
      end
      replacements[index] = list
    end
  end
  return assemble(notes, replacements)
end

local function tool_quantize(notes, options)
  local grid = option_number(options, 'grid_ppq', nil, 1e-6, MAX_PPQ)
  local strength = option_number(options, 'strength', 1, 0, 1)
  local replacements, changed = {}, {}
  for index = 1, #notes do
    local note = notes[index]
    if note.selected then
      local quotient = note.startppq / grid
      local lower = math.floor(quotient)
      if quotient - lower > 0.5 then lower = lower + 1 end
      local target = lower * grid
      local startppq = note.startppq + (target - note.startppq) * strength
      local endppq = startppq + (note.endppq - note.startppq)
      check_times(startppq, endppq)
      local out = copy_note(note)
      out.startppq = startppq
      out.endppq = endppq
      replacements[index] = { out }
      changed[#changed + 1] = out
    end
  end
  assert_no_external_collision(changed, notes)
  return assemble(notes, replacements)
end

local function tool_reverse(notes, options)
  local range_start = option_number(options, 'range_start', nil, 0, MAX_PPQ)
  local range_end = option_number(options, 'range_end', nil, 0, MAX_PPQ)
  if range_end <= range_start then fail('Invalid reverse range') end
  local replacements, changed = {}, {}
  for index = 1, #notes do
    local note = notes[index]
    if note.selected then
      if note.startppq < range_start or note.endppq > range_end then
        fail('Reverse range must contain every selected note')
      end
      local startppq = range_start + (range_end - note.endppq)
      local endppq = range_start + (range_end - note.startppq)
      check_times(startppq, endppq)
      local out = copy_note(note)
      out.startppq = startppq
      out.endppq = endppq
      replacements[index] = { out }
      changed[#changed + 1] = out
    end
  end
  assert_no_external_collision(changed, notes)
  return assemble(notes, replacements)
end

local function tool_stretch(notes, options)
  local factor = option_number(options, 'factor', nil, 0.01, 100)
  local anchor = option_number(options, 'anchor', nil, 0, MAX_PPQ)
  local replacements, changed = {}, {}
  for index = 1, #notes do
    local note = notes[index]
    if note.selected then
      local startppq = anchor + (note.startppq - anchor) * factor
      local endppq = anchor + (note.endppq - anchor) * factor
      check_times(startppq, endppq)
      local out = copy_note(note)
      out.startppq = startppq
      out.endppq = endppq
      replacements[index] = { out }
      changed[#changed + 1] = out
    end
  end
  assert_no_external_collision(changed, notes)
  return assemble(notes, replacements)
end

local function tool_legato(notes, options)
  local _ = options -- legato has no options
  local replacements, changed = {}, {}
  for index = 1, #notes do
    local note = notes[index]
    if note.selected then
      local next_start
      for other_index = 1, #notes do
        local other = notes[other_index]
        if other.channel == note.channel
            and other.startppq > note.startppq
            and (next_start == nil or other.startppq < next_start) then
          next_start = other.startppq
        end
      end
      local out = copy_note(note)
      if next_start and next_start > out.endppq then
        out.endppq = next_start
        check_times(out.startppq, out.endppq)
        changed[#changed + 1] = out
      end
      replacements[index] = { out }
    end
  end
  assert_no_external_collision(changed, notes)
  return assemble(notes, replacements)
end

local function tool_fit_scale(notes, options)
  local root = option_integer(options, 'root', nil, 0, 11)
  local intervals = options.intervals
  if type(intervals) ~= 'table' or #intervals < 1 or #intervals > 12 then
    fail('Invalid option: intervals')
  end
  local degrees = {}
  for index = 1, #intervals do
    local value = integer(intervals[index], 0, 11, 'scale interval')
    if degrees[value] then fail('Duplicate scale interval') end
    degrees[value] = true
  end
  local function in_scale(pitch)
    return degrees[(pitch - root) % 12] == true
  end
  local replacements, changed = {}, {}
  for index = 1, #notes do
    local note = notes[index]
    if note.selected then
      local pitch = note.pitch
      if not in_scale(pitch) then
        local found
        for distance = 1, 127 do
          local lower = pitch - distance
          if lower >= 0 and in_scale(lower) then
            found = lower
            break
          end
          local upper = pitch + distance
          if upper <= 127 and in_scale(upper) then
            found = upper
            break
          end
        end
        if not found then fail('No scale pitch inside the MIDI range') end
        pitch = found
      end
      local out = copy_note(note)
      out.pitch = pitch
      replacements[index] = { out }
      if pitch ~= note.pitch then changed[#changed + 1] = out end
    end
  end
  assert_no_external_collision(changed, notes)
  return assemble(notes, replacements)
end

local function tool_invert(notes, options)
  local pivot = option_integer(options, 'pivot', nil, 0, 127)
  local replacements, changed = {}, {}
  for index = 1, #notes do
    local note = notes[index]
    if note.selected then
      local pitch = 2 * pivot - note.pitch
      if pitch < 0 or pitch > 127 then
        fail('Invert result is outside the MIDI pitch range')
      end
      local out = copy_note(note)
      out.pitch = pitch
      replacements[index] = { out }
      changed[#changed + 1] = out
    end
  end
  assert_no_external_collision(changed, notes)
  return assemble(notes, replacements)
end

local function tool_arpeggiate(notes, options)
  local mode = options.mode or 'up'
  if mode ~= 'up' and mode ~= 'down' and mode ~= 'updown' then
    fail('Invalid option: mode')
  end
  local rate = option_number(options, 'rate_ppq', nil, 1e-6, MAX_PPQ)
  local gate = option_number(options, 'gate', nil, 0.01, 8)
  local octaves = option_integer(options, 'octaves', 1, 1, 8)
  local range_start = option_number(options, 'range_start', nil, 0, MAX_PPQ)
  local range_end = option_number(options, 'range_end', nil, 0, MAX_PPQ)
  if range_end <= range_start then fail('Invalid arpeggiate range') end

  local pool, seen = {}, {}
  for index = 1, #notes do
    local note = notes[index]
    if note.selected and not seen[note.pitch] then
      seen[note.pitch] = true
      pool[#pool + 1] = { note = note, ordinal = index }
    end
  end
  table.sort(pool, function(a, b)
    return a.note.pitch < b.note.pitch
  end)
  if #pool == 0 then return assemble(notes, {}) end

  local sequence = {}
  for octave = 0, octaves - 1 do
    for _, item in ipairs(pool) do
      local pitch = item.note.pitch + 12 * octave
      if pitch > 127 then
        fail('Arpeggiate octave exceeds the MIDI pitch range')
      end
      sequence[#sequence + 1] = {
        pitch = pitch, source = item.note, ordinal = item.ordinal,
      }
    end
  end
  if mode == 'down' then
    local reversed = {}
    for index = #sequence, 1, -1 do
      reversed[#reversed + 1] = sequence[index]
    end
    sequence = reversed
  elseif mode == 'updown' then
    local updown = {}
    for index = 1, #sequence do updown[#updown + 1] = sequence[index] end
    for index = #sequence - 1, 2, -1 do
      updown[#updown + 1] = sequence[index]
    end
    sequence = updown
  end

  local count = math.ceil((range_end - range_start) / rate - 1e-9)
  if count < 1 then count = 1 end
  if count > MAX_GENERATED then
    fail('Arpeggiate would generate too many notes')
  end
  local selected = selected_count(notes)
  if #notes - selected + count > MAX_NOTES then
    fail('Arpeggiate would exceed the note limit')
  end

  local list = {}
  for step = 1, count do
    local startppq = range_start + (step - 1) * rate
    local endppq = startppq + rate * gate
    if endppq > range_end then endppq = range_end end
    if endppq <= startppq then
      fail('Arpeggiate produced an empty note at the range end')
    end
    local item = sequence[(step - 1) % #sequence + 1]
    local out = generated_note(item.source, item.ordinal, 'arpeggiate',
      step, startppq, endppq)
    out.pitch = item.pitch
    list[#list + 1] = out
  end
  assert_no_external_collision(list, notes)

  local first_selected
  for index = 1, #notes do
    if notes[index].selected then first_selected = index; break end
  end
  local replacements = { [first_selected] = list }
  for index = 1, #notes do
    if notes[index].selected and index ~= first_selected then
      replacements[index] = {}
    end
  end
  return assemble(notes, replacements)
end

local function tool_strum(notes, options)
  local low = option_number(options, 'low', nil, -100, 100)
  local high = option_number(options, 'high', nil, -100, 100)
  local grid = option_number(options, 'grid_ppq', nil, 1e-6, MAX_PPQ)
  local tension = option_number(options, 'tension', 0, -1, 1)
  local tolerance = option_number(options, 'onset_tolerance', nil, 0, MAX_PPQ)
  if low == 0 and high == 0 then return assemble(notes, {}) end

  local list = {}
  for index = 1, #notes do
    if notes[index].selected then
      list[#list + 1] = { note = notes[index], ordinal = index }
    end
  end
  table.sort(list, function(a, b)
    if a.note.startppq ~= b.note.startppq then
      return a.note.startppq < b.note.startppq
    end
    if a.note.pitch ~= b.note.pitch then
      return a.note.pitch < b.note.pitch
    end
    return a.ordinal < b.ordinal
  end)

  local groups = {}
  for _, item in ipairs(list) do
    local group = groups[#groups]
    if not group or item.note.startppq - group.anchor > tolerance then
      groups[#groups + 1] = { anchor = item.note.startppq, items = { item } }
    else
      group.items[#group.items + 1] = item
    end
  end

  local replacements, changed = {}, {}
  local low_amplitude = low / 100 * grid
  local high_amplitude = high / 100 * grid
  local exponent = 2 ^ (2 * tension)
  for _, group in ipairs(groups) do
    local items = group.items
    if #items > 1 then
      table.sort(items, function(a, b)
        if a.note.pitch ~= b.note.pitch then
          return a.note.pitch < b.note.pitch
        end
        if a.note.startppq ~= b.note.startppq then
          return a.note.startppq < b.note.startppq
        end
        return a.ordinal < b.ordinal
      end)
      local count = #items
      for position, item in ipairs(items) do
        local t = (position - 1) / (count - 1)
        local shaped = 1 - (1 - t) ^ exponent
        local offset = low_amplitude * (1 - shaped) + high_amplitude * shaped
        local startppq = item.note.startppq + offset
        local endppq = item.note.endppq
        check_times(startppq, endppq)
        local out = copy_note(item.note)
        out.startppq = startppq
        out.endppq = endppq
        replacements[item.ordinal] = { out }
        changed[#changed + 1] = out
      end
    end
  end
  assert_no_external_collision(changed, notes)
  return assemble(notes, replacements)
end

local tools = {
  arpeggiate = tool_arpeggiate,
  chop = tool_chop,
  fit_scale = tool_fit_scale,
  invert = tool_invert,
  legato = tool_legato,
  quantize = tool_quantize,
  reverse = tool_reverse,
  stretch = tool_stretch,
  strum = tool_strum,
}

function M.apply(notes, tool, options)
  validate_notes(notes)
  if type(tool) ~= 'string' then fail('Transformation name must be a string') end
  options = options or {}
  if type(options) ~= 'table' then fail('Options must be a table') end
  local implementation = tools[tool]
  if not implementation then fail('Unknown transformation: ' .. tool) end
  return implementation(notes, options)
end

return M
