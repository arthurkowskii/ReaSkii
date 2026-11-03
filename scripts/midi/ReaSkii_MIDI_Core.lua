-- ReaSkii MIDI laboratory. Independent implementation, not Ableton-verified.
-- Raw event editing preserves note-off velocity and unrelated MIDI bytes.
local M = {}
local function integer(value, name, low, high)
  assert(type(value)=='number' and value==value and value%1==0
    and value>=low and value<=high, 'Invalid '..name)
  return value
end
local function replace_byte(message, index, value)
  return message:sub(1,index-1)..string.char(value)..message:sub(index+1)
end
function M.decode(raw)
  assert(type(raw)=='string', 'MIDI must be a raw string')
  local events, offset, pos = {}, 1, 0
  while offset<=#raw do
    local delta, flags, msg
    delta,flags,msg,offset=string.unpack('i4Bs4',raw,offset)
    pos=pos+delta
    events[#events+1]={pos=pos,flags=flags,msg=msg,id=#events+1}
  end
  return events
end
local function encode(events)
  table.sort(events,function(a,b) return a.pos<b.pos or (a.pos==b.pos and a.id<b.id) end)
  local parts, previous={},0
  for _,e in ipairs(events) do
    local pos=math.floor(e.pos+.5)
    parts[#parts+1]=string.pack('i4Bs4',pos-previous,e.flags,e.msg)
    previous=pos
  end
  return table.concat(parts)
end
local function notes_from(events)
  -- A queue per (channel,pitch) supports overlapping notes instead of poisoning the whole take.
  local notes, active, order = {}, {}, 0
  for _,e in ipairs(events) do
    if #e.msg>=3 then
      local status,pitch,vel=e.msg:byte(1,3)
      local kind=status & 0xF0
      local key=(status & 15)*128+pitch
      if kind==0x90 and vel>0 then
        active[key]=active[key] or {}
        local queue=active[key]
        order=order+1
        queue[#queue+1]={on=e,seq=order}
      elseif kind==0x80 or (kind==0x90 and vel==0) then
        local queue=active[key]
        if queue and #queue>0 then
          local head=table.remove(queue,1)
          if #queue==0 then active[key]=nil end
          notes[#notes+1]={on=head.on,off=e,pitch=pitch,seq=head.seq,selected=(head.on.flags & 1)==1}
        end
      end
    end
  end
  -- An unterminated note carries no end and is left untouched by pitch edits.
  for _,queue in pairs(active) do
    for _,entry in ipairs(queue) do
      notes[#notes+1]={on=entry.on,pitch=entry.on.msg:byte(2),seq=entry.seq,selected=(entry.on.flags & 1)==1,unterminated=true}
    end
  end
  return notes
end
local function overlaps(a,b)
  if a.unterminated or b.unterminated then return false end
  return a.on.pos<b.off.pos and b.on.pos<a.off.pos
end
-- Changing one pitch onto another sounding note on the same channel makes them indistinguishable.
local function assert_no_selected_collision(notes)
  -- Selected notes all move by the same amount, so they keep their relative stacking.
  -- Only landing on a note that stays put makes two notes indistinguishable.
  for i=1,#notes do
    local a=notes[i]
    if a.selected then
      for j=1,#notes do
        local b=notes[j]
        if not b.selected and a.pitch==b.pitch and a.channel==b.channel and overlaps(a,b) then
          error('Transpose would overlap an unselected note on the same pitch and channel; narrow the selection first')
        end
      end
    end
  end
end
local function expression_present(events)
  for _,e in ipairs(events) do
    if #e.msg>0 then
      local kind=e.msg:byte(1) & 0xF0
      if kind==0xA0 or kind==0xB0 or kind==0xD0 or kind==0xE0 then return true end
    end
  end
  return false
end
function M.transform(raw, tool, options)
  local events=M.decode(raw)
  local notes=notes_from(events)
  local selected={}
  for _,n in ipairs(notes) do if n.selected then selected[#selected+1]=n end end
  local p=options or {}
  if tool=='transpose' then
    local amount=integer(p.amount,'transpose',-127,127)
    -- Polyphonic key pressure contains a pitch too; refuse instead of orphaning it.
    for _,e in ipairs(events) do
      assert(#e.msg==0 or e.msg:byte(1) & 0xF0~=0xA0, 'Polyphonic key pressure is not supported for transpose yet')
    end
    for _,n in ipairs(notes) do n.channel=n.on.msg:byte(1) & 15 end
    for _,n in ipairs(selected) do
      local pitch=n.pitch+amount
      assert(pitch>=0 and pitch<=127, 'Transpose exceeds MIDI pitch range')
      n.new_pitch=pitch
    end
    for _,n in ipairs(selected) do n.pitch=n.new_pitch end
    assert_no_selected_collision(notes)
    for _,n in ipairs(selected) do
      if not n.unterminated then
        n.on.msg=replace_byte(n.on.msg,2,n.pitch)
        n.off.msg=replace_byte(n.off.msg,2,n.pitch)
      end
    end
  elseif tool=='velocity' or tool=='random_velocity' then
    local amount=integer(p.amount,'velocity amount',tool=='velocity' and -126 or 0,126)
    local seed=tool=='random_velocity' and integer(p.seed,'seed',1,2147483646) or 1
    for _,n in ipairs(selected) do
      local delta=amount
      if tool=='random_velocity' then
        seed=(seed*48271)%2147483647
        delta=seed%(amount*2+1)-amount
      end
      local velocity=math.max(1,math.min(127,n.on.msg:byte(3)+delta))
      n.on.msg=replace_byte(n.on.msg,3,velocity)
    end
  elseif tool=='strum' then
    local low=integer(p.low,'Strum Low',-100,100)
    local high=integer(p.high,'Strum High',-100,100)
    assert(type(p.grid)=='number' and p.grid>0 and p.grid<10000000,'Invalid grid')
    assert(not expression_present(events),'Timing edit blocked: CC/expression preservation is not implemented')
    -- Only exact-onset chords; tolerance and nonlinear tension need Ableton measurements.
    local groups={}
    for _,n in ipairs(selected) do
      groups[n.on.pos]=groups[n.on.pos] or {}
      table.insert(groups[n.on.pos],n)
    end
    for _,group in pairs(groups) do
      table.sort(group,function(a,b) return a.pitch<b.pitch or (a.pitch==b.pitch and a.on.id<b.on.id) end)
      if #group>1 then
        for i,n in ipairs(group) do
          local t=(i-1)/(#group-1)
          local pos=math.floor(n.on.pos+(low+(high-low)*t)*p.grid/100+.5)
          assert(pos>=0 and pos<n.off.pos,'Strum would create a negative start or nonpositive duration')
          n.on.pos=pos
        end
      end
    end
  else
    error('Unknown MIDI tool: '..tostring(tool))
  end
  return encode(events)
end

-- Recovery journals are versioned, checksummed and size-bounded. A journal is
-- written and read back before the take changes, and the previous journal is kept
-- if finalisation fails. Take identity comes from REAPER GUIDs, never names or
-- item indices, and the target is resolved again before restoring.
local RECOVERY='ReaSkiiMIDI-recovery'
local MAGIC='RSMR'
local VERSION=2
local MAX_BYTES=64*1024*1024
local MAX_META=4096
local MAX_FILE=2*MAX_BYTES+MAX_META+64

local function u16(data,pos)
  local a,b=data:byte(pos,pos+1)
  if not a or not b then return nil end
  return a+b*256
end
local function u32(data,pos)
  local a,b,c,d=data:byte(pos,pos+3)
  if not a or not b or not c or not d then return nil end
  return a+b*256+c*65536+d*16777216
end
local function p16(value)
  return string.char(value%256,math.floor(value/256)%256)
end
local function p32(value)
  return string.char(value%256,math.floor(value/256)%256,
    math.floor(value/65536)%256,math.floor(value/16777216)%256)
end
local function checksum(data)
  local hash=2166136261
  for i=1,#data do
    hash=((hash ~ data:byte(i))*16777619)&0xFFFFFFFF
  end
  return hash
end
-- Two 32-bit accumulators give a stable 64-bit file name without collisions from
-- 32-bit-only truncation. Metadata still verifies the real take/item GUIDs.
local function hash2(text)
  local a,b=5381,2166136261
  for i=1,#text do
    local byte=text:byte(i)
    a=(a*33+byte)&0xFFFFFFFF
    b=((b~byte)*16777619)&0xFFFFFFFF
  end
  return string.format('%08x%08x',a,b)
end
local function file_exists(path)
  local f=io.open(path,'rb')
  if not f then return false end
  f:close()
  return true
end
-- Reads with an explicit bound: a truncated or hostile length never reaches
-- string.unpack, and no allocation is made from an unchecked header field.
local function read_bounded(path,limit)
  local f,err=io.open(path,'rb')
  if not f then return nil,err or 'missing' end
  local size=f:seek('end')
  if not size then f:close(); return nil,'cannot size recovery file' end
  if size>limit then f:close(); return nil,'recovery file is too large' end
  f:seek('set',0)
  local raw,readerr=f:read(size)
  f:close()
  if not raw then return nil,readerr or 'cannot read recovery file' end
  if #raw~=size then return nil,'recovery file is truncated' end
  return raw
end

local function take_guid(take)
  if type(reaper.GetSetMediaItemTakeInfo_String)~='function' then
    return nil,'Take GUID API is unavailable'
  end
  local ok,ret,guid=pcall(reaper.GetSetMediaItemTakeInfo_String,take,'GUID','',false)
  if not ok then return nil,'Take GUID query failed: '..tostring(ret) end
  if type(guid)~='string' or guid=='' then return nil,'Take GUID is unavailable' end
  return guid
end
local function item_guid(item)
  if type(reaper.GetSetMediaItemInfo_String)~='function' then
    return nil,'Item GUID API is unavailable'
  end
  local ok,ret,guid=pcall(reaper.GetSetMediaItemInfo_String,item,'GUID','',false)
  if not ok then return nil,'Item GUID query failed: '..tostring(ret) end
  if type(guid)~='string' or guid=='' then return nil,'Item GUID is unavailable' end
  return guid
end
local function identity(take)
  local project=reaper.EnumProjects(-1,'')
  if not project then return nil,'No active project' end
  if not reaper.ValidatePtr2(project,take,'MediaItem_Take*') then
    return nil,'Invalid MIDI take'
  end
  local guid,gerr=take_guid(take)
  if not guid then return nil,gerr end
  local item=reaper.GetMediaItemTake_Item(take)
  if not item then return nil,'The take has no item' end
  local iguid,ierr=item_guid(item)
  if not iguid then return nil,ierr end
  if type(reaper.GetMediaItemTakeByGUID)~='function' then
    return nil,'Take lookup API is unavailable'
  end
  if reaper.GetMediaItemTakeByGUID(project,guid)~=take then
    return nil,'Take identity cannot be verified in the active project'
  end
  local project_name=type(reaper.GetProjectName)=='function'
    and (reaper.GetProjectName(project) or '') or ''
  local project_path=type(reaper.GetProjectPath)=='function'
    and (reaper.GetProjectPath() or '') or ''
  return {
    project=project,
    project_name=project_name,
    project_path=project_path,
    take_guid=guid,
    item_guid=iguid,
    -- Names and item positions are metadata only: they may change on rename.
    filename=hash2(guid..'\0'..iguid)..'.midirec',
  }
end
local function recovery_target(take)
  local meta,err=identity(take)
  if not meta then return nil,nil,err end
  return meta,reaper.GetResourcePath()..'/'..RECOVERY..'/'..meta.filename
end

local function encode_journal(meta,original,preview)
  local meta_text=table.concat({meta.project_name,meta.project_path,
    meta.take_guid,meta.item_guid},'\0')
  if #meta_text>MAX_META then return nil,'Recovery metadata is too large' end
  if #original>MAX_BYTES or #preview>MAX_BYTES then
    return nil,'MIDI is too large for a recovery file'
  end
  local body=MAGIC..string.char(VERSION,0)..p16(#meta_text)
    ..p32(#original)..p32(#preview)..meta_text..original..preview
  return body..p32(checksum(body))
end
-- Bounded, versioned parser. Every length is checked before slicing; there is
-- no string.unpack call and no trust in the file header.
local function decode_journal(raw)
  if type(raw)~='string' or #raw<20 then return nil,'Recovery file is truncated' end
  if raw:sub(1,4)~=MAGIC then return nil,'Not a ReaSkii recovery file (legacy or foreign format)' end
  local version=raw:byte(5)
  if version~=VERSION then
    return nil,'Unsupported recovery version: '..tostring(version)
  end
  local flags=raw:byte(6)
  if flags~=0 then return nil,'Unsupported recovery flags' end
  local meta_len=u16(raw,7)
  local original_len=u32(raw,9)
  local preview_len=u32(raw,13)
  if not meta_len or not original_len or not preview_len then
    return nil,'Recovery header is truncated'
  end
  if meta_len>MAX_META then return nil,'Recovery metadata is too large' end
  if original_len>MAX_BYTES or preview_len>MAX_BYTES then
    return nil,'Recovery payload is too large'
  end
  local total=16+meta_len+original_len+preview_len+4
  if total>#raw then return nil,'Recovery file is truncated' end
  if total~=#raw then return nil,'Recovery file has trailing data' end
  local expected=u32(raw,#raw-3)
  if checksum(raw:sub(1,#raw-4))~=expected then
    return nil,'Recovery checksum mismatch'
  end
  local meta_text=raw:sub(17,16+meta_len)
  local fields,start={},1
  for i=1,3 do
    local stop=meta_text:find('\0',start,true)
    if not stop then return nil,'Recovery metadata is malformed' end
    fields[i]=meta_text:sub(start,stop-1)
    start=stop+1
  end
  fields[4]=meta_text:sub(start)
  if fields[4]=='' or fields[4]:find('\0',1,true) then
    return nil,'Recovery metadata has unexpected fields'
  end
  local ostart=17+meta_len
  local pstart=ostart+original_len
  return {
    project_name=fields[1],project_path=fields[2],
    take_guid=fields[3],item_guid=fields[4],
    original=raw:sub(ostart,pstart-1),
    preview=raw:sub(pstart,pstart+preview_len-1),
  }
end

-- Write temp, close, read the exact bytes back, then finalise. POSIX os.rename
-- replaces atomically; Windows cannot, so the previous journal is moved aside
-- and restored if the new file cannot take its place. No atomicity is claimed
-- across platforms, only that the last valid journal is not deleted early.
local function write_recovery_file(path,data)
  local directory=path:match('^(.*)[/\\]')
  if directory then reaper.RecursiveCreateDirectory(directory,0) end
  local temp=path..'.tmp'
  local f,err=io.open(temp,'wb')
  if not f then return false,'Cannot create recovery file: '..tostring(err) end
  local wrote,werr=f:write(data)
  if wrote then f:flush() end
  local closed,cerr=f:close()
  if not wrote or not closed then
    os.remove(temp)
    return false,'Cannot write recovery file: '..tostring(werr or cerr)
  end
  local check,rerr=read_bounded(temp,MAX_FILE)
  if check~=data then
    os.remove(temp)
    return false,'Recovery readback failed: '..tostring(rerr or 'byte mismatch')
  end
  if os.rename(temp,path) then
    os.remove(path..'.bak')
    return true
  end
  local backup=path..'.bak'
  if file_exists(backup) then os.remove(backup) end
  if not os.rename(path,backup) then
    if os.rename(temp,path) then return true end
    os.remove(temp)
    return false,'Cannot finalise recovery file'
  end
  if os.rename(temp,path) then
    os.remove(backup)
    return true
  end
  local restored=os.rename(backup,path)
  os.remove(temp)
  if restored then
    return false,'Cannot finalise recovery file; the previous journal was preserved'
  end
  return false,'Cannot finalise recovery file; the previous journal is at '..backup
end

function M._write_recovery(take,original,preview)
  assert(type(original)=='string' and type(preview)=='string',
    'Recovery payloads must be raw MIDI')
  local meta,path,err=recovery_target(take)
  if not meta then error(err,0) end
  local data,enc_err=encode_journal(meta,original,preview)
  if not data then error(enc_err,0) end
  local ok,werr=write_recovery_file(path,data)
  if not ok then error(werr,0) end
  return true
end
function M._clear_recovery(take)
  local _,path,err=recovery_target(take)
  if not path then return false,err end
  local failure
  for _,suffix in ipairs({'','.bak','.tmp'}) do
    local candidate=path..suffix
    if file_exists(candidate) then
      local ok,rerr=os.remove(candidate)
      if not ok and file_exists(candidate) then
        failure=tostring(rerr or candidate)
      end
    end
  end
  if failure then return false,'Cannot remove recovery file: '..failure end
  return true
end
function M.recovery_pending(take)
  local ok,_,path=pcall(recovery_target,take)
  if not ok or not path then return false end
  return file_exists(path) or file_exists(path..'.bak')
end
function M.recover(take)
  local meta,path,err=recovery_target(take)
  if not meta then return false,err end
  local last_error='No interrupted preview was found for this take'
  for _,candidate in ipairs({path,path..'.bak'}) do
    if file_exists(candidate) then
      local raw,rerr=read_bounded(candidate,MAX_FILE)
      if not raw then
        last_error='Cannot read the recovery file: '..tostring(rerr)
      else
        local journal,jerr=decode_journal(raw)
        if not journal then
          last_error='Invalid recovery file: '..tostring(jerr)
        else
          if journal.take_guid~=meta.take_guid or journal.item_guid~=meta.item_guid then
            return false,'The recovery file belongs to a different take; it was left untouched'
          end
          local resolved=reaper.GetMediaItemTakeByGUID(meta.project,journal.take_guid)
          if resolved~=take then
            return false,'The recovery target cannot be verified in the active project'
          end
          local okread,current=reaper.MIDI_GetAllEvts(take,'')
          if not okread then return false,'Cannot read the MIDI take' end
          if current~=journal.preview then
            return false,'The MIDI changed after the preview; the recovery file was left for inspection'
          end
          if not reaper.MIDI_SetAllEvts(take,journal.original) then
            return false,'Failed to restore MIDI; the recovery file was kept'
          end
          local okback,restored=reaper.MIDI_GetAllEvts(take,'')
          if not okback or restored~=journal.original then
            return false,'The restored MIDI could not be verified; the recovery file was kept'
          end
          reaper.UpdateItemInProject(reaper.GetMediaItemTake_Item(take))
          -- Only now that the take holds the original bytes is the journal removed.
          M._clear_recovery(take)
          return true
        end
      end
    end
  end
  return false,last_error
end

function M.session(take)
  local project=reaper.EnumProjects(-1,'')
  assert(reaper.ValidatePtr2(project,take,'MediaItem_Take*'),'Invalid MIDI take')
  assert(reaper.TakeIsMIDI(take),'The selected take is not MIDI')
  local meta,path,err=recovery_target(take)
  assert(meta,err)
  local ok,snapshot=reaper.MIDI_GetAllEvts(take,'')
  assert(ok,'Failed to read MIDI')
  local s={take=take,original=snapshot,last=snapshot,project=project,closed=false,
    previewing=false,identity=meta,journal_path=path,recovery_written=false,
    pending_at_open=file_exists(path) or file_exists(path..'.bak')}
  local function status()
    assert(not s.closed,'Preview session is closed')
    assert(reaper.EnumProjects(-1,'')==s.project,'Active project changed; preview stopped')
    assert(reaper.ValidatePtr2(s.project,s.take,'MediaItem_Take*'),'MIDI take no longer exists')
    local current_meta=identity(s.take)
    assert(current_meta and current_meta.take_guid==s.identity.take_guid
      and current_meta.item_guid==s.identity.item_guid,'MIDI take identity changed')
    local read,current=reaper.MIDI_GetAllEvts(s.take,'')
    assert(read,'Failed to read MIDI')
    return current
  end
  local function clear_own()
    if not s.recovery_written then return true end
    return M._clear_recovery(s.take)
  end
  function s:check()
    local current=status()
    assert(current==self.last,'MIDI changed outside the panel; refusing to overwrite it')
  end
  function s:write(raw)
    assert(reaper.MIDI_SetAllEvts(self.take,raw),'Failed to write MIDI')
    local okread,current=reaper.MIDI_GetAllEvts(self.take,'')
    assert(okread,'Failed to read MIDI back')
    self.last=current
    reaper.UpdateItemInProject(reaper.GetMediaItemTake_Item(self.take))
    return current
  end
  function s:preview(tool,options)
    self:check()
    if not self.recovery_written
      and (file_exists(self.journal_path) or file_exists(self.journal_path..'.bak')) then
      error('A recovery file from an interrupted preview exists for this take; '
        ..'restore it before previewing again',0)
    end
    local transformed=M.transform(self.original,tool,options)
    -- Recovery is written and verified before the visible MIDI changes, never after.
    M._write_recovery(self.take,self.original,transformed)
    self.recovery_written=true
    local okwrite,werr=pcall(function() self:write(transformed) end)
    if not okwrite then
      -- If the take is still byte-identical to the original, the journal is not needed.
      local okread,current=reaper.MIDI_GetAllEvts(self.take,'')
      if okread and current==self.original then clear_own() end
      error(werr,0)
    end
    local okread,current=reaper.MIDI_GetAllEvts(self.take,'')
    assert(okread,'Failed to read MIDI back')
    self.last=current
    -- The write may already be visible even if the readback disagrees.
    self.previewing=true
    if current~=transformed then
      error('MIDI readback differs from the preview; the recovery file was kept',0)
    end
  end
  -- Used when the take was edited elsewhere: leave that edit intact and free the panel.
  -- When the take still holds our preview, the original is actually restored first.
  function s:abandon()
    if self.closed then return false,'closed' end
    local okread,current=reaper.MIDI_GetAllEvts(self.take,'')
    if not okread then
      self.closed=true
      return true,'unreadable'
    end
    if current~=self.last then
      -- If the journal's preview is still exactly in the take, it was our own write
      -- and the original can be restored; a genuine external edit is never touched.
      if self.recovery_written then
        local recovered=false
        pcall(function() recovered=M.recover(self.take)==true end)
        self.closed=true
        if recovered then return false,'original restored' end
      end
      self.closed=true
      -- Keep the recovery file: the user's external edit is not ours to discard.
      return true,'external edit preserved'
    end
    if current==self.original then
      self.closed=true
      local cleared,cerr=clear_own()
      return false,cleared and 'no preview to restore' or tostring(cerr)
    end
    local okwrite,werr=pcall(function() self:write(self.original) end)
    local restored=false
    if okwrite then
      local okback,after=reaper.MIDI_GetAllEvts(self.take,'')
      restored=okback and after==self.original
    end
    self.closed=true
    if restored then
      self.previewing=false
      local cleared,cerr=clear_own()
      return false,cleared and 'original restored' or tostring(cerr)
    end
    -- Report a kept preview/recovery, never a restore that did not happen.
    return true,'restore failed: '..tostring(werr or 'readback mismatch')
  end
  function s:cancel()
    self:check()
    -- Also covers a preview whose readback verification failed after a real write.
    if self.last~=self.original then
      local okwrite,werr=pcall(function() self:write(self.original) end)
      if not okwrite then
        error('Cancel could not restore the original MIDI; recovery kept: '
          ..tostring(werr),0)
      end
      local okread,current=reaper.MIDI_GetAllEvts(self.take,'')
      if not okread or current~=self.original then
        error('Cancel could not verify the original MIDI; recovery kept',0)
      end
    end
    self.closed=true
    local cleared,cerr=clear_own()
    if not cleared then
      error('Original MIDI restored, but the recovery file could not be removed: '
        ..tostring(cerr),0)
    end
  end
  function s:apply(description)
    self:check()
    local result=self.last
    local changed=result~=self.original
    if not changed then
      self.closed=true
      local cleared,cerr=clear_own()
      if not cleared then
        error('No MIDI change, but the recovery file could not be removed: '
          ..tostring(cerr),0)
      end
      return false
    end
    -- Put the original back outside the undo point, so undo returns to it.
    local okfirst,ferr=pcall(function() self:write(self.original) end)
    if not okfirst then
      self.closed=true
      error('Apply could not prepare the undo step: '..tostring(ferr),0)
    end
    reaper.Undo_BeginBlock2(self.project)
    local oksecond,serr=pcall(function() self:write(result) end)
    -- The block is always closed, including after a failed write.
    reaper.Undo_EndBlock2(self.project,description or 'ReaSkii MIDI',-1)
    if not oksecond then
      local restored=false
      pcall(function()
        self:write(self.original)
        local okread,current=reaper.MIDI_GetAllEvts(self.take,'')
        restored=okread and current==self.original
      end)
      self.closed=true
      if restored then clear_own() end
      error('Apply failed; '..(restored and 'the original MIDI was restored'
        or 'the recovery file was kept')..': '..tostring(serr),0)
    end
    -- Verify the bytes REAPER really holds before deleting the recovery journal.
    local okread,current=reaper.MIDI_GetAllEvts(self.take,'')
    if not okread or current~=result then
      local restored=false
      pcall(function()
        self:write(self.original)
        local okback,after=reaper.MIDI_GetAllEvts(self.take,'')
        restored=okback and after==self.original
      end)
      self.closed=true
      if restored then clear_own() end
      error('Apply could not be verified; '..(restored and 'the original MIDI was restored'
        or 'the recovery file was kept'),0)
    end
    self.closed=true
    local cleared,cerr=clear_own()
    if not cleared then
      error('Applied MIDI, but the recovery file could not be removed: '
        ..tostring(cerr),0)
    end
    return true
  end
  -- Test-only hook: emulate a panel that dies without atexit or cancel.
  function s:simulate_crash()
    self.closed=true
  end
  return s
end
return M
