#!/usr/bin/env python3
"""Reproducibly build ReaSkii: the full package and the tools-only package."""
from pathlib import Path
import hashlib
import json
import zipfile
from src.engine import make_rules
from src.skin_assets import write_assets

ROOT = Path(__file__).resolve().parent
VERSION = '0.4.0'
THEME_VERSION = '0.2.0'
# Installed below Scripts/ReaSkii/, one subdirectory per tool family.
TOOL_GROUPS = ('midi', 'device')
DOCS = ('README.md', 'THIRD_PARTY_NOTICES.md')


def write_zip(path, payload):
    with zipfile.ZipFile(path, 'w') as archive:
        for name, data in sorted(payload.items()):
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, data)


def tool_payload():
    """Files shared by both packages: the tools, their JSFX and the action registrar."""
    payload = {'ReaSkii_RegisterTools.lua': (ROOT / 'scripts/ReaSkii_RegisterTools.lua').read_bytes()}
    for group in TOOL_GROUPS:
        sources = sorted((ROOT / 'scripts' / group).glob('*.lua'))
        if not sources:
            raise ValueError(f'No tool script found in scripts/{group}')
        for source in sources:
            payload[f'scripts/{group}/{source.name}'] = source.read_bytes()
    effects = sorted((ROOT / 'effects').rglob('*.jsfx'))
    if not effects:
        raise ValueError('No JSFX found in effects/')
    for effect in effects:
        payload[f'effects/{effect.relative_to(ROOT / "effects").as_posix()}'] = effect.read_bytes()
    return payload


def write_package(path, payload, kind):
    manifest = {'version': VERSION, 'package': kind,
                'engine': 'Reapertips v1.95a Dark', 'artwork': 'reARK X',
                'sha256': {name: hashlib.sha256(data).hexdigest() for name, data in payload.items()}}
    if kind == 'full':
        manifest['theme_version'] = THEME_VERSION
    package = dict(payload)
    package['manifest.json'] = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
    write_zip(path, package)
    return path


def build():
    write_assets(ROOT / 'theme/ReaSkii')
    (ROOT / 'theme/ReaSkii/rtconfig.txt').write_text(make_rules())
    colors = (ROOT / 'upstream/reARK X.ReaperTheme').read_text()
    if colors.count('ui_img=reARK X') != 1:
        raise ValueError('Unexpected reARK color-theme identity')
    (ROOT / 'theme/ReaSkii.ReaperTheme').write_text(colors.replace('ui_img=reARK X', 'ui_img=ReaSkii'))
    theme = ROOT / 'dist/ReaSkii.ReaperThemeZip'
    theme.parent.mkdir(exist_ok=True)
    write_zip(theme, {p.relative_to(ROOT / 'theme').as_posix(): p.read_bytes()
                      for p in (ROOT / 'theme').rglob('*') if p.is_file()})

    tools = tool_payload()

    full = {'ReaSkii.ReaperThemeZip': theme.read_bytes()}
    for name in ('ReaSkii_Adjuster.lua', 'ReaSkii_Defaults.lua', 'ReaSkii_ApplyDefaults.lua'):
        full[name] = (ROOT / 'scripts' / name).read_bytes()
    full.update(tools)
    for name in ('Install-ReaSkii.ps1', 'Get-ReaSkii.ps1', 'Get-ReaSkiiTools.ps1') + DOCS:
        full[name] = (ROOT / name).read_bytes()
    full_path = write_package(ROOT / f'dist/ReaSkii-v{VERSION}.zip', full, 'full')

    only = dict(tools)
    for name in ('Install-ReaSkii.ps1', 'Install-ReaSkiiTools.ps1', 'Get-ReaSkii.ps1',
                 'Get-ReaSkiiTools.ps1') + DOCS:
        only[name] = (ROOT / name).read_bytes()
    tools_path = write_package(ROOT / f'dist/ReaSkii-Tools-v{VERSION}.zip', only, 'tools')

    print(theme)
    print(full_path)
    print(tools_path)
    return theme


if __name__ == '__main__':
    build()
