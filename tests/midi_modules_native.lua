-- Execute both independent pure suites inside the real REAPER Lua interpreter.
local out=assert(io.open(REASKII_RESULT,'w'))
local oldprint=print
local function run(name)
  local lines={}
  print=function(...) local t={...}; for i,v in ipairs(t) do t[i]=tostring(v) end; lines[#lines+1]=table.concat(t,' ') end
  local ok,err=xpcall(function() dofile(REASKII_ROOT..'/tests/'..name) end,debug.traceback)
  print=oldprint
  for _,line in ipairs(lines) do out:write('INFO\t',name,'\t',line,'\n') end
  if not ok then out:write('ERROR\t',name,'\t',err,'\n'); return false end
  out:write('PASS\t',name,'\n'); return true
end
local a=run('midi_transformations_unit.lua')
local b=run('midi_generators_unit.lua')
local c=run('midi_adapter_unit.lua')
local d=run('midi_syntax_unit.lua')
out:write('DONE\t',a and b and c and d and '4' or '0','\n'); out:close()
