#!/usr/bin/env python3
"""Reproducibly build ReaSkii: Reapertips engine and preserved reARK art."""
from pathlib import Path
import hashlib
import json
import zipfile
from src.engine import make_rules
from src.skin_assets import write_assets

ROOT = Path(__file__).resolve().parent
VERSION = '0.3.0'
THEME_VERSION = '0.2.0'
# Installed below Scripts/ReaSkii/, one subdirectory per tool family.
TOOL_GROUPS = ('midi', 'device')


def write_zip(path, payload):
    with zipfile.ZipFile(path, 'w') as archive:
        for name, data in sorted(payload.items()):
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, data)


def build():
    write_assets(ROOT / 'theme/ReaSkii')
    (ROOT / 'theme/ReaSkii/rtconfig.txt').write_text(make_rules())
    colors = (ROOT / 'upstream/reARK X.ReaperTheme').read_text()
    if colors.count('ui_img=reARK X') != 1:
        raise ValueError('Unexpected reARK color-theme identity')
    (ROOT / 'theme/ReaSkii.ReaperTheme').write_text(colors.replace('ui_img=reARK X', 'ui_img=ReaSkii'))
    target = ROOT / 'dist/ReaSkii.ReaperThemeZip'
    target.parent.mkdir(exist_ok=True)
    write_zip(target, {p.relative_to(ROOT / 'theme').as_posix(): p.read_bytes()
                       for p in (ROOT / 'theme').rglob('*') if p.is_file()})
    payload = {'ReaSkii.ReaperThemeZip': target.read_bytes()}
    for name in ('ReaSkii_Adjuster.lua', 'ReaSkii_Defaults.lua', 'ReaSkii_ApplyDefaults.lua'):
        payload[name] = (ROOT / 'scripts' / name).read_bytes()
    payload['ReaSkii_RegisterTools.lua'] = (ROOT / 'scripts/ReaSkii_RegisterTools.lua').read_bytes()
    for group in TOOL_GROUPS:
        sources = sorted((ROOT / 'scripts' / group).glob('*.lua'))
        if not sources:
            raise ValueError(f'No tool script found in scripts/{group}')
        for source in sources:
            payload[f'scripts/{group}/{source.name}'] = source.read_bytes()
    for name in ('Install-ReaSkii.ps1', 'Get-ReaSkii.ps1', 'README.md', 'THIRD_PARTY_NOTICES.md'):
        payload[name] = (ROOT / name).read_bytes()
    manifest = {'version': VERSION, 'theme_version': THEME_VERSION,
                'engine': 'Reapertips v1.95a Dark', 'artwork': 'reARK X',
                'sha256': {name: hashlib.sha256(data).hexdigest() for name, data in payload.items()}}
    payload['manifest.json'] = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
    write_zip(ROOT / f'dist/ReaSkii-v{VERSION}.zip', payload)
    print(target)
    return target


if __name__ == '__main__':
    build()
