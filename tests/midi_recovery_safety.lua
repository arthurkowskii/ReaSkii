-- Standalone Lua 5.4 regression tests for MIDI recovery safety.
-- Run with the shared liblua runner; only a unique directory under TMPDIR is used.
local IS_WINDOWS = package.config:sub(1,1) == '\\'
local function script_dir()
  local source = debug.getinfo(1, 'S').source
  source = source:gsub('^@', '')
  return source:match('^(.*)[/\\]') or '.'
end
local ROOT = os.getenv('REASKII_ROOT') or (script_dir() .. '/..')
local TMP = os.getenv('TMPDIR') or (IS_WINDOWS and os.getenv('TEMP')) or '/tmp'
math.randomseed(os.time() + math.floor(os.clock() * 1000000))
local DIR = string.format('%s/reaskii-midi-safety-%d-%06d', TMP, os.time(), math.random(0, 999999))
local function sh(command)
  local ok = os.execute(command)
  return ok == true or ok == 0
end
assert(IS_WINDOWS and sh('mkdir "' .. DIR .. '"') or sh('mkdir -p "' .. DIR .. '"'),
  'Cannot create isolated test directory')

local pass, failures = 0, {}
local function check(condition, name)
  if condition then
    pass = pass + 1
    print('PASS\t' .. name)
  else
    failures[#failures + 1] = name
    print('FAIL\t' .. name)
  end
end
local function event(delta, flags, msg)
  return string.pack('i4Bs4', delta, flags, msg)
end
local BASE = event(0, 1, string.char(0x90, 60, 100))
  .. event(120, 0, string.char(0x80, 60, 37)) .. event(0, 0, '')

-- Minimal REAPER model: takes own raw MIDI, GUIDs resolve inside the project.
local mock = {
  set_window = 0, set_fail_at = nil,
  set_calls = 0, get_calls = 0, update_calls = 0,
  undo_begins = 0, undo_ends = 0, undo_names = {},
  fail_write = false, fail_final_rename = false,
}
local project = {name = 'Safety.rpp', path = DIR .. '/project', items = {}}
local item_counter = 0
local function add_take(opts)
  item_counter = item_counter + 1
  local item = {
    guid = opts.item_guid or string.format('{ITEM-%08d-0000-0000-0000-000000000000}', item_counter),
    project = project, number = item_counter,
  }
  local take = {
    guid = opts.guid or string.format('{TAKE-%08d-0000-0000-0000-000000000000}', item_counter),
    name = opts.name or 'Piano', item = item, project = project,
    raw = opts.raw or BASE, midi = true, read_plan = nil,
  }
  item.take = take
  project.items[#project.items + 1] = item
  return take
end
local function find_take_by_guid(proj, guid)
  for _, item in ipairs(proj.items) do
    if item.take and item.take.guid == guid then return item.take end
  end
end
local function write_file(path, data)
  local f = assert(io.open(path, 'wb'))
  assert(f:write(data))
  return assert(f:close())
end
local function read_file(path)
  local f = assert(io.open(path, 'rb'))
  local data = f:read('a')
  f:close()
  return data
end

local reaper_mock = {}
function reaper_mock.EnumProjects(index, filename)
  if index == -1 then return project end
end
function reaper_mock.ValidatePtr2(proj, pointer, kind)
  return kind == 'MediaItem_Take*' and pointer ~= nil and pointer.project == proj
end
function reaper_mock.TakeIsMIDI(take) return take ~= nil and take.midi == true end
function reaper_mock.GetMediaItemTake_Item(take) return take.item end
function reaper_mock.GetSetMediaItemTakeInfo_String(take, parm, value, set)
  if set then return false, value end
  if parm == 'GUID' then return true, take.guid end
  if parm == 'P_NAME' then return true, take.name end
  return false, ''
end
function reaper_mock.GetSetMediaItemInfo_String(item, parm, value, set)
  if set then return false, value end
  if parm == 'GUID' then return true, item.guid end
  return false, ''
end
function reaper_mock.GetMediaItemTakeByGUID(proj, guid)
  return find_take_by_guid(proj, guid)
end
function reaper_mock.GetProjectName(proj) return proj.name end
function reaper_mock.GetProjectPath() return project.path end
function reaper_mock.GetResourcePath() return DIR .. '/resources' end
function reaper_mock.RecursiveCreateDirectory(path, recursive)
  assert(sh(IS_WINDOWS and ('mkdir "' .. path .. '" 2>NUL')
    or ('mkdir -p "' .. path .. '"')))
  return 1
end
function reaper_mock.MIDI_GetAllEvts(take, flags)
  mock.get_calls = mock.get_calls + 1
  if take.read_plan and #take.read_plan > 0 then
    return true, table.remove(take.read_plan, 1)
  end
  return true, take.raw
end
function reaper_mock.MIDI_SetAllEvts(take, raw)
  if type(raw) ~= 'string' then return false end
  mock.set_window = mock.set_window + 1
  if mock.set_fail_at and mock.set_window == mock.set_fail_at then
    return false
  end
  mock.set_calls = mock.set_calls + 1
  take.raw = raw
  return true
end
function reaper_mock.UpdateItemInProject(item) mock.update_calls = mock.update_calls + 1 end
function reaper_mock.Undo_BeginBlock2(proj) mock.undo_begins = mock.undo_begins + 1 end
function reaper_mock.Undo_EndBlock2(proj, name, flags)
  mock.undo_ends = mock.undo_ends + 1
  mock.undo_names[#mock.undo_names + 1] = name
end
function reaper_mock.Undo_OnStateChange2(proj, name) end

local saved_reaper = rawget(_G, 'reaper')
_G.reaper = reaper_mock
local ok, err = xpcall(function()
  local C = dofile(ROOT .. '/scripts/midi/ReaSkii_MIDI_Core.lua')
  local function reset_failures()
    mock.set_window = 0
    mock.set_fail_at = nil
  end
  local function fresh(raw)
    return add_take({raw = raw or BASE})
  end
  local function crash_with_preview(take, tool, options)
    local session = C.session(take)
    session:preview(tool, options)
    local preview = take.raw
    session:simulate_crash()
    return session, preview
  end

  -- (1) abandon restores the original when the take still holds our preview.
  local take = fresh()
  local session = C.session(take)
  session:preview('transpose', {amount = 2})
  local preview = take.raw
  local kept, reason = session:abandon()
  check(kept == false and reason == 'original restored', 'abandon reports an actual restore')
  check(take.raw == BASE, 'abandon restores the original bytes, not just the journal')
  check(not C.recovery_pending(take), 'abandon clears the journal after a verified restore')

  -- abandon keeps an external edit and its journal, untouched.
  take = fresh()
  session = C.session(take)
  session:preview('transpose', {amount = 2})
  local external = take.raw .. event(0, 0, string.char(0xB0, 7, 90))
  take.raw = external
  kept, reason = session:abandon()
  check(kept == true and reason == 'external edit preserved', 'abandon keeps an external edit')
  check(take.raw == external and C.recovery_pending(take), 'external edit and journal both survive')
  C._clear_recovery(take)

  -- A failed restore is never reported as restored and keeps the journal.
  take = fresh()
  session = C.session(take)
  session:preview('transpose', {amount = 2})
  preview = take.raw
  reset_failures()
  mock.set_fail_at = 1
  local pcall_ok, abandon_kept, abandon_reason = pcall(function() return session:abandon() end)
  check(pcall_ok and abandon_kept == true, 'failed abandon does not claim a restore')
  check(tostring(abandon_reason):find('restore failed', 1, true) ~= nil, 'failed abandon reports the failure')
  check(take.raw == preview and C.recovery_pending(take), 'failed abandon keeps the preview and journal')
  reset_failures()
  check(C.recover(take) == true and take.raw == BASE, 'recovery still works after a failed abandon')

  -- A preview whose readback verification failed is still recoverable, not lost.
  take = fresh()
  session = C.session(take)
  take.read_plan = {BASE, BASE, BASE}
  local readback_preview = pcall(function() session:preview('transpose', {amount = 2}) end)
  take.read_plan = nil
  check(readback_preview == false and C.recovery_pending(take),
    'preview readback mismatch keeps the journal')
  check(C.recover(take) == true and take.raw == BASE,
    'preview readback mismatch is recoverable')

  -- A stale last-read still resolves through the journal rather than discarding it.
  take = fresh()
  session = C.session(take)
  take.read_plan = {BASE, BASE .. 'stale', BASE .. 'stale'}
  pcall(function() session:preview('transpose', {amount = 2}) end)
  take.read_plan = nil
  kept, reason = session:abandon()
  check(kept == false and reason == 'original restored' and take.raw == BASE,
    'abandon restores through the journal when its last read was stale')
  check(not C.recovery_pending(take), 'stale-read abandon clears the journal after restoring')

  -- (2) Stable identity: same names and positions, different takes.
  local a = add_take({name = 'Same name'})
  local b = add_take({name = 'Same name'})
  local a_journal, a_preview = crash_with_preview(a, 'transpose', {amount = 2})
  check(C.recovery_pending(a) and not C.recovery_pending(b), 'journals keyed by GUIDs, not names/indices')
  local b_before = b.raw
  local recovered_b = C.recover(b)
  check(recovered_b == false and b.raw == b_before, 'recovery never applies to a lookalike take')
  check(C.recover(a) == true and a.raw == BASE, 'recovery applies to the GUID-matching take')

  -- Renaming the take, item and project must not break recovery.
  local c = fresh()
  local c_session, c_preview = crash_with_preview(c, 'velocity', {amount = 20})
  c.name = 'Renamed take'
  project.name = 'Renamed project.rpp'
  project.path = DIR .. '/project-renamed'
  c.item.number = 999
  check(C.recover(c) == true and c.raw == BASE, 'rename and item move do not break recovery')
  project.name = 'Safety.rpp'
  project.path = DIR .. '/project'

  -- Metadata mismatch is refused even with a valid checksum.
  local d = fresh()
  local e = fresh()
  local d_session, d_preview = crash_with_preview(d, 'transpose', {amount = 3})
  local journal = read_file(d_session.journal_path)
  local meta_len = journal:byte(7) + journal:byte(8) * 256
  local meta = journal:sub(17, 16 + meta_len)
  local guid_start, guid_end = meta:find(d.guid, 1, true)
  local patched = guid_start and
    (meta:sub(1, guid_start - 1) .. e.guid .. meta:sub(guid_end + 1)) or meta
  check(patched ~= meta and #patched == #meta, 'test can patch journal metadata')
  local body = journal:sub(1, 16) .. patched .. journal:sub(17 + meta_len, #journal - 4)
  local function fnv(data)
    local hash = 2166136261
    for i = 1, #data do hash = ((hash ~ data:byte(i)) * 16777619) & 0xFFFFFFFF end
    return hash
  end
  local function p32(value)
    return string.char(value % 256, math.floor(value / 256) % 256,
      math.floor(value / 65536) % 256, math.floor(value / 16777216) % 256)
  end
  write_file(d_session.journal_path, body .. p32(fnv(body)))
  local sets_before = mock.set_calls
  local meta_ok, meta_msg = C.recover(d)
  check(meta_ok == false and tostring(meta_msg):find('different take', 1, true) ~= nil,
    'journal metadata is verified against the target take')
  check(d.raw == d_preview and mock.set_calls == sets_before, 'metadata mismatch never writes MIDI')
  C._clear_recovery(d)

  -- (3) Bounded parser: malformed journals are refused without touching MIDI.
  local f = fresh()
  local f_session, f_preview = crash_with_preview(f, 'transpose', {amount = 2})
  local valid = read_file(f_session.journal_path)
  local function refused(raw, label)
    write_file(f_session.journal_path, raw)
    local before = mock.set_calls
    local recovered, message = C.recover(f)
    check(recovered == false and f.raw == f_preview and mock.set_calls == before,
      'refused journal leaves MIDI untouched: ' .. label)
    check(type(message) == 'string' and #message > 0, 'refusal has a diagnostic: ' .. label)
    check(read_file(f_session.journal_path) == raw, 'malformed journal is preserved: ' .. label)
  end
  refused(valid:sub(1, math.floor(#valid / 2)), 'truncated')
  refused(valid:sub(1, 4) .. string.char(99, 0) .. valid:sub(7), 'bad version')
  refused(valid:sub(1, 4) .. string.char(2, 1) .. valid:sub(7), 'bad flags')
  local huge = valid:sub(1, 8) .. string.char(255, 255, 255, 255) .. valid:sub(13)
  refused(huge, 'oversized length')
  refused(valid .. 'x', 'trailing data')
  local flipped = valid:sub(1, 30) .. string.char((valid:byte(31) ~ 1)) .. valid:sub(32)
  refused(flipped, 'checksum mismatch')
  refused('', 'empty file')
  refused(string.pack('i4', #BASE) .. BASE .. string.pack('i4', #f_preview) .. f_preview,
    'legacy format')
  write_file(f_session.journal_path, valid)
  check(C.recover(f) == true and f.raw == BASE, 'valid journal still recovers after refusals')

  -- A pending journal is not overwritten by a new panel session.
  local g = fresh()
  local g_session, g_preview = crash_with_preview(g, 'transpose', {amount = 2})
  local pending_bytes = read_file(g_session.journal_path)
  local second = C.session(g)
  local preview_ok, preview_err = pcall(function() second:preview('velocity', {amount = 5}) end)
  check(preview_ok == false and tostring(preview_err):find('interrupted preview', 1, true) ~= nil,
    'new session refuses to overwrite a pending journal')
  check(read_file(g_session.journal_path) == pending_bytes and g.raw == g_preview,
    'pending journal and preview bytes are unchanged')
  check(C.recover(g) == true and g.raw == BASE, 'pending journal is still restorable')

  -- (4) Disk failures preserve the previous valid journal.
  local h = fresh()
  local h_session, h_preview = crash_with_preview(h, 'transpose', {amount = 2})
  local h_journal = read_file(h_session.journal_path)
  local real_open = io.open
  io.open = function(path, mode)
    if mock.fail_write and mode == 'wb' and tostring(path):find('%.midirec%.tmp$') then
      return nil, 'simulated write failure'
    end
    return real_open(path, mode)
  end
  mock.fail_write = true
  local write_ok, write_err = pcall(C._write_recovery, h, BASE, h_preview .. 'x')
  mock.fail_write = false
  io.open = real_open
  check(write_ok == false and tostring(write_err):find('simulated write failure', 1, true) ~= nil,
    'write failure is reported')
  check(read_file(h_session.journal_path) == h_journal, 'write failure keeps the previous journal')

  local real_rename = os.rename
  os.rename = function(from, to)
    if mock.fail_final_rename and tostring(from):find('%.tmp$') and tostring(to):find('%.midirec$') then
      return nil, 'simulated rename failure'
    end
    return real_rename(from, to)
  end
  mock.fail_final_rename = true
  local rename_ok, rename_err = pcall(C._write_recovery, h, BASE, h_preview .. 'y')
  mock.fail_final_rename = false
  os.rename = real_rename
  check(rename_ok == false and tostring(rename_err):find('previous journal', 1, true) ~= nil,
    'rename failure reports the preserved journal')
  check(read_file(h_session.journal_path) == h_journal, 'rename failure keeps the previous journal')
  check(C.recover(h) == true and h.raw == BASE, 'previous journal remains usable after disk failures')

  -- Successful writes leave no temp or backup file.
  local i = fresh()
  local i_session = C.session(i)
  i_session:preview('transpose', {amount = 1})
  local i_dir = i_session.journal_path:match('^(.*)[/\\]')
  local leftovers = 0
  local pipe = io.popen(IS_WINDOWS and ('dir /b "' .. i_dir .. '"') or ('ls -1 "' .. i_dir .. '"'))
  if pipe then
    for line in pipe:lines() do
      if line:find('%.tmp$') or line:find('%.bak$') then leftovers = leftovers + 1 end
    end
    pipe:close()
  end
  check(leftovers == 0, 'successful journal write leaves no temp or backup')
  i_session:cancel()
  check(i.raw == BASE, 'cancel after disk tests restores the original')

  -- Readback is mandatory before a journal is removed.
  local j = fresh()
  local j_session = C.session(j)
  j_session:preview('transpose', {amount = 2})
  local j_preview = j.raw
  local clear_calls = 0
  local real_clear = C._clear_recovery
  C._clear_recovery = function(take)
    clear_calls = clear_calls + 1
    return real_clear(take)
  end
  j.read_plan = {j_preview, j_preview, j_preview}
  local cancel_ok = pcall(function() j_session:cancel() end)
  C._clear_recovery = real_clear
  j.read_plan = nil
  check(cancel_ok == false and clear_calls == 0, 'cancel does not clear a journal before readback')
  check(j.raw == BASE and C.recovery_pending(j), 'cancel readback failure leaves the original and journal')
  real_clear(j)

  local k = fresh()
  local k_session, k_preview = crash_with_preview(k, 'transpose', {amount = 2})
  k.read_plan = {k_preview, k_preview}
  local recover_ok = C.recover(k)
  k.read_plan = nil
  check(recover_ok == false and C.recovery_pending(k), 'recover verifies bytes before removing its journal')
  k.raw = k_preview
  check(C.recover(k) == true and k.raw == BASE, 'recover succeeds once readback is honest')

  -- (5) apply/cancel failures keep the original or preview recoverable, undo balanced.
  local l = fresh()
  local l_session = C.session(l)
  l_session:preview('velocity', {amount = 10})
  local l_preview = l.raw
  reset_failures()
  mock.set_fail_at = 1
  local apply_ok, apply_err = pcall(function() l_session:apply('Safety apply') end)
  check(apply_ok == false and l.raw == l_preview and C.recovery_pending(l),
    'apply failure before undo keeps preview and journal')
  check(mock.undo_begins == mock.undo_ends, 'undo block is not left open after early failure')
  reset_failures()
  check(C.recover(l) == true and l.raw == BASE, 'early apply failure is recoverable')

  l = fresh()
  l_session = C.session(l)
  l_session:preview('velocity', {amount = 10})
  l_preview = l.raw
  reset_failures()
  mock.set_fail_at = 2
  apply_ok, apply_err = pcall(function() l_session:apply('Safety apply') end)
  check(apply_ok == false and mock.undo_begins == mock.undo_ends,
    'apply failure closes the undo block')
  check(l.raw == BASE and not C.recovery_pending(l),
    'apply failure restores and verifies the original before clearing')
  reset_failures()

  l = fresh()
  l_session = C.session(l)
  l_session:preview('velocity', {amount = 10})
  local l_result = l.raw
  l_session:apply('Safety apply')
  check(l.raw == l_result and not C.recovery_pending(l),
    'successful apply keeps the result and removes the journal')
  check(mock.undo_begins == mock.undo_ends and mock.undo_names[#mock.undo_names] == 'Safety apply',
    'successful apply creates one named, closed undo block')
  check(mock.undo_ends - mock.undo_begins == 0, 'undo counters stay balanced')

  local m = fresh()
  local m_session = C.session(m)
  m_session:preview('velocity', {amount = 10})
  local m_preview = m.raw
  reset_failures()
  mock.set_fail_at = 1
  local m_ok = pcall(function() m_session:cancel() end)
  check(m_ok == false and m.raw == m_preview and C.recovery_pending(m) and not m_session.closed,
    'cancel failure keeps preview, journal and session retryable')
  reset_failures()
  m_session:cancel()
  check(m.raw == BASE and not C.recovery_pending(m), 'cancel retry restores byte-exact MIDI')

  -- Closing an untouched session must not delete a journal it never wrote.
  local n = fresh()
  local n_session, n_preview = crash_with_preview(n, 'transpose', {amount = 2})
  local untouched = C.session(n)
  check(untouched.pending_at_open == true, 'session exposes a pending journal at open')
  untouched:abandon()
  check(C.recovery_pending(n) and n.raw == n_preview,
    'closing a new session never deletes a journal it did not write')
  check(C.recover(n) == true and n.raw == BASE, 'foreign journal still restores after abandon')
end, debug.traceback)
_G.reaper = saved_reaper

if not ok then
  print('ERROR\t' .. tostring(err))
  failures[#failures + 1] = 'runtime error'
end
local cleanup = IS_WINDOWS and ('rmdir /s /q "' .. DIR .. '"') or ('rm -rf -- "' .. DIR .. '"')
if DIR:find('reaskii%-midi%-safety%-', 1) and #DIR > #TMP + 5 then
  os.execute(cleanup)
end
if #failures > 0 then
  print('FAILED\t' .. #failures)
  os.exit(1)
end
print('DONE\t' .. pass)
