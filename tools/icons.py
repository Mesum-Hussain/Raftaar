#!/usr/bin/env python3
"""Generates src/gfx/icondata.s: icon drawing programs on a 128x128 grid (16 px = 128 units), and
the explorer's tables of file icon names and file types; the icon numbers of the SVG icons go into
src/raftaar.inc. Ops: W w | M x y | L x y | O cx cy r (ring) | D cx cy r (disc) | P n x y ... (filled
polygon) | F n x y ... preserves SVG contour winding, including holes."""
import json, math, os

def arc(cx, cy, r, a0, a1, n):
    return [(round(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n))),
             round(cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n)))) for i in range(n + 1)]

def line(pts):
    return [('M',) + pts[0]] + [('L',) + p for p in pts[1:]]

# ---- Hugeicons (MIT, assets/icons/hugeicons): stroked 24x24 icons, as Terax draws its chrome ----
import re as _re
_HUGE = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets/icons/hugeicons/icons.json')))

def _arc_points(x0, y0, rx, ry, phi, large, sweep, x1, y1):
    """an SVG elliptical arc as points after its start (endpoint to center form)"""
    if rx == 0 or ry == 0 or (x0, y0) == (x1, y1):
        return [(x1, y1)]
    rx, ry, ph = abs(rx), abs(ry), math.radians(phi)
    c, sn = math.cos(ph), math.sin(ph)
    dx, dy = (x0 - x1) / 2, (y0 - y1) / 2
    xp, yp = c * dx + sn * dy, -sn * dx + c * dy
    lam = xp * xp / (rx * rx) + yp * yp / (ry * ry)
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = max(0, rx * rx * ry * ry - rx * rx * yp * yp - ry * ry * xp * xp)
    k = math.sqrt(num / (rx * rx * yp * yp + ry * ry * xp * xp)) * (-1 if large == sweep else 1)
    cxp, cyp = k * rx * yp / ry, -k * ry * xp / rx
    cx, cy = c * cxp - sn * cyp + (x0 + x1) / 2, sn * cxp + c * cyp + (y0 + y1) / 2
    a0 = math.atan2((yp - cyp) / ry, (xp - cxp) / rx)
    a1 = math.atan2((-yp - cyp) / ry, (-xp - cxp) / rx)
    da = a1 - a0
    if sweep and da < 0: da += 2 * math.pi
    if not sweep and da > 0: da -= 2 * math.pi
    n = max(2, int(abs(da) / 0.3) + 1)
    return [(cx + rx * math.cos(a0 + da * i / n) * c - ry * math.sin(a0 + da * i / n) * sn,
             cy + rx * math.cos(a0 + da * i / n) * sn + ry * math.sin(a0 + da * i / n) * c) for i in range(1, n + 1)]

def _path_lines(d):
    """the polylines of an SVG path, curves flattened"""
    tok = _re.findall(r'[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?', d)
    i, cmd, x, y, sx, sy, lines, cur, last = 0, None, 0.0, 0.0, 0.0, 0.0, [], None, None
    def num():
        nonlocal i
        i += 1
        return float(tok[i - 1])
    def bez(pts):
        n = 8
        out = []
        for k in range(1, n + 1):
            t, q = k / n, list(pts)
            while len(q) > 1:
                q = [((1 - t) * a[0] + t * b[0], (1 - t) * a[1] + t * b[1]) for a, b in zip(q, q[1:])]
            out.append(q[0])
        return out
    while i < len(tok):
        if _re.match(r'[A-Za-z]', tok[i]):
            cmd = tok[i]; i += 1
            if cmd in 'Zz':
                if cur: cur.append((sx, sy))
                x, y = sx, sy
                last = None
                continue
        rel = cmd.islower()
        c = cmd.upper()
        ox, oy = (x, y) if rel else (0, 0)
        if c == 'M':
            x, y = ox + num(), oy + num()
            sx, sy = x, y
            cur = [(x, y)]; lines.append(cur)
            cmd = 'l' if rel else 'L'
            last = None
        elif c == 'L':
            x, y = ox + num(), oy + num(); cur.append((x, y)); last = None
        elif c == 'H':
            x = ox + num(); cur.append((x, y)); last = None
        elif c == 'V':
            y = oy + num(); cur.append((x, y)); last = None
        elif c == 'C':
            p1 = (ox + num(), oy + num()); p2 = (ox + num(), oy + num()); p3 = (ox + num(), oy + num())
            cur += bez([(x, y), p1, p2, p3]); x, y = p3; last = ('C', p2)
        elif c == 'S':
            p1 = (2 * x - last[1][0], 2 * y - last[1][1]) if last and last[0] == 'C' else (x, y)
            p2 = (ox + num(), oy + num()); p3 = (ox + num(), oy + num())
            cur += bez([(x, y), p1, p2, p3]); x, y = p3; last = ('C', p2)
        elif c == 'Q':
            p1 = (ox + num(), oy + num()); p2 = (ox + num(), oy + num())
            cur += bez([(x, y), p1, p2]); x, y = p2; last = ('Q', p1)
        elif c == 'T':
            p1 = (2 * x - last[1][0], 2 * y - last[1][1]) if last and last[0] == 'Q' else (x, y)
            p2 = (ox + num(), oy + num())
            cur += bez([(x, y), p1, p2]); x, y = p2; last = ('Q', p1)
        elif c == 'A':
            rx, ry, phi, large, sweep = num(), num(), num(), num(), num()
            ex, ey = ox + num(), oy + num()
            cur += _arc_points(x, y, rx, ry, phi, int(large), int(sweep), ex, ey); x, y = ex, ey; last = None
        else:
            raise ValueError(cmd)
    return lines

def huge(name, width=9):
    """a Hugeicons icon as a drawing program: its 24 units over the 128 grid"""
    k = 128 / 24
    g = lambda v: max(0, min(128, round(v * k)))
    ops = [('W', width)]
    for kind, a in _HUGE[name]:
        assert 'fill' not in a or a['fill'] == 'none', name
        if kind == 'circle':
            ops.append(('O', g(float(a['cx'])), g(float(a['cy'])), max(1, round(float(a['r']) * k))))
            continue
        assert kind == 'path', (name, kind)
        for pts in _path_lines(a['d']):
            q = []
            for pt in pts:
                pt = (g(pt[0]), g(pt[1]))
                if not q or q[-1] != pt:
                    q.append(pt)
            if len(q) == 1:
                q.append(q[0])
            ops += line(q)
    return ops


def rrect(x0, y0, x1, y1, r, n=4):
    """a closed rounded rectangle, clockwise from the top left corner's end"""
    pts = (arc(x1 - r, y0 + r, r, -90, 0, n) + arc(x1 - r, y1 - r, r, 0, 90, n)
           + arc(x0 + r, y1 - r, r, 90, 180, n) + arc(x0 + r, y0 + r, r, 180, 270, n))
    return line(pts + [pts[0]])

def poly(pts):
    return line(pts + [pts[0]])

# the outline style of the chrome: thin strokes, round joins and rounded corners
SW = 9
box = rrect(12, 18, 116, 110, 20)
folder = (arc(24, 36, 12, 180, 270, 3) + [(46, 24), (60, 38)] + arc(102, 50, 12, -90, 0, 3)
          + arc(102, 92, 12, 0, 90, 3) + arc(24, 92, 12, 90, 180, 3))
filep = [(34, 12), (72, 12), (102, 42), (102, 104)] + arc(90, 104, 12, 0, 90, 3) + arc(38, 104, 12, 90, 180, 3) \
        + [(26, 24)] + arc(38, 24, 12, 180, 270, 3)
ICONS = [
    ('CHEV_R', huge('ArrowRight01Icon')),
    ('CHEV_D', huge('ArrowDown01Icon')),
    ('FOLDER', huge('Folder01Icon')),
    ('FILE', huge('File01Icon')),
    ('CLOSE', huge('Cancel01Icon')),
    ('SIDEBAR', huge('SidebarLeftIcon')),
    ('PANEL_R',  [('W', SW)] + box + [('M', 80, 18), ('L', 80, 110)]),
    # the settings button: a nut, as Terax's
    ('SLIDERS', huge('Settings01Icon')),
    ('SEARCH', huge('Search01Icon')),
    ('SPARK',    [('P', 8, 64, 8, 74, 54, 120, 64, 74, 74, 64, 120, 54, 74, 8, 64, 54, 54)]),
    ('MIN',      [('W', 8), ('M', 40, 64), ('L', 88, 64)]),
    ('MAX',      [('W', 8)] + rrect(40, 40, 88, 88, 8, 2)),
    ('RESTORE',  [('W', 8)] + rrect(40, 54, 74, 88, 6, 2)
                 + line([(54, 54), (54, 40), (88, 40), (88, 74), (74, 74)])),
    ('WCLOSE',   [('W', 8), ('M', 42, 42), ('L', 86, 86), ('M', 86, 42), ('L', 42, 86)]),
    ('DOT',      [('D', 64, 64, 30)]),
    ('PLUS', huge('PlusSignIcon')),
    ('CHECK',    [('W', 13), ('M', 26, 66), ('L', 54, 94), ('L', 104, 36)]),
    # a window with a prompt in it
    ('TERMINAL', huge('ComputerTerminal02Icon')),
    ('BACK',     [('W', 11), ('M', 106, 64), ('L', 26, 64), ('M', 60, 30), ('L', 26, 64), ('L', 60, 98)]),
    ('USER',     [('W', 10), ('O', 64, 42, 22)] + line(arc(64, 122, 46, -160, -20, 10))),
    ('ARROW_DN', [('W', 10), ('M', 64, 18), ('L', 64, 106), ('M', 30, 72), ('L', 64, 106), ('L', 98, 72)]),
    ('REFRESH', huge('Refresh01Icon')),
    ('CHEV_UP', huge('ArrowUp01Icon')),
    ('CHEV_DN2', huge('ArrowDown01Icon')),
    ('CASE',     [('D', 64, 64, 20)]),
    ('WORD',     [('D', 64, 64, 20)]),
    # the app mark: assets/icons/raftaar.svg's shape, its curves as polygons
    ('RUNE',     [('P', 32, 30, 30, 37, 36, 44, 41, 51, 46, 57, 50, 62, 54, 67, 58, 70, 61, 71, 64, 70, 66, 67, 70, 62, 73, 57, 77, 51, 82, 44, 86, 37, 92, 30, 97, 35, 92, 40, 86, 44, 82, 48, 77, 52, 73, 54, 70, 56, 66, 57, 64, 56, 61, 54, 58, 52, 54, 48, 50, 44, 46, 40, 41, 35, 36), ('P', 4, 57, 95, 97, 95, 97, 98, 57, 98)]),
    ('BRANCH', huge('GitBranchIcon')),
    ('ARROW_UP', [('W', 10), ('M', 64, 110), ('L', 64, 22), ('M', 30, 56), ('L', 64, 22), ('L', 98, 56)]),
    ('MINUS', huge('MinusSignIcon')),
    ('DISCARD',  [('W', 10)] + line(arc(66, 70, 36, 180, 360, 12) + [(102, 98)]) + [('P', 3, 14, 62, 46, 62, 30, 84)]),
    # FILE and FOLDER with a plus at the lower right, their outlines open around it
    ('FILE_PLUS', huge('FileAddIcon')),
    ('FOLDER_PLUS', huge('FolderAddIcon')),
    # ---- the chrome's own ----
    ('HOME', huge('Home03Icon')),
    ('CLOCK', huge('Clock01Icon')),
    # the file tree: a trunk with two leaves
    ('TREE', huge('FolderTreeIcon')),
    ('SPLIT_H',  [('W', SW)] + box + [('M', 64, 18), ('L', 64, 110)]),
    ('SPLIT_V',  [('W', SW)] + box + [('M', 12, 64), ('L', 116, 64)]),
    ('GLOBE',    [('W', SW), ('O', 64, 64, 48), ('M', 16, 64), ('L', 112, 64)] + line(arc(64, 64, 48, -90, 90, 2)[:1]
                 + [(84, 40), (88, 64), (84, 88), (64, 112), (44, 88), (40, 64), (44, 40), (64, 16)])),
    ('IMAGE',    [('W', SW)] + box + [('O', 44, 48, 9)] + line([(14, 96), (48, 70), (72, 90), (90, 76), (114, 94)])),
    ('DOWNLOAD', huge('Download01Icon')),
    ('UPLOAD', huge('Upload01Icon')),
    ('SCM', huge('FolderGitTwoIcon')),
    ('MORE', huge('MoreHorizontalIcon', 12)),
    ('GRAPH',    [('W', SW), ('O', 34, 24, 12), ('O', 34, 104, 12), ('O', 94, 64, 12), ('M', 34, 36), ('L', 34, 92)]
                 + line([(34, 44)] + arc(54, 44, 20, 180, 90, 4) + [(82, 64)])),
]

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
inc = os.path.join(root, 'src/raftaar.inc')
with open(os.path.join(root, 'assets/icons/providers/contours.json')) as source:
    for name, contours in json.load(source).items():
        ICONS.append((name, [('F', len(points), *[v for point in points for v in point])
                            for points in contours]))
# explorer file icons (assets/icons/files, flattened by tools/file-icons.py): F_ and the file's name
FILE_ICONS = {}
with open(os.path.join(root, 'assets/icons/files/contours.json')) as source:
    for name, contours in json.load(source).items():
        FILE_ICONS[name] = len(ICONS)
        ICONS.append(('F_' + name.upper().replace('-', '_'), [('F', len(points), *[v for point in points for v in point])
                                                              for points in contours]))
# icon_mask keys its cache by icon | size << 8
assert len(ICONS) <= 256, len(ICONS)
# the color names of file icons, in the order of their theme slots from T_ICON (src/app/theme.s)
COLORS = ['red', 'orange', 'yellow', 'green', 'blue', 'purple', 'pink', 'cyan', 'grey', 'white']

def file_icon(icon, color, where):
    # as src/app/fileicon.s reads them: names in any case, and gray for grey
    names = {name.lower(): name for name in FILE_ICONS}
    assert icon.lower() in names, '%s: no icon %s' % (where, icon)
    color = 'grey' if color.lower() == 'gray' else color.lower()
    assert color in COLORS, '%s: no color %s' % (where, color)
    return FILE_ICONS[names[icon.lower()]], COLORS.index(color)

# grammars name their icon at run time (icon = name color, grey when the color is left out); check
# the built-in ones here
for f in sorted(os.listdir(os.path.join(root, 'runtime/syntax'))):
    for line in open(os.path.join(root, 'runtime/syntax', f), encoding='utf-8'):
        key, eq, value = line.partition('=')
        words = value.split()
        if eq and key.strip() == 'icon' and words:
            file_icon(words[0], words[1] if len(words) > 1 else 'grey', f)
# types.txt: patterns, then icon and color; whole names first, as file_icon tries them first
types = []
for n, line in enumerate(open(os.path.join(root, 'assets/icons/files/types.txt'), encoding='utf-8')):
    words = line.split()
    if not words or words[0].startswith('#'):
        continue
    icon, color = file_icon(words[-2], words[-1], 'types.txt:%d' % (n + 1))
    for pat in words[:-2]:
        ext = pat.startswith('*.')
        name = pat[2:] if ext else pat
        assert name and '*' not in name and len(name) < 256 and name.isascii(), pat
        types.append((ext, name.lower(), icon, color))
types.sort(key=lambda e: e[0])

def name_bytes(s):
    return ', '.join(str(b) for b in s.encode())

out = ['# vector icon programs, generated by tools/icons.py', '.section .rodata', '.globl icon_table',
       '.p2align 3', 'icon_table:']
out += ['    .quad ic_%s' % n.lower() for n, _ in ICONS]
for name, prog in ICONS:
    b = []
    for c in prog:
        b += [ord(c[0])] + list(c[1:])
    b.append(0)
    assert all(0 <= v <= 255 for v in b), name
    out.append('ic_%s: .byte %s' % (name.lower(), ', '.join(map(str, b))))
# file_icon_names: length, icon, name; a length of 0 ends it
out += ['# file icon names for the grammars\' icon keys: length, icon, name', '.globl file_icon_names',
        'file_icon_names:']
for name, icon in sorted(FILE_ICONS.items()):
    out.append('    .byte %d, %d, %s    # %s' % (len(name), icon, name_bytes(name), name))
out.append('    .byte 0')
# file_types: length, 1 for an extension, icon, color, lowercase name or extension
out += ['# types.txt: length, 1 for an extension (0 for a whole name), icon, color, lowercase pattern',
        '.globl file_types', 'file_types:']
for ext, name, icon, color in types:
    out.append('    .byte %d, %d, %d, %d, %s    # %s' % (len(name), ext, icon, color, name_bytes(name), name))
out.append('    .byte 0')
open(os.path.join(root, 'src/gfx/icondata.s'), 'w').write('\n'.join(out) + '\n')

# icon numbers in src/raftaar.inc: the drawn icons are written by hand there (checked here), the
# others between the markers
BEGIN, END = '# icons from SVG files (tools/icons.py)\n', '# end of the icons from SVG files\n'
text = open(inc).read()
head, rest = text.split(BEGIN)
_, tail = rest.split(END)
import re
for name, value in re.findall(r'^\.equ IC_(\w+), (\d+)', head, re.M):
    assert ICONS[int(value)][0] == name, ('raftaar.inc: IC_%s is not icon %s' % (name, value))
first = len(re.findall(r'^\.equ IC_\w+, \d+', head, re.M))
gen = ['.equ IC_%s, %d\n' % (name, n) for n, (name, _) in enumerate(ICONS) if n >= first]
gen.append('.equ IC_COUNT, %d\n' % len(ICONS))
open(inc, 'w').write(head + BEGIN + ''.join(gen) + END + tail)
