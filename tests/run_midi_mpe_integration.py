#!/usr/bin/env python3
"""Hash-bound pure/native MPE proof; dedicated config and auto-allocated Xvfb."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
FILES = ['scripts/midi/ReaSkii_MIDI_MPEAdapter.lua',
         'scripts/midi/ReaSkii_MIDI_Expression.lua', 'scripts/midi/ReaSkii_MIDI_Core.lua',
         'tests/midi_expression_unit.lua', 'tests/midi_mpe_integration_unit.lua',
         'tests/midi_mpe_integration_native.lua', 'tests/run_midi_mpe_integration.py',
         'docs/MIDI-MPE-INTEGRATION.md']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--reaper', type=Path, required=True)
    parser.add_argument('--lua-runner', type=Path, required=True)
    args = parser.parse_args()
    exe = args.reaper.resolve()
    if 'reaskii-native' not in str(exe):
        raise ValueError('Only isolated reaskii-native executable allowed')
    scratch = Path(os.environ['TMPDIR'])
    work = Path(tempfile.mkdtemp(prefix='reaskii-native-mpe-integration-', dir=scratch))
    hashes = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in FILES}
    lines = [f'META\t{name}\t{value}' for name, value in hashes.items()]
    # This compiles/executes the adapter through its pure tests in real Lua 5.4.
    for name in ('midi_expression_unit.lua', 'midi_mpe_integration_unit.lua'):
        command = ['python3', str(args.lua_runner), str(ROOT / 'tests' / name)]
        run = subprocess.run(command, capture_output=True, text=True, timeout=60)
        lines.append('COMMAND\t' + json.dumps(command))
        lines.append('INFO\t' + name + '\t' + run.stdout.strip())
        if run.returncode:
            print(run.stdout + run.stderr)
            (ROOT / 'qa/midi-mpe-integration-results.tsv').write_text('\n'.join(lines) + '\n')
            return 1
    if not exe.is_file():
        lines.append('BLOCKED\tnative REAPER executable missing: ' + str(exe))
        lines.append('INFO\tNo native proof; no install attempted; pure tests passed.')
        lines.append('WORK\t' + str(work))
        (ROOT / 'qa/midi-mpe-integration-results.tsv').write_text('\n'.join(lines) + '\n')
        print('\n'.join(lines))
        return 2
    result = work / 'native.tsv'
    (work / 'reaper.ini').write_text('[REAPER]\nfirst_run=0\nloadlastproj=0\nvstpath=\nvstpath64=\n')
    wrapper = work / 'run.lua'
    wrapper.write_text('REASKII_ROOT=' + json.dumps(str(ROOT)) + '\nREASKII_RESULT='
                       + json.dumps(str(result)) + '\ndofile('
                       + json.dumps(str(ROOT / 'tests/midi_mpe_integration_native.lua')) + ')\n')
    command = ['xvfb-run', '-a', '-s', '-screen 0 1024x768x24', str(exe), '-newinst',
               '-nosplash', '-cfgfile', str(work / 'reaper.ini'), str(wrapper)]
    lines.append('COMMAND\t' + json.dumps(command))
    # Own process group includes Xvfb + REAPER and cannot kill parallel workers.
    with (work / 'run.log').open('w') as log:
        proc = subprocess.Popen(command, stdout=log, stderr=log, start_new_session=True)
        try:
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                text = result.read_text() if result.exists() else ''
                if 'DONE\t' in text:
                    break
                if proc.poll() is not None:
                    raise RuntimeError('Native REAPER exited before completion: ' + str(work))
                time.sleep(.2)
            else:
                raise TimeoutError('Native suite timed out: ' + str(work))
        finally:
            import signal
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
    lines.extend(text.splitlines())
    done = [line for line in text.splitlines() if line.startswith('DONE\t')]
    passed = [line for line in text.splitlines() if line.startswith('PASS\t')]
    success = (len(done) == 1 and int(done[0].split('\t')[1]) == len(passed)
               and bool(passed) and 'ERROR\t' not in text)
    for name, value in hashes.items():
        if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != value:
            lines.append('ERROR\tsource changed during test: ' + name)
            success = False
    lines.append('WORK\t' + str(work))
    target = ROOT / 'qa/midi-mpe-integration-results.tsv'
    target.write_text('\n'.join(lines) + '\n')
    print('\n'.join(lines))
    return 0 if success else 1


if __name__ == '__main__':
    raise SystemExit(main())
