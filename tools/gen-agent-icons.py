#!/usr/bin/env python3
"""Flatten provider SVGs to the icon grid. Regeneration needs reportlab; builds do not."""
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

from reportlab.graphics.svgpath import SvgPath

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets/icons/providers'


def flatten(start, controls, output):
    """Subdivide a cubic until the control polygon is within 0.2 grid units of its chord."""
    p0, p1, p2, p3 = start, *controls
    dx, dy = p3[0] - p0[0], p3[1] - p0[1]
    length = math.hypot(dx, dy)
    distance = max(abs(dx * (p[1] - p0[1]) - dy * (p[0] - p0[0])) / length
                   if length else math.dist(p, p0) for p in (p1, p2))
    if distance <= 0.2:
        output.append(p3)
        return
    def midpoint(a, b):
        return tuple((x + y) / 2 for x, y in zip(a, b))
    a, b, c = midpoint(p0, p1), midpoint(p1, p2), midpoint(p2, p3)
    d, e = midpoint(a, b), midpoint(b, c)
    f = midpoint(d, e)
    flatten(p0, (a, d, f), output)
    flatten(f, (e, c, p3), output)


def contours(filename):
    svg = ET.parse(filename).getroot()
    x, y, width, height = map(float, svg.attrib['viewBox'].split())
    scale = 112 / max(width, height)
    result = []

    def close(contour):
        rounded = []
        for point in contour:
            point = tuple(round(v) for v in point)
            if not rounded or point != rounded[-1]:
                rounded.append(point)
        if rounded[-1] == rounded[0]:
            rounded.pop()
        assert 3 <= len(rounded) <= 255
        assert all(0 <= v <= 128 for point in rounded for v in point)
        result.append(rounded)

    for element in svg.iter('{http://www.w3.org/2000/svg}path'):
        path = SvgPath(element.attrib['d'])
        points = iter(zip(path.points[::2], path.points[1::2]))
        contour = []
        for operation in path.operators:
            if operation in (0, 1):  # move, line
                if operation == 0 and contour:
                    close(contour)  # a fill closes a subpath that has no Z
                    contour = []
                px, py = next(points)
                contour.append((64 + (px - x - width / 2) * scale,
                                64 + (py - y - height / 2) * scale))
            elif operation == 2:  # cubic
                controls = [(64 + (px - x - width / 2) * scale,
                             64 + (py - y - height / 2) * scale)
                            for px, py in (next(points), next(points), next(points))]
                flatten(contour[-1], controls, contour)
            else:
                assert operation == 3, operation  # close
                close(contour)
                contour = []
        if contour:
            close(contour)
    return result

data = {name: contours(ASSETS / f'{name.lower()}.svg') for name in ('CLAUDE', 'OPENAI', 'GROK')}
(ASSETS / 'contours.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
