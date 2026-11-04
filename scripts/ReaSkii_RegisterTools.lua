-- ReaSkii: declare the tool entry points in REAPER's Action List.
-- Run once per machine after installing or updating ReaSkii:
--   Actions > Show action list > Load ReaScript, pick this file, then Run it.
-- It registers the maintained entry points only. The laboratory prototype
-- scripts/midi/ReaSkii_MIDI_Tools.lua is installed but deliberately not registered.
-- Re-running is harmless: REAPER keys a ReaScript by its path, so the same
-- command ID is returned instead of a duplicate entry.

local script = debug.getinfo(1, 'S').source:sub(2)
local directory = script:match('^(.*[/\\])') or ''
local sep = directory:sub(-1)
if sep ~= '/' and sep ~= '\\' then sep = '/' end

local entries = {
  {
    label = 'ReaSkii MIDI Panel',
    section = 32060, -- MIDI Editor
    path = directory .. 'midi' .. sep .. 'ReaSkii_MIDI_Panel.lua',
  },
  {
    label = 'ReaSkii Device Rack',
    section = 0, -- Main
    path = directory .. 'device' .. sep .. 'ReaSkii_DeviceRack.lua',
  },
}

local function say(text)
  reaper.ShowConsoleMsg(text .. '\n')
end

say('ReaSkii tool registration')
local failed = 0
for _, entry in ipairs(entries) do
  local handle = io.open(entry.path, 'r')
  if not handle then
    say('MISSING  ' .. entry.label .. '  ' .. entry.path)
    failed = failed + 1
  else
    handle:close()
    local command = reaper.AddRemoveReaScript(true, entry.section, entry.path, true)
    if not command or command == 0 then
      say('FAILED   ' .. entry.label .. '  ' .. entry.path)
      failed = failed + 1
    else
      say(string.format('OK       %s  command %d  %s', entry.label, command, entry.path))
    end
  end
end

if failed > 0 then
  say(string.format('%d entrée(s) en échec. Vérifie que les fichiers sont bien installés.', failed))
else
  say('Tout est enregistré. Assigne les raccourcis depuis la liste d’actions.')
end
