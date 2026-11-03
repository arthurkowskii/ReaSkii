-- ReaSkii MIDI Tools, laboratory prototype for the native REAPER MIDI editor.
-- Load this action from the MIDI Editor section. No theme/extension dependency.
reaper.set_action_options(1) -- one instance: the panel owns exactly one preview session
local script = debug.getinfo(1,'S').source:sub(2)
local directory = script:match('^(.*[/\\])') or ''
local function optional(name)
  local ok,module=pcall(dofile,directory..name)
  return ok and module or nil
end
local C = assert(dofile(directory .. 'ReaSkii_MIDI_Core.lua'))
local T = optional('ReaSkii_MIDI_Transformations.lua')
local G = optional('ReaSkii_MIDI_Generators.lua')
local A = optional('ReaSkii_MIDI_Adapter.lua')
if A then
  A.configure({C=C,T=T,G=G})
  -- Local interception: every Core preview now goes through the Adapter,
  -- which delegates legacy tools to the original Core function.
  A.install(C)
end

local session, active_tool, status = nil, nil, 'Select notes in the native MIDI editor.'
local transpose, velocity, random_amount, seed, low, high = 0,0,10,1,0,100
local previous_mouse = 0
local view = 'edit'
local last_inputs = {}

local SCALES = {
  major = {0,2,4,5,7,9,11}, minor = {0,2,3,5,7,8,10},
  harmonic_minor = {0,2,3,5,7,8,11}, dorian = {0,2,3,5,7,9,10},
  phrygian = {0,1,3,5,7,8,10}, lydian = {0,2,4,6,7,9,11},
  mixolydian = {0,2,4,5,7,9,10}, pentatonic_major = {0,2,4,7,9},
  pentatonic_minor = {0,3,5,7,10}, chromatic = {0,1,2,3,4,5,6,7,8,9,10,11},
}

local function target()
  local editor = reaper.MIDIEditor_GetActive()
  if not editor or reaper.MIDIEditor_GetMode(editor)==-1 then return nil, nil end
  local take = reaper.MIDIEditor_GetTake(editor)
  if not take or not reaper.TakeIsMIDI(take) then return nil, nil end
  return take, editor
end
local function take_label(take)
  local _,name = reaper.GetSetMediaItemTakeInfo_String(take,'P_NAME','',false)
  return name ~= '' and name or 'untitled MIDI take'
end
local function safe(fn)
  local ok,err=pcall(fn)
  if not ok then status=tostring(err):gsub('^.-:%d+: ','') end
end
local function reset_counters()
  transpose, velocity = 0, 0
end
local function clear()
  session=nil; active_tool=nil; reset_counters()
end
-- A take edited outside the panel keeps that edit; the panel simply releases it.
local function drop_session(reason)
  if not session then return end
  local ok,kept=pcall(function() return session:abandon() end)
  session, active_tool = nil, nil
  reset_counters()
  status = ok and kept and (reason..' The MIDI was left as edited outside the panel.')
    or (ok and (reason..' Original MIDI restored.') or ('Preview released: '..tostring(kept)))
end
local function sync_ppq(take)
  local ppq = reaper.MIDI_GetPPQPosFromProjQN(take,1)
    - reaper.MIDI_GetPPQPosFromProjQN(take,0)
  assert(ppq and ppq>0,'Cannot read the take PPQ resolution')
  if A then A.set_ppq(ppq) end
  return ppq
end
local function preview(tool, options)
  local take=assert(target(),'Open a MIDI item in the native MIDI editor first')
  sync_ppq(take)
  if session then
    assert(session.take==take,'Apply or Cancel before switching MIDI takes')
    if active_tool and active_tool~=tool then
      local ok,err=pcall(function() session:cancel() end)
      session, active_tool = nil, nil
      reset_counters()
      assert(ok,'Previous preview could not be cancelled: '..tostring(err))
    end
  end
  if not session then session=C.session(take) end
  local ok,err=pcall(function() session:preview(tool,options) end)
  if not ok then
    -- A failed first preview must not leave an empty session behind. A
    -- failed re-preview keeps the previous, still valid preview.
    if session and not session.previewing then
      pcall(function() session:cancel() end)
      session, active_tool = nil, nil
      reset_counters()
    end
    error(err)
  end
  active_tool=tool
  status='Preview: '..tool..' on '..take_label(take)..'. Apply or Cancel.'
end
local function finish(keep)
  assert(session,'No preview to '..(keep and 'apply' or 'cancel'))
  local label=take_label(session.take)
  local applied, kept
  local tool_name=active_tool or 'edit'
  local ok,err=pcall(function()
    if keep then applied=session:apply('ReaSkii MIDI: '..tool_name)
    else session:cancel(); kept=true end
  end)
  session, active_tool = nil, nil
  reset_counters()
  if not ok then error(err) end
  if keep then
    status=applied and ('Applied to '..label..'. REAPER Undo is available.')
      or ('No change on '..label..': nothing was selected or nothing moved.')
  else
    status='Cancelled. '..label..' was restored.'
  end
end
local function number_input(title,value,min,max)
  local ok,text=reaper.GetUserInputs(title,1,'Integer ('..min..' to '..max..')',tostring(value))
  if not ok then return value end
  local n=tonumber(text)
  assert(n and n%1==0 and n>=min and n<=max,'Value outside allowed range')
  return n
end

--------------------------------------------------------------------------
-- Dialog helpers (all validated before a preview can start)
--------------------------------------------------------------------------

local function trim(text)
  return (tostring(text):gsub('^%s+',''):gsub('%s+$',''))
end
local function field_values(title,names,values)
  local ok,csv=reaper.GetUserInputs(title,#names,table.concat(names,','),
    table.concat(values,','))
  if not ok then return nil end
  local out,index={},1
  for field in (csv..','):gmatch('([^,]*),') do out[index]=field; index=index+1 end
  while #out<#names do out[#out+1]='' end
  return out
end
local function number(text,name,min,max)
  local value=tonumber(trim(text))
  assert(value and value==value and value>=-math.huge and value<math.huge
    and value>=min and value<=max,
    name..' must be a number between '..min..' and '..max)
  return value
end
local function integer(text,name,min,max)
  local value=number(text,name,min,max)
  assert(value%1==0,name..' must be an integer')
  return value
end
local function list(text,name,min,max)
  local values={}
  for token in trim(text):gmatch('%S+') do
    values[#values+1]=integer(token,name,min,max)
  end
  assert(#values>0,name..' must not be empty')
  return values
end
local function mode_value(text)
  local mode=trim(text):lower()
  assert(mode=='add' or mode=='replace',"Mode must be 'add' or 'replace'")
  return mode
end
local function fmt(value)
  if value%1==0 then return tostring(math.tointeger(value) or value) end
  return string.format('%.6f',value)
end
local function grid_info(take)
  local grid=reaper.MIDI_GetGrid(take)
  assert(grid and grid>0,'The MIDI editor grid is off; choose a grid value first')
  local ppq=sync_ppq(take)
  return grid*ppq, grid, ppq
end
local function project_range(take)
  local item=reaper.GetMediaItemTake_Item(take)
  local position=reaper.GetMediaItemInfo_Value(item,'D_POSITION')
  local length=reaper.GetMediaItemInfo_Value(item,'D_LENGTH')
  local startoffs=reaper.GetMediaItemTakeInfo_Value(take,'D_STARTOFFS')
  local source_start=position-startoffs
  local ppq=sync_ppq(take)
  local source_qn=reaper.TimeMap2_timeToQN(0,source_start)
  local function ppq_at(time)
    return (reaper.TimeMap2_timeToQN(0,time)-source_qn)*ppq
  end
  local start_qn,end_qn=reaper.GetSet_LoopTimeRange2(0,false,false,0,0,false)
  local label='item'
  if not (end_qn and start_qn and end_qn>start_qn) then
    start_qn,end_qn=reaper.GetSet_LoopTimeRange2(0,false,true,0,0,false)
    label='loop'
  else
    label='time selection'
  end
  if not (end_qn and start_qn and end_qn>start_qn) then
    start_qn,end_qn=position,position+length
    label='item'
  else
    start_qn=math.max(start_qn,position)
    end_qn=math.min(end_qn,position+length)
    if end_qn<=start_qn then
      start_qn,end_qn=position,position+length
      label='item'
    end
  end
  return ppq_at(start_qn),ppq_at(end_qn),label
end
local function range_dialog(take,title)
  local startppq,endppq,label=project_range(take)
  local values=field_values(title..' range ('..label..')',
    {'Start (QN)','End (QN)'},{fmt(A.ppq_to_qn(startppq)),fmt(A.ppq_to_qn(endppq))})
  if not values then return nil end
  local start_qn=number(values[1],'Range start',0,1000000000)
  local end_qn=number(values[2],'Range end',0,1000000000)
  assert(end_qn>start_qn,'Range end must be after range start')
  local start_ppq=A.qn_to_ppq(start_qn)
  local end_ppq=A.qn_to_ppq(end_qn)
  assert(end_ppq>start_ppq,'Range is empty')
  return {start=start_ppq, ["end"]=end_ppq}
end

--------------------------------------------------------------------------
-- Transformation dialogs: 9 tools
--------------------------------------------------------------------------

local function dlg_arpeggiate(take)
  local grid_ppq=grid_info(take)
  local values=last_inputs.arpeggiate or {'up','1','50','1'}
  local f=field_values('Arpeggiate',{'Mode (up/down/updown)','Rate (grid steps)',
    'Gate (%)','Octaves'},values)
  if not f then return nil end
  local mode_value_text=trim(f[1]):lower()
  assert(mode_value_text=='up' or mode_value_text=='down' or mode_value_text=='updown',
    'Mode must be up, down or updown')
  local rate=integer(f[2],'Rate',1,64)
  local gate=number(f[3],'Gate',1,800)
  local octaves=integer(f[4],'Octaves',1,8)
  local range=range_dialog(take,'Arpeggiate')
  if not range then return nil end
  last_inputs.arpeggiate={mode_value_text,tostring(rate),tostring(gate),tostring(octaves)}
  return {mode=mode_value_text, rate_ppq=rate*grid_ppq, gate=gate/100,
    octaves=octaves, range_start=range.start, range_end=range["end"]}
end
local function dlg_chop(take)
  local _=take
  local values=last_inputs.chop or {'2'}
  local f=field_values('Chop',{'Parts (2 to 64)'},values)
  if not f then return nil end
  local parts=integer(f[1],'Parts',2,64)
  last_inputs.chop={tostring(parts)}
  return {parts=parts}
end
local function dlg_fit_scale(take)
  local _=take
  local values=last_inputs.fit_scale or {'0','major'}
  local f=field_values('Fit to scale',{'Root (0=C to 11=B)',
    'Scale name (major/minor/chromatic/...)'},values)
  if not f then return nil end
  local root=integer(f[1],'Root',0,11)
  local name=trim(f[2]):lower()
  local intervals=SCALES[name]
  assert(intervals,'Unknown scale: '..name)
  last_inputs.fit_scale={tostring(root),name}
  return {root=root, intervals=intervals}
end
local function dlg_invert(take)
  local _=take
  local values=last_inputs.invert or {'60'}
  local f=field_values('Invert (melodic)',{'Pivot (0 to 127)'},values)
  if not f then return nil end
  local pivot=integer(f[1],'Pivot',0,127)
  last_inputs.invert={tostring(pivot)}
  return {pivot=pivot}
end
local function dlg_legato(take)
  local _=take
  return {}
end
local function dlg_quantize(take)
  local grid_ppq=grid_info(take)
  local values=last_inputs.quantize or {'1','100'}
  local f=field_values('Quantize',{'Grid (steps)','Strength (%)'},values)
  if not f then return nil end
  local steps=integer(f[1],'Grid steps',1,64)
  local strength=number(f[2],'Strength',0,100)
  last_inputs.quantize={tostring(steps),tostring(strength)}
  return {grid_ppq=steps*grid_ppq, strength=strength/100}
end
local function dlg_reverse(take)
  local range=range_dialog(take,'Reverse')
  if not range then return nil end
  return {range_start=range.start, range_end=range["end"]}
end
local function dlg_stretch(take)
  local values=last_inputs.stretch or {'200'}
  local f=field_values('Stretch',{'Factor (%)'},values)
  if not f then return nil end
  local percent=number(f[1],'Factor',1,10000)
  local range=range_dialog(take,'Stretch anchor')
  if not range then return nil end
  last_inputs.stretch={tostring(percent)}
  return {factor=percent/100, anchor=range.start}
end
local function dlg_strum(take)
  local grid_ppq=grid_info(take)
  local values=last_inputs.strum_new or {'0','100','0','10'}
  local f=field_values('Strum',{'Low (-100 to 100)','High (-100 to 100)',
    'Tension (-100 to 100)','Onset tolerance (% of grid)'},values)
  if not f then return nil end
  local low_value=integer(f[1],'Low',-100,100)
  local high_value=integer(f[2],'High',-100,100)
  local tension=integer(f[3],'Tension',-100,100)
  local tolerance=number(f[4],'Onset tolerance',0,100)
  last_inputs.strum_new={tostring(low_value),tostring(high_value),
    tostring(tension),tostring(tolerance)}
  return {low=low_value, high=high_value, grid_ppq=grid_ppq,
    tension=tension/100, onset_tolerance=grid_ppq*tolerance/100}
end

local TRANSFORM_ORDER={'Arpeggiate','Chop','Fit scale','Invert','Legato','Quantize',
  'Reverse','Stretch','Strum'}
local TRANSFORM_TOOL={['Arpeggiate']='arpeggiate',['Chop']='chop',
  ['Fit scale']='fit_scale',['Invert']='invert',['Legato']='legato',
  ['Quantize']='quantize',['Reverse']='reverse',['Stretch']='stretch',
  ['Strum']='strum'}
local TRANSFORM_DIALOG={arpeggiate=dlg_arpeggiate,chop=dlg_chop,
  fit_scale=dlg_fit_scale,invert=dlg_invert,legato=dlg_legato,
  quantize=dlg_quantize,reverse=dlg_reverse,stretch=dlg_stretch,strum=dlg_strum}

--------------------------------------------------------------------------
-- Generator dialogs: 5 tools, add mode by default
--------------------------------------------------------------------------

local function dlg_rhythm(take)
  local grid_ppq=grid_info(take)
  local values=last_inputs.rhythm or {'8','4','1','0.5','60','100','add'}
  local f=field_values('Rhythm',{'Steps','Density','Seed','Note length (grid steps)',
    'Pitches (space separated)','Velocity','Mode (add/replace)'},values)
  if not f then return nil end
  local steps=integer(f[1],'Steps',1,1024)
  local density=integer(f[2],'Density',0,steps)
  local seed_value=integer(f[3],'Seed',-2147483648,2147483647)
  local note_length=number(f[4],'Note length',0.001,1000000000)
  local pitches=list(f[5],'Pitch',0,127)
  local vel=integer(f[6],'Velocity',1,127)
  local mode=mode_value(f[7])
  local range=range_dialog(take,'Rhythm')
  if not range then return nil end
  last_inputs.rhythm={tostring(steps),tostring(density),tostring(seed_value),
    tostring(note_length),trim(f[5]),tostring(vel),mode}
  return {range_start=range.start, range_end=range["end"], steps=steps,
    density=density, seed=seed_value, note_length=note_length*grid_ppq,
    step_ppq=grid_ppq, pitches=pitches, vel=vel, channel=0,
    release_velocity=0, mode=mode}
end
local function dlg_euclidean(take)
  local grid_ppq=grid_info(take)
  local values=last_inputs.euclidean or {'8','4','0','60','100','0.5','add'}
  local f=field_values('Euclidean',{'Steps','Pulses','Rotation','Pitch','Velocity',
    'Note length (grid steps)','Mode (add/replace)'},values)
  if not f then return nil end
  local steps=integer(f[1],'Steps',1,1024)
  local pulses=integer(f[2],'Pulses',0,steps)
  local rotation=integer(f[3],'Rotation',-16384,16384)
  local pitch=integer(f[4],'Pitch',0,127)
  local vel=integer(f[5],'Velocity',1,127)
  local note_length=number(f[6],'Note length',0.001,1000000000)
  local mode=mode_value(f[7])
  local range=range_dialog(take,'Euclidean')
  if not range then return nil end
  last_inputs.euclidean={tostring(steps),tostring(pulses),tostring(rotation),
    tostring(pitch),tostring(vel),tostring(note_length),mode}
  return {range_start=range.start, range_end=range["end"], steps=steps,
    pulses=pulses, rotation=rotation, pitch=pitch, vel=vel,
    note_length=note_length*grid_ppq, step_ppq=grid_ppq, channel=0,
    release_velocity=0, mode=mode}
end
local function dlg_seed(take)
  local grid_ppq=grid_info(take)
  local values=last_inputs.seed or {'50','60','72','80','110','1','add'}
  local f=field_values('Seed',{'Density (%)','Pitch min','Pitch max',
    'Velocity min','Velocity max','Seed','Mode (add/replace)'},values)
  if not f then return nil end
  local density=number(f[1],'Density',0,100)
  local pitch_min=integer(f[2],'Pitch min',0,127)
  local pitch_max=integer(f[3],'Pitch max',0,127)
  assert(pitch_max>=pitch_min,'Pitch max must be >= pitch min')
  local vel_min=integer(f[4],'Velocity min',1,127)
  local vel_max=integer(f[5],'Velocity max',1,127)
  assert(vel_max>=vel_min,'Velocity max must be >= velocity min')
  local seed_value=integer(f[6],'Seed',-2147483648,2147483647)
  local mode=mode_value(f[7])
  local range=range_dialog(take,'Seed')
  if not range then return nil end
  last_inputs.seed={tostring(density),tostring(pitch_min),tostring(pitch_max),
    tostring(vel_min),tostring(vel_max),tostring(seed_value),mode}
  return {range_start=range.start, range_end=range["end"], grid_ppq=grid_ppq,
    density=density/100, pitch_min=pitch_min, pitch_max=pitch_max,
    vel_min=vel_min, vel_max=vel_max, seed=seed_value, channel=0,
    release_velocity=0, mode=mode}
end
local function dlg_shape(take)
  local _=take
  local values=last_inputs.shape or {'sine','16','60','72','100','add'}
  local f=field_values('Shape',{'Shape (line/sine/triangle)','Steps','Pitch min',
    'Pitch max','Velocity','Mode (add/replace)'},values)
  if not f then return nil end
  local shape=trim(f[1]):lower()
  assert(shape=='line' or shape=='sine' or shape=='triangle',
    'Shape must be line, sine or triangle')
  local steps=integer(f[2],'Steps',1,1024)
  local pitch_min=integer(f[3],'Pitch min',0,127)
  local pitch_max=integer(f[4],'Pitch max',0,127)
  assert(pitch_max>=pitch_min,'Pitch max must be >= pitch min')
  local vel=integer(f[5],'Velocity',1,127)
  local mode=mode_value(f[6])
  local range=range_dialog(take,'Shape')
  if not range then return nil end
  last_inputs.shape={shape,tostring(steps),tostring(pitch_min),tostring(pitch_max),
    tostring(vel),mode}
  return {range_start=range.start, range_end=range["end"], shape=shape, steps=steps,
    pitch_min=pitch_min, pitch_max=pitch_max, vel=vel, channel=0,
    release_velocity=0, mode=mode}
end
local function dlg_stacks(take)
  local grid_ppq=grid_info(take)
  local values=last_inputs.stacks or {'48','0 4 7','1','100','add'}
  local f=field_values('Stacks',{'Roots (space separated)',
    'Intervals (space separated)','Duration (grid steps)','Velocity',
    'Mode (add/replace)'},values)
  if not f then return nil end
  local roots=list(f[1],'Root',0,127)
  local intervals=list(f[2],'Interval',-127,127)
  local duration=number(f[3],'Duration',0.001,1000000000)
  local vel=integer(f[4],'Velocity',1,127)
  local mode=mode_value(f[5])
  local range=range_dialog(take,'Stacks')
  if not range then return nil end
  local chords={}
  for index,root in ipairs(roots) do
    chords[index]={root=root,intervals=intervals,duration_ppq=duration*grid_ppq}
  end
  last_inputs.stacks={trim(f[1]),trim(f[2]),tostring(duration),tostring(vel),mode}
  return {range_start=range.start, range_end=range["end"], chords=chords, vel=vel,
    channel=0, release_velocity=0, mode=mode}
end

local GENERATOR_ORDER={'Rhythm','Euclidean','Seed','Shape','Stacks'}
local GENERATOR_DIALOG={rhythm=dlg_rhythm,euclidean=dlg_euclidean,seed=dlg_seed,
  shape=dlg_shape,stacks=dlg_stacks}

local function run_transform(name)
  local take=assert(target(),'Open a MIDI item in the native MIDI editor first')
  local dialog=TRANSFORM_DIALOG[name]
  local options=dialog and dialog(take)
  if options then preview(name,options) end
end
local function run_generator(name)
  local take=assert(target(),'Open a MIDI item in the native MIDI editor first')
  local dialog=GENERATOR_DIALOG[name]
  local options=dialog and dialog(take)
  if options then preview(name,options) end
end

local function offer_recovery()
  local take=target()
  if not take or not C.recovery_pending or not C.recovery_pending(take) then return end
  if reaper.ShowMessageBox('An interrupted ReaSkii preview was found for "'..take_label(take)
    ..'".\n\nRestore the MIDI as it was before that preview?','ReaSkii MIDI Tools: recovery',4)==6 then
    local ok,restored=pcall(C.recover,take)
    status=ok and restored and 'Interrupted preview restored.' or ('Not restored: '..tostring(restored))
  else
    status='Recovery declined. The current MIDI was left untouched.'
  end
end
reaper.atexit(function()
  if session and not session.closed then
    local ok,err=pcall(function() session:cancel() end)
    if not ok then
      -- The recovery file stays on disk; the next panel run offers it back.
      reaper.ShowMessageBox('Preview could not be restored safely:\n'..tostring(err)
        ..'\n\nThe MIDI is intact; reopen the panel to be offered the recovery.','ReaSkii MIDI Tools',0)
    end
  end
  gfx.quit()
end)
gfx.init('ReaSkii MIDI Tools',320,560,0,30,100)
gfx.setfont(1,'Arial',15)
local function text(x,y,label,r,g,b)
  gfx.set(r or .88,g or .89,b or .91,1); gfx.x=x; gfx.y=y; gfx.drawstr(label)
end
local function button(x,y,w,label,clicked,fn,h,active)
  h=h or 28
  local over=gfx.mouse_x>=x and gfx.mouse_x<x+w and gfx.mouse_y>=y and gfx.mouse_y<y+h
  gfx.set(active and .30 or (over and .28 or .20),active and .26 or .22,.25,1)
  gfx.rect(x,y,w,h,true)
  text(x+7,y+(h-16)/2,label,active and .98 or .88,active and .98 or .89,active and .98 or .91)
  if clicked and over then safe(fn) end
end
local function draw_edit(take,clicked)
  local _=take
  text(12,106,'Pitch: '..transpose..' semitones')
  for i,d in ipairs({-12,-1,1,12}) do
    button(12+(i-1)*73,128,66,(d>0 and '+' or '')..d,clicked,function()
      local amount=transpose+d
      preview('transpose',{amount=amount}); transpose=amount
    end)
  end
  text(12,169,'Velocity: '..velocity)
  button(12,193,138,'-10',clicked,function()
    local amount=velocity-10; preview('velocity',{amount=amount}); velocity=amount
  end)
  button(160,193,138,'+10',clicked,function()
    local amount=velocity+10; preview('velocity',{amount=amount}); velocity=amount
  end)
  button(12,232,138,'Range: '..random_amount,clicked,function()
    random_amount=number_input('Random velocity range',random_amount,0,126)
  end)
  button(160,232,138,'Seed: '..seed,clicked,function()
    seed=number_input('Random velocity seed',seed,1,2147483646)
  end)
  button(12,268,286,'Preview random velocity',clicked,function()
    preview('random_velocity',{amount=random_amount,seed=seed})
  end)
  text(12,312,'TRANSFORM / Strum (linear only)')
  button(12,338,138,'Low: '..low..' %',clicked,function()
    low=number_input('Strum Low',low,-100,100)
  end)
  button(160,338,138,'High: '..high..' %',clicked,function()
    high=number_input('Strum High',high,-100,100)
  end)
  button(12,374,286,'Preview Strum',clicked,function()
    local take_now=assert(target(),'No native MIDI editor take')
    local grid=reaper.MIDI_GetGrid(take_now)
    assert(grid and grid>0,'The MIDI editor grid is off; choose a grid value first')
    local ticks=reaper.MIDI_GetPPQPosFromProjQN(take_now,1)-reaper.MIDI_GetPPQPosFromProjQN(take_now,0)
    preview('strum',{low=low,high=high,grid=grid*ticks})
  end)
end
local function draw_transform(clicked)
  text(12,106,'TRANSFORMATIONS / parameters in dialog')
  for index,name in ipairs(TRANSFORM_ORDER) do
    local tool=TRANSFORM_TOOL[name]
    button(12,118+(index-1)*30,286,name,clicked,function()
      run_transform(tool)
    end)
  end
  text(12,400,'Range: item/loop/time selection, confirmed per tool.',.72,.75,.8)
end
local function draw_generate(clicked)
  text(12,106,'GENERATORS / explicit range and mode')
  for index,name in ipairs(GENERATOR_ORDER) do
    local generator=string.lower(name)
    button(12,118+(index-1)*30,286,name,clicked,function()
      run_generator(generator)
    end)
  end
  text(12,282,'Mode add by default; replace must be typed.',.72,.75,.8)
  text(12,302,'Range comes from item/loop/time selection and is confirmed.',.72,.75,.8)
end
local function loop()
  local key=gfx.getchar()
  if key<0 then
    -- The window manager closed the panel: cancel the preview, then leave.
    if session and not session.closed then pcall(function() session:cancel() end) end
    session=nil; active_tool=nil
    gfx.quit()
    return
  end
  if key==27 and not session then gfx.quit(); return end
  local down=(gfx.mouse_cap & 1)==1
  local clicked=down and previous_mouse==0
  previous_mouse=down and 1 or 0
  gfx.set(.115,.125,.14,1); gfx.rect(0,0,gfx.w,gfx.h,true)
  text(12,12,'ReaSkii / MIDI Tools')
  text(12,36,'LAB: Ableton parity not measured',.75,.77,.80)
  local take=target()
  text(12,58,'Target: '..(take and take_label(take) or 'no MIDI editor take'))
  button(12,72,94,'Edit',clicked,function() view='edit' end,26,view=='edit')
  button(110,72,94,'Transform',clicked,function() view='transform' end,26,view=='transform')
  button(208,72,94,'Generate',clicked,function() view='generate' end,26,view=='generate')
  if view=='edit' then draw_edit(take,clicked)
  elseif view=='transform' then draw_transform(clicked)
  else draw_generate(clicked) end
  button(12,421,138,'Apply',clicked,function() finish(true) end)
  button(160,421,138,'Cancel',clicked,function() finish(false) end)
  button(12,458,286,'Toggle REAPER docker',clicked,function()
    gfx.dock(gfx.dock(-1)==0 and 1 or 0)
  end)
  text(12,494,'Session: '..(session and ('PREVIEW '..tostring(active_tool)) or 'no preview'),
    session and .95 or .7,.8,.85)
  local line,y='',512
  for word in status:gmatch('%S+') do
    if gfx.measurestr(line..word)>gfx.w-25 then text(12,y,line); y=y+17; line='' end
    line=line..word..' '
  end
  text(12,y,line)
  gfx.update()
  reaper.defer(guarded_loop)
end
function guarded_loop()
  local ok,err=xpcall(loop,debug.traceback)
  if not ok then
    if session then pcall(function() drop_session('Panel error:') end) end
    reaper.ShowMessageBox(err,'ReaSkii MIDI Tools error',0)
  end
end
offer_recovery()
guarded_loop()
