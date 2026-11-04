#!/usr/bin/env python3
"""Native Device Rack suite in an isolated REAPER process/config."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(); p.add_argument('--reaper',required=True,type=Path); args=p.parse_args()
    exe=args.reaper.resolve()
    assert 'reaskii-native' in str(exe) and os.environ.get('DISPLAY'), 'Isolated REAPER/Xvfb required'
    work=Path(os.environ['TMPDIR'])/'reaskii-native-device-rack'; work.mkdir(exist_ok=True)
    result=work/'native.tsv'; result.unlink(missing_ok=True)
    (work/'reaper.ini').write_text('[REAPER]\nfirst_run=0\nloadlastproj=0\nvstpath=\nvstpath64=\nwnd_w=1300\nwnd_h=900\n')
    wrapper=work/'run.lua'; wrapper.write_text('REASKII_ROOT='+json.dumps(str(ROOT))+'\nREASKII_RESULT='+json.dumps(str(result))+'\ndofile('+json.dumps(str(ROOT/'tests/device_rack_native.lua'))+')\n')
    with (work/'run.log').open('w') as log:
        proc=subprocess.Popen([str(exe),'-newinst','-nosplash','-cfgfile',str(work/'reaper.ini'),str(wrapper)],stdout=log,stderr=log)
        try:
            deadline=time.monotonic()+40
            while time.monotonic()<deadline:
                text=result.read_text() if result.exists() else ''
                if 'DONE\t' in text: break
                if proc.poll() is not None: raise RuntimeError('REAPER exited before tests finished')
                time.sleep(.25)
            else: raise TimeoutError('Native Device Rack suite timed out')
        finally:
            proc.terminate()
            try: proc.wait(timeout=5)
            except subprocess.TimeoutExpired: proc.kill(); proc.wait()
    print(text)
    checks=text.splitlines(); good=[x for x in checks if x.startswith('PASS\t')]; done=[x for x in checks if x.startswith('DONE\t')]
    ok=len(done)==1 and int(done[0].split('\t')[1])==len(good) and len(good)>0 and 'ERROR\t' not in text
    if ok:
        files=[*(ROOT/'scripts/device').glob('*.lua'),ROOT/'effects/ReaSkii/ReaSkii MIDI LFO.jsfx',ROOT/'tests/device_rack_native.lua',Path(__file__)]
        meta=''.join('SHA256\t'+str(f.relative_to(ROOT))+'\t'+hashlib.sha256(f.read_bytes()).hexdigest()+'\n' for f in files)
        (ROOT/'qa/device-rack-native.tsv').write_text(meta+text)
    return 0 if ok else 1

if __name__=='__main__': raise SystemExit(main())
