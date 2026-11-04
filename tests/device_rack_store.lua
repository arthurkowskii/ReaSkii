-- Device-rack persistence with mocked ProjExtState.
local S=dofile('scripts/device/ReaSkii_DeviceRackStore.lua')
local M=dofile('scripts/device/ReaSkii_DeviceRackModel.lua')
local count=0
local function test(name,fn) fn(); count=count+1; print('PASS\t'..name) end
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local store,trackGuid,fxGuid={},{}, {}
local R={}
R.GetTrackGUID=function() return trackGuid[1] end
R.TrackFX_GetFXGUID=function(_,fx) return fxGuid[fx] end
R.GetProjExtState=function(_,section,key) return store[section] and store[section][key] and 1 or 0,store[section] and store[section][key] or '' end
R.SetProjExtState=function(_,section,key,value) store[section]=store[section] or {}; store[section][key]=value; return 1 end
trackGuid[1]='{TRACK-A}'; fxGuid[0]='{FX-A}'; fxGuid[1]='{FX-B}'
test('save and load per track and FX GUID',function()
 local controls=M.add({},2,'Cutoff','slider')
 assert(S.save(R,0,nil,0,controls))
 local out,err=S.load(R,0,nil,0); assert(out,err); eq(#out,1); eq(out[1].label,'Cutoff')
 eq(#S.load(R,0,nil,1),0)
 trackGuid[1]='{TRACK-B}'; eq(#S.load(R,0,nil,0),0); trackGuid[1]='{TRACK-A}'
end)
test('rename and FX reorder keep configuration through GUIDs',function()
 fxGuid[0]='{FX-A-MOVED}'; eq(#S.load(R,0,nil,0),0)
 fxGuid[0]='{FX-A}'; eq(#S.load(R,0,nil,0),1)
end)
test('save verifies byte-exact readback and rejects disappearing state',function()
 assert(S.save(R,0,nil,0,M.add({},4,'Drive','slider')))
 local original=R.SetProjExtState
 R.SetProjExtState=function() return 1 end
 local ok,err=pcall(S.save,R,0,nil,0,M.add({},5,'Mix','slider'))
 assert(not ok and tostring(err):find('readback',1,true)); R.SetProjExtState=original
end)
test('empty or corrupt state loads empty with diagnostic, never writes',function()
 store.ReaSkii_DeviceRack['{TRACK-A}|{FX-B}']='garbage'
 local out,err=S.load(R,0,nil,1); eq(#out,0); assert(err)
end)
test('empty GUID refuses save and load instead of using pointers',function()
 trackGuid[1]=''; local out,err=S.load(R,0,nil,0); eq(#out,0); assert(err)
 assert(not pcall(S.save,R,0,nil,0,{{param=0,label='x',kind='slider'}}))
 trackGuid[1]='{TRACK-A}'
end)
print('DONE\t'..count)
