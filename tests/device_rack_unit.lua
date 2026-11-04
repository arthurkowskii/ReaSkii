-- Pure device-rack model tests. No REAPER, no gfx.
local M=dofile('scripts/device/ReaSkii_DeviceRackModel.lua')
local count=0
local function test(name,fn) fn(); count=count+1; print('PASS\t'..name) end
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function controls() return {
 {param=0,label='Cutoff',kind='slider'},
 {param=3,label='Mode',kind='toggle'},
 {param=7,label='Drive',kind='slider'},
} end
test('round-trip preserves order, labels and kinds',function()
 local text=M.encode(controls()); local out,err=M.decode(text); assert(out,err)
 eq(#out,3); eq(out[1].param,0); eq(out[1].label,'Cutoff'); eq(out[2].kind,'toggle'); eq(out[3].param,7)
end)
test('labels escape tabs, newlines, backslashes and unicode',function()
 local list={{param=1,label='A\tB\nC\\D é',kind='slider'}}
 local out,err=M.decode(M.encode(list)); assert(out,err)
 eq(out[1].label,'A\tB\nC\\D é')
end)
test('decode refuses bad version, malformed bounds and duplicate params',function()
 assert(not M.decode('v2\n0\tA\tslider\n'))
 local out,err=M.decode('v1\n0\tA\tslider\n0\tB\ttoggle\nx\tC\tslider\n999999\tD\tslider\n')
 assert(out); eq(#out,1); eq(out[1].label,'A'); assert(err and err:find('ignored',1,true))
end)
test('add refuses duplicate, remove and move keep a new ordered list',function()
 local list=controls(); local added=M.add(list,9,'Mix','slider'); eq(#added,4); eq(list[4],nil)
 eq(#M.add(list,0,'Dup','slider'),3)
 local removed=M.remove(added,3); eq(#removed,3); eq(removed[3].param,9)
 local moved=M.move(added,9,-1); eq(moved[3].param,9); eq(moved[2].param,3); eq(moved[4].param,7)
 eq(M.move(added,9,5)[4].param,9)
end)
test('unknown kinds normalise to slider; invalid labels sanitise',function()
 local list=M.add({},2,'  Tab\there \n','weird'); eq(list[1].kind,'slider'); eq(list[1].label,'Tab here')
 eq(#M.add({},-1,'X','slider'),0)
end)
test('slider x mapping clamps and supports inverted range',function()
 eq(M.x_to_norm(0,10,100),0); eq(M.x_to_norm(60,10,100),.5); eq(M.x_to_norm(500,10,100),1)
 eq(M.x_to_norm(600,10,100,true),0)
end)
test('empty and whitespace configuration decode empty without error',function()
 local out,err=M.decode(''); assert(out); eq(#out,0); assert(not err)
 out=M.decode('v1\n\n'); assert(out); eq(#out,0)
end)
print('DONE\t'..count)
