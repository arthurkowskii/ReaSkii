"""Check the actual, reproducible delivery boundary, not only its source tree."""
import hashlib
import json
from pathlib import Path
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class DeliveryPackage(unittest.TestCase):
    def test_delivery_matches_current_sources(self):
        with zipfile.ZipFile(ROOT / 'dist/ReaSkii-v0.1.1.zip') as package:
            expected = {
                'ReaSkii.ReaperThemeZip': ROOT / 'dist/ReaSkii.ReaperThemeZip',
                'ReaSkii_Adjuster.lua': ROOT / 'scripts/ReaSkii_Adjuster.lua',
                'Install-ReaSkii.ps1': ROOT / 'Install-ReaSkii.ps1',
                'README.md': ROOT / 'README.md',
                'THIRD_PARTY_NOTICES.md': ROOT / 'THIRD_PARTY_NOTICES.md',
            }
            self.assertEqual(set(package.namelist()), set(expected) | {'manifest.json'})
            manifest = json.loads(package.read('manifest.json'))
            self.assertEqual(manifest['version'], '0.1.1')
            for name, path in expected.items():
                self.assertEqual(package.read(name), path.read_bytes(), name)
                self.assertEqual(manifest['sha256'][name], hashlib.sha256(path.read_bytes()).hexdigest())


if __name__ == '__main__':
    unittest.main()
