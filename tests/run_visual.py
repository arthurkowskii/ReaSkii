#!/usr/bin/env python3
"""Capture a real theme/adjuster preview in the isolated REAPER/Xvfb fixture."""
import argparse
from pathlib import Path
import shutil
import subprocess
import time

from PIL import ImageGrab
from x11_gui import Display, windows

ROOT = Path(__file__).resolve().parents[1]


def run(root, reference=False):
    if 'reaskii-native' not in str(root):
        raise ValueError('Refusing a non-QA installation')
    shutil.copyfile(ROOT / 'dist/ReaSkii.ReaperThemeZip', root / 'ColorThemes/ReaSkii.ReaperThemeZip')
    for name in ('ReaSkii_Adjuster.lua', 'ReaSkii_Defaults.lua', 'ReaSkii_ApplyDefaults.lua'):
        shutil.copyfile(ROOT / 'scripts' / name, root / 'Scripts/Cockos' / name)
    (root / 'visual-config.lua').write_text('return {reference=' + ('true' if reference else 'false') + '}\n')
    shutil.copyfile(ROOT / 'tests/visual_fixture.lua', root / 'visual.lua')
    (root / 'reaper-themeconfig.ini').unlink(missing_ok=True)
    (root / 'fixture-ready.txt').unlink(missing_ok=True)
    (root / 'reaper.ini').write_text('[REAPER]\nfirst_run=0\nloadlastproj=0\nvstpath64=\nvstpath=\nwnd_w=1600\nwnd_h=1000\nleftpanewid=540\nmixwnd_vis=0\n')
    log = (root / 'visual-run.log').open('w')
    process = subprocess.Popen([str(root / 'reaper'), '-newinst', '-nosplash', '-cfgfile', str(root / 'reaper.ini'), str(root / 'visual.lua')], cwd=root, stdout=log, stderr=log)
    display = Display()
    try:
        for _ in range(24):
            time.sleep(0.5)
            if (root / 'fixture-ready.txt').exists():
                break
        else:
            raise RuntimeError('Visual fixture did not initialize')
        for handle, name in windows():
            if name == 'Error opening devices':
                display.escape(handle)
        main = next(h for h, name in windows() if 'REAPER v7.84' in name)
        display.focus(main)
        time.sleep(0.3)
        ImageGrab.grab().crop((80, 80, 1680, 1080)).save(ROOT / ('qa/compact-reference.png' if reference else 'qa/theme-preview.png'))
        for _ in range(24):
            time.sleep(0.5)
            own = [h for h, name in windows() if name == 'ReaSkii - Theme controls']
            if own:
                break
        else:
            raise RuntimeError('Adjuster did not open')
        display.focus(own[0])
        time.sleep(0.3)
        ImageGrab.grab().crop((0, 0, 720, 670)).save(ROOT / ('qa/adjuster-reference.png' if reference else 'qa/adjuster-defaults.png'))
        print('Saved actual REAPER theme and default-adjuster screenshots')
    finally:
        display.close()
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        log.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--reaper-dir', type=Path, required=True)
    parser.add_argument('--reference', action='store_true')
    args = parser.parse_args()
    run(args.reaper_dir.resolve(), args.reference)
