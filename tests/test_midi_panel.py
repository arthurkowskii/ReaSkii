"""Static contract for the MIDI laboratory: the panel is covered by the evidence,
never silently weaker than the core, and its documented limits stay honest."""
import hashlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / 'docs/MIDI-LAB.md'


class MidiPanelContract(unittest.TestCase):
    def test_native_evidence_covers_the_panel_file(self):
        report = (ROOT / 'qa/midi-panel-native.tsv').read_text()
        for name in ('scripts/midi/ReaSkii_MIDI_Core.lua', 'scripts/midi/ReaSkii_MIDI_Tools.lua'):
            current = hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
            self.assertIn(f'META\t{name}\t{current}', report, f'{name} is not covered by the report')
        self.assertEqual(report.count('DONE\t'), 2, 'both native suites must report a completion line')
        self.assertNotIn('ERROR\t', report)
        self.assertNotIn('FAIL\t', report)

    def test_panel_guards_its_own_session(self):
        tools = (ROOT / 'scripts/midi/ReaSkii_MIDI_Tools.lua').read_text()
        core = (ROOT / 'scripts/midi/ReaSkii_MIDI_Core.lua').read_text()
        for guard in ('set_action_options(1)', 'drop_session', 'recovery_pending', 'reset_counters()'):
            self.assertIn(guard, tools, guard)
        for guard in ('_write_recovery', 'M.recover', 'abandon'):
            self.assertIn(guard, core, guard)
        # A preview must not be able to persist silently: only apply() opens an undo block.
        self.assertEqual(core.count('Undo_BeginBlock2'), 1)

    def test_documentation_states_what_is_not_delivered(self):
        text = DOC.read_text()
        for claim in ('Générateurs, arpégiateur', 'ne sont pas livrés', 'pas une sidebar injectée',
                      'Aucune installation sur le laptop'):
            self.assertIn(claim, text, claim)


if __name__ == '__main__':
    unittest.main()
