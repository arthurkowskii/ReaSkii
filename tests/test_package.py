"""Verify the delivery archive built from the current sources.

dist/ is gitignored, so these checks only run after `python3 build.py`.
"""
import hashlib
import json
from pathlib import Path
import sys
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import build  # noqa: E402  (needs ROOT on sys.path)

RELEASE = ROOT / f'dist/ReaSkii-v{build.VERSION}.zip'
ROOT_ENTRIES = {'ReaSkii.ReaperThemeZip', 'ReaSkii_Adjuster.lua', 'ReaSkii_Defaults.lua',
                'ReaSkii_ApplyDefaults.lua', 'ReaSkii_RegisterTools.lua',
                'Install-ReaSkii.ps1', 'Get-ReaSkii.ps1', 'README.md',
                'THIRD_PARTY_NOTICES.md'}


def tool_entries():
    return {f'scripts/{group}/{path.name}'
            for group in build.TOOL_GROUPS
            for path in (ROOT / 'scripts' / group).glob('*.lua')}


class DeliveryPackage(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not RELEASE.exists():
            raise unittest.SkipTest(f'{RELEASE.name} absent: run python3 build.py first')
        cls.package = zipfile.ZipFile(RELEASE)
        cls.entries = set(cls.package.namelist())
        cls.manifest = json.loads(cls.package.read('manifest.json'))

    @classmethod
    def tearDownClass(cls):
        cls.package.close()

    def test_archive_lists_exactly_the_expected_payload(self):
        self.assertEqual(self.entries, ROOT_ENTRIES | tool_entries() | {'manifest.json'})

    def test_manifest_covers_every_entry_with_matching_hashes(self):
        self.assertEqual(self.manifest['version'], build.VERSION)
        self.assertEqual(self.manifest['theme_version'], build.THEME_VERSION)
        self.assertEqual(set(self.manifest['sha256']), self.entries - {'manifest.json'})
        for name, digest in self.manifest['sha256'].items():
            self.assertEqual(digest, hashlib.sha256(self.package.read(name)).hexdigest(), name)

    def test_shipped_theme_is_the_one_this_build_produces(self):
        self.assertEqual(hashlib.sha256(self.package.read('ReaSkii.ReaperThemeZip')).hexdigest(),
                         hashlib.sha256((ROOT / 'dist/ReaSkii.ReaperThemeZip').read_bytes()).hexdigest())

    def test_every_tool_script_on_disk_is_shipped(self):
        shipped = {name for name in self.entries if name.startswith('scripts/')}
        self.assertEqual(shipped, tool_entries())


if __name__ == '__main__':
    unittest.main()
