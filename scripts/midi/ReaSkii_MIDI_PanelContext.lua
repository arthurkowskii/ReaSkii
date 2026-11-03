-- Read-only host context. All project-time/source conversions use native APIs.
local H={}
function H.context(R,take,project)
 local item=R.GetMediaItemTake_Item(take)
 local pos=R.GetMediaItemInfo_Value(item,'D_POSITION')
 local length=R.GetMediaItemInfo_Value(item,'D_LENGTH')
 local _,name=R.GetSetMediaItemTakeInfo_String(take,'P_NAME','',false)
 local ppq=R.MIDI_GetPPQPosFromProjQN(take,1)-R.MIDI_GetPPQPosFromProjQN(take,0)
 local s,e=R.GetSet_LoopTimeRange2(project,false,false,0,0,false)
 local label='time selection'
 if not s or e<=s or e<=pos or s>=pos+length then s,e=pos,pos+length; label='item' end
 s,e=math.max(s,pos),math.min(e,pos+length)
 local first,last,low,high,count
 local _,n=R.MIDI_CountEvts(take)
 count=0
 for i=0,n-1 do
  local ok,selected,_,a,b,_,pitch=R.MIDI_GetNote(take,i)
  if ok and selected then first=math.min(first or a,a); last=math.max(last or b,b); low=math.min(low or pitch,pitch); high=math.max(high or pitch,pitch); count=count+1 end
 end
 return {grid_ppq=R.MIDI_GetGrid(take)*ppq,ppq=ppq,anchor=first or 0,range_start=first,range_end=last,
  pivot=low and math.floor((low+high)/2),pitch_low=low,pitch_high=high,selected=count,
  generate_start=R.MIDI_GetPPQPosFromProjTime(take,s),generate_end=R.MIDI_GetPPQPosFromProjTime(take,e),range_label=label,
  item=item,name=name,position=pos,length=length,loop=R.GetMediaItemInfo_Value(item,'B_LOOPSRC')~=0,
  offset=R.GetMediaItemTakeInfo_Value(take,'D_STARTOFFS'),playrate=R.GetMediaItemTakeInfo_Value(take,'D_PLAYRATE')}
end
return H
