#!/usr/bin/env python3
"""Real X11 clicks on the MIDI panel beside REAPER's native MIDI editor."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from PIL import ImageGrab
from x11_gui import Display, windows

ROOT = Path(__file__).resolve().parents[1]

def wait_for(predicate, message):
    deadline = time.monotonic()+18
    while time.monotonic()<deadline:
        value=predicate()
        if value:
            return value
        time.sleep(.15)
    raise TimeoutError(message)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--reaper',type=Path,required=True)
    args=parser.parse_args()
    executable=args.reaper.resolve()
    if 'reaskii-native' not in str(executable) or not os.environ.get('DISPLAY'):
        raise ValueError('Isolated REAPER/Xvfb required')
    work=Path(os.environ['TMPDIR'])/'reaskii-native-midi-gui'
    work.mkdir(exist_ok=True)
    state=work/'pitch.txt'
    state.unlink(missing_ok=True)
    # A previous interrupted run must not seed this scenario with its own recovery offer.
    recovery=(work/'ReaSkiiMIDI-recovery')
    for stale in recovery.glob('*.bin'):
        stale.unlink()
    ini=work/'reaper.ini'
    ini.write_text('[REAPER]\nfirst_run=0\nloadlastproj=0\nvstpath=\nvstpath64=\nwnd_w=1400\nwnd_h=850\n')
    wrapper=work/'run.lua'
    wrapper.write_text('REASKII_ROOT='+json.dumps(str(ROOT))+'\nREASKII_STATE='+json.dumps(str(state))+'\ndofile('+json.dumps(str(ROOT/'tests/midi_panel_gui.lua'))+')\n')
    checks=[]
    display=Display()
    with (work/'run.log').open('w') as log:
        proc=subprocess.Popen([str(executable),'-newinst','-nosplash','-cfgfile',str(ini),str(wrapper)],stdout=log,stderr=log)
        try:
            handle=wait_for(lambda:next((h for h,n in windows() if n=='ReaSkii MIDI Tools'),None),'Panel did not open: '+str(windows()))
            print('Windows:',windows())
            native=wait_for(lambda:next((h for h,n in windows() if 'ReaSkii MIDI test chord' in n),None),'Native MIDI editor missing')
            display.x.XMoveResizeWindow.argtypes=[ctypes.c_void_p,ctypes.c_ulong,ctypes.c_int,ctypes.c_int,ctypes.c_uint,ctypes.c_uint]
            display.x.XMoveResizeWindow(display.display,native,350,70,1000,700)
            display.x.XFlush(display.display)
            def expect(pitch,label):
                wait_for(lambda:state.exists() and state.read_text()==str(pitch),label)
                checks.append('PASS\t'+label)
            expect(60,'native fixture starts at C4')
            display.click(handle,180,142)
            expect(61,'real click +1 previews C#4 in native MIDI take')
            display.focus(native)
            time.sleep(.3)
            display.focus(handle)
            time.sleep(.3)
            image=ROOT/'qa/midi-panel-native.png'
            ImageGrab.grab().save(image)
            display.click(handle,180,142)
            expect(62,'second +1 previews D4 from original snapshot')
            display.click(handle,220,435)
            expect(60,'Cancel button restores C4')
            display.click(handle,180,142)
            expect(61,'new preview starts from restored original')
            display.click(handle,65,435)
            expect(61,'Apply keeps C#4')
            display.click(handle,180,142)
            expect(62,'preview after Apply uses new committed baseline')
            display.escape(handle)
            time.sleep(.5)
            assert any(h==handle for h,_ in windows()), 'ESC must not discard a pending preview'
            checks.append('PASS\tESC is neutralised while a preview is pending')
            display.click(handle,220,435)
            expect(61,'Cancel button restores C#4 after ESC guard')
            display.escape(handle)
            wait_for(lambda:not any(n=='ReaSkii MIDI Tools' for _,n in windows()),'Panel did not close')
            assert any(h==native for h,_ in windows()), 'Native MIDI editor disappeared'
            checks.append('PASS\tpanel closes without replacing native MIDI editor')
            leftover=list(recovery.glob('*.bin'))
            assert not leftover, f'Recovery files left after a clean cancel: {leftover}'
            checks.append('PASS\tclean cancel removes its recovery file')
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill(); proc.wait()
            display.close()
    text='\n'.join(checks)+'\nDONE\t'+str(len(checks))+'\n'
    files=['scripts/midi/ReaSkii_MIDI_Core.lua','scripts/midi/ReaSkii_MIDI_Tools.lua','tests/midi_panel_gui.lua','tests/run_midi_panel_gui.py']
    meta=''.join('META\t'+name+'\t'+hashlib.sha256((ROOT/name).read_bytes()).hexdigest()+'\n' for name in files)
    (ROOT/'qa/midi-panel-gui.tsv').write_text(meta+text)
    print(text)
    print('Screenshot:',image)

if __name__=='__main__':
    main()
