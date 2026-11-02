"""Check recorded required controls fit their actual native track panels.

This is validation of the committed native evidence, not a new REAPER run.
It deliberately checks actual CASE panel heights, not I_HEIGHTOVERRIDE requests.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CompactGeometryEvidence(unittest.TestCase):
    def test_required_controls_are_inside_actual_panels(self):
        checked = 0
        heights = set()
        for width in (960, 640, 540, 320):
            panel = None
            for line in (ROOT / f'qa/native-{width}.tsv').read_text().splitlines():
                parts = line.split('\t')
                if parts[0] == 'CASE':
                    panel = list(map(float, parts[2].split()))
                if 'required two-row ' not in line and 'reference-style ' not in line:
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
        self.assertEqual(checked, 203)
        self.assertTrue({50, 58, 61, 65}.issubset(heights))


if __name__ == '__main__':
    unittest.main()
