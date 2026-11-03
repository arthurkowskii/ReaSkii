local H=dofile('scripts/midi/ReaSkii_MIDI_PanelContext.lua')
local calls={}
local R={GetMediaItemTake_Item=function() return 2 end,GetMediaItemInfo_Value=function(_,k) return ({D_POSITION=10,D_LENGTH=4,B_LOOPSRC=0})[k] end,
 GetSetMediaItemTakeInfo_String=function() return true,'fixture' end,MIDI_GetPPQPosFromProjQN=function(_,q) return q*1920-123 end,
 GetSet_LoopTimeRange2=function() return 11,12 end,MIDI_CountEvts=function() return true,0 end,MIDI_GetGrid=function() return .25 end,
 MIDI_GetPPQPosFromProjTime=function(_,t) calls[#calls+1]=t; return t*1234+345 end,
 GetMediaItemTakeInfo_Value=function(_,k) return k=='D_STARTOFFS' and 2 or 1.5 end}
local x=H.context(R,1,0); assert(calls[1]==11 and calls[2]==12); assert(x.generate_start==11*1234+345 and x.ppq==1920 and x.offset==2 and x.playrate==1.5)
print('PASS\tnative source PPQ conversion used for offset/playrate context')
R.GetSet_LoopTimeRange2=function() return 100,101 end
calls={}; x=H.context(R,1,0); assert(calls[1]==10 and calls[2]==14 and x.range_label=='item')
print('PASS\tno-overlap time selection falls back to item')
print('DONE\t2')
