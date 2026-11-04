#!/usr/bin/env python3
"""Native MIDI suite in a dedicated REAPER process/config, never the laptop."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]

def suite(executable, work, name):
    work.mkdir(exist_ok=True)
    result = work / 'native.tsv'
    result.unlink(missing_ok=True)
    (work / 'reaper.ini').write_text('[REAPER]\nfirst_run=0\nloadlastproj=0\nvstpath=\nvstpath64=\n')
    wrapper = work / 'run.lua'
    wrapper.write_text('REASKII_ROOT=' + json.dumps(str(ROOT)) + '\nREASKII_RESULT='
                       + json.dumps(str(result)) + '\ndofile(' + json.dumps(str(ROOT / 'tests' / name)) + ')\n')
    with (work / 'run.log').open('w') as log:
        proc = subprocess.Popen([str(executable), '-newinst', '-nosplash', '-cfgfile', str(work / 'reaper.ini'), str(wrapper)], stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 25
            while time.monotonic() < deadline:
                text = result.read_text() if result.exists() else ''
                if 'DONE\t' in text:
                    break
                if proc.poll() is not None:
                    raise RuntimeError('REAPER exited before tests finished')
                time.sleep(.25)
            else:
                raise TimeoutError('Native suite timed out')
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
    print(text)
    good = [x for x in text.splitlines() if x.startswith('PASS\t')]
    done = [x for x in text.splitlines() if x.startswith('DONE\t')]
    success = len(done) == 1 and int(done[0].split('\t')[1]) == len(good) and len(good) > 0 and 'ERROR\t' not in text
    return result.parent, text, success

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--reaper', required=True, type=Path)
    args = parser.parse_args()
    executable = args.reaper.resolve()
    if 'reaskii-native' not in str(executable) or not os.environ.get('DISPLAY'):
        raise ValueError('Use isolated reaskii-native REAPER under Xvfb')
    scratch = Path(os.environ.get('TMPDIR') or '/tmp')
    outputs, success = [], True
    for name, folder in (('midi_panel_native.lua', 'midi-panel-1'), ('midi_panel_regressions.lua', 'midi-panel-2')):
        work = scratch / ('reaskii-native-' + folder)
        _, text, ok = suite(executable, work, name)
        outputs.append(text)
        success = success and ok
    text = ''.join(outputs)
    if success:
        files = ['scripts/midi/ReaSkii_MIDI_Core.lua', 'scripts/midi/ReaSkii_MIDI_Tools.lua',
                 'tests/midi_panel_native.lua', 'tests/midi_panel_regressions.lua']
        meta = ''.join('META\t' + name + '\t' + hashlib.sha256((ROOT/name).read_bytes()).hexdigest() + '\n' for name in files)
        (ROOT/'qa/midi-panel-native.tsv').write_text(meta+text)
    return 0 if success else 1

if __name__ == '__main__':
    raise SystemExit(main())
