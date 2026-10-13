#!/usr/bin/env python3
"""Flattens the explorer's file icons (assets/icons/files/*.svg, from Seti UI) into
assets/icons/files/contours.json on the 128x128 icon grid; tools/icons.py turns them into icon
programs. Python 3 standard library only.

The SVGs are glyph sources: every shape is filled with one color, as in the Seti font, except that a
white shape cuts out what it covers, as it shows in the SVG. Even-odd paths are reoriented by nesting
depth, since the rasterizer fills nonzero."""
import json
import math
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = ROOT / 'assets/icons/files'
# the 32-unit glyph box maps onto this square of the 128 grid: Seti draws inside a margin of a
# few units, so the box is cut down to make the glyphs about as large as the other icons
BOX = (4.0, 28.0)
TOL = 0.5           # flattening tolerance in grid units (8 to a pixel at 16 px)
SPECK = 16          # contours of a smaller area in square grid units are left out
MAXPTS = 255        # points per contour (the F op's count is a byte)

TOKEN = re.compile(r'[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')


def matmul(a, b):
    return (a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1],
            a[0] * b[2] + a[2] * b[3], a[1] * b[2] + a[3] * b[3],
            a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5])


def transform(text):
    m = (1, 0, 0, 1, 0, 0)
    for name, args in re.findall(r'(\w+)\s*\(([^)]*)\)', text or ''):
        v = [float(x) for x in re.findall(TOKEN, args)]
        if name == 'translate':
            t = (1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0)
        elif name == 'scale':
            t = (v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0)
        elif name == 'matrix':
            t = tuple(v)
        elif name == 'rotate':
            a = math.radians(v[0])
            t = (math.cos(a), math.sin(a), -math.sin(a), math.cos(a), 0, 0)
            if len(v) == 3:
                t = matmul(matmul((1, 0, 0, 1, v[1], v[2]), t), (1, 0, 0, 1, -v[1], -v[2]))
        else:
            raise ValueError('transform ' + name)
        m = matmul(m, t)
    return m


def cubic(out, p0, p1, p2, p3, tol, depth=0):
    """subdivide until the control points are within tol of the chord"""
    dx, dy = p3[0] - p0[0], p3[1] - p0[1]
    length = math.hypot(dx, dy)
    dist = max((abs(dx * (p[1] - p0[1]) - dy * (p[0] - p0[0])) / length) if length else math.dist(p, p0)
               for p in (p1, p2))
    if dist <= tol or depth > 12:
        out.append(p3)
        return
    mid = lambda a, b: ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    a, b, c = mid(p0, p1), mid(p1, p2), mid(p2, p3)
    d, e = mid(a, b), mid(b, c)
    f = mid(d, e)
    cubic(out, p0, a, d, f, tol, depth + 1)
    cubic(out, f, e, c, p3, tol, depth + 1)


def arc(out, p0, rx, ry, rot, large, sweep, p1, tol):
    """SVG endpoint arc to the center form, then points along the ellipse"""
    if p0 == p1:
        return              # an arc that ends where it starts is left out (SVG)
    if not rx or not ry:
        out.append(p1)
        return
    rx, ry = abs(rx), abs(ry)
    phi = math.radians(rot)
    cp, sp = math.cos(phi), math.sin(phi)
    dx, dy = (p0[0] - p1[0]) / 2, (p0[1] - p1[1]) / 2
    x1, y1 = cp * dx + sp * dy, -sp * dx + cp * dy
    lam = (x1 / rx) ** 2 + (y1 / ry) ** 2
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    co = math.sqrt(max(0, num / den)) * (-1 if large == sweep else 1)
    cx1, cy1 = co * rx * y1 / ry, -co * ry * x1 / rx
    cx = cp * cx1 - sp * cy1 + (p0[0] + p1[0]) / 2
    cy = sp * cx1 + cp * cy1 + (p0[1] + p1[1]) / 2
    angle = lambda ux, uy: math.atan2(uy, ux)
    a0 = angle((x1 - cx1) / rx, (y1 - cy1) / ry)
    da = angle((-x1 - cx1) / rx, (-y1 - cy1) / ry) - a0
    if sweep and da < 0:
        da += 2 * math.pi
    elif not sweep and da > 0:
        da -= 2 * math.pi
    # a step whose chord error stays under tol
    r = max(rx, ry)
    step = 2 * math.acos(max(-1, min(1, 1 - tol / r))) if r > tol else math.pi / 2
    n = max(2, math.ceil(abs(da) / max(step, 1e-3)))
    for i in range(1, n + 1):
        a = a0 + da * i / n
        x, y = rx * math.cos(a), ry * math.sin(a)
        out.append((cp * x - sp * y + cx, sp * x + cp * y + cy))


def path_contours(d, tol):
    toks = TOKEN.findall(d)
    i = 0
    contours, cur = [], None
    pos = start = (0.0, 0.0)
    last_c = last_q = None
    cmd = None

    def num():
        nonlocal i
        v = float(toks[i])
        i += 1
        return v

    def flag():
        # arc flags are single digits that may run into the next number ("0 01.5")
        nonlocal i
        t = toks[i]
        if len(t) > 1 and t[0] in '01':
            toks[i] = t[1:]
            return int(t[0])
        i += 1
        return int(float(t))

    while i < len(toks):
        if toks[i][0].isalpha():
            cmd = toks[i]
            i += 1
        elif cmd in ('M', 'm'):
            cmd = 'L' if cmd == 'M' else 'l'    # coordinates after a moveto are linetos
        rel = cmd.islower()
        c = cmd.upper()

        def pt():
            x, y = num(), num()
            return (pos[0] + x, pos[1] + y) if rel else (x, y)

        if c == 'Z':
            if cur:
                contours.append(cur)
            cur = None
            pos = start
            last_c = last_q = None
            continue
        if c == 'M':
            if cur:
                contours.append(cur)
            pos = start = pt()
            cur = [pos]
            last_c = last_q = None
            continue
        if cur is None:
            cur = [pos]
        if c == 'L':
            pos = pt()
            cur.append(pos)
            last_c = last_q = None
        elif c == 'H':
            x = num()
            pos = (pos[0] + x if rel else x, pos[1])
            cur.append(pos)
            last_c = last_q = None
        elif c == 'V':
            y = num()
            pos = (pos[0], pos[1] + y if rel else y)
            cur.append(pos)
            last_c = last_q = None
        elif c in ('C', 'S'):
            if c == 'S':
                p1 = (2 * pos[0] - last_c[0], 2 * pos[1] - last_c[1]) if last_c else pos
            else:
                p1 = pt()
            p2, p3 = pt(), pt()
            cubic(cur, pos, p1, p2, p3, tol)
            pos, last_c, last_q = p3, p2, None
        elif c in ('Q', 'T'):
            if c == 'T':
                q = (2 * pos[0] - last_q[0], 2 * pos[1] - last_q[1]) if last_q else pos
            else:
                q = pt()
            p3 = pt()
            p1 = (pos[0] + 2 / 3 * (q[0] - pos[0]), pos[1] + 2 / 3 * (q[1] - pos[1]))
            p2 = (p3[0] + 2 / 3 * (q[0] - p3[0]), p3[1] + 2 / 3 * (q[1] - p3[1]))
            cubic(cur, pos, p1, p2, p3, tol)
            pos, last_q, last_c = p3, q, None
        elif c == 'A':
            rx, ry, rot = num(), num(), num()
            large, sweep = flag(), flag()
            p1 = pt()
            arc(cur, pos, rx, ry, rot, large, sweep, p1, tol)
            pos = p1
            last_c = last_q = None
        else:
            raise ValueError('path command ' + cmd)
    if cur:
        contours.append(cur)
    return contours


def ellipse(cx, cy, rx, ry, tol):
    r = max(rx, ry)
    step = 2 * math.acos(max(-1, min(1, 1 - tol / r))) if r > tol else math.pi / 2
    n = max(8, math.ceil(2 * math.pi / step))
    return [[(cx + rx * math.cos(2 * math.pi * k / n), cy + ry * math.sin(2 * math.pi * k / n))
             for k in range(n)]]


def area(c):
    return sum(c[k][0] * c[k - 1][1] - c[k - 1][0] * c[k][1] for k in range(len(c))) / 2


def inside(p, c):
    x, y = p
    hit = False
    for k in range(len(c)):
        (x0, y0), (x1, y1) = c[k - 1], c[k]
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            hit = not hit
    return hit


def evenodd(contours):
    """orient contours so nonzero filling gives the even-odd result: by nesting depth"""
    out = []
    for c in contours:
        depth = sum(1 for o in contours if o is not c and inside(c[0], o))
        want = 1 if depth % 2 == 0 else -1
        out.append(c if area(c) * want >= 0 else c[::-1])
    return out


WHITE = ('#fff', '#ffffff', 'white')


def shapes(svg, tol):
    """(contours, fill rule, white) per filled shape, in the user units of the root viewBox"""
    ns = lambda tag: tag.split('}')[-1]
    defs = {e.attrib['id']: e for e in svg.iter() if 'id' in e.attrib}
    out = []

    def style(e, name):
        m = re.search(name + r'\s*:\s*([^;]+)', e.attrib.get('style', ''))
        return m.group(1).strip() if m else e.attrib.get(name)

    def walk(e, m, rule, fill):
        tag = ns(e.tag)
        if tag in ('defs', 'style', 'title', 'desc', 'linearGradient', 'radialGradient', 'clipPath', 'mask'):
            return
        m = matmul(m, transform(e.attrib.get('transform')))
        rule = style(e, 'fill-rule') or rule
        fill = style(e, 'fill') or fill
        # the font ignores colors, so an inherited fill="none" does not hide a shape; a shape's
        # own fill="none" is an outline guide or a background
        if style(e, 'display') == 'none' or (tag not in ('svg', 'g') and style(e, 'fill') == 'none'):
            return
        if tag == 'use':
            ref = e.attrib.get('{http://www.w3.org/1999/xlink}href') or e.attrib.get('href')
            m = matmul(m, (1, 0, 0, 1, float(e.attrib.get('x', 0)), float(e.attrib.get('y', 0))))
            walk(defs[ref[1:]], m, rule, fill)
            return
        scale = math.sqrt(abs(m[0] * m[3] - m[1] * m[2])) or 1
        t = tol / scale
        if tag == 'path':
            cs = path_contours(e.attrib['d'], t)
        elif tag == 'circle':
            r = float(e.attrib['r'])
            cs = ellipse(float(e.attrib.get('cx', 0)), float(e.attrib.get('cy', 0)), r, r, t)
        elif tag == 'ellipse':
            cs = ellipse(float(e.attrib.get('cx', 0)), float(e.attrib.get('cy', 0)),
                         float(e.attrib['rx']), float(e.attrib['ry']), t)
        elif tag in ('rect', 'polygon', 'polyline'):
            if tag == 'rect':
                if '%' in e.attrib.get('width', '') + e.attrib.get('height', ''):
                    return          # a background the size of the canvas
                x, y = float(e.attrib.get('x', 0)), float(e.attrib.get('y', 0))
                w, h = float(e.attrib['width']), float(e.attrib['height'])
                cs = [[(x, y), (x + w, y), (x + w, y + h), (x, y + h)]]
            else:
                v = [float(x) for x in TOKEN.findall(e.attrib['points'])]
                cs = [list(zip(v[::2], v[1::2]))]
        elif tag in ('svg', 'g'):
            for k in e:
                walk(k, m, rule, fill)
            return
        else:
            raise ValueError('element ' + tag)
        cs = [[(m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]) for x, y in c] for c in cs]
        out.append((cs, rule or 'nonzero', (fill or '').strip().lower() in WHITE))

    walk(svg, (1, 0, 0, 1, 0, 0), None, None)
    return out


def winding(p, contours):
    w = 0
    for c in contours:
        if inside(p, c):
            w += 1 if area(c) > 0 else -1
    return w


def glyph(path):
    svg = ET.parse(path).getroot()
    vb = svg.attrib.get('viewBox')
    if vb:
        x, y, w, h = map(float, vb.replace(',', ' ').split())
    else:
        x, y = 0.0, 0.0
        w, h = float(svg.attrib.get('width', 32)), float(svg.attrib.get('height', 32))
    # the viewBox square as the 32-unit glyph box, centered
    size = max(w, h)
    x -= (size - w) / 2
    y -= (size - h) / 2
    lo, hi = BOX
    k = 128 / (hi - lo)
    found = shapes(svg, TOL * size / 32 / k)
    # a glyph that reaches past the box shrinks about the middle until it fits
    units = [((px - x) / size * 32, (py - y) / size * 32) for cs, _, _ in found for c in cs for px, py in c]
    reach = max([16 - v for p in units for v in p] + [v - 16 for p in units for v in p] + [0])
    fit = min(1, (hi - lo) / 2 / reach) if reach else 1

    def grid(p):
        ux, uy = (p[0] - x) / size * 32, (p[1] - y) / size * 32
        return ((16 + (ux - 16) * fit) - lo) * k, ((16 + (uy - 16) * fit) - lo) * k

    # with white shapes, every shape is oriented by nesting and the white ones reversed, so they
    # cancel what they cover; overlapping white shapes would fill again
    cuts = any(white for _, _, white in found)
    if cuts:
        holes = [c for cs, _, white in found if white for c in evenodd(cs)]
        for j in range(64):
            for i in range(64):
                p = (x + (i + .5) * size / 64, y + (j + .5) * size / 64)
                assert winding(p, holes) <= 1, (path.name, 'white shapes overlap')
    result = []
    for cs, rule, white in found:
        cs = [[grid(p) for p in c] for c in cs]
        if rule == 'evenodd' or cuts:
            cs = evenodd(cs)
        if white:
            cs = [c[::-1] for c in cs]
        for c in cs:
            pts = []
            for px, py in c:
                p = (round(px), round(py))
                if not pts or p != pts[-1]:
                    pts.append(p)
            if len(pts) > 1 and pts[-1] == pts[0]:
                pts.pop()
            # points on the line through their neighbors add nothing once rounded
            i = 0
            while len(pts) > 3 and i < len(pts):
                (ax, ay), (bx, by), (cx, cy) = pts[i - 1], pts[i], pts[(i + 1) % len(pts)]
                if (bx - ax) * (cy - ay) == (by - ay) * (cx - ax):
                    del pts[i]
                else:
                    i += 1
            # specks under a quarter pixel at 16 px draw nothing
            if len(pts) < 3 or abs(area(pts)) < SPECK:
                continue
            assert len(pts) <= MAXPTS, (path.name, len(pts))
            assert all(0 <= v <= 255 for p in pts for v in p), (path.name, 'outside the grid')
            result.append(pts)
    return result


def main():
    names = sys.argv[1:] or sorted(p.stem for p in FILES.glob('*.svg'))
    out = FILES / 'contours.json'
    # icons named on the command line replace theirs; the others stay
    data = json.loads(out.read_text()) if sys.argv[1:] and out.exists() else {}
    for name in names:
        data[name] = glyph(FILES / (name + '.svg'))
    data = dict(sorted(data.items()))
    out.write_text(json.dumps(data, separators=(',', ':')) + '\n')
    print('%d icons, %d points' % (len(data), sum(len(c) for v in data.values() for c in v)))


if __name__ == '__main__':
    main()
