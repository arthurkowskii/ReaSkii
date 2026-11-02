"""Validate current 0.2 native evidence, not the archived 0.1 TSV files."""
from pathlib import Path
import hashlib
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CompactGeometryEvidence(unittest.TestCase):
    def test_native_evidence_matches_current_inputs(self):
        inputs = {'theme_sha256': 'dist/ReaSkii.ReaperThemeZip', 'suite_sha256': 'tests/native_v02.lua',
                  'defaults_sha256': 'scripts/ReaSkii_Defaults.lua'}
        expected = {name: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for name, path in inputs.items()}
        for width in (960, 640, 540, 320):
            lines = (ROOT / f'qa/v02-native-{width}.tsv').read_text().splitlines()
            actual = {parts[1]: parts[2] for line in lines if (parts := line.split('\t'))[0] == 'META'}
            self.assertEqual(actual, expected, f'{width}: regenerate stale native evidence')

    def test_required_controls_are_inside_actual_panels(self):
        checked = 0
        heights = set()
        for width in (960, 640, 540, 320):
            panel = None
            lines = (ROOT / f'qa/v02-native-{width}.tsv').read_text().splitlines()
            self.assertFalse(any(l.startswith(('FAIL\t', 'ERROR\t')) for l in lines))
            self.assertEqual(sum(l.startswith('DONE\t') for l in lines), 1)
            for line in lines:
                parts = line.split('\t')
                if parts[0] == 'CASE':
                    panel = list(map(float, parts[2].split()))
                if 'required two-row ' not in line:
                    continue
                with self.subTest(width=width, assertion=parts[1]):
                    self.assertEqual(parts[0], 'PASS')
                    self.assertIsNotNone(panel)
                    x, y, w, h = map(float, parts[2].split())
                    px, py, pw, ph = panel
                    self.assertGreaterEqual(w, 1)
                    self.assertGreaterEqual(h, 19)
                    self.assertGreaterEqual(x, px - 1)
                    self.assertGreaterEqual(y, py - 1)
                    self.assertLessEqual(x + w, px + pw + 1)
                    self.assertLessEqual(y + h, py + ph + 1)
                    heights.add(ph)
                    checked += 1
        self.assertEqual(checked, 3 * 3 * 4 * 5)  # widths x A/B/C x heights x controls
        self.assertTrue({50, 58, 61, 65}.issubset(heights))


if __name__ == '__main__':
    unittest.main()
