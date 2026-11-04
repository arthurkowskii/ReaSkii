#!/usr/bin/env python3
"""Run Device Rack pure/controller/UI suites and hash runtime dependencies."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
RUNNER=Path(os.environ.get('LUA54_RUNNER','/home/randomaccessmemories/.hermes/cache/scratch/lua54_run.py'))
files=[ROOT/'tests'/n for n in ['device_rack_unit.lua','device_rack_store.lua','device_rack_controller.lua','device_rack_ui.lua']]
out=[]
for path in files:
    r=subprocess.run([sys.executable,str(RUNNER),str(path)],cwd=ROOT,capture_output=True,text=True)
    print(path.name+'\n'+r.stdout+r.stderr,end='')
    out.append('SUITE\t'+path.name+'\n'+r.stdout+r.stderr)
    if r.returncode:
        print('FAILED',path); raise SystemExit(r.returncode)
runtime=sorted([*(ROOT/'scripts/device').glob('*.lua'),ROOT/'effects/ReaSkii/ReaSkii MIDI LFO.jsfx',*files,Path(__file__),RUNNER])
meta=''.join('SHA256\t'+str(p.relative_to(ROOT) if p.is_relative_to(ROOT) else p)+'\t'+hashlib.sha256(p.read_bytes()).hexdigest()+'\n' for p in runtime)
(ROOT/'qa/device-rack-unit.tsv').write_text('REFERENCE_PARITY\tNOT_MEASURED\n'+meta+''.join(out))
print('All Device Rack Lua suites passed.')
