#!/usr/bin/env python3
"""Native expansion integration + real X11 buttons/numerics. No Live parity."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from PIL import ImageGrab
from run_midi_fidelity_gui import Input, wait
from x11_gui import windows
ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(); p.add_argument('--reaper',required=True,type=Path); args=p.parse_args()
    exe=args.reaper.resolve(); assert 'reaskii-native' in str(exe) and os.environ.get('DISPLAY')
    work=Path(os.environ['TMPDIR'])/('reaskii-native-midi-expansion-quantize-'+str(time.time_ns())); work.mkdir(exist_ok=True)
    state=work/'state.json'; state.unlink(missing_ok=True); (work/'state.json.cmd').unlink(missing_ok=True)
    ini=work/'reaper.ini'; ini.write_text('[REAPER]\nfirst_run=0\nloadlastproj=0\nvstpath=\nvstpath64=\nwnd_w=1300\nwnd_h=900\n')
    wrapper=work/'run.lua'; wrapper.write_text('REASKII_ROOT='+json.dumps(str(ROOT))+'\nREASKII_STATE='+json.dumps(str(state))+'\ndofile('+json.dumps(str(ROOT/'tests/midi_expansion_gui.lua'))+')\n')
    checks=[]; d=Input()
    def snapshot():
        try: return json.loads(state.read_text())
        except (OSError,ValueError): return {}
    def cmd(code):
        old=snapshot().get('token',''); (work/'state.json.cmd').write_text(code)
        s=wait(lambda:(x if (x:=snapshot()).get('token','')!=old else None),'host command timeout')
        assert not s['error'],s['error']; time.sleep(.15); return snapshot()
    def check(condition,label):
        assert condition,label+'; actual='+str(snapshot()); checks.append('PASS\t'+label)
    def click(label):
        xy=wait(lambda:snapshot().get('controls',{}).get(label),'control missing '+label)
        assert 0<=xy[1]<850,(label,xy)
        d.click(panel,int(xy[0]),int(xy[1])); time.sleep(.3)
    def capture(name): ImageGrab.grab().save(ROOT/('qa/midi-expansion-quantize-'+name+'.png'))
    with (work/'run.log').open('w') as log:
        proc=subprocess.Popen([str(exe),'-newinst','-nosplash','-cfgfile',str(ini),str(wrapper)],stdout=log,stderr=log)
        try:
            panel=wait(lambda:next((h for h,n in windows() if n=='ReaSkii MIDI Panel'),None),'Panel missing')
            error=next((h for h,n in windows() if n=='Error opening devices'),None)
            if error:d.key(error,'Return')
            d.resize(panel,260,850); wait(lambda:snapshot().get('token') is not None,'observer missing')
            baseline=snapshot()['notes']; check(len(baseline)==3,'real native fixture selected notes')
            for tool in ['arpeggiate','chop','connect','ornament','quantize','recombine','span','strum','velocity_shaper']:
                cmd('configure('+json.dumps(tool)+')')
                if tool=='quantize': cmd('c.values.quantize_grid=1')
                if tool=='strum': cmd('reaper.MIDI_SetNote(take,1,nil,nil,960,nil,nil,nil,nil,false); reaper.MIDI_SetNote(take,2,nil,nil,960,nil,nil,nil,nil,false); reaper.Undo_OnStateChange2(0,"Chord fixture")')
                before=snapshot()['notes']
                click('b:Transform')
                s=snapshot(); check(not s['session'] and 'Committed' in s['status'],tool+' native Transform committed')
                if tool!='quantize':check(s['notes']!=before,tool+' real MIDI changed')
                if tool in ['connect','velocity_shaper']:capture(tool)
                cmd('reaper.Undo_DoUndo2(0)')
                check(snapshot()['notes']==before,tool+' native Undo restores pre-transform fixture')
            # Actual chooser: Home + Return selects Arpeggiate, not another toolbox.
            cmd('configure("strum")'); click('b:Strum v')
            # Native popup owns focus; focusing the parent cancels gfx.showmenu.
            for name in ('Home','Return'):
                code=d.x.XKeysymToKeycode(d.display,d.x.XStringToKeysym(name.encode()))
                for down in (1,0):
                    d.xt.XTestFakeKeyEvent(d.display,code,down,0); d.flush()
            time.sleep(.4)
            check(snapshot()['tool']=='arpeggiate','real X11 transformation chooser selects inline panel')
            cmd('configure("chop"); c.auto=true')
            click('n:parts'); d.key(panel,'3'); d.key(panel,'Return')
            wait(lambda:len(snapshot().get('notes',[]))==9,'inline Chop numeric edit failed')
            check(snapshot()['session'],'inline numeric Auto creates native preview')
            click('b:Auto ON'); check(snapshot()['notes']==baseline,'Auto off cancels native preview')
            cmd('configure("velocity_shaper"); c.auto=true')
            # Draggable middle envelope point: inspect graph via source geometry (numeric keys are above it).
            xy=snapshot()['controls']['n:last']; graph_top=xy[1]+13
            d.drag(panel,126,graph_top,126,graph_top+25)
            check(snapshot()['session'],'real velocity envelope endpoint drag previews')
            click('b:Cancel'); check(snapshot()['notes']==baseline,'Cancel restores envelope preview')
            # Pitch actions, including explicit Stretch with Auto off.
            cmd('reset(false); u.sections.Transform=false; u.sections["Pitch & Time"]=true; c.values.stretch=2')
            click('b:Apply Stretch'); check(snapshot()['notes']!=baseline and not snapshot()['session'],'Auto-off Apply Stretch works')
            cmd('reaper.Undo_DoUndo2(0)'); check(snapshot()['notes']==baseline,'Apply Stretch native Undo')
            for key,value,label in [('interval',7,'Add Interval'),('grid',3,'Set Length'),('humanize',30,'Humanize'),('transpose',2,'Transpose')]:
                cmd('reset(false); u.sections.Transform=false; u.sections["Pitch & Time"]=true; c.values.'+key+'='+str(value))
                click('b:'+label); check(snapshot()['notes']!=baseline and not snapshot()['session'],label+' native inline action')
            capture('pitch')
            # Each generator starts from a genuinely empty MIDI item, no silent clearing.
            for tool in ['rhythm','euclidean','seed','shape','stacks']:
                cmd('configure('+json.dumps(tool)+',true,true)')
                check(len(snapshot()['notes'])==0,tool+' empty native clip baseline')
                click('b:Generate'); s=snapshot()
                check(len(s['notes'])>0 and not s['session'] and 'Committed' in s['status'],tool+' native Generate empty clip')
                capture(tool)
                cmd('reaper.Undo_DoUndo2(0)'); check(len(snapshot()['notes'])==0,tool+' native Undo empty clip')
            cmd('configure("rhythm",true,true); c.auto=true; c:set("hits",3,"rhythm")')
            check(snapshot()['session'] and len(snapshot()['notes'])>0,'generator Auto preview empty clip')
            click('b:Auto ON'); check(len(snapshot()['notes'])==0,'generator Auto off restores empty clip')
            # Explicit replace is armed and tested against real occupied data.
            cmd('configure("rhythm",true,false); c:mode()'); click('b:Generate')
            check('Committed' in snapshot()['status'] and len(snapshot()['notes'])>3,'explicit replace generates inside range')
            # Offset/playrate source range is read using actual host conversion APIs.
            cmd('reset(false); reaper.SetMediaItemTakeInfo_Value(take,"D_STARTOFFS",.5); reaper.SetMediaItemTakeInfo_Value(take,"D_PLAYRATE",1.5); local H=dofile(REASKII_ROOT.."/scripts/midi/ReaSkii_MIDI_PanelContext.lua"); local x=H.context(reaper,take,0); assert(math.abs(x.generate_start-reaper.MIDI_GetPPQPosFromProjTime(take,0))<.001); assert(math.abs(x.generate_end-reaper.MIDI_GetPPQPosFromProjTime(take,8))<.001); reaper.SetMediaItemTakeInfo_Value(take,"D_STARTOFFS",0); reaper.SetMediaItemTakeInfo_Value(take,"D_PLAYRATE",1)')
            checks.append('PASS\tnative offset/playrate source PPQ conversion')
            # Quantize reference-layout controls: actual X11 clicks, no test-only algorithm.
            cmd('configure("quantize"); reaper.MIDI_SetNote(take,0,true,false,110,410,nil,nil,nil,false); reaper.Undo_OnStateChange2(0,"Quantize edge fixture")')
            original=snapshot()['notes']
            click('b:1/32'); click('b:Start'); click('b:End')
            check(snapshot()['notes']==original,'Quantize Auto OFF toggles do not write')
            click('b:Transform')
            check(snapshot()['notes'][0][:2]==[110,360],'Quantize End-only keeps start and snaps end in native MIDI')
            cmd('reaper.Undo_DoUndo2(0)')
            check(snapshot()['notes']==original,'Quantize End-only native Undo restores exact notes')
            cmd('c.auto=true')
            click('n:strength'); d.key(panel,'5'); d.key(panel,'0'); d.key(panel,'Return')
            check(snapshot()['notes'][0][:2]==[110,385],'Quantize Amount 50% inline updates native end from original')
            click('b:Auto ON')
            check(snapshot()['notes']==original,'Quantize Auto OFF cancels end preview')
            cmd('c.values.strength=100')
            click('b:1/8'); click('b:Triplets'); click('b:Transform')
            check(snapshot()['notes'][0][:2]==[110,320],'Quantize musical triplet meter maps to native PPQ')
            capture('end-triplets')
            cmd('reaper.Undo_DoUndo2(0); c.auto=true')
            click('b:Start')
            check(snapshot()['notes'][0][:2]==[0,320],'Quantize Start+End toggles both from snapshot')
            click('b:Cancel')
            check(snapshot()['notes']==original,'Quantize both-edge Cancel restores baseline')
            capture('panel')
            cmd('configure("strum"); c.auto=true; c:set("high",30); reaper.MIDI_SetNote(take,0,nil,nil,nil,nil,nil,nil,77,false)')
            wait(lambda:snapshot().get('blocked'),'external edit not detected')
            external=snapshot()['notes']; d.key(panel,'Escape'); time.sleep(.4)
            check(snapshot()['notes']==external and snapshot()['session'] and 'refused' in snapshot()['status'].lower(),'external edit Escape refuses restore, retains session')
            capture('external')
            # Native close must not overwrite the external edit.
            d.wmclose(panel); wait(lambda:not any(n=='ReaSkii MIDI Panel' for _,n in windows()),'close failed')
            check(snapshot()['notes']==external,'native close preserves external edit')
            check(bool(list(work.glob('ReaSkiiMIDI-recovery/*.midirec'))),'external conflict recovery retained')
            check(any('ReaSkii expansion fixture' in n for _,n in windows()),'native piano roll remains open')
        finally:
            capture('last'); proc.terminate()
            try:proc.wait(timeout=5)
            except subprocess.TimeoutExpired:proc.kill(); proc.wait()
            d.close()
            (ROOT/'qa/midi-expansion-quantize-host-partial.tsv').write_text('\n'.join(checks)+'\n')
    files=[*(ROOT/'scripts/midi').glob('ReaSkii_MIDI_Panel*.lua'),*[ROOT/'scripts/midi'/('ReaSkii_MIDI_'+n+'.lua') for n in ['Core','Adapter','Transformations','Generators']],ROOT/'tests/midi_expansion_gui.lua',Path(__file__),ROOT/'tests/run_midi_fidelity_gui.py',ROOT/'tests/x11_gui.py',*(ROOT/'qa').glob('midi-expansion-quantize-*.png')]
    report='REFERENCE_PARITY\tNOT_MEASURED\n'+''.join('SHA256\t'+str(f.relative_to(ROOT))+'\t'+hashlib.sha256(f.read_bytes()).hexdigest()+'\n' for f in files)+'\n'.join(checks)+'\nDONE\t'+str(len(checks))+'\n'
    (ROOT/'qa/midi-expansion-quantize-host.tsv').write_text(report); print(report)
if __name__=='__main__':main()
