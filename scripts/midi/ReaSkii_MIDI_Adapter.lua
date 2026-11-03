-- ReaSkii MIDI Adapter: raw REAPER MIDI events <-> independent note modules.
-- Pure Lua 5.4, no reaper.* calls and no I/O. The caller owns the take, the
-- preview session and the undo block; this module only maps bytes.
--
--   local A = dofile('ReaSkii_MIDI_Adapter.lua')
--   A.configure({ C = Core, T = Transformations, G = Generators, ppq = 960 })
--   raw_out = A.transform(raw_in, tool, options)  -- legacy + 9 tools
--   raw_out = A.generate(raw_in, tool, options)   -- 5 generators
--
-- Legacy tools (transpose, velocity, random_velocity, strum without grid_ppq)
-- are delegated to the Core function captured at configure() time, so wrapping
-- C.transform later cannot recurse.
--
-- Note tables keep the REAPER on-event id, release_velocity, selected
-- (flags & 1), muted (flags & 2), CCBZ/raw flag (flags & 4), and the mapping
-- metadata `on`, `off`, `source`. Events that do not belong to an edited note
-- are emitted with their original bytes and absolute position.
--
-- Deliberate refusals (never silent deletion):
--   * timing/pitch tools and every generator refuse a take containing CC,
--     poly/channel pressure or pitch bend, because note <-> curve ownership
--     cannot be proven in either direction;
--   * note-structural tools refuse SysEx/text/meta/notation and CCBZ-flagged
--     events attached without a safe mapping;
--   * selected notes that are malformed or have no note-off are refused;
--   * ambiguous same-pitch/same-channel collisions are refused.

local A = {}

local C, T, G = nil, nil, nil
local core_transform = nil
local PPQ = 960

local LEGACY = {
  transpose = true, velocity = true, random_velocity = true, strum = true,
}
local TIMING_TOOLS = {
  arpeggiate = true, chop = true, legato = true, quantize = true,
  reverse = true, stretch = true, strum = true,
}
local PITCH_TOOLS = { fit_scale = true, invert = true }
local STRUCTURAL_TOOLS = {
  arpeggiate = true, chop = true, rhythm = true, euclidean = true,
  seed = true, shape = true, stacks = true,
}
local TRANSFORM_TOOLS = {
  arpeggiate = true, chop = true, fit_scale = true, invert = true,
  legato = true, quantize = true, reverse = true, stretch = true,
  strum = true,
}
local GENERATOR_TOOLS = {
  rhythm = true, euclidean = true, seed = true, shape = true, stacks = true,
}

local function fail(message, level)
  error(message, (level or 1) + 1)
end

local function message_of(err)
  return (tostring(err):gsub('^.-:%d+: ', ''))
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

function A.configure(options)
  if type(options) ~= 'table' then fail('Adapter options must be a table') end
  if options.C then
    if type(options.C.transform) ~= 'function' or type(options.C.decode) ~= 'function' then
      fail('Core must expose transform and decode')
    end
    C = options.C
    core_transform = core_transform or C.transform
  end
  if options.T then
    if type(options.T.apply) ~= 'function' then fail('Transformations.apply is missing') end
    T = options.T
  end
  if options.G then
    if type(options.G.generate) ~= 'function' then fail('Generators.generate is missing') end
    G = options.G
  end
  if options.ppq ~= nil then A.set_ppq(options.ppq) end
  return A
end

function A.ppq() return PPQ end

function A.set_ppq(value)
  if not finite(value) or value <= 0 then fail('Invalid PPQ resolution') end
  PPQ = value
  return PPQ
end

-- Native grid values are quarter-note multiples; REAPER exposes PPQ too.
function A.qn_to_ppq(qn)
  if not finite(qn) then fail('Invalid quarter-note value') end
  return qn * PPQ
end

function A.ppq_to_qn(ppq)
  if not finite(ppq) then fail('Invalid PPQ value') end
  return ppq / PPQ
end

--------------------------------------------------------------------------
-- Analysis
--------------------------------------------------------------------------

local function status_of(event)
  if #event.msg == 0 then return nil end
  return event.msg:byte(1)
end

local function is_note_off(event)
  local status = status_of(event)
  if not status or #event.msg < 3 then return false end
  local kind = status & 0xF0
  return kind == 0x80 or (kind == 0x90 and event.msg:byte(3) == 0)
end

local function is_note_on(event)
  local status = status_of(event)
  if not status or #event.msg < 3 then return false end
  return status & 0xF0 == 0x90 and event.msg:byte(3) > 0
end

local function is_expression(event)
  local status = status_of(event)
  if not status then return false end
  local kind = status & 0xF0
  if kind == 0xA0 or kind == 0xD0 or kind == 0xE0 then return true end
  -- Bank select (CC0/CC32) is channel setup, not a note-owned curve. All
  -- other controllers (mod, volume, pan, sustain, expression...) can own one.
  if kind == 0xB0 then
    local controller = event.msg:byte(2)
    return controller ~= 0 and controller ~= 32
  end
  return false
end

local function is_unknown_attachment(event)
  local status = status_of(event)
  if not status then return false end
  if (event.flags & 4) ~= 0 then return true end -- CCBZ/raw-format attachment
  return status >= 0xF0 -- SysEx, text/meta and other system events
end

-- Decode through the Core and copy every event so its tables cannot be
-- mutated by the note modules.
local function analyse(raw)
  local decoded = C.decode(raw)
  local events, expression, unknown = {}, {}, {}
  for index = 1, #decoded do
    local source = decoded[index]
    local event = {
      pos = source.pos, flags = source.flags, msg = source.msg,
      id = source.id, seq = index,
    }
    events[index] = event
    if is_expression(event) then expression[#expression + 1] = event end
    if is_unknown_attachment(event) then unknown[#unknown + 1] = event end
  end
  return events, expression, unknown
end

local function note_parts(note)
  return note.on.msg:byte(1, 3)
end

-- Builds note tables. Unterminated unselected notes are omitted (they are not
-- touched); unterminated selected notes are refused.
local function notes_from(events, strict_selected)
  local active, notes, order = {}, {}, 0
  for _, event in ipairs(events) do
    if #event.msg >= 3 then
      local status, pitch, velocity = event.msg:byte(1, 3)
      local kind = status & 0xF0
      local key = (status & 15) * 128 + pitch
      if kind == 0x90 and velocity > 0 then
        active[key] = active[key] or {}
        local queue = active[key]
        order = order + 1
        queue[#queue + 1] = { on = event, seq = order }
      elseif kind == 0x80 or (kind == 0x90 and velocity == 0) then
        local queue = active[key]
        if queue and #queue > 0 then
          local head = table.remove(queue, 1)
          if #queue == 0 then active[key] = nil end
          notes[#notes + 1] = {
            on = head.on, off = event, pitch = pitch, seq = head.seq,
            selected = (head.on.flags & 1) == 1,
          }
        end
      end
    end
  end
  for _, queue in pairs(active) do
    for _, entry in ipairs(queue) do
      notes[#notes + 1] = {
        on = entry.on, pitch = entry.on.msg:byte(2), seq = entry.seq,
        selected = (entry.on.flags & 1) == 1, unterminated = true,
      }
    end
  end
  return notes, strict_selected
end

local function module_note(note)
  if note.unterminated then
    if note.selected then
      fail('Selected note at PPQ ' .. tostring(note.on.pos) .. ' (pitch '
        .. note.pitch .. ') has no note-off; fix or delete it first')
    end
    return nil
  end
  if #note.on.msg ~= 3 or #note.off.msg ~= 3 then
    if note.selected then
      fail('Selected note at PPQ ' .. tostring(note.on.pos)
        .. ' has a malformed event; fix it first')
    end
    return nil
  end
  local channel = note.on.msg:byte(1) & 15
  local note_flags = 0
  if (note.on.flags & 1) ~= 0 then note_flags = note_flags | 1 end
  if (note.on.flags & 2) ~= 0 then note_flags = note_flags | 2 end
  if (note.on.flags & 4) ~= 0 then note_flags = note_flags | 4 end
  return {
    id = note.on.id,
    startppq = note.on.pos,
    endppq = note.off.pos,
    pitch = note.pitch,
    vel = note.on.msg:byte(3),
    channel = channel,
    selected = note.selected,
    muted = (note.on.flags & 2) ~= 0,
    release_velocity = note.off.msg:byte(3),
    note_flags = note_flags,
    on = { id = note.on.id, pos = note.on.pos, msg = note.on.msg,
      flags = note.on.flags },
    off = { id = note.off.id, pos = note.off.pos, msg = note.off.msg,
      flags = note.off.flags },
    source = { on_id = note.on.id, off_id = note.off.id },
  }
end

-- Two selected/overlapping notes of the same pitch and channel cannot be
-- mapped back to a unique pair of note-offs without guessing.
local function assert_no_ambiguity(notes)
  for left = 1, #notes do
    local a = notes[left]
    if not a.unterminated then
      for right = left + 1, #notes do
        local b = notes[right]
        if not b.unterminated and (a.selected or b.selected)
            and a.pitch == b.pitch
            and (a.on.msg:byte(1) & 15) == (b.on.msg:byte(1) & 15)
            and a.on.pos < b.off.pos and b.on.pos < a.off.pos then
          fail('Ambiguous MIDI: pitch ' .. a.pitch .. ' on channel '
            .. (a.on.msg:byte(1) & 15)
            .. ' has overlapping or coincident notes; narrow the selection '
            .. 'and remove duplicates first')
        end
      end
    end
  end
end

-- Results may not land on an unselected note of the same pitch and channel.
local function assert_no_landing(results, originals)
  for _, result in ipairs(results) do
    if result.selected then
      for _, other in ipairs(originals) do
        if not other.selected and not other.unterminated
            and result.pitch == other.pitch
            and result.channel == other.channel
            and result.startppq < other.endppq
            and other.startppq < result.endppq then
          fail('Result would overlap an unselected note (pitch '
            .. result.pitch .. ', channel ' .. result.channel
            .. '); narrow or extend the selection')
        end
      end
    end
  end
end

--------------------------------------------------------------------------
-- Encoding
--------------------------------------------------------------------------

local function instant_key(event)
  if #event.msg < 3 then return nil end
  local status = event.msg:byte(1)
  return (status & 15) * 128 + event.msg:byte(2)
end

-- At one instant, a note-off must precede a note-on of the same pitch and
-- channel (contiguous legato boundary). Every other event keeps its order.
local function order_instant(group)
  local has_on = {}
  for _, event in ipairs(group) do
    if is_note_on(event) then
      local key = instant_key(event)
      if key then has_on[key] = true end
    end
  end
  if next(has_on) == nil then return group end
  local early, rest = {}, {}
  for _, event in ipairs(group) do
    local key = instant_key(event)
    if is_note_off(event) and key and has_on[key] then
      early[#early + 1] = event
    else
      rest[#rest + 1] = event
    end
  end
  local ordered = {}
  for _, event in ipairs(early) do ordered[#ordered + 1] = event end
  for _, event in ipairs(rest) do ordered[#ordered + 1] = event end
  return ordered
end

local function encode(events)
  local data, terminator = {}, nil
  for index, event in ipairs(events) do
    event.seq = event.seq or index
    if #event.msg == 0 then
      if not terminator or event.pos >= terminator.pos then terminator = event end
    else
      data[#data + 1] = event
    end
  end
  table.sort(data, function(a, b)
    if a.pos ~= b.pos then return a.pos < b.pos end
    return a.seq < b.seq
  end)
  local final, index = {}, 1
  while index <= #data do
    local position = data[index].pos
    local group = {}
    while index <= #data and data[index].pos == position do
      group[#group + 1] = data[index]
      index = index + 1
    end
    for _, event in ipairs(order_instant(group)) do final[#final + 1] = event end
  end
  local parts, previous = {}, 0
  for _, event in ipairs(final) do
    local position = math.floor(event.pos + 0.5)
    local delta = position - previous
    if delta < 0 then fail('Internal error: negative MIDI delta') end
    parts[#parts + 1] = string.pack('i4Bs4', delta, event.flags & 0xFF, event.msg)
    previous = position
  end
  if terminator then
    local last = previous
    if terminator.pos > last then last = math.floor(terminator.pos + 0.5) end
    local delta = last - previous
    parts[#parts + 1] = string.pack('i4Bs4', delta, terminator.flags & 0xFF, '')
  end
  return table.concat(parts)
end

local function replace_byte(message, index, value)
  return message:sub(1, index - 1) .. string.char(value) .. message:sub(index + 1)
end

local function remove_event(events, target)
  for index = 1, #events do
    if events[index] == target or events[index].id == target.id then
      table.remove(events, index)
      return true
    end
  end
  fail('Internal error: note event disappeared during rendering')
end

local function note_off_message(original, pitch, release)
  local status = original.off.msg:byte(1)
  local channel = status & 15
  if status & 0xF0 == 0x90 then
    -- A note-off encoded as note-on velocity 0 must stay velocity 0; a real
    -- release velocity needs the canonical 0x80 status.
    if release == 0 then
      return string.char(0x90 | channel, pitch, 0)
    end
    return string.char(0x80 | channel, pitch, release)
  end
  return string.char(status, pitch, release)
end

local function validate_result(note)
  integer(note.pitch, 0, 127, 'pitch')
  integer(note.vel, 1, 127, 'velocity')
  local release = note.release_velocity
  integer(release, 0, 127, 'release velocity')
  if not finite(note.startppq) or not finite(note.endppq) then
    fail('Result has a non-finite time')
  end
  local startppq = math.floor(note.startppq + 0.5)
  local endppq = math.floor(note.endppq + 0.5)
  if endppq <= startppq then fail('Result would create an empty note') end
  return startppq, endppq, release
end

local function render_mapped(events, originals, results)
  local by_source = {}
  for _, result in ipairs(results) do
    if result.selected then
      local source = result.source
      local on_id = source and source.on_id
      if on_id == nil and type(result.id) == 'number' then on_id = result.id end
      if on_id == nil then
        fail('Adapter lost the event mapping of a transformed note')
      end
      by_source[on_id] = by_source[on_id] or {}
      by_source[on_id][#by_source[on_id] + 1] = result
    end
    -- Unselected results are module copies; their raw events are untouched.
  end

  local writes, removals = {}, {}
  for _, original in ipairs(originals) do
    if original.selected then
      local list = by_source[original.id]
      if not list or #list == 0 then
        removals[#removals + 1] = original
      else
        local changed = {}
        for _, result in ipairs(list) do
          local startppq, endppq, release = validate_result(result)
          local flags = result.note_flags
          if flags == nil then flags = original.on.flags & 7 end
          local identical = startppq == original.on.pos and endppq == original.off.pos
            and result.pitch == original.pitch
            and result.vel == original.on.msg:byte(3)
            and release == original.off.msg:byte(3)
            and (flags & 7) == (original.on.flags & 7)
          changed[#changed + 1] = {
            result = result, startppq = startppq, endppq = endppq,
            release = release, flags = flags, identical = identical,
          }
        end
        local any_changed = #changed > 1
        if not any_changed then any_changed = not changed[1].identical end
        if any_changed then
          removals[#removals + 1] = original
          for _, item in ipairs(changed) do
            item.original = original
            writes[#writes + 1] = item
          end
        end
        -- A single identical result leaves the original events in place,
        -- byte-exact and order-exact.
      end
    end
  end

  for _, original in ipairs(removals) do
    remove_event(events, original.on)
    if original.off then remove_event(events, original.off) end
  end
  for _, item in ipairs(writes) do
    local original, result = item.original, item.result
    local on_message = replace_byte(replace_byte(original.on.msg, 2, result.pitch),
      3, result.vel)
    local off_message = note_off_message(original, result.pitch, item.release)
    events[#events + 1] = {
      pos = item.startppq, flags = item.flags & 7, msg = on_message,
      id = original.on.id, seq = #events + 1,
    }
    events[#events + 1] = {
      pos = item.endppq, flags = original.off.flags & 7, msg = off_message,
      id = original.off.id, seq = #events + 1,
    }
  end
end

local function render_generated(events, generated, base_id, check_collisions)
  local buckets = {}
  for _, event in ipairs(events) do
    local key = instant_key(event)
    if key then
      buckets[key] = buckets[key] or {}
      buckets[key][#buckets[key] + 1] = event
    end
  end
  local next_id = base_id
  for _, note in ipairs(generated) do
    local startppq, endppq, release = validate_result(note)
    local channel = integer(note.channel, 0, 15, 'channel')
    local key = channel * 128 + note.pitch
    local bucket = buckets[key]
    local _ = check_collisions
    next_id = next_id + 1
    local flags = 1
    if note.muted then flags = flags | 2 end
    local on_event = {
      pos = startppq, flags = flags,
      msg = string.char(0x90 | channel, note.pitch, note.vel),
      id = next_id, seq = #events + 1,
    }
    next_id = next_id + 1
    local off_event = {
      pos = endppq, flags = 0,
      msg = string.char(0x80 | channel, note.pitch, release),
      id = next_id, seq = #events + 2,
    }
    events[#events + 1] = on_event
    events[#events + 1] = off_event
    if bucket then
      bucket[#bucket + 1] = on_event
      bucket[#bucket + 1] = off_event
    end
  end
end

--------------------------------------------------------------------------
-- Dispatch
--------------------------------------------------------------------------

local function is_integral(events)
  for _, event in ipairs(events) do
    if math.abs(event.pos - math.floor(event.pos + 0.5)) > 1e-6 then return false end
  end
  return true
end

local function assert_integral(events)
  if not is_integral(events) then
    fail('This take has fractional PPQ positions; this edit needs integral ticks')
  end
end

local function legacy(raw, tool, options)
  if not core_transform then fail('Adapter.configure({C=Core}) must run first') end
  return core_transform(raw, tool, options)
end

function A.is_legacy(tool) return LEGACY[tool] == true end

function A.tools()
  local list = {}
  local seen = {}
  for _, name in ipairs({ 'transpose', 'velocity', 'random_velocity', 'strum',
    'arpeggiate', 'chop', 'fit_scale', 'invert', 'legato', 'quantize',
    'reverse', 'stretch' }) do
    if not seen[name] then
      seen[name] = true
      list[#list + 1] = name
    end
  end
  return list
end

function A.generators()
  local list = {}
  for _, name in ipairs({ 'rhythm', 'euclidean', 'seed', 'shape', 'stacks' }) do
    list[#list + 1] = name
  end
  return list
end

local function build_notes(events)
  local raw_notes = notes_from(events)
  local list, originals = {}, {}
  for _, note in ipairs(raw_notes) do
    if note.selected and note.unterminated then
      fail('Selected note at PPQ ' .. tostring(note.on.pos) .. ' (pitch '
        .. note.pitch .. ') has no note-off; fix or delete it first')
    end
    local mapped = module_note(note)
    if mapped then
      list[#list + 1] = mapped
      originals[#originals + 1] = note
    elseif note.selected then
      fail('Selected note cannot be mapped to raw MIDI events')
    end
  end
  return list, originals
end

local function guard_structure(events)
  local notes = notes_from(events)
  for _, note in ipairs(notes) do
    if note.selected and note.unterminated then
      fail('Selected note at PPQ ' .. tostring(note.on.pos) .. ' (pitch '
        .. note.pitch .. ') has no note-off; fix or delete it first')
    end
  end
  assert_no_ambiguity(notes)
end

function A.transform(raw, tool, options)
  if type(raw) ~= 'string' then fail('MIDI must be a raw string') end
  if type(tool) ~= 'string' then fail('Tool name must be a string') end
  options = options or {}
  if type(options) ~= 'table' then fail('Options must be a table') end
  if GENERATOR_TOOLS[tool] then return A.generate(raw, tool, options) end
  if LEGACY[tool] and not (tool == 'strum' and options.grid_ppq ~= nil) then
    local events = analyse(raw)
    guard_structure(events)
    return legacy(raw, tool, options)
  end
  if not TRANSFORM_TOOLS[tool] then fail('Unknown MIDI tool: ' .. tool) end
  if not T then fail('Transformations module is not loaded') end

  local events, expression, unknown = analyse(raw)
  if (TIMING_TOOLS[tool] or PITCH_TOOLS[tool]) and #expression > 0 then
    fail('Blocked: the take contains CC, pressure or pitch-bend data. '
      .. 'ReaSkii cannot prove which expression belongs to each edited note, '
      .. 'so nothing was changed')
  end
  if STRUCTURAL_TOOLS[tool] and #unknown > 0 then
    fail('Blocked: SysEx, text/notation or CCBZ-flagged events are attached to '
      .. 'this take and this tool would have to split them. Nothing was changed')
  end
  guard_structure(events)

  local notes, _ = build_notes(events)
  local selected = 0
  for _, note in ipairs(notes) do if note.selected then selected = selected + 1 end end
  if selected == 0 then fail('Select at least one note before using ' .. tool) end

  local ok, result = pcall(T.apply, notes, tool, options)
  if not ok then fail(message_of(result)) end
  if type(result) ~= 'table' then fail('Transformation returned no notes') end
  assert_no_landing(result, notes)
  assert_integral(events)
  render_mapped(events, notes, result)
  return encode(events)
end

function A.generate(raw, tool, options)
  if type(raw) ~= 'string' then fail('MIDI must be a raw string') end
  if type(tool) ~= 'string' then fail('Generator name must be a string') end
  if not GENERATOR_TOOLS[tool] then fail('Unknown generator: ' .. tool) end
  if not G then fail('Generators module is not loaded') end
  options = options or {}
  if type(options) ~= 'table' then fail('Options must be a table') end
  local mode = options.mode or 'add'
  if mode ~= 'add' and mode ~= 'replace' then
    fail("mode must be 'add' or 'replace'")
  end
  if not finite(options.range_start) or not finite(options.range_end)
      or options.range_end <= options.range_start then
    fail('An explicit generation range (range_start < range_end) is required')
  end

  local events, expression, unknown = analyse(raw)
  if #expression > 0 then
    fail('Blocked: the take contains CC, pressure or pitch-bend data; '
      .. 'generated notes would orphan those curves. Nothing was changed')
  end
  if #unknown > 0 then
    fail('Blocked: SysEx, text/notation or CCBZ-flagged events are attached to '
      .. 'this take and generation could split them. Nothing was changed')
  end
  assert_no_ambiguity(notes_from(events))

  local notes = build_notes(events)
  local generation = {}
  for key, value in pairs(options) do
    if key ~= 'mode' then generation[key] = value end
  end
  local ok, generated = pcall(G.generate, tool, generation)
  if not ok then fail(message_of(generated)) end
  if type(generated) ~= 'table' then fail('Generator returned no notes') end
  for _, note in ipairs(generated) do
    if note.startppq < options.range_start
        or note.startppq >= options.range_end
        or note.endppq > options.range_end + 1e-6
        or note.endppq <= note.startppq then
      fail('Generator produced a note outside the explicit range')
    end
  end
  assert_integral(events)

  if mode == 'replace' then
    local kept = {}
    for _, note in ipairs(notes) do
      if note.startppq >= options.range_start
          and note.startppq < options.range_end then
        remove_event(events, note.on)
        if note.off then remove_event(events, note.off) end
      else
        kept[#kept + 1] = note
      end
    end
    for _, note in ipairs(generated) do
      for _, other in ipairs(kept) do
        if note.pitch == other.pitch and note.channel == other.channel
            and note.startppq < other.endppq
            and other.startppq < note.endppq then
          fail('Generated note would overlap a note outside the replaced range '
            .. '(pitch ' .. note.pitch .. ', channel ' .. note.channel .. ')')
        end
      end
    end
    local base_id = 0
    for _, event in ipairs(events) do
      if type(event.id) == 'number' and event.id > base_id then base_id = event.id end
    end
    render_generated(events, generated, base_id, false)
  else
    for _, note in ipairs(generated) do
      for _, other in ipairs(notes) do
        if note.pitch == other.pitch and note.channel == other.channel
            and note.startppq < other.endppq
            and other.startppq < note.endppq then
          fail('Generated note would overlap an existing note (pitch '
            .. note.pitch .. ', channel ' .. note.channel
            .. '); remove it, choose another range or use explicit replace mode')
        end
      end
    end
    local base_id = 0
    for _, event in ipairs(events) do
      if type(event.id) == 'number' and event.id > base_id then base_id = event.id end
    end
    render_generated(events, generated, base_id, true)
  end
  return encode(events)
end

-- Read-only diagnostics for the panel.
function A.inspect(raw)
  local events, expression, unknown = analyse(raw)
  local notes = notes_from(events)
  local selected, unterminated = 0, 0
  for _, note in ipairs(notes) do
    if note.selected then selected = selected + 1 end
    if note.unterminated then unterminated = unterminated + 1 end
  end
  return {
    events = #events, notes = #notes, selected = selected,
    unterminated = unterminated, expression = #expression,
    unknown = #unknown,
  }
end

-- Optional local interception of Core.transform. The original function was
-- captured at configure() time, so no call can recurse.
function A.install(Core)
  if Core then A.configure({ C = Core }) end
  if not C or not core_transform then fail('Adapter.install needs the Core module') end
  if C.transform ~= A.transform then C.transform = A.transform end
  return C
end

A.legacy_tools = LEGACY
A.timing_tools = TIMING_TOOLS
A.pitch_tools = PITCH_TOOLS
A.structural_tools = STRUCTURAL_TOOLS
A.transform_tools = TRANSFORM_TOOLS
A.generator_tools = GENERATOR_TOOLS

return A
