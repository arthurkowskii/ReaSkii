-- ReaSkii MIDI Expression: independent MPE expression prototype.
-- Pure Lua 5.4. No host API calls, no gfx calls, no I/O, no synth/RPN setup.
-- This is not an Ableton-parity claim; it is a byte-level editing contract.
--
-- E.transform(raw, dimension, options) edits the selected notes only.
--   dimension: 'pitch' (14-bit pitch bend), 'slide' (CC74), 'pressure'
--              (channel pressure).
--   options.points = { {t=0,value=...}, {t=1,value=...}, ... }
--     t is relative 0..1 and strictly increasing. Values are absolute in
--     replace mode: 0..16383 for pitch (8192 is centre), 0..127 for slide and
--     pressure. At least two points are required.
--   options.mode = 'replace' (default) removes only the chosen dimension
--     events inside each selected note's attributable window. 'add' keeps
--     other chosen-dimension events and adds explicit offsets: pitch uses
--     (point.value - 8192), slide/pressure use point.value, against the last
--     existing value on that channel at or before the point (neutral when
--     none exists). Add results are clamped and are not fed back into later
--     points, so a single call is deterministic rather than cumulative.
--   options.steps = 2..1024 samples across the note (default 32). Samples are
--     rounded to whole PPQ ticks; when several samples share a tick the later
--     sample wins, which is a stable deduplication.
--   options.shape = 'constant' | 'linear' (default) | 'sine' | 'triangle'.
--     Sine is cosine ease; triangle is a monotonic quadratic ease through the
--     midpoint. Constant holds the left point until the next point.
--   options.member_channels = explicit 0-based MIDI channels. Default 1..15
--     (MIDI channels 2..16). Channel 0 is the master channel and is refused.
--
-- Selected note flags come from the note-on (flags & 1), matching the Core
-- and Adapter modules. Note-on/note-off bytes, release velocity and note
-- flags are never rewritten here. Unrelated CC, SysEx, text/meta and all
-- non-selected-channel data keep their message bytes and positions.
--
-- Attribution is deliberately conservative. A selected note is refused when:
--   * it is unterminated or malformed;
--   * its channel is the master channel or is outside member_channels;
--   * another note on the same channel overlaps it, selected or not;
--   * another note on the same channel starts or ends exactly at its boundary
--     (a contiguous boundary makes an event at that tick ambiguous).
-- No channel reallocation is attempted. Ambiguity is an error, never a guess.
--
-- Editable window: [note-on tick, note-off tick - 1]. A point at t=0 lands on
-- the note-on tick and is sorted after the note-on; a point at t=1 lands one
-- tick before the note-off. At one tick the order is note-off, neutral pitch
-- reset, note-on, generated expression, then other events. The original final
-- terminator is preserved, moved beyond every event if necessary.
--
-- Bounds: 64 MiB raw payload, 100000 events, 2^31-1 PPQ, 4096 notes, 4096
-- points per call. Budgets are checked before allocation. Nothing is emitted
-- for an empty selection: the exact input string is returned.

local E = {}

local MAX_RAW_BYTES = 64 * 1024 * 1024
local MAX_EVENTS = 100000
local MAX_NOTES = 4096
local MAX_POINTS = 4096
local MAX_PPQ = 0x7FFFFFFF
local MASTER_CHANNEL = 0

local DIMENSIONS = {
  pitch = {
    name = 'pitch', min = 0, max = 16383, neutral = 8192,
    kind = 0xE0,
  },
  slide = {
    name = 'slide', min = 0, max = 127, neutral = 0,
    kind = 0xB0, controller = 74,
  },
  pressure = {
    name = 'pressure', min = 0, max = 127, neutral = 0,
    kind = 0xD0,
  },
}

local function fail(message)
  error(message, 0)
end

local function finite(value)
  return type(value) == 'number' and value == value
    and value > -math.huge and value < math.huge
end

local function integer(value, low, high, name)
  if not finite(value) or value % 1 ~= 0 or value < low or value > high then
    fail('Invalid ' .. name)
  end
  return value
end

local function dimension_of(name)
  if type(name) ~= 'string' or not DIMENSIONS[name] then
    fail('Unsupported expression dimension: ' .. tostring(name))
  end
  return DIMENSIONS[name]
end

local function decode(raw)
  if type(raw) ~= 'string' then fail('MIDI must be a raw string') end
  if #raw > MAX_RAW_BYTES then fail('MIDI payload exceeds the expression limit') end
  local events, offset, position = {}, 1, 0
  while offset <= #raw do
    if offset + 8 > #raw then fail('Truncated MIDI event header') end
    local delta = string.unpack('i4', raw, offset)
    local flags = raw:byte(offset + 4)
    local length = string.unpack('i4', raw, offset + 5)
    local data = offset + 9
    if delta < 0 then fail('Negative MIDI delta') end
    if length < 0 then fail('Negative MIDI event length') end
    if data + length - 1 > #raw then fail('Truncated MIDI event payload') end
    position = position + delta
    if position > MAX_PPQ then fail('MIDI position exceeds the expression limit') end
    events[#events + 1] = {
      pos = position, flags = flags,
      msg = raw:sub(data, data + length - 1), id = #events + 1,
    }
    if #events > MAX_EVENTS then fail('MIDI event count exceeds the expression limit') end
    offset = data + length
  end
  return events
end

-- A queue per channel/pitch preserves overlapping notes instead of losing the
-- second note. Unterminated notes are still reported so selected ones can be
-- refused; unselected ones only matter when they overlap a selected note.
local function notes_from(events)
  local active, notes, order = {}, {}, 0
  for _, event in ipairs(events) do
    if #event.msg >= 3 then
      local status, pitch, velocity = event.msg:byte(1, 3)
      local kind = status & 0xF0
      local key = (status & 15) * 128 + pitch
      if kind == 0x90 and velocity > 0 then
        active[key] = active[key] or {}
        order = order + 1
        active[key][#active[key] + 1] = { on = event, seq = order }
      elseif kind == 0x80 or (kind == 0x90 and velocity == 0) then
        local queue = active[key]
        if queue and #queue > 0 then
          local head = table.remove(queue, 1)
          if #queue == 0 then active[key] = nil end
          notes[#notes + 1] = {
            on = head.on, off = event, pitch = pitch,
            channel = status & 15, seq = head.seq,
            selected = (head.on.flags & 1) == 1,
          }
        end
      end
    end
  end
  for _, queue in pairs(active) do
    for _, entry in ipairs(queue) do
      local on = entry.on
      notes[#notes + 1] = {
        on = on, pitch = on.msg:byte(2), channel = on.msg:byte(1) & 15,
        seq = entry.seq, selected = (on.flags & 1) == 1,
        unterminated = true,
      }
    end
  end
  table.sort(notes, function(a, b)
    if a.on.pos ~= b.on.pos then return a.on.pos < b.on.pos end
    return a.seq < b.seq
  end)
  return notes
end

local function is_dimension_event(event, dim, channel)
  if #event.msg < 2 then return false end
  local status = event.msg:byte(1)
  if (status & 15) ~= channel then return false end
  local kind = status & 0xF0
  if dim.name == 'pitch' then return kind == 0xE0 end
  if dim.name == 'slide' then
    return kind == 0xB0 and event.msg:byte(2) == dim.controller
  end
  return kind == 0xD0
end

local function value_of(event, dim)
  if dim.name == 'pitch' then
    return event.msg:byte(2) | (event.msg:byte(3) << 7)
  elseif dim.name == 'slide' then
    return event.msg:byte(3)
  end
  return event.msg:byte(2)
end

local function message_of(dim, channel, value)
  if dim.name == 'pitch' then
    return string.char(0xE0 | channel, value & 0x7F, (value >> 7) & 0x7F)
  elseif dim.name == 'slide' then
    return string.char(0xB0 | channel, dim.controller, value)
  end
  return string.char(0xD0 | channel, value)
end

local function parse_member_channels(options)
  local list = options.member_channels
  if list == nil then
    list = {}
    for channel = 1, 15 do list[#list + 1] = channel end
  end
  if type(list) ~= 'table' then fail('options.member_channels must be a table') end
  if #list == 0 then fail('options.member_channels cannot be empty') end
  local members = {}
  for index = 1, #list do
    local channel = list[index]
    if not finite(channel) or channel % 1 ~= 0 or channel < 0 or channel > 15 then
      fail('Invalid member channel at index ' .. index)
    end
    if channel == MASTER_CHANNEL then
      fail('MIDI channel 0 is the master channel and cannot be an expression member')
    end
    if members[channel] then fail('Duplicate member channel ' .. channel) end
    members[channel] = true
  end
  return members
end

local function parse_points(dim, points)
  if type(points) ~= 'table' then fail('options.points must be an explicit point list') end
  if #points < 2 then fail('options.points needs at least two points') end
  if #points > MAX_POINTS then fail('options.points exceeds the point limit') end
  local parsed, previous = {}, -math.huge
  for index = 1, #points do
    local point = points[index]
    if type(point) ~= 'table' then fail('Invalid expression point at index ' .. index) end
    local t, value = point.t, point.value
    if not finite(t) or t < 0 or t > 1 then
      fail('Invalid point time at index ' .. index)
    end
    if not (t > previous) then fail('Point times must strictly increase') end
    previous = t
    if not finite(value) or value < dim.min or value > dim.max then
      fail('Point value outside ' .. dim.name .. ' range at index ' .. index)
    end
    parsed[index] = { t = t, value = value }
  end
  return parsed
end

local function parse_options(dim, options)
  if options == nil then options = {} end
  if type(options) ~= 'table' then fail('Expression options must be a table') end
  local mode = options.mode or 'replace'
  if mode ~= 'replace' and mode ~= 'add' then fail('Invalid expression mode') end
  local steps = options.steps
  if steps == nil then steps = 32 end
  integer(steps, 2, 1024, 'expression steps')
  local shape = options.shape or 'linear'
  if shape ~= 'constant' and shape ~= 'linear'
      and shape ~= 'sine' and shape ~= 'triangle' then
    fail('Invalid expression shape')
  end
  return {
    mode = mode, steps = steps, shape = shape,
    points = parse_points(dim, options.points),
    members = parse_member_channels(options),
  }
end

local function assert_attributable(notes)
  for left = 1, #notes do
    local a = notes[left]
    for right = left + 1, #notes do
      local b = notes[right]
      if a.channel == b.channel and (a.selected or b.selected) then
        if a.unterminated or b.unterminated then
          local live = a.unterminated and a or b
          local fixed = a.unterminated and b or a
          if not fixed.unterminated then
            -- An unselected unterminated note occupies [start, infinity).
            if live.on.pos <= fixed.off.pos then
              fail('Expression attribution is ambiguous: an unterminated note on channel '
                .. a.channel .. ' overlaps or touches the selected note')
            end
          end
        else
          local overlap = a.on.pos < b.off.pos and b.on.pos < a.off.pos
          if overlap then
            fail('Expression attribution is ambiguous: overlapping notes on channel '
              .. a.channel .. '; narrow the selection or split the channel')
          end
          if a.off.pos == b.on.pos or b.off.pos == a.on.pos then
            fail('Expression attribution is ambiguous: contiguous notes on channel '
              .. a.channel .. ' share a boundary tick')
          end
        end
      end
    end
  end
end

local function validate_selected(selected, members)
  for _, note in ipairs(selected) do
    if note.unterminated then
      fail('Selected note at PPQ ' .. tostring(note.on.pos) .. ' (pitch '
        .. tostring(note.pitch) .. ') has no note-off')
    end
    if #note.on.msg ~= 3 or #note.off.msg ~= 3 then
      fail('Selected note at PPQ ' .. tostring(note.on.pos)
        .. ' has a malformed event')
    end
    if note.channel == MASTER_CHANNEL then
      fail('Selected note uses the master channel 0; expression edits are refused')
    end
    if not members[note.channel] then
      fail('Selected note on channel ' .. note.channel
        .. ' is outside options.member_channels')
    end
    if note.off.pos <= note.on.pos then
      fail('Selected note at PPQ ' .. tostring(note.on.pos)
        .. ' has no positive duration')
    end
  end
end

local function ease(shape, u)
  if shape == 'constant' then return 0 end
  if shape == 'linear' then return u end
  if shape == 'sine' then return 0.5 - 0.5 * math.cos(math.pi * u) end
  -- Monotonic triangle ease: accelerate to the midpoint, then decelerate.
  if u < 0.5 then return 2 * u * u end
  return 1 - 2 * (1 - u) * (1 - u)
end

local function value_at(points, t, shape)
  if t <= points[1].t then return points[1].value end
  local last = points[#points]
  if t >= last.t then return last.value end
  for index = 1, #points - 1 do
    local a, b = points[index], points[index + 1]
    if t >= a.t and t < b.t then
      local u = (t - a.t) / (b.t - a.t)
      return a.value + (b.value - a.value) * ease(shape, u)
    end
  end
  return last.value
end

-- Samples are rounded to whole ticks. If several samples round to the same
-- tick, the later sample wins and the tick stays once; this is deterministic
-- and keeps the final value of a dense curve.
local function sample_note(start_pos, end_pos, points, steps, shape, dim)
  local span = end_pos - start_pos - 1
  local samples = {}
  for index = 1, steps do
    local t = (index - 1) / (steps - 1)
    local position = start_pos + math.floor(span * t + 0.5)
    local value = math.floor(value_at(points, t, shape) + 0.5)
    if value < dim.min then value = dim.min elseif value > dim.max then value = dim.max end
    local previous = samples[#samples]
    if previous and previous.pos == position then
      previous.value = value
    else
      samples[#samples + 1] = { pos = position, value = value }
    end
  end
  return samples
end

local function priority(event)
  if event.generated then return 4 end
  if #event.msg >= 3 then
    local status = event.msg:byte(1)
    local kind = status & 0xF0
    if kind == 0x80 or (kind == 0x90 and event.msg:byte(3) == 0) then return 1 end
    if kind == 0xE0 and event.msg:byte(2) == 0 and event.msg:byte(3) == 64 then
      return 2
    end
    if kind == 0x90 and event.msg:byte(3) > 0 then return 3 end
  end
  return 5
end

local function encode(events, terminator)
  local data = {}
  for _, event in ipairs(events) do
    if #event.msg > 0 then data[#data + 1] = event end
  end
  table.sort(data, function(a, b)
    if a.pos ~= b.pos then return a.pos < b.pos end
    local pa, pb = priority(a), priority(b)
    if pa ~= pb then return pa < pb end
    return a.id < b.id
  end)
  local parts, previous = {}, 0
  for _, event in ipairs(data) do
    local delta = event.pos - previous
    if delta < 0 then fail('Internal error: negative MIDI delta') end
    parts[#parts + 1] = string.pack('i4Bs4', delta, event.flags & 0xFF, event.msg)
    previous = event.pos
  end
  local terminator_pos = terminator.pos
  if #data > 0 and data[#data].pos > terminator_pos then
    terminator_pos = data[#data].pos
  end
  local delta = terminator_pos - previous
  if delta < 0 or delta > MAX_PPQ then fail('Invalid final terminator position') end
  parts[#parts + 1] = string.pack('i4Bs4', delta, terminator.flags & 0xFF, '')
  return table.concat(parts)
end

local function baseline_lookup(events, dim)
  local by_channel = {}
  for _, event in ipairs(events) do
    if #event.msg > 0 then
      local channel = event.msg:byte(1) & 15
      if is_dimension_event(event, dim, channel) then
        by_channel[channel] = by_channel[channel] or {}
        by_channel[channel][#by_channel[channel] + 1] = event
      end
    end
  end
  for _, list in pairs(by_channel) do
    table.sort(list, function(a, b)
      if a.pos ~= b.pos then return a.pos < b.pos end
      return a.id < b.id
    end)
  end
  return function(channel, position)
    local list = by_channel[channel]
    if not list then return dim.neutral end
    local low, high, found = 1, #list, nil
    while low <= high do
      local middle = (low + high) // 2
      if list[middle].pos <= position then
        found = list[middle]
        low = middle + 1
      else
        high = middle - 1
      end
    end
    return found and value_of(found, dim) or dim.neutral
  end
end

function E.transform(raw, dimension, options)
  local dim = dimension_of(dimension)
  local events = decode(raw)
  local notes = notes_from(events)
  if #notes > MAX_NOTES then fail('MIDI note count exceeds the expression limit') end

  local selected = {}
  for _, note in ipairs(notes) do
    if note.selected then selected[#selected + 1] = note end
  end
  -- An empty selection is byte-exact input, even if other options are invalid.
  if #selected == 0 then return raw end

  local opts = parse_options(dim, options)
  validate_selected(selected, opts.members)
  assert_attributable(notes)

  local projected = #selected * opts.steps
  if projected > MAX_EVENTS or #events + projected > MAX_EVENTS then
    fail('Expression event budget exceeded: ' .. tostring(projected)
      .. ' generated events for ' .. tostring(#selected)
      .. ' selected notes at ' .. tostring(opts.steps) .. ' steps')
  end

  local terminator
  for _, event in ipairs(events) do
    if #event.msg == 0 then
      if terminator then fail('MIDI contains multiple terminators') end
      terminator = event
    end
  end
  if not terminator then fail('MIDI has no final terminator') end

  table.sort(selected, function(a, b)
    if a.on.pos ~= b.on.pos then return a.on.pos < b.on.pos end
    return a.seq < b.seq
  end)

  local baseline = opts.mode == 'add' and baseline_lookup(events, dim) or nil
  local exact_dimension = {}
  if opts.mode == 'add' then
    for _, event in ipairs(events) do
      if #event.msg > 0 then
        local channel = event.msg:byte(1) & 15
        if is_dimension_event(event, dim, channel) then
          local key = channel .. ':' .. event.pos
          exact_dimension[key] = exact_dimension[key] or {}
          exact_dimension[key][#exact_dimension[key] + 1] = event
        end
      end
    end
  end
  local remove = {}
  local generated = {}
  local next_id = #events

  for _, note in ipairs(selected) do
    local samples = sample_note(note.on.pos, note.off.pos, opts.points,
      opts.steps, opts.shape, dim)
    for _, sample in ipairs(samples) do
      local value = sample.value
      local exact
      if opts.mode == 'add' then
        exact = exact_dimension[note.channel .. ':' .. sample.pos]
        local offset = dim.name == 'pitch' and (value - dim.neutral) or value
        value = baseline(note.channel, sample.pos) + offset
        if value < dim.min then value = dim.min
        elseif value > dim.max then value = dim.max end
        value = math.floor(value + 0.5)
      end
      next_id = next_id + 1
      generated[#generated + 1] = {
        pos = sample.pos,
        flags = exact and exact[1] and exact[1].flags or 0,
        msg = message_of(dim, note.channel, value),
        id = next_id, generated = true, channel = note.channel,
      }
      if exact then
        for _, event in ipairs(exact) do remove[event.id] = true end
      end
    end
    if opts.mode == 'replace' then
      for _, event in ipairs(events) do
        if event.pos >= note.on.pos and event.pos < note.off.pos
            and is_dimension_event(event, dim, note.channel) then
          remove[event.id] = true
        end
      end
    end
  end

  local output = {}
  for _, event in ipairs(events) do
    if not remove[event.id] and #event.msg > 0 then output[#output + 1] = event end
  end
  for _, event in ipairs(generated) do output[#output + 1] = event end
  return encode(output, terminator)
end

local function bounded_value(value, dim, name)
  if not finite(value) or value < dim.min or value > dim.max then
    fail('Invalid ' .. name .. ' for ' .. dim.name)
  end
  return value
end

-- A glissando is explicit: it builds two points and reuses E.transform.
function E.glissando(raw, dimension, options)
  local dim = dimension_of(dimension)
  if options == nil then options = {} end
  if type(options) ~= 'table' then fail('Glissando options must be a table') end
  local from = bounded_value(options.from == nil and dim.neutral or options.from,
    dim, 'glissando start')
  local to = bounded_value(options.to == nil and dim.neutral or options.to,
    dim, 'glissando end')
  local copy = {}
  for key, value in pairs(options) do copy[key] = value end
  copy.points = { { t = 0, value = from }, { t = 1, value = to } }
  return E.transform(raw, dimension, copy)
end

-- An LFO is explicit: it samples a sine into points, then reuses E.transform.
function E.lfo(raw, dimension, options)
  local dim = dimension_of(dimension)
  if options == nil then options = {} end
  if type(options) ~= 'table' then fail('LFO options must be a table') end
  local center = bounded_value(options.center == nil and dim.neutral or options.center,
    dim, 'LFO center')
  local amplitude = options.amplitude
  if not finite(amplitude) or amplitude < 0 then fail('Invalid LFO amplitude') end
  local cycles = options.cycles == nil and 1 or options.cycles
  local phase = options.phase == nil and 0 or options.phase
  if not finite(cycles) or cycles < 0 then fail('Invalid LFO cycles') end
  if not finite(phase) then fail('Invalid LFO phase') end
  local samples = options.samples == nil and 64 or options.samples
  integer(samples, 2, 1024, 'LFO samples')
  local points = {}
  for index = 1, samples do
    local t = (index - 1) / (samples - 1)
    local value = center + amplitude * math.sin(2 * math.pi * (cycles * t + phase))
    if value < dim.min then value = dim.min elseif value > dim.max then value = dim.max end
    points[index] = { t = t, value = value }
  end
  local copy = {}
  for key, value in pairs(options) do copy[key] = value end
  copy.points = points
  copy.steps = samples
  return E.transform(raw, dimension, copy)
end

function E.dimensions()
  return { 'pitch', 'slide', 'pressure' }
end

function E.decode(raw)
  return decode(raw)
end

return E
