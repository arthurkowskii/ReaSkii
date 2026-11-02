"""Reject invisible custom buttons and advertised layouts without matching artwork."""
import pathlib
import re
import struct
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
ART = ROOT / 'theme/ReaSkii'


class SkinAssets(unittest.TestCase):
    def test_all_advertised_layout_image_directories_exist(self):
        code = (ART / 'rtconfig.txt').read_text()
        for directory in re.findall(r"(?mi)^\s*Layout\s+'[^']*'\s+'([^']+)'", code):
            self.assertTrue((ART / directory).is_dir(), directory)
        for variant in ('A_Solid', 'A_Fader_White', 'A_Classic'):
            self.assertNotRegex(code, rf"(?m)^\s*Layout '{variant}'")

    def test_missing_custom_art_only_used_by_explicitly_disabled_skin_overlays(self):
        code = (ART / 'rtconfig.txt').read_text()
        skin = (ROOT / 'src/reark-skin.walter').read_text()
        bindings = re.findall(r"(?m)^\s*custom\s+(\S+)[^\n]*?'(custom_[^']+)'", code)
        self.assertTrue(bindings)
        for element, name in bindings:
            for directory in ('', '150', '200'):
                if not (ART / directory / (name + '.png')).exists():
                    self.assertRegex(skin, r'(?m)^\s*set ' + re.escape(element) + r' \[0\]$', element)

    def test_pin_and_comping_buttons_are_valid_three_state_images(self):
        for directory, scale in (('', 1), ('150', 1.5), ('200', 2)):
            for name in ('custom_track_pin_on', 'custom_track_pin_off', 'custom_master_track_pin_on', 'custom_master_track_pin_off', 'custom_comping'):
                png = (ART / directory / (name + '.png')).read_bytes()
                self.assertEqual(png[:8], b'\x89PNG\r\n\x1a\n')
                self.assertEqual(struct.unpack('>II', png[16:24]), (int(60*scale), int(20*scale)))
            self.assertNotEqual((ART / directory / 'custom_track_pin_on.png').read_bytes(),
                                (ART / directory / 'custom_track_pin_off.png').read_bytes())

    def test_folder_aliases_come_from_reark_not_reference_art(self):
        for directory in ('', '150', '200'):
            base = ART / directory
            for name in ('custom_track_folder_w1', 'custom_track_folder_w18', 'custom_mcp_folder_start'):
                original = base / 'folder_start.png'
                if not original.exists():
                    original = ART / 'folder_start.png'
                self.assertEqual((base / (name + '.png')).read_bytes(), original.read_bytes())


if __name__ == '__main__':
    unittest.main()
