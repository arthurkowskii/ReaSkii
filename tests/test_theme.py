"""Contract checks; native geometry tests live in tests/native.lua."""
import pathlib
import hashlib
import json
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class ThemeContract(unittest.TestCase):
    def setUp(self):
        self.code = (ROOT / 'theme/ReaSkii/rtconfig.txt').read_text()

    def default(self, name, value):
        self.assertRegex(self.code, rf"define_parameter\s+{name}\s+'[^']+'\s+{value}\s+0\s+1")

    def test_full_row_defaults_on(self):
        self.default('tcp_name_full_row', 1)

    def test_smart_indent_defaults_on(self):
        self.default('smart_folder_indent', 1)

    def test_keep_options_default_off(self):
        for name in ('vol', 'pan', 'info', 'io'):
            self.default('tcp_name_keep_' + name, 0)

    def test_every_tcp_layout_uses_common_flow(self):
        tcp = self.code.split('clear master.tcp.*')[0]
        self.assertEqual(len(re.findall(r'^\s*reaskiiTcpFlow\s*$', tcp, re.M)), 10)

    def test_theme_has_own_identity(self):
        text = (ROOT / 'theme/ReaSkii.ReaperTheme').read_text()
        self.assertRegex(text, r'(?m)^ui_img=ReaSkii$')

    def test_indent_uses_rounded_accumulators_in_all_panels(self):
        for marker in ('macro reaskiiAcc', 'reaskiiAcc reaskii_env_indent',
                       'reaskiiAcc reaskii_mcp_indent', 'reaskiiAcc reaskii_indent_acc'):
            self.assertIn(marker, self.code)

    def test_mixer_minimum_height_scales_indent(self):
        self.assertIn('+ 180 * scale reaskii_mcp_max', self.code)
        self.assertNotIn('+ 180 reaskii_mcp_max', self.code)

    def test_original_assets_unchanged(self):
        manifest = json.loads((ROOT / 'upstream/assets.sha256.json').read_text())
        self.assertEqual(len(manifest), 2892)
        for name, expected in manifest.items():
            actual = hashlib.sha256((ROOT / 'theme' / name).read_bytes()).hexdigest()
            self.assertEqual(actual, expected, name)

    def test_macro_layout_balance(self):
        for start, end in [('macro', 'endmacro'), ('layout', 'endlayout')]:
            a = len(re.findall(r'^\s*' + start + r'\s', self.code, re.M | re.I))
            b = len(re.findall(r'^\s*' + end + r'\s*$', self.code, re.M | re.I))
            self.assertEqual(a, b)

if __name__ == '__main__':
    unittest.main()
