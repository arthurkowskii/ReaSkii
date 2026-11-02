#!/usr/bin/env python3
"""Run real REAPER/WALTER acceptance tests under an isolated Xvfb display.
Usage: xvfb-run -a -s '-screen 0 1800x1200x24' python3 tests/run_native.py --reaper-dir /path/to/reaskii-native/.../REAPER
The portable REAPER binary/license are external inputs, never repository assets.
"""
import argparse
import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def run(reaper_dir, width):
    if 'reaskii-native' not in str(reaper_dir) or not os.environ.get('DISPLAY'):
        raise ValueError('Use the isolated reaskii-native directory under Xvfb')
    (reaper_dir / 'ColorThemes').mkdir(exist_ok=True)
    shutil.copyfile(ROOT / 'dist/ReaSkii.ReaperThemeZip', reaper_dir / 'ColorThemes/ReaSkii.ReaperThemeZip')
    shutil.copyfile(ROOT / 'tests/native_v02.lua', reaper_dir / 'native-suite.lua')
    (reaper_dir / 'native.lua').write_text('''local ok,err=xpcall(function() dofile(reaper.GetExePath()..'/native-suite.lua') end,debug.traceback)
if not ok then local f=assert(io.open(reaper.GetExePath()..'/native-results.tsv','a'));f:write('ERROR\\t'..err..'\\n');f:close() end
''')
    (reaper_dir / 'Scripts/Cockos').mkdir(parents=True, exist_ok=True)
    for name in ('ReaSkii_Defaults.lua', 'ReaSkii_Adjuster.lua', 'ReaSkii_ApplyDefaults.lua'):
        shutil.copyfile(ROOT / 'scripts' / name, reaper_dir / 'Scripts/Cockos' / name)
    (reaper_dir / 'native-config.lua').write_text(f'return {{width={width}}}\n')
    ini = reaper_dir / 'reaper.ini'
    ini.write_text(f'[REAPER]\nfirst_run=0\nloadlastproj=0\nvstpath64=\nvstpath=\nwnd_w=1600\nwnd_h=1000\nleftpanewid={width}\nmixwnd_vis=0\n')
    result = reaper_dir / 'native-results.tsv'
    (reaper_dir / 'reaper-themeconfig.ini').unlink(missing_ok=True)
    result.unlink(missing_ok=True)
    with (reaper_dir / 'native-run.log').open('w') as log:
        proc = subprocess.Popen([str(reaper_dir / 'reaper'), '-newinst', '-nosplash', '-cfgfile', str(ini), str(reaper_dir / 'native.lua')], cwd=reaper_dir, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 110
            while time.monotonic() < deadline:
                time.sleep(1)
                content = result.read_text() if result.exists() else ''
                if '\nDONE\t' in content or '\nERROR\t' in content or proc.poll() is not None:
                    break
            else:
                raise TimeoutError('Native test did not finish')
            lines = content.splitlines()
            failures = [line for line in lines if line.startswith(('FAIL\t', 'ERROR\t'))]
            done = [line for line in lines if line.startswith('DONE\t')]
            target = ROOT / f'qa/v02-native-{width}.tsv'
            target.parent.mkdir(exist_ok=True)
            inputs = {'theme_sha256': reaper_dir / 'ColorThemes/ReaSkii.ReaperThemeZip',
                      'suite_sha256': reaper_dir / 'native-suite.lua',
                      'defaults_sha256': reaper_dir / 'Scripts/Cockos/ReaSkii_Defaults.lua'}
            metadata = ''.join(f'META\t{name}\t{hashlib.sha256(path.read_bytes()).hexdigest()}\n'
                               for name, path in inputs.items())
            target.write_text(metadata + content)
            summary = {'width': width, 'done': done, 'failure_count': len(failures), 'sample_failures': failures[:15], 'report': str(target)}
            print(json.dumps(summary, indent=2))
            return bool(done) and not failures
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--reaper-dir', required=True, type=Path)
    parser.add_argument('--width', type=int, default=960)
    args = parser.parse_args()
    raise SystemExit(0 if run(args.reaper_dir.resolve(), args.width) else 1)
