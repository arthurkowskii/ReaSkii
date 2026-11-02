#!/usr/bin/env python3
"""Build ReaSkii from the preserved reARK X artwork/rules and scoped additions."""
from pathlib import Path
import re
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parent


def replace_once(code, old, new):
    if code.count(old) != 1:
        raise ValueError(f'Expected one upstream anchor: {old!r}')
    return code.replace(old, new, 1)


def make_rules():
    code = (ROOT / 'upstream/rtconfig.txt').read_text()
    additions = (ROOT / 'src/reaskii.walter').read_text()
    code = replace_once(code, 'adjuster_script "Default_6.0_theme_adjuster.lua"', 'adjuster_script "ReaSkii_Adjuster.lua"')
    code = replace_once(code, 'macro calcTcpSecs scale', additions + '\nmacro calcTcpSecs scale')
    if code.count('* * scale tcp_indent{0} folderdepth{0}') != 2:
        raise ValueError('Expected the TCP and EnvCP depth anchors')
    code = code.replace('* * scale tcp_indent{0} folderdepth{0}', '* scale reaskii_indent_acc{0}', 1)
    code = replace_once(code, 'macro calcTcpSecs scale\n', '''macro calcTcpSecs scale
    reaskiiIndent reaskii_units folderdepth
    reaskiiIndent reaskii_units_max maxfolderdepth
    reaskiiAcc reaskii_indent_acc tcp_indent reaskii_units
    reaskiiAcc reaskii_indent_max tcp_indent reaskii_units_max
    set reaskii_indent_diff - reaskii_indent_max reaskii_indent_acc
''')
    code = replace_once(code, '* tcp_indent{0} maxfolderdepth{0}', 'reaskii_indent_max{0}')
    code = replace_once(code, '* tcp_indent{0} folderdepth{0}', 'reaskii_indent_acc{0}')
    code = replace_once(code, '* - maxfolderdepth folderdepth tcp_indent', 'reaskii_indent_diff')
    code = replace_once(code, '* * scale tcp_indent - maxfolderdepth folderdepth', '* scale reaskii_indent_diff')
    # Drag/drop's child target uses the next compressed depth step, not a full linear step.
    code = replace_once(code, 'set tcp.dragdropinfo', '''set reaskii_child_depth + folderdepth 1
    reaskiiIndent reaskii_child_units reaskii_child_depth
    reaskiiAcc reaskii_child_acc tcp_indent reaskii_child_units
    set reaskii_child_step - reaskii_child_acc reaskii_indent_acc
    set tcp.dragdropinfo''')
    code = replace_once(code, '* scale [0 tcp_indent{0}]', '* scale [0 reaskii_child_step{0}]')
    # Let a narrow first-row name stay horizontal instead of using the old fixed-label cutoff.
    pattern = r'(?m)^(\s*set labelEnd[^\n]+)'
    code, count = re.subn(pattern, r'\1\n    set labelEnd ?tcp_name_full_row * scale 90', code)
    assert count == 1
    # Use one flow implementation for default + A/B/C at all supported scales.
    pattern = r'(?m)^([ \t]*)then tcp\.recarm[^\n]*\n(?:[^\n]*\n)*?\1then input_group[^\n]*'
    prefix, flow_code = code.split('front tcp.fxparm tcp.recarm', 1)
    flow_code, count = re.subn(pattern, r'\1reaskiiTcpFlow', flow_code)
    if count != 10:
        raise ValueError(f'Expected 10 TCP layout flow blocks, got {count}')
    code = prefix + 'front tcp.fxparm tcp.recarm' + flow_code
    # Envelope labels must use the same rounded, unscaled depth curve as their tracks.
    code = replace_once(code, 'macro calcEnvSecs scale\n', '''macro calcEnvSecs scale
    reaskiiIndent reaskii_env_units folderdepth
    reaskiiIndent reaskii_env_units_max maxfolderdepth
    reaskiiAcc reaskii_env_indent tcp_indent reaskii_env_units
    reaskiiAcc reaskii_env_max tcp_indent reaskii_env_units_max
''')
    code = replace_once(code, '* * scale tcp_indent{0} folderdepth{0}', '* scale reaskii_env_indent{0}')
    # Mixer indentation is vertical and has an independent base indent setting.
    code = replace_once(code, 'macro drawMcp scale\n', '''macro drawMcp scale
    reaskiiIndent reaskii_mcp_units folderdepth
    reaskiiIndent reaskii_mcp_units_max mcp_maxfolderdepth
    reaskiiAcc reaskii_mcp_indent mcp_indent reaskii_mcp_units
    reaskiiAcc reaskii_mcp_max mcp_indent reaskii_mcp_units_max
    set reaskii_mcp_offset * scale - reaskii_mcp_max reaskii_mcp_indent
''')
    code = replace_once(code, '+ 180 * mcp_maxfolderdepth mcp_indent_s', '+ 180 * scale reaskii_mcp_max')
    code = replace_once(code, '* mcp_maxfolderdepth mcp_indent_s', '* scale reaskii_mcp_max')
    code = replace_once(code, '* folderdepth mcp_indent_s', '* scale reaskii_mcp_indent')
    code = replace_once(code, '* - mcp_maxfolderdepth folderdepth [0 0 0 mcp_indent_s{0}]', '[0 0 0 reaskii_mcp_offset{0}]')
    return code


def build():
    rules = make_rules()
    (ROOT / 'theme/ReaSkii/rtconfig.txt').write_text(rules)
    colors = (ROOT / 'upstream/reARK X.ReaperTheme').read_text()
    colors = replace_once(colors, 'ui_img=reARK X', 'ui_img=ReaSkii')
    (ROOT / 'theme/ReaSkii.ReaperTheme').write_text(colors)
    target = ROOT / 'dist/ReaSkii.ReaperThemeZip'
    target.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted((ROOT / 'theme').rglob('*')):
            if path.is_file():
                info = zipfile.ZipInfo(path.relative_to(ROOT / 'theme').as_posix(), (2026, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o644 << 16
                archive.writestr(info, path.read_bytes())
    # Produce the real, self-contained delivery package as part of every build.
    payload = {
        'ReaSkii.ReaperThemeZip': target.read_bytes(),
        'ReaSkii_Adjuster.lua': (ROOT / 'scripts/ReaSkii_Adjuster.lua').read_bytes(),
        'Install-ReaSkii.ps1': (ROOT / 'Install-ReaSkii.ps1').read_bytes(),
        'README.md': (ROOT / 'README.md').read_bytes(),
        'THIRD_PARTY_NOTICES.md': (ROOT / 'THIRD_PARTY_NOTICES.md').read_bytes(),
    }
    manifest = {'version': '0.1.1', 'sha256': {
        name: hashlib.sha256(data).hexdigest() for name, data in payload.items()}}
    payload['manifest.json'] = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
    with zipfile.ZipFile(ROOT / 'dist/ReaSkii-v0.1.1.zip', 'w') as archive:
        for name, data in sorted(payload.items()):
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, data)
    print(target)
    return target


if __name__ == '__main__':
    build()
