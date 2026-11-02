"""Compile the preserved Reapertips engine with an explicit reARK skin layer.
No Reapertips image is copied. Keep behavior macros verbatim; style hooks run last.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
DRAW = {'drawTcp': 'Tcp', 'drawMasterTcp': 'MasterTcp', 'drawEnvcp': 'Env',
        'drawMcp': 'Mcp', 'drawMasterMcp': 'MasterMcp', 'drawTransport': 'Transport'}


def once(code, old, new):
    if code.count(old) != 1:
        raise ValueError(f'Upstream anchor cardinality changed: {old!r}')
    return code.replace(old, new, 1)


def remove_unavailable_layouts(code):
    """Do not advertise graphical variants whose image directories do not exist."""
    output, stack, removed = [], [], set()
    for line in code.splitlines(keepends=True):
        match = re.match(r"\s*Layout\s+'([^']*)'(?:\s+'([^']*)')?", line, re.I)
        if match:
            name, directory = match.groups()
            skip = bool(stack and stack[-1]) or bool(directory and not (ROOT / 'theme/ReaSkii' / directory).is_dir())
            stack.append(skip)
            if skip:
                removed.add(name)
            else:
                output.append(line)
        elif re.match(r'\s*EndLayout\s*$', line, re.I):
            if not stack:
                raise ValueError('Unbalanced upstream layout')
            skip = stack.pop()
            if not skip:
                output.append(line)
        elif not any(stack):
            output.append(line)
    if stack:
        raise ValueError('Unclosed upstream layout')
    code = ''.join(output)
    # A DPI translation to a removed layout is just as misleading as the layout.
    result = []
    for line in code.splitlines(keepends=True):
        if line.startswith('layout_dpi_translate') and any(name in removed for name in re.findall(r"'([^']*)'", line)):
            continue
        result.append(line)
    return ''.join(result)


def make_rules():
    code = (ROOT / 'upstream/reapertips/rtconfig.txt').read_text()
    code = once(code, "adjuster_script 'Default_6.0_theme_adjuster.lua'", 'adjuster_script "ReaSkii_Adjuster.lua"')
    code = once(code, "'Track name takes the whole row' 0 0 1", "'Track name takes the whole row' 1 0 1")
    # Artwork rendering flags, not layout/flow behavior.
    base = (ROOT / 'upstream/rtconfig.txt').read_text()
    for key in ('use_overlays', 'tcp_vol_zeroline', 'mcp_vol_zeroline', 'item_volknobfg'):
        original = re.search(r'(?m)^' + key + r' .*$', code)
        replacement = re.search(r'(?m)^' + key + r' .*$', base)
        if original is None or replacement is None:
            raise ValueError(f'Missing artwork flag: {key}')
        code = once(code, original.group(), replacement.group())
    # reARK fonts are arranged in 3 banks of 5, unlike the Reapertips size ladder.
    # Keep the Reapertips per-scale font override controls operational.
    code = once(code, '    ; User font overrides (only used when value > 0)', '''    ; ReaSkii: reARK font banks, before Reapertips user overrides.
    set main_font scale==1 [1] scale==1.5 [6] [11]
    set list_font scale==1 [1] scale==1.5 [6] [11]
    set trans_font scale==1 [1] scale==1.5 [6] [11]
    set header_font scale==1 [3] scale==1.5 [8] [13]
    ; User font overrides (only used when value > 0)''')
    # Requested exception: retain reARK's combined FX sidebar on the TCP right.
    code = once(code, '    ; Check placement of side buttons', '    reaskiiSidebarSecs scale\n\n    ; Check placement of side buttons')
    # The same padding assignment also exists in other panels: scope it to TCP.
    match = re.search(r'(?ms)^macro calcTcpSecs scale\n.*?^endmacro', code)
    assert match is not None
    tcp = match.group()
    padding = re.search(r'(?m)^\s*set tcp_padding[^\n]+', tcp)
    assert padding is not None
    code = once(code, tcp, once(tcp, padding.group(), padding.group() + '\n    reaskiiCompactPadding scale'))
    # Insert skin definitions before any layout expands the drawing macros.
    skin = (ROOT / 'src/reark-skin.walter').read_text()
    code = once(code, 'macro drawTcp scale\n', skin + '\nmacro drawTcp scale\n')
    for name, hook in DRAW.items():
        pattern = r'(?ms)(^macro ' + name + r' scale\n.*?)(^endmacro)'
        code, n = re.subn(pattern, lambda m: m[1] + '    reaskiiSkin' + hook + ' scale\n' + m[2], code)
        if n != 1:
            raise ValueError(f'Expected one {name}, found {n}')
    return remove_unavailable_layouts(code)
