"""Small native-looking buttons for functions reARK predates; no external art.
PNG encoding is stdlib-only, preserving the dependency-free reproducible build.
Folder connectors alias reARK's own original files byte-for-byte.
"""
from pathlib import Path
import binascii
import struct
import zlib

GLYPHS = {'P': ('11110','10001','10001','11110','10000','10000','10000'),
          'p': ('00000','00000','11110','10001','11110','10000','10000'),
          'C': ('01111','10000','10000','10000','10000','10000','01111')}
BUTTONS = {'custom_track_pin_on': 'P', 'custom_track_pin_off': 'p',
           'custom_master_track_pin_on': 'P', 'custom_master_track_pin_off': 'p',
           'custom_comping': 'C'}


def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', binascii.crc32(kind + data) & 0xffffffff)


def button_png(glyph, scale):
    size = int(20 * scale)
    pixels = bytearray(size * 3 * size * 4)
    def put(x, y, color):
        i = (y * size * 3 + x) * 4
        pixels[i:i+4] = bytes(color)
    for state in range(3):
        for y in range(size):
            for x in range(size):
                bx, by = x / scale, y / scale
                if bx < 1 or by < 1 or bx >= 19 or by >= 19:
                    c = (24,24,24,255)
                else:
                    shade = (49,63,39)[state]
                    c = (shade,shade,shade,255)
                put(x + state * size, y, c)
        ink = (54,217,190,255) if glyph == 'P' else (210,210,210,255)
        for y, line in enumerate(GLYPHS[glyph]):
            for x, value in enumerate(line):
                if value == '1':
                    for yy in range(int((6+y)*scale), int((7+y)*scale)):
                        for xx in range(int((7+x)*scale), int((8+x)*scale)):
                            put(xx + state * size, yy, ink)
    rows = b''.join(b'\0' + bytes(pixels[y*size*3*4:(y+1)*size*3*4]) for y in range(size))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size*3,size,8,6,0,0,0)) + chunk(b'IDAT', zlib.compress(rows,9)) + chunk(b'IEND',b'')


def write_assets(theme: Path):
    generated = []
    for directory, scale in (('',1), ('150',1.5), ('200',2)):
        root = theme / directory
        for name, glyph in BUTTONS.items():
            path = root / (name + '.png')
            path.write_bytes(button_png(glyph,scale))
            generated.append(path)
        aliases = {'custom_track_folder_recarm': 'track_recarm_off.png'}
        for width in (1,2,3,4,5,7,9,10,14,18):
            aliases[f'custom_track_folder_w{width}'] = 'folder_start.png'
            aliases[f'custom_track_folder_half_w{width}'] = 'folder_end.png'
        for height in (2,3,4,5,7,8,9,10,11,12,13,14,15,17,19,20,21):
            aliases[f'custom_mcp_folder_h{height}'] = 'folder_indent.png'
        aliases['custom_mcp_folder_start'] = 'folder_start.png'
        for target, source in aliases.items():
            original = root / source
            if not original.exists():
                original = theme / source
            path = root / (target + '.png')
            path.write_bytes(original.read_bytes())
            generated.append(path)
    return generated
