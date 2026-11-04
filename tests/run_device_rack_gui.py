#!/usr/bin/env python3
"""Real X11 Device Rack GUI test on isolated REAPER. No Live parity claim."""
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
    work=Path(os.environ['TMPDIR'])/('reaskii-native-device-rack-gui-'+str(time.time_ns())); work.mkdir()
    state=work/'state.json'
    ini=work/'reaper.ini'; ini.write_text('[REAPER]\nfirst_run=0\nloadlastproj=0\nvstpath=\nvstpath64=\nwnd_w=1400\nwnd_h=900\n')
    wrapper=work/'run.lua'; wrapper.write_text('REASKII_ROOT='+json.dumps(str(ROOT))+'\nREASKII_STATE='+json.dumps(str(state))+'\ndofile('+json.dumps(str(ROOT/'tests/device_rack_gui.lua'))+')\n')
    checks=[]; d=Input()
    def snap():
        try:return json.loads(state.read_text())
        except (OSError,ValueError):return {}
    def cmd(code):
        old=snap().get('token',''); (work/'state.json.cmd').write_text(code)
        s=wait(lambda:(x if (x:=snap()).get('token','')!=old else None),'fixture command timeout')
        time.sleep(.15); return s
    def check(ok,label):
        assert ok,label+'; actual='+json.dumps(snap())[:2000]; checks.append('PASS\t'+label)
    def click(label):
        xy=wait(lambda:snap().get('ui',{}).get(label),'control missing '+label)
        d.click(panel,int(xy['x']),int(xy['y'])); time.sleep(.3)
    def capture(name): ImageGrab.grab().save(ROOT/('qa/device-rack-'+name+'.png'))
    with (work/'run.log').open('w') as log:
        proc=subprocess.Popen([str(exe),'-newinst','-nosplash','-cfgfile',str(ini),str(wrapper)],stdout=log,stderr=log)
        try:
            time.sleep(4)
            print('WINDOWS:',windows())
            panel=wait(lambda:next((h for h,n in windows() if n=='ReaSkii Device Rack'),None),'Device Rack window missing')
            error=next((h for h,n in windows() if n=='Error opening devices'),None)
            if error:d.key(error,'Return')
            about=next((h for h,n in windows() if n.startswith('About REAPER')),None)
            if about:d.key(about,'Return')
            s=wait(lambda:snap() if snap().get('devices') else None,'observer missing')
            check(s['track_name']=='Device rack fixture','real selected track exposed')
            check(len(s['devices'])==2 and s['devices'][0]['name'].find('ReaSkii MIDI LFO')>=0,'real FX chain listed')
            check(s['width']>=1000 and s['height']>=300,'panel has usable real window geometry')
            capture('initial')
            click('b:Configure'); check(snap()['configure'],'Configure mode opens by real click')
            capture('configure')
            # Parameter browser: first row in right panel.
            width=snap()['width']; leftw=int((width-30)*.48); rightx=12+leftw+10
            d.click(panel,rightx+24,145); time.sleep(.4)
            s=snap(); check(any(c['param']==0 for c in s['controls']),'real parameter row adds a preview control')
            capture('configured')
            click('b:Done'); check(not snap()['configure'],'Done returns to previews')
            s=snap(); x=wait(lambda:s.get('ui',{}).get('s:0'),'slider missing')
            d.drag(panel,int(x['x']+x['w']*.2),int(x['y']),int(x['x']+x['w']*.8),int(x['y']))
            s=snap(); norm=next(p['norm'] for p in s['params'] if p['param']==0)
            check(abs(norm-.8)<.06,'real slider drag writes FX parameter')
            capture('preview')
            x=wait(lambda:snap().get('ui',{}).get('s:0'),'slider missing')
            d.move(panel,int(x['x']+x['w']*.5),int(x['y'])); d.button(4,True); d.button(4,False)
            norm2=next(p['norm'] for p in snap()['params'] if p['param']==0)
            check(norm2!=norm,'wheel changes FX parameter')
            d.move(panel,int(x['x']+x['w']*.5),int(x['y'])); d.key(panel,'Shift_L',True); d.button(4,True); d.button(4,False); d.key(panel,'Shift_L',False)
            norm3=next(p['norm'] for p in snap()['params'] if p['param']==0)
            check(abs(norm3-norm2)<.02 and norm3!=norm2,'Shift wheel is finer')
            # Chain selection through a real card click.
            d.click(panel,250,52); time.sleep(.4)
            check(snap()['fx']==1,'chain card selects second device')
            click('b:Add MIDI LFO')
            s=snap(); check(s['fx_count']==3 and s['devices'][2]['name'].find('ReaSkii MIDI LFO')>=0,'Add MIDI LFO inserts and selects real JSFX')
            capture('lfo')
            # Track change: select no track via command and verify panel does not write.
            cmd('reaper.SetOnlyTrackSelected(track); reaper.SetMediaTrackInfo_Value(track,"I_SELECTED",0)')
            time.sleep(.4); check(snap().get('fx') is None,'no selected track handled without FX selection')
        finally:
            capture('last'); proc.terminate()
            try:proc.wait(timeout=5)
            except subprocess.TimeoutExpired:proc.kill(); proc.wait()
            d.close()
            (ROOT/'qa/device-rack-host-partial.tsv').write_text('\n'.join(checks)+'\n')
    files=[*(ROOT/'scripts/device').glob('*.lua'),ROOT/'effects/ReaSkii/ReaSkii MIDI LFO.jsfx',ROOT/'tests/device_rack_gui.lua',Path(__file__),ROOT/'tests/run_midi_fidelity_gui.py',ROOT/'tests/x11_gui.py',*(ROOT/'qa').glob('device-rack-*.png')]
    meta=''.join('SHA256\t'+str(f.relative_to(ROOT))+'\t'+hashlib.sha256(f.read_bytes()).hexdigest()+'\n' for f in files)
    report='REFERENCE_PARITY\tNOT_MEASURED\n'+meta+'\n'.join(checks)+'\nDONE\t'+str(len(checks))+'\n'
    (ROOT/'qa/device-rack-host.tsv').write_text(report); print(report)

if __name__=='__main__':main()
