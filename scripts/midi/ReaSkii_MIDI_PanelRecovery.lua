-- Explicit conflict resolution: archive verified recovery evidence; NEVER write MIDI.
local R={}
function R.archive(path,suffix)
 local archived={}
 for _,ext in ipairs({'','.bak','.tmp'}) do
  local source=path..ext
  local f=io.open(source,'rb')
  if f then
   local raw=f:read('*a'); f:close()
   local destination=source..'.conflict-'..suffix
   local existing=io.open(destination,'rb'); if existing then existing:close(); error('Archive already exists') end
   assert(os.rename(source,destination),'Could not archive recovery evidence')
   local check=assert(io.open(destination,'rb')); local read=check:read('*a'); check:close()
   assert(read==raw,'Recovery archive readback mismatch; inspect '..destination)
   archived[#archived+1]=destination
  end
 end
 assert(#archived>0,'No recovery evidence found to archive')
 return archived
end
return R
