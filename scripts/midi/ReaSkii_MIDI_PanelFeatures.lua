-- Inline feature definitions, intentionally restricted independent variants.
local F={}
F.spec={transpose={-127,127,0,1},grid={1,9,1,1},parts={2,64,2,1},gate={1,100,50,1},octaves={1,4,1,1},style={1,3,1,1},strength={0,100,100,1},
 spread={0,24,0,1},density={0,100,50,1},tie={0,100,0,1},seed={1,2147483646,1,1},position={-100,100,20,1},ornament_kind={1,2,1,1},graces={1,8,2,1},grace_pitch={-1,1,0,1},relative_velocity={1,100,80,1},
 dimension={1,4,2,1},shuffle={0,1,0,1},mirror={0,1,0,1},rotate={-127,127,0,1},articulation={1,3,1,1},offset={-100,100,0,1},variation={-100,100,0,1},
 first={0,100,0,1},middle={0,100,100,1},last={0,100,0,1},minimum={1,127,1,1},maximum={1,127,127,1},loops={1,16,1,1},
 steps={1,64,8,1},hits={0,64,4,1},rotation={-64,64,0,1},pitch={0,127,60,1},pitch_max={0,127,72,1},vel={1,127,100,1},vel_min={1,127,80,1},vel_max={1,127,110,1},note_length={.01,1,.5,.01},shape_kind={1,3,1,1},chord={1,4,1,1},chords={1,8,1,1}}
F.spec.quantize_grid={0,4,0,1}
F.spec.quantize_triplets={0,1,0,1}
F.spec.quantize_start={0,1,1,1}
F.spec.quantize_end={0,1,0,1}
F.grids={{'Native',0},{'1/4',1},{'1/8',.5},{'1/16',.25},{'1/32',.125},{'1/4 T',2/3},{'1/8 T',1/3},{'1/16 T',1/6},{'1/32 T',1/12}}
F.transforms={{'Arpeggiate','arpeggiate'},{'Chop','chop'},{'Connect','connect'},{'Glissando MPE',false},{'LFO MPE',false},{'Ornament','ornament'},{'Quantize','quantize'},{'Recombine','recombine'},{'Span','span'},{'Strum','strum'},{'Time Warp',false},{'Velocity Shaper','velocity_shaper'}}
F.generators={{'Rhythm','rhythm'},{'Euclidean','euclidean'},{'Seed','seed'},{'Shape','shape'},{'Stacks','stacks'}}
F.fields={arpeggiate={'grid','style','gate','octaves'},chop={'parts'},quantize={'quantize_grid','quantize_triplets','quantize_start','quantize_end','strength'},connect={'grid','spread','density','tie','seed'},ornament={'ornament_kind','position','relative_velocity','graces','grace_pitch'},recombine={'dimension','shuffle','mirror','rotate','seed'},span={'articulation','offset','variation','seed'},velocity_shaper={'minimum','maximum','loops','rotate','first','middle','last'},strum={'low','high','tension'},
 rhythm={'grid','steps','hits','seed','pitch','vel','note_length'},euclidean={'grid','steps','hits','rotation','pitch','vel','note_length'},seed={'grid','density','pitch','pitch_max','vel_min','vel_max','seed'},shape={'shape_kind','steps','pitch','pitch_max','vel','note_length'},stacks={'pitch','chord','chords','vel'}}
F.labels={grid='Grid',style='Style',gate='Gate %',octaves='Octaves',parts='Parts',strength='Amount %',spread='Spread st',density='Density %',tie='Tie %',seed='Seed',ornament_kind='Type',position='Position %',relative_velocity='Velocity %',graces='Grace amount',grace_pitch='Grace pitch st',dimension='Dimension',shuffle='Shuffle 0/1',mirror='Mirror 0/1',rotate='Rotate',articulation='Articulation',offset='Offset %',variation='Variation %',minimum='Minimum vel',maximum='Maximum vel',loops='Loop',first='Start %',middle='Middle %',last='End %',steps='Steps',hits='Hits',rotation='Rotation',pitch='Pitch / root',pitch_max='Maximum pitch',vel='Velocity',vel_min='Minimum vel',vel_max='Maximum vel',note_length='Length / step',shape_kind='Shape',chord='Chord',chords='Chord count'}
F.choices={style={'Up','Down','Up-down'},ornament_kind={'Flam','Grace'},dimension={'Position','Pitch','Duration','Velocity'},articulation={'Legato','Tenuto','Staccato'},shape_kind={'Line','Sine','Triangle'},chord={'Major','Minor','Sus2','Seventh'}}
function F.options(tool,v,ctx,c)
 local grid=F.grids[v.grid][2]; grid=grid==0 and ctx.grid_ppq or grid*ctx.ppq
 local p={grid_ppq=grid,seed=v.seed}
 if tool=='transpose' then return {amount=v.transpose}
 elseif tool=='add_interval' then p.amount=v.interval
 elseif tool=='set_length' then p.length=grid
 elseif tool=='humanize' then p.amount=v.humanize
 elseif tool=='chop' then p.parts=v.parts
 elseif tool=='quantize' then
  local division=({1,.5,.25,.125})[v.quantize_grid]
  p.grid_ppq=division and division*assert(ctx.ppq,'Missing native PPQ') or ctx.grid_ppq
  if division and v.quantize_triplets==1 then p.grid_ppq=p.grid_ppq*2/3 end
  p.strength=v.strength/100
  p.adjust_start=v.quantize_start==1; p.adjust_end=v.quantize_end==1
 elseif tool=='arpeggiate' then p.mode=({'up','down','updown'})[v.style]; p.rate_ppq=grid; p.gate=v.gate/100; p.octaves=v.octaves; p.range_start=assert(ctx.range_start,'Select notes'); p.range_end=assert(ctx.range_end)
 elseif tool=='connect' then p.rate_ppq=grid; p.spread=v.spread; p.density=v.density; p.tie=v.tie
 elseif tool=='ornament' then p.kind=v.ornament_kind==1 and 'flam' or 'grace'; p.position=v.position; p.velocity=v.relative_velocity; p.count=v.graces; p.pitch_delta=v.grace_pitch
 elseif tool=='recombine' then p.dimension=({'position','pitch','duration','velocity'})[v.dimension]; p.shuffle=v.shuffle==1; p.mirror=v.mirror==1; p.rotate=v.rotate
 elseif tool=='span' then p.articulation=({'legato','tenuto','staccato'})[v.articulation]; p.offset=v.offset; p.variation=v.variation; p.range_end=ctx.generate_end or ctx.range_end
 elseif tool=='velocity_shaper' then
  for _,key in ipairs({'first','middle','last','minimum','maximum','loops','rotate'}) do p[key]=v[key] end
  assert(p.maximum>=p.minimum,'Maximum velocity must be >= minimum')
  p.range_start=assert(ctx.range_start,'Select notes'); p.range_end=assert(ctx.range_end)
 else
  p.range_start=assert(ctx.generate_start,'Missing native range'); p.range_end=assert(ctx.generate_end)
  p.mode=c.replace and 'replace' or 'add'; p.channel=0; p.release_velocity=0; p.max_notes=4096
  p.pitch=v.pitch; p.pitches={v.pitch}; p.vel=v.vel; p.steps=v.steps; p.step_ppq=grid; p.note_length=grid*v.note_length
  if tool=='rhythm' then p.density=math.min(v.hits,v.steps)
  elseif tool=='euclidean' then p.pulses=math.min(v.hits,v.steps); p.rotation=v.rotation
  elseif tool=='seed' then p.density=v.density/100; p.pitch_min=v.pitch; p.pitch_max=v.pitch_max; p.vel_min=v.vel_min; p.vel_max=v.vel_max; p.root=c.root; p.scale=c.scale_enabled and c.scale_intervals or nil
  elseif tool=='shape' then p.shape=({'line','sine','triangle'})[v.shape_kind]; p.pitch_min=v.pitch; p.pitch_max=v.pitch_max
  elseif tool=='stacks' then
   p.chords={}; local intervals=({{0,4,7},{0,3,7},{0,2,7},{0,4,7,10}})[v.chord]
   for i=1,v.chords do p.chords[i]={root=v.pitch,intervals=intervals,duration_ppq=(p.range_end-p.range_start)/v.chords} end
  else return nil end
 end
 return p
end
return F
