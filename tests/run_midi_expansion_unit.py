#!/usr/bin/env python3
"""Run real Lua suites; hash all panel runtime dependencies. Native is separate."""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
runner=Path(os.environ.get('LUA54_RUNNER','/home/randomaccessmemories/.hermes/cache/scratch/lua54_run.py'))
files=sorted((ROOT/'tests').glob('midi_expansion_*.lua'))
checks=[f for f in files if f.name!='midi_expansion_gui.lua']
output=[]
for path in checks:
    result=subprocess.run([sys.executable,str(runner),str(path)],cwd=ROOT,capture_output=True,text=True)
    print(path.name+'\n'+result.stdout+result.stderr,end='')
    output.append('SUITE\t'+path.name+'\n'+result.stdout+result.stderr)
    if result.returncode:
        (ROOT/'qa/midi-expansion-unit-partial.tsv').write_text(''.join(output))
        raise SystemExit(result.returncode)
runtime=[*(ROOT/'scripts/midi').glob('ReaSkii_MIDI_Panel*.lua'),*[ROOT/'scripts/midi'/('ReaSkii_MIDI_'+n+'.lua') for n in ['Core','Adapter','Transformations','Generators']]]
manifest=''.join('SHA256\t'+str(p.relative_to(ROOT) if p.is_relative_to(ROOT) else p)+'\t'+hashlib.sha256(p.read_bytes()).hexdigest()+'\n' for p in sorted(set(runtime+files+[Path(__file__),runner])))
(ROOT/'qa/midi-expansion-unit.tsv').write_text('REFERENCE_PARITY\tNOT_MEASURED\n'+manifest+''.join(output))
print('All expansion Lua suites passed. Native/Xvfb acceptance is separate.')
