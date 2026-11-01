#!/usr/bin/env python3
"""Exercise the real adjuster via the standard menu action, a mouse click and a fresh REAPER process."""
import argparse
from pathlib import Path
import shutil
import subprocess
import time

from PIL import ImageGrab
from x11_gui import Display, windows

ROOT = Path(__file__).resolve().parents[1]


def launch(root, script):
    log = (root / 'adjuster-run.log').open('w')
    process = subprocess.Popen([str(root / 'reaper'), '-newinst', '-nosplash', '-cfgfile', str(root / 'reaper.ini'), str(root / script)], cwd=root, stdout=log, stderr=log)
    return process, log


def stop(process, log):
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    log.close()


def run(root):
    if 'reaskii-native' not in str(root):
        raise ValueError('Refusing non-QA installation')
    (root / 'Scripts/Cockos').mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'scripts/ReaSkii_Adjuster.lua', root / 'Scripts/Cockos/ReaSkii_Adjuster.lua')
    shutil.copyfile(ROOT / 'tests/adjuster_smoke.lua', root / 'adjuster-smoke.lua')
    shutil.copyfile(ROOT / 'dist/ReaSkii.ReaperThemeZip', root / 'ColorThemes/ReaSkii.ReaperThemeZip')
    (root / 'reaper-themeconfig.ini').unlink(missing_ok=True)
    result = root / 'adjuster-result.txt'
    result.unlink(missing_ok=True)
    display = Display()
    process, log = launch(root, 'adjuster-smoke.lua')
    try:
        for _ in range(24):
            time.sleep(0.5)
            found = [h for h, name in windows() if name == 'ReaSkii - Theme controls']
            if found:
                break
        else:
            raise RuntimeError(f'Adjuster did not appear: {windows()}')
        handle = found[0]
        display.click(handle, 29, 57)
        time.sleep(1)
        text = result.read_text()
        if not text.startswith('PASS:'):
            raise AssertionError(text)
        display.focus(handle)
        time.sleep(0.2)
        ImageGrab.grab().crop((0, 0, 570, 455)).save(ROOT / 'qa/adjuster.png')
        print(text)
    finally:
        stop(process, log)
        display.close()
    (root / 'persistence.lua').write_text('''local root=reaper.GetExePath()
assert(root:find('reaskii%-native'))
reaper.OpenColorThemeFile(root..'/ColorThemes/ReaSkii.ReaperThemeZip')
for i=0,1000 do
 local n,_,v=reaper.ThemeLayout_GetParameter(i)
 if not n or n=='' then break end
 if n=='tcp_name_full_row' then local f=assert(io.open(root..'/persistence.txt','w'));f:write(tostring(v));f:close();break end
end
''')
    (root / 'persistence.txt').unlink(missing_ok=True)
    process, log = launch(root, 'persistence.lua')
    try:
        time.sleep(4)
        value = (root / 'persistence.txt').read_text()
        if value != '0':
            raise AssertionError(f'Checkbox value was not persisted: {value}')
        print('PASS: fresh REAPER instance restored full-row=0 after the GUI click')
        (ROOT / 'qa/adjuster-test.txt').write_text(text + '\nPASS: persistence restored full-row=0 in a fresh process\n')
    finally:
        stop(process, log)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--reaper-dir', type=Path, required=True)
    run(parser.parse_args().reaper_dir.resolve())
