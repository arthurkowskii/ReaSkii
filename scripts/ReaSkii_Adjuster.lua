-- ReaSkii: Reapertips behavior/parameters, reARK graphics and right-hand FX.
local dir=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
local D=dofile(dir..'ReaSkii_Defaults.lua')
if not D.is_theme() then reaper.ShowMessageBox('Select ReaSkii first.','ReaSkii',0);return end
local ok,result=pcall(D.ensure)
if not ok then reaper.ShowMessageBox(tostring(result),'ReaSkii migration failed',0);return end
local controls={
 {'tcp_name_full_row','Track name takes the whole row'},
 {'tcp_name_keep_vol','...but keep volume'},
 {'tcp_name_keep_pan','...but keep pan'},
 {'tcp_name_keep_info','...but keep infoblock (requires Use InfoBlock)'},
 {'tcp_name_keep_io','...but keep routing button'},
 {'tcp_infoblock','Use InfoBlock'},
 {'smart_folder_indent','Smart folder indent'},
 {'reark_tcp_fx_sidebar','Keep reARK FX presentation on the TCP right'},
}
local tab,offset,query,was_down='First row',0,'',false
local function text(x,y,label,bright)
 gfx.set(bright and 0.94 or 0.69,bright and 0.94 or 0.69,bright and 0.94 or 0.69)
 gfx.x,gfx.y=x,y;gfx.drawstr(label)
end
local function inside(x,y,w,h) return gfx.mouse_x>=x and gfx.mouse_x<x+w and gfx.mouse_y>=y and gfx.mouse_y<y+h end
local function button(x,y,w,label,click)
 gfx.set(0.25,0.25,0.25);gfx.rect(x,y,w,28);text(x+8,y+5,label,true)
 return click and inside(x,y,w,28)
end
local function set(p,v) D.set(p,v);D.refresh() end
local function edit(p)
 if p.maximum==1 and p.minimum==0 then set(p,1-p.value);return end
 local accept,value=reaper.GetUserInputs(p.desc,1,'Value ('..p.minimum..' to '..p.maximum..'):',tostring(p.value))
 if accept then value=tonumber(value);if value and value>=p.minimum and value<=p.maximum then set(p,value) end end
end
local function matches(p)
 if p.name:match('^label_') or p.name:match('^user_notice') or p.name=='defaultV6' then return false end
 local desc=p.desc:lower();local name=p.name
 if query~='' and not (desc..' '..name):find(query:lower(),1,true) then return false end
 if tab=='All' then return true end
 if tab=='TCP' then return desc:find('tcp',1,true)~=nil or desc:find('envelope',1,true)~=nil end
 if tab=='Mixer' then return desc:find('mcp',1,true)~=nil end
 if tab=='Other' then return not desc:find('tcp',1,true) and not desc:find('mcp',1,true) end
 return false
end
local function mask(p)
 return p.name:match('^param') and p.maximum==15 and p.minimum==0 and p.desc:match('_tcp_')
end
local function edit_mask(p)
 local labels={'Hide when mixer is visible','Hide when not selected','Hide when not armed','Always hide'}
 local menu='Always visible (clear mask)'
 for i,label in ipairs(labels) do menu=menu..'|'..((p.value & (1 << (i-1)))~=0 and '!' or '')..label end
 local choice=gfx.showmenu(menu)
 if choice==1 then set(p,0) elseif choice>=2 then set(p,p.value ~ (1 << (choice-2))) end
end
local function reset()
 local success,backup=pcall(D.apply)
 reaper.ShowMessageBox(success and ('Defaults applied. Previous values saved in:\n'..backup) or tostring(backup),'ReaSkii',0)
end
gfx.init('ReaSkii - Theme controls',720,670,0)
gfx.setfont(1,'Arial',16)
reaper.SetExtState('ReaSkii','adjuster_open','1',false)
reaper.atexit(function() reaper.DeleteExtState('ReaSkii','adjuster_open',false);gfx.quit() end)
local function loop()
 if not D.is_theme() or gfx.getchar()<0 then return end
 local params,ordered=D.parameters()
 local down=gfx.mouse_cap & 1==1;local click=down and not was_down;was_down=down
 gfx.set(0.12,0.12,0.12);gfx.rect(0,0,gfx.w,gfx.h)
 text(18,14,'ReaSkii 0.2: Reapertips engine / reARK graphics',true)
 if tab=='First row' then
  for i,entry in ipairs(controls) do
   local p=assert(params[entry[1]],'Missing control '..entry[1]);local y=48+(i-1)*34
   local enabled=not (i>=2 and i<=5) or params.tcp_name_full_row.value==1
   gfx.set(0.7,0.7,0.7);gfx.rect(20,y,19,19,0)
   if p.value==1 then gfx.line(23,y+9,28,y+14);gfx.line(28,y+14,36,y+4) end
   text(49,y,entry[2],enabled)
   if click and enabled and inside(18,y-3,650,27) then set(p,1-p.value) end
  end
  text(20,340,'Keep options choose placement; A / B / C visibility masks still apply.',false)
  text(20,368,'TCP tab: visibility masks, sizes, reARK FX width / rows / columns.',false)
  text(20,396,'All tab: every engine parameter, searchable and editable.',false)
  text(20,424,'reARK skin replaces Reapertips panel paint and font defaults.',false)
 else
  local list={};for _,p in ipairs(ordered) do if matches(p) then list[#list+1]=p end end
  if gfx.mouse_wheel~=0 then offset=offset-math.floor(gfx.mouse_wheel/120)*3;gfx.mouse_wheel=0 end
  local rows=13;offset=math.max(0,math.min(math.max(0,#list-rows),offset))
  for i=1,rows do
   local p=list[offset+i];if not p then break end
   local y=46+(i-1)*34
   local label=p.desc
   if #label>62 then label=label:sub(1,59)..'...' end
   text(20,y,label,true)
   if button(560,y-3,125,tostring(p.value)..(mask(p) and ' mask' or ''),click) then
    if mask(p) then edit_mask(p) else edit(p) end
   end
  end
  text(20,496,string.format('%d-%d / %d parameters | Mouse wheel to scroll',#list==0 and 0 or offset+1,math.min(#list,offset+rows),#list),false)
  if button(500,490,80,'Up',click) then offset=math.max(0,offset-rows) end
  if button(590,490,95,'Down',click) then offset=math.min(math.max(0,#list-rows),offset+rows) end
 end
 local tabs={'First row','TCP','Mixer','Other','All'}
 for i,name in ipairs(tabs) do
  if button(20+(i-1)*136,535,125,(tab==name and '> ' or '')..name,click) then tab=name;offset=0 end
 end
 if button(20,578,280,'Apply Reapertips / ReaSkii defaults',click) then reset() end
 if button(312,578,120,'Search...',click) then
  local accepted,value=reaper.GetUserInputs('Filter parameters',1,'Name or description:',query)
  if accepted then query=value;offset=0;if query~='' then tab='All' end end
 end
 if button(445,578,240,'Clear filter',click) then query='';offset=0 end
 text(20,625,'Defaults migration is automatic once per engine version, with a restore backup.',false)
 gfx.update();reaper.defer(loop)
end
loop()
