#!/usr/bin/env python3
# Writes assets/icons/raftaar-256.png, raftaar-512.png and raftaar.icns from assets/icons/raftaar.svg,
# for the launchers and docks that do not draw SVG, and for the macOS app bundle.
# usage: tools/app-icons.py   (needs ImageMagick's magick)
import os
import struct
import subprocess
import tempfile

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
icons = os.path.join(root, 'assets', 'icons')
svg = os.path.join(icons, 'raftaar.svg')


def png(size, path):
    subprocess.run(['magick', '-background', 'none', '-density', '384', svg, '-resize', f'{size}x{size}',
                    '-depth', '8', '-strip', path], check=True)


png(256, os.path.join(icons, 'raftaar-256.png'))
png(512, os.path.join(icons, 'raftaar-512.png'))
# an icns is its PNGs, each under the type of its size
entries = b''
with tempfile.TemporaryDirectory() as tmp:
    for kind, size in ((b'ic07', 128), (b'ic08', 256), (b'ic09', 512), (b'ic10', 1024)):
        path = os.path.join(tmp, f'{size}.png')
        png(size, path)
        data = open(path, 'rb').read()
        entries += kind + struct.pack('>I', len(data) + 8) + data
open(os.path.join(icons, 'raftaar.icns'), 'wb').write(b'icns' + struct.pack('>I', len(entries) + 8) + entries)
