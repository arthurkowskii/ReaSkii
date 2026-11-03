#!/usr/bin/env python3
"""Real X11 panel interaction, isolated REAPER only. No Live-parity assertions."""
import argparse
import ctypes as C
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from PIL import ImageGrab
from x11_gui import Display, windows
ROOT=Path(__file__).resolve().parents[1]

def wait(fn,label):
    end=time.monotonic()+90
    while time.monotonic()<end:
        value=fn()
        if value: return value
        time.sleep(.1)
    raise AssertionError(label)

class Input(Display):
    def click(self,window,x,y):
        super().click(window,x,y); time.sleep(.3)
    def move(self,w,x,y):
        self.x.XWarpPointer(self.display,0,w,0,0,0,0,int(x),int(y)); self.flush()
    def flush(self):
        self.x.XFlush(self.display); time.sleep(.09)
    def button(self,n,down):
        self.xt.XTestFakeButtonEvent(self.display,n,int(down),0); self.flush()
    def key(self,w,name,down=None):
        self.focus(w)
        code=self.x.XKeysymToKeycode(self.display,self.x.XStringToKeysym(name.encode()))
        for d in ([1,0] if down is None else [int(down)]):
            self.xt.XTestFakeKeyEvent(self.display,code,d,0); self.flush()
    def drag(self,w,x,y,xx,yy,fine=False):
        self.focus(w); self.move(w,x,y)
        if fine: self.key(w,'Shift_L',True)
        self.button(1,True); time.sleep(.3)
        for i in range(1,9): self.move(w,x+(xx-x)*i/8,y+(yy-y)*i/8)
        time.sleep(.3); self.button(1,False)
        if fine: self.key(w,'Shift_L',False)
        time.sleep(.25)
    def resize(self,w,width,height):
        self.x.XMoveResizeWindow.argtypes=[C.c_void_p,C.c_ulong,C.c_int,C.c_int,C.c_uint,C.c_uint]
        self.x.XMoveResizeWindow(self.display,w,25,40,width,height); self.flush(); time.sleep(.3)
    def wmclose(self,w):
        class Data(C.Union): _fields_=[('l',C.c_long*5)]
        class Event(C.Structure):
            _fields_=[('type',C.c_int),('serial',C.c_ulong),('send',C.c_int),('display',C.c_void_p),('window',C.c_ulong),('message_type',C.c_ulong),('format',C.c_int),('data',Data),('pad',C.c_long*10)]
        self.x.XInternAtom.argtypes=[C.c_void_p,C.c_char_p,C.c_int]; self.x.XInternAtom.restype=C.c_ulong
        event=Event(); event.type=33; event.display=self.display; event.window=w; event.format=32
        event.message_type=self.x.XInternAtom(self.display,b'WM_PROTOCOLS',0)
        event.data.l[0]=self.x.XInternAtom(self.display,b'WM_DELETE_WINDOW',0)
        self.x.XSendEvent.argtypes=[C.c_void_p,C.c_ulong,C.c_int,C.c_long,C.c_void_p]
        self.x.XSendEvent(self.display,w,False,0,C.byref(event)); self.flush()

def main():
    p=argparse.ArgumentParser(); p.add_argument('--reaper',required=True,type=Path); args=p.parse_args()
    exe=args.reaper.resolve()
    assert 'reaskii-native' in str(exe) and os.environ.get('DISPLAY'), 'Isolated Xvfb host required'
    work=Path(os.environ['TMPDIR'])/'reaskii-native-midi-fidelity'; work.mkdir(exist_ok=True)
    state=work/'state.json'; state.unlink(missing_ok=True)
    ini=work/'reaper.ini'; ini.write_text('[REAPER]\nfirst_run=0\nloadlastproj=0\nvstpath=\nvstpath64=\nwnd_w=1300\nwnd_h=900\n')
    wrapper=work/'run.lua'; wrapper.write_text('REASKII_ROOT='+json.dumps(str(ROOT))+'\nREASKII_STATE='+json.dumps(str(state))+'\ndofile('+json.dumps(str(ROOT/'tests/midi_fidelity_gui.lua'))+')\n')
    checks=[]; d=Input()
    def snapshot():
        try: return json.loads(state.read_text())
        except (OSError,ValueError): return {}
    def expect(fn,label):
        wait(lambda:fn(snapshot()),label+'; actual='+str(snapshot())); checks.append('PASS\t'+label)
    with (work/'run.log').open('w') as log:
        proc=subprocess.Popen([str(exe),'-newinst','-nosplash','-cfgfile',str(ini),str(wrapper)],stdout=log,stderr=log)
        try:
            panel=wait(lambda:next((h for h,n in windows() if n=='ReaSkii MIDI Panel'),None),'Panel missing')
            error=next((h for h,n in windows() if n=='Error opening devices'),None)
            if error: d.key(error,'Return')
            native=wait(lambda:next((h for h,n in windows() if 'ReaSkii fidelity chord' in n),None),'Native editor missing')
            d.resize(panel,224,850)
            d.x.XMoveResizeWindow(d.display,native,270,40,1020,760); d.flush(); d.focus(native); time.sleep(.5); d.focus(panel)
            expect(lambda s:s.get('60')==[960,1920,100],'selected chord baseline')
            d.drag(panel,59,244,59,224)
            expect(lambda s:s.get('60',[0,0])[1]==2112,'Stretch rotary vertical drag previews factor 1.20 in MIDI')
            d.click(panel,108,738)
            expect(lambda s:s.get('60',[0,0])[1]==1920,'Cancel restores knob preview')
            # Double click knob restores default; next fine drag changes factor by .02.
            d.focus(panel); d.move(panel,59,244)
            for _ in range(2): d.button(1,True); d.button(1,False)
            time.sleep(.4)
            d.drag(panel,59,244,59,224,True)
            expect(lambda s:s.get('60',[0,0])[1]==1939,'Shift fine rotary drag factor 1.02')
            d.click(panel,108,738)
            # Inline number commit and Escape: no GetUserInputs anywhere.
            d.click(panel,45,274); d.key(panel,'2'); d.key(panel,'Return')
            expect(lambda s:s.get('60',[0,0])[1]==2880,'inline Stretch number commits without modal')
            d.click(panel,45,274); d.key(panel,'3'); d.key(panel,'Escape')
            expect(lambda s:s.get('60',[0,0])[1]==2880,'inline Escape cancels text only')
            d.click(panel,108,738)
            d.drag(panel,109,442,160,442)
            expect(lambda s:s.get('67',[0])[0]>960,'Strum upper endpoint drag changes chord timing')
            first=snapshot()
            d.drag(panel,160,442,140,442)
            expect(lambda s:960<s.get('67',[0])[0]<first['67'][0],'Strum re-preview is noncumulative')
            linear=snapshot()['64'][0]
            d.click(panel,105,586); d.key(panel,'5'); d.key(panel,'0'); d.key(panel,'Return')
            expect(lambda s:s.get('64',[0])[0]>linear,'inline Tension changes real middle-note timing nonlinearly')
            ImageGrab.grab().save(ROOT/'qa/midi-fidelity-panel.png')
            d.click(panel,40,619)
            expect(lambda s:s.get('67',[0])[0]==960,'Auto off restores original timing')
            d.drag(panel,140,442,170,442)
            expect(lambda s:s.get('67',[0])[0]==960,'Auto off graph adjusts parameters without MIDI write')
            d.click(panel,150,619)
            expect(lambda s:s.get('67',[0])[0]>960,'Transform commits intended Strum with Auto off')
            committed=snapshot()
            print('Committed snapshot:',committed)
            ImageGrab.grab().save(ROOT/'qa/midi-fidelity-commit.png')
            d.click(panel,20,390)
            expect(lambda s:s==committed,'Reset params preserves committed MIDI')
            d.click(panel,40,619); d.drag(panel,59,244,59,224)
            expect(lambda s:s.get('60',[0,0])[1]>committed['60'][1],'post-commit Stretch preview uses committed baseline')
            d.click(panel,108,738)
            expect(lambda s:s==committed,'Cancel after commit preserves committed baseline')
            # Collapse pitch to show hierarchy and a compact Strum-only panel.
            d.click(panel,100,130)
            ImageGrab.grab().save(ROOT/'qa/midi-fidelity-collapsed.png')
            d.click(panel,100,130)
            # Wheel over label area scrolls small viewport all the way to Generate.
            d.resize(panel,224,400); d.move(panel,5,200)
            for _ in range(12): d.button(5,True); d.button(5,False)
            ImageGrab.grab().save(ROOT/'qa/midi-fidelity-small.png')
            checks.append('PASS\tsection collapse and small-window scroll exercised (screenshots)')
            d.resize(panel,224,850)
            # resize clamps scroll on next frame, then explicitly scroll back to top
            d.move(panel,5,60)
            for _ in range(12): d.button(4,True); d.button(4,False)
            d.drag(panel,59,244,59,224)
            expect(lambda s:s.get('60',[0,0])[1]>committed['60'][1],'preview before native close')
            d.wmclose(panel)
            wait(lambda:not any(n=='ReaSkii MIDI Panel' for _,n in windows()),'Panel native close failed')
            expect(lambda s:s==committed,'native close / atexit restores only pending preview')
            assert any(h==native for h,_ in windows()); checks.append('PASS\tnative piano roll remains open')
            assert not list(work.glob('ReaSkiiMIDI-recovery/*.midirec')); checks.append('PASS\tclean close removed recovery journal')
            (state.parent/(state.name+'.cmd')).write_text('undo')
            expect(lambda s:s.get('67',[0])[0]==960,'native Undo reverses Transform commit')
        finally:
            print('Final windows:', windows())
            ImageGrab.grab().save(ROOT/'qa/midi-fidelity-last.png')
            proc.terminate()
            try: proc.wait(timeout=5)
            except subprocess.TimeoutExpired: proc.kill(); proc.wait()
            d.close()
            (ROOT/'qa/midi-fidelity-host-partial.tsv').write_text('\n'.join(checks)+'\n')
    files=['scripts/midi/ReaSkii_MIDI_Panel.lua','scripts/midi/ReaSkii_MIDI_PanelController.lua','scripts/midi/ReaSkii_MIDI_PanelUI.lua','tests/midi_fidelity_unit.lua','tests/midi_fidelity_gui.lua','tests/run_midi_fidelity_gui.py','qa/midi-fidelity-panel.png','qa/midi-fidelity-collapsed.png','qa/midi-fidelity-small.png']
    meta=''.join('SHA256\t'+f+'\t'+hashlib.sha256((ROOT/f).read_bytes()).hexdigest()+'\n' for f in files)
    report=meta+'REFERENCE_PARITY\tNOT_MEASURED\n'+'\n'.join(checks)+'\nDONE\t'+str(len(checks))+'\n'
    (ROOT/'qa/midi-fidelity-host.tsv').write_text(report); print(report)
if __name__=='__main__': main()
