"""ReaSkii 0.2 contract: Reapertips behavior, reARK artwork, explicit skin changes."""
import pathlib
import hashlib
import json
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def macro(code, name):
    return re.search(r'(?m)^macro ' + re.escape(name) + r'[^\n]*\n.*?^endmacro', code, re.S).group()


def parameters(code):
    direct = dict(re.findall(r"(?m)^define_parameter\s+(\w+)\s+'[^']+'\s+([^\n;]+)", code))
    indexed = dict(re.findall(r"(?m)^indexParams\s+'([^']+)'\s+([^\n;]+)", code))
    return {k: v.split() for k, v in (direct | indexed).items()}


class ThemeContract(unittest.TestCase):
    def setUp(self):
        self.code = (ROOT / 'theme/ReaSkii/rtconfig.txt').read_text()
        self.reference = (ROOT / 'upstream/reapertips/rtconfig.txt').read_text()

    def test_reapertips_parameter_contract(self):
        expected = parameters(self.reference)
        expected['tcp_name_full_row'][0] = '1'
        actual = parameters(self.code)
        for name in ('reark_tcp_fx_sidebar', 'reark_tcp_fx_size', 'reark_tcp_fx_columns', 'reark_tcp_fx_height'):
            self.assertIn(name, actual)
            actual.pop(name)
        self.assertEqual(actual, expected)

    def test_all_behavior_macros_preserved(self):
        names = re.findall(r'(?m)^macro (\w+)', self.reference)
        style = {'calcFontSizes', 'drawTcp', 'drawMasterTcp', 'drawEnvcp', 'drawMcp', 'drawMasterMcp', 'drawTransport'}
        for name in names:
            if name not in style:
                actual = macro(self.code, name)
                if name == 'calcTcpSecs':
                    actual = actual.replace('\n    reaskiiCompactPadding scale', '').replace('    reaskiiSidebarSecs scale\n\n', '')
                self.assertEqual(actual, macro(self.reference, name), name)

    def test_render_macros_only_append_skin(self):
        for name in ('drawTcp', 'drawMasterTcp', 'drawEnvcp', 'drawMcp', 'drawMasterMcp', 'drawTransport'):
            expected = macro(self.reference, name).removesuffix('endmacro')
            actual = macro(self.code, name)
            self.assertTrue(actual.startswith(expected), name)
            self.assertRegex(actual[len(expected):], r'^    reaskiiSkin\w+ scale\nendmacro$')

    def test_full_row_defaults_on(self):
        self.assertEqual(parameters(self.code)['tcp_name_full_row'], ['1', '0', '1'])

    def test_smart_indent_defaults_on(self):
        self.assertEqual(parameters(self.code)['smart_folder_indent'], ['1', '0', '1'])

    def test_keep_options_default_off(self):
        for name in ('vol', 'pan', 'info', 'io'):
            self.assertEqual(parameters(self.code)['tcp_name_keep_' + name], ['0', '0', '1'])

    def test_reapertips_lists_not_legacy_reark_options(self):
        for name in ('tcp_side_fx', 'tcp_sep_sends', 'tcp_side_sends', 'tcp_show_pin', 'trans_centered'):
            self.assertIn(name, parameters(self.code))
        self.assertNotIn('tcp_fx_section_mode', parameters(self.code))

    def test_theme_has_own_identity_and_reark_colors(self):
        colors = (ROOT / 'upstream/reARK X.ReaperTheme').read_text().replace('ui_img=reARK X', 'ui_img=ReaSkii')
        self.assertEqual((ROOT / 'theme/ReaSkii.ReaperTheme').read_text(), colors)
        self.assertIn('adjuster_script "ReaSkii_Adjuster.lua"', self.code)

    def test_original_assets_unchanged(self):
        manifest = json.loads((ROOT / 'upstream/assets.sha256.json').read_text())
        self.assertEqual(len(manifest), 2892)
        for name, expected in manifest.items():
            self.assertEqual(hashlib.sha256((ROOT / 'theme' / name).read_bytes()).hexdigest(), expected, name)

    def test_macro_layout_balance(self):
        for start, end in [('macro', 'endmacro'), ('layout', 'endlayout')]:
            self.assertEqual(len(re.findall(r'^\s*' + start + r'\s', self.code, re.M | re.I)),
                             len(re.findall(r'^\s*' + end + r'\s*$', self.code, re.M | re.I)))


if __name__ == '__main__':
    unittest.main()
