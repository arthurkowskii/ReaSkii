-- Pure device-rack configuration model. No REAPER, gfx or I/O.
local M={}
M.VERSION='v1'
local MAX_PARAMS=4096

local function trim(s) return (tostring(s):gsub('^%s+',''):gsub('%s+$','')) end
local function escape(s)
  return (tostring(s):gsub('\\','\\\\'):gsub('\t','\\t'):gsub('\n','\\n'):gsub('\r','\\r'))
end
local function unescape(s)
  local out={}
  local i=1
  while i<=#s do
    local c=s:sub(i,i)
    if c=='\\' then
      local n=s:sub(i+1,i+1)
      if n=='t' then out[#out+1]='\t'
      elseif n=='n' then out[#out+1]='\n'
      elseif n=='r' then out[#out+1]='\r'
      elseif n=='\\' then out[#out+1]='\\'
      else out[#out+1]=n end
      i=i+2
    else out[#out+1]=c; i=i+1 end
  end
  return table.concat(out)
end
local function split_fields(line)
  local fields,current,escaped={},'',false
  for i=1,#line do
    local c=line:sub(i,i)
    if escaped then current=current..'\\'..c; escaped=false
    elseif c=='\\' then escaped=true
    elseif c=='\t' and #fields<2 then fields[#fields+1]=current; current=''
    else current=current..c end
  end
  if escaped then current=current..'\\' end
  fields[#fields+1]=current
  return fields
end
local function valid_kind(kind) return kind=='toggle' and 'toggle' or 'slider' end
function M.sanitize_label(label)
  local s=tostring(label or ''):gsub('[%z\1-\31\127]',' ')
  s=trim(s:gsub('%s+',' '))
  if s=='' then s='Parameter' end
  if #s>80 then s=s:sub(1,80) end
  return s
end
function M.encode(controls)
  local lines={M.VERSION}
  for _,control in ipairs(controls or {}) do
    if type(control)=='table' and type(control.param)=='number' then
      lines[#lines+1]=string.format('%d\t%s\t%s',control.param,
        escape(control.label or ('Param '..control.param)),valid_kind(control.kind))
    end
  end
  return table.concat(lines,'\n')..'\n'
end
function M.decode(text)
  if type(text)~='string' or text=='' or text:match('^%s*$') then return {},nil end
  local lines={}
  for line in (text..'\n'):gmatch('(.-)\r?\n') do lines[#lines+1]=line end
  if lines[1]~=M.VERSION then return nil,'Unsupported device-rack configuration version' end
  local controls,seen,ignored={},{},0
  for index=2,#lines do
    local line=lines[index]
    if line~='' then
      local fields=split_fields(line)
      local param=tonumber(fields[1])
      if not param or param%1~=0 or param<0 or param>MAX_PARAMS or fields[2]==nil then
        ignored=ignored+1
      else
        local label=unescape(fields[2] or '')
        local kind=valid_kind(fields[3])
        if not seen[param] then
          seen[param]=true
          controls[#controls+1]={param=param,label=label,kind=kind}
        else ignored=ignored+1 end
      end
    end
  end
  if ignored>0 then return controls,'Some invalid or duplicate entries were ignored' end
  return controls,nil
end
function M.add(controls,param,label,kind)
  local out={}
  for _,control in ipairs(controls or {}) do out[#out+1]=control end
  if type(param)~='number' or param%1~=0 or param<0 or param>MAX_PARAMS then return out end
  for _,control in ipairs(out) do if control.param==param then return out end end
  out[#out+1]={param=param,label=M.sanitize_label(label or ('Param '..param)),kind=valid_kind(kind)}
  return out
end
function M.remove(controls,param)
  local out={}
  for _,control in ipairs(controls or {}) do
    if control.param~=param then out[#out+1]=control end
  end
  return out
end
function M.move(controls,param,delta)
  local out={}
  for _,control in ipairs(controls or {}) do out[#out+1]=control end
  if type(delta)~='number' or delta==0 then return out end
  local index
  for i,control in ipairs(out) do if control.param==param then index=i; break end end
  if not index then return out end
  local target=math.max(1,math.min(#out,index+delta))
  if target==index then return out end
  local moved=table.remove(out,index)
  table.insert(out,target,moved)
  return out
end
function M.find(controls,param)
  for index,control in ipairs(controls or {}) do
    if control.param==param then return control,index end
  end
end
function M.x_to_norm(x,left,width,inverted)
  if type(x)~='number' or type(left)~='number' or type(width)~='number' or width<=0 then return 0 end
  local value=math.max(0,math.min(1,(x-left)/width))
  if inverted then value=1-value end
  return value
end
return M
