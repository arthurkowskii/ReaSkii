#!/usr/bin/env python3
"""Read-only ergonomics audit; actual X11 input on isolated fixture only.
An OBSERVED defect is not an acceptance PASS. Does not alter production code.
"""
import argparse
import ctypes as C
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
    parser=argparse.ArgumentParser(); parser.add_argument('--reaper',required=True,type=Path); args=parser.parse_args()
    exe=args.reaper.resolve(); assert exe.is_file() and 'reaskii-native' in str(exe) and os.environ.get('DISPLAY')
    work=Path(os.environ['TMPDIR'])/('reaskii-native-polish-'+str(time.time_ns())); work.mkdir()
    state=work/'state.json'
    ini=work/'reaper.ini'; ini.write_text('[REAPER]\nfirst_run=0\nloadlastproj=0\nvstpath=\nvstpath64=\nwnd_w=1300\nwnd_h=900\n')
    wrapper=work/'run.lua'; wrapper.write_text('REASKII_ROOT='+json.dumps(str(ROOT))+'\nREASKII_STATE='+json.dumps(str(state))+'\ndofile('+json.dumps(str(ROOT/'tests/midi_expansion_gui.lua'))+')\n')
    d=Input(); observations=[]; frames=[]
    def snapshot():
        try:return json.loads(state.read_text())
        except (OSError,ValueError):return {}
    def cmd(code):
        old=snapshot().get('token',''); (work/'state.json.cmd').write_text(code)
        s=wait(lambda:(s if (s:=snapshot()).get('token','')!=old else None),'fixture command timeout')
        assert not s['error'],s['error']; time.sleep(.2); return snapshot()
    def record(name):observations.append('VERIFIED\t'+name)
    def frame():
        # Isolated Xvfb only: raise and place fixture, capture its exact panel rectangle.
        d.x.XMoveResizeWindow.argtypes=[C.c_void_p,C.c_ulong,C.c_int,C.c_int,C.c_uint,C.c_uint]
        d.x.XMoveResizeWindow(d.display,panel,0,0,260,850); d.x.XRaiseWindow(d.display,panel); d.flush(); time.sleep(.25)
        frames.append(ImageGrab.grab().crop((0,0,260,460)))
    with (work/'run.log').open('w') as log:
        proc=subprocess.Popen([str(exe),'-newinst','-nosplash','-cfgfile',str(ini),str(wrapper)],stdout=log,stderr=log)
        try:
            panel=wait(lambda:next((h for h,n in windows() if n=='ReaSkii MIDI Panel'),None),'panel missing')
            error=next((h for h,n in windows() if n=='Error opening devices'),None)
            if error:d.key(error,'Return')
            d.resize(panel,260,850); wait(lambda:snapshot().get('token') is not None,'observer missing')
            cmd('configure("rhythm",true,true); c.values.hits=2; c.auto=true; c:preview("rhythm")')
            before=len(snapshot()['notes']); frame()
            x,y=snapshot()['controls']['n:hits']
            d.drag(panel,x,y,x,y-4)
            ImageGrab.grab().save(ROOT/'qa/midi-expansion-polish-drag-probe.png')
            cmd('assert(c.values.hits==6,"normal drag actual hits="..tostring(c.values.hits))')
            assert len(snapshot()['notes'])>before
            record('Generate numeric vertical drag changes Hits 2 to 6 and real MIDI'); frame()
            d.drag(panel,x,y,x,y-20,True)
            cmd('assert(c.values.hits==8,"fine drag did not set hits=8")')
            record('Shift drag gives finer integer adjustment: 20 pixels, Hits 6 to 8'); frame()
            cmd('c:set("hits",4,"rhythm")'); unchanged=snapshot()['notes']
            d.move(panel,x,y); d.key(panel,'Shift_L',True)
            for _ in range(10):d.button(4,True); d.button(4,False)
            d.key(panel,'Shift_L',False)
            cmd('assert(c.values.hits==5,"fine-wheel did not accumulate; hits="..tostring(c.values.hits))')
            record('Ten Shift-wheel ticks accumulate to one integer step (Hits 4 to 5)')
            d.move(panel,x,y); d.button(4,True); d.button(4,False)
            cmd('assert(c.values.hits==6,"normal wheel did not increment")')
            record('Normal wheel increments integer value and previews real MIDI')
            d.click(panel,int(x),int(y)); d.key(panel,'3'); d.key(panel,'Return')
            cmd('assert(c.values.hits==3,"typed edit did not commit")')
            record('Single click then keyboard/Enter edits the same numeric control inline')
            xy=snapshot()['controls']['b:Cancel']; d.click(panel,int(xy[0]),int(xy[1]))
            assert len(snapshot()['notes'])==0
            record('Cancel restores original empty clip after drag/wheel/type previews')
            frames[0].save(ROOT/'qa/midi-expansion-polish-drag.gif',save_all=True,append_images=frames[1:],duration=[1400,1400,1400],loop=0)
            ImageGrab.grab().save(ROOT/'qa/midi-expansion-polish-last.png')
        finally:
            proc.terminate()
            try:proc.wait(timeout=5)
            except subprocess.TimeoutExpired:proc.kill(); proc.wait()
            d.close()
    files=[*(ROOT/'scripts/midi').glob('ReaSkii_MIDI_Panel*.lua'),*[ROOT/'scripts/midi'/('ReaSkii_MIDI_'+n+'.lua') for n in ['Core','Adapter','Transformations','Generators']],ROOT/'tests/midi_expansion_gui.lua',Path(__file__),ROOT/'tests/run_midi_fidelity_gui.py',ROOT/'tests/x11_gui.py',ROOT/'qa/midi-expansion-polish-drag.gif',ROOT/'qa/midi-expansion-polish-last.png']
    manifest=''.join('SHA256\t'+str(p.relative_to(ROOT))+'\t'+hashlib.sha256(p.read_bytes()).hexdigest()+'\n' for p in files)
    report='SCOPE\tNative ergonomics audit, not Live parity\n'+manifest+'\n'.join(observations)+'\n'
    (ROOT/'qa/midi-expansion-polish-probe.tsv').write_text(report); print(report)
if __name__=='__main__':main()
