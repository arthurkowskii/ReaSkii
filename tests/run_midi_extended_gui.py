#!/usr/bin/env python3
"""Real X11 integration for the Transform/Generate views beside native REAPER."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import traceback

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from x11_gui import Display, windows  # noqa: E402

ROOT = HERE.parent
REAPER_SOURCE_CONFIG = Path(
    '/home/randomaccessmemories/.hermes/cache/scratch/reaskii-native-midi-gui/reaper-reginfo2.ini')
SCENARIOS = ('chord', 'empty', 'offset')


def wait_for(predicate, message, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.15)
    raise TimeoutError(message)


class Gui(Display):
    CHAR_NAMES = {' ': 'space', '.': 'period', '-': 'minus', '/': 'slash'}

    def _keycode(self, name):
        keysym = self.x.XStringToKeysym(name.encode())
        if not keysym:
            raise ValueError('Unknown keysym: ' + name)
        return self.x.XKeysymToKeycode(self.display, keysym)

    def key(self, name, modifiers=()):
        codes = [self._keycode(modifier) for modifier in modifiers]
        for code in codes:
            self.xt.XTestFakeKeyEvent(self.display, code, 1, 0)
        code = self._keycode(name)
        self.xt.XTestFakeKeyEvent(self.display, code, 1, 0)
        self.xt.XTestFakeKeyEvent(self.display, code, 0, 0)
        for code in reversed(codes):
            self.xt.XTestFakeKeyEvent(self.display, code, 0, 0)
        self.x.XFlush(self.display)
        time.sleep(0.03)

    def type_text(self, text):
        for char in text:
            self.key(self.CHAR_NAMES.get(char, char))

    def clear_field(self):
        self.key('a', ('Control_L',))
        self.key('BackSpace')


def read_state(path):
    try:
        text = path.read_text()
    except (FileNotFoundError, ValueError):
        return None
    count, _, dump = text.partition('|')
    try:
        return int(count), dump
    except ValueError:
        return None


def notes_from(dump):
    notes = []
    for item in filter(None, dump.split(';')):
        start, end, pitch, vel, selected = (int(value) for value in item.split(':'))
        notes.append((start, end, pitch, vel, selected))
    return notes


def run_scenario(display, reaper, scenario, actions, checks, work_root):
    work = work_root / scenario
    work.mkdir(parents=True)
    config = work / 'reaper-reginfo2.ini'
    config.write_bytes(REAPER_SOURCE_CONFIG.read_bytes())
    ini = work / 'reaper.ini'
    ini.write_text('[REAPER]\nfirst_run=0\nloadlastproj=0\nvstpath=\nvstpath64=\n'
                   'wnd_w=1400\nwnd_h=850\n')
    state = work / 'state.txt'
    wrapper = work / 'run.lua'
    wrapper.write_text(
        'REASKII_ROOT=' + json.dumps(str(ROOT)) + '\n'
        'REASKII_STATE=' + json.dumps(str(state)) + '\n'
        'REASKII_SCENARIO=' + json.dumps(scenario) + '\n'
        'dofile(' + json.dumps(str(ROOT / 'tests/midi_extended_gui.lua')) + ')\n')
    log = (work / 'run.log').open('w')
    proc = subprocess.Popen(
        [str(reaper), '-newinst', '-nosplash', '-cfgfile', str(ini), str(wrapper)],
        stdout=log, stderr=log)
    try:
        handle = wait_for(
            lambda: next((h for h, name in windows() if name == 'ReaSkii MIDI Tools'), None),
            'Panel missing: ' + repr(windows()))
        native = wait_for(
            lambda: next((h for h, name in windows() if 'ReaSkii extended' in name), None),
            'Native MIDI editor missing')
        display.x.XMoveResizeWindow.argtypes = [
            ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int,
            ctypes.c_uint, ctypes.c_uint]
        display.x.XMoveResizeWindow(display.display, native, 350, 70, 1000, 700)
        display.x.XFlush(display.display)
        actions(display, handle, native, state, checks)
        assert any(h == handle for h, _ in windows()), 'Panel disappeared early'
        display.escape(handle)
        wait_for(lambda: not any(h == handle for h, _ in windows()),
                 'Panel did not close with Escape')
        assert any(h == native for h, _ in windows()), 'Native MIDI editor disappeared'
        checks.append('PASS\t' + scenario + ': panel closes and native editor survives')
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        log.close()


def click_dialog(display, title):
    dialog = wait_for(
        lambda: next((h for h, name in windows() if name == title), None),
        'Dialog missing: ' + title)
    display.focus(dialog)
    return dialog


def chord_actions(display, handle, native, state, checks):
    initial = wait_for(lambda: read_state(state) if read_state(state)[0] == 4 else None,
                       'Chord fixture did not publish four notes')
    display.click(handle, 150, 85)
    time.sleep(0.25)
    display.click(handle, 150, 162)
    click_dialog(display, 'Chop')
    display.clear_field()
    display.type_text('3')
    display.key('Return')
    click_dialog(display, 'Chop range (item)')
    display.key('Return')
    preview = wait_for(lambda: (lambda s: s if s and s[0] == 12 else None)(read_state(state)),
                       'Chop preview did not produce 12 notes')
    checks.append('PASS\tchord: real Chop dialog parts=3 previews 12 notes')
    display.click(handle, 220, 435)
    restored = wait_for(
        lambda: (lambda s: s if s and s[0] == 4 and s[1] == initial[1] else None)(
            read_state(state)), 'Chop cancel did not restore the exact chord')
    checks.append('PASS\tchord: Cancel restores the byte-identical four-note dump')

    display.click(handle, 150, 162)
    dialog = click_dialog(display, 'Chop')
    display.escape(dialog)
    wait_for(lambda: not any(name == 'Chop' for _, name in windows()), 'Chop dialog stayed open')
    time.sleep(0.4)
    modal = read_state(state)
    assert modal == restored, 'Escaping the modal dialog changed the take'
    assert any(h == handle for h, _ in windows()), 'Panel vanished after modal cancel'
    checks.append('PASS\tchord: modal Escape leaves no preview session or MIDI change')

    display.click(handle, 150, 162)
    click_dialog(display, 'Chop')
    display.clear_field()
    display.type_text('x')
    display.key('Return')
    wait_for(lambda: not any(name == 'Chop' for _, name in windows()), 'Invalid dialog stayed open')
    time.sleep(0.5)
    assert read_state(state) == restored, 'Invalid Chop input wrote to the take'
    assert any(h == handle for h, _ in windows()), 'Panel vanished after invalid input'
    checks.append('PASS\tchord: invalid Chop input is refused without writing')


def empty_actions(display, handle, native, state, checks):
    wait_for(lambda: read_state(state) if read_state(state)[0] == 0 else None,
             'Empty fixture did not publish zero notes')
    display.click(handle, 250, 85)
    time.sleep(0.25)
    display.click(handle, 150, 132)
    click_dialog(display, 'Euclidean')
    display.key('Return')
    click_dialog(display, 'Euclidean range (item)')
    display.key('Return')
    preview = wait_for(
        lambda: (lambda s: s if s and s[0] > 0 else None)(read_state(state)),
        'Euclidean preview did not generate notes')
    notes = notes_from(preview[1])
    assert all(note[2] == 60 for note in notes), 'Euclidean preview used an unexpected pitch'
    checks.append('PASS\tempty: real Euclidean dialog previews %d notes at pitch 60' % len(notes))
    display.click(handle, 220, 435)
    wait_for(lambda: (lambda s: s if s and s[0] == 0 else None)(read_state(state)),
             'Euclidean cancel did not empty the range')
    checks.append('PASS\tempty: Euclidean Cancel returns the range to zero notes')


def offset_actions(display, handle, native, state, checks):
    initial = wait_for(
        lambda: (lambda s: s if s and s[0] == 1 else None)(read_state(state)),
        'Offset fixture did not publish its note')
    assert initial[1].startswith('1440:1920:60'), 'Offset fixture note is wrong: ' + initial[1]
    display.click(handle, 150, 85)
    time.sleep(0.25)
    display.click(handle, 150, 312)
    click_dialog(display, 'Reverse range (item)')
    display.key('Return')
    preview = wait_for(
        lambda: (lambda s: s if s and s[0] == 1 and s[1] != initial[1] else None)(
            read_state(state)), 'Reverse preview did not move the note')
    start, end = notes_from(preview[1])[0][:2]
    expected = (4560, 5040)
    if (start, end) == expected:
        checks.append('PASS\toffset: range honours start offset, tempo and playrate '
                      '(note mirrored to %d..%d)' % (start, end))
    else:
        checks.append('FAIL\toffset: range ignores item playrate: expected %d..%d, got %d..%d'
                      % (expected[0], expected[1], start, end))
    display.click(handle, 220, 435)
    wait_for(lambda: (lambda s: s if s and s[1] == initial[1] else None)(read_state(state)),
             'Reverse cancel did not restore the offset note')
    checks.append('PASS\toffset: Reverse Cancel restores the source note')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--reaper', type=Path, required=True)
    args = parser.parse_args()
    reaper = args.reaper.resolve()
    if 'reaskii-native' not in str(reaper) or not os.environ.get('DISPLAY'):
        raise ValueError('Isolated REAPER/Xvfb display required')
    if not REAPER_SOURCE_CONFIG.is_file():
        raise FileNotFoundError('Missing recorded QA config: ' + str(REAPER_SOURCE_CONFIG))

    work_root = Path(os.environ['TMPDIR']) / ('reaskii-extended-gui-%d' % time.time_ns())
    work_root.mkdir(parents=True)
    checks = []
    display = Gui()
    try:
        for scenario, actions in (
                ('chord', chord_actions),
                ('empty', empty_actions),
                ('offset', offset_actions)):
            try:
                run_scenario(display, reaper, scenario, actions, checks, work_root)
            except Exception:
                checks.append('FAIL\t%s: %s' % (
                    scenario, traceback.format_exc().strip().splitlines()[-1]))
    finally:
        display.close()

    text = '\n'.join(checks) + '\nDONE\t%d\n' % len(checks)
    files = [
        'scripts/midi/ReaSkii_MIDI_Core.lua',
        'scripts/midi/ReaSkii_MIDI_Tools.lua',
        'scripts/midi/ReaSkii_MIDI_Adapter.lua',
        'scripts/midi/ReaSkii_MIDI_Transformations.lua',
        'scripts/midi/ReaSkii_MIDI_Generators.lua',
        'tests/midi_extended_gui.lua',
        'tests/run_midi_extended_gui.py',
    ]
    meta = ''.join(
        'META\t%s\t%s\n' % (name, hashlib.sha256((ROOT / name).read_bytes()).hexdigest())
        for name in files)
    (ROOT / 'qa/midi-extended-gui.tsv').write_text(meta + text)
    print(text)
    if any(line.startswith('FAIL') for line in checks):
        sys.exit(1)


if __name__ == '__main__':
    main()
