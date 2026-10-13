#!/usr/bin/env python3
"""Copy a TrueType font keeping only the tables raftaar reads, optionally only some characters.

usage: mkfont.py src.ttf dst.ttf [RANGES]
RANGES: comma separated hex code points or ranges, e.g. 20-7e,a0-24f,2500-257f.
Without RANGES every glyph is kept. With them, the kept glyphs are those the ranges map to
(plus the parts of composite glyphs), renumbered; cmap becomes a single format 12 table."""
import struct, sys

KEEP = [b'OS/2', b'cmap', b'glyf', b'head', b'hhea', b'hmtx', b'loca', b'maxp', b'name', b'post']


def tables_of(data):
    n = struct.unpack('>H', data[4:6])[0]
    out = {}
    for i in range(n):
        tag, _, off, ln = struct.unpack('>4sIII', data[12 + 16*i:28 + 16*i])
        out[tag] = data[off:off + ln]
    return out


def read_cmap(cmap):
    """code point -> glyph id, from the format 12 or format 4 subtable"""
    n = struct.unpack('>H', cmap[2:4])[0]
    subs = {}
    for i in range(n):
        _, _, off = struct.unpack('>HHI', cmap[4 + 8*i:12 + 8*i])
        subs.setdefault(struct.unpack('>H', cmap[off:off + 2])[0], off)
    m = {}
    if 12 in subs:
        s = subs[12]
        for i in range(struct.unpack('>I', cmap[s + 12:s + 16])[0]):
            a, b, g = struct.unpack('>III', cmap[s + 16 + 12*i:s + 28 + 12*i])
            for c in range(a, b + 1):
                m[c] = g + c - a
        return m
    s = subs[4]
    seg = struct.unpack('>H', cmap[s + 6:s + 8])[0] // 2
    ends = struct.unpack('>%dH' % seg, cmap[s + 14:s + 14 + 2*seg])
    base = s + 16 + 2*seg
    starts = struct.unpack('>%dH' % seg, cmap[base:base + 2*seg])
    deltas = struct.unpack('>%dh' % seg, cmap[base + 2*seg:base + 4*seg])
    ro = base + 4*seg
    offs = struct.unpack('>%dH' % seg, cmap[ro:ro + 2*seg])
    for i in range(seg):
        for c in range(starts[i], ends[i] + 1):
            if c == 0xffff:
                continue
            if offs[i] == 0:
                g = (c + deltas[i]) & 0xffff
            else:
                a = ro + 2*i + offs[i] + 2*(c - starts[i])
                g = struct.unpack('>H', cmap[a:a + 2])[0]
                g = (g + deltas[i]) & 0xffff if g else 0
            if g:
                m[c] = g
    return m


def components(glyph):
    """offsets of the glyph index fields in a composite glyph"""
    if len(glyph) < 10 or struct.unpack('>h', glyph[:2])[0] >= 0:
        return []
    p, out = 10, []
    while True:
        flags = struct.unpack('>H', glyph[p:p + 2])[0]
        out.append(p + 2)
        p += 4 + (4 if flags & 1 else 2)
        p += 2 if flags & 8 else 4 if flags & 0x40 else 8 if flags & 0x80 else 0
        if not flags & 0x20:
            return out


def subset(t, ranges):
    head, hhea, maxp, hmtx = t[b'head'], t[b'hhea'], t[b'maxp'], t[b'hmtx']
    long_loca = struct.unpack('>h', head[50:52])[0]
    count = struct.unpack('>H', maxp[4:6])[0]
    fmt = '>%dI' % (count + 1) if long_loca else '>%dH' % (count + 1)
    loca = struct.unpack(fmt, t[b'loca'][:(count + 1) * (4 if long_loca else 2)])
    if not long_loca:
        loca = [o * 2 for o in loca]
    glyphs = [t[b'glyf'][loca[g]:loca[g + 1]] for g in range(count)]
    nh = struct.unpack('>H', hhea[34:36])[0]
    metrics = []
    for g in range(count):
        adv = struct.unpack('>H', hmtx[4*min(g, nh - 1):4*min(g, nh - 1) + 2])[0]
        lsb = struct.unpack('>h', hmtx[4*g + 2:4*g + 4] if g < nh else hmtx[4*nh + 2*(g - nh):4*nh + 2*(g - nh) + 2])[0]
        metrics.append((adv, lsb))

    cmap = {c: g for c, g in read_cmap(t[b'cmap']).items() if any(a <= c <= b for a, b in ranges)}
    keep, todo = set(), [0] + list(cmap.values())
    while todo:
        g = todo.pop()
        if g not in keep:
            keep.add(g)
            todo += [struct.unpack('>H', glyphs[g][o:o + 2])[0] for o in components(glyphs[g])]
    order = sorted(keep)
    new = {g: i for i, g in enumerate(order)}

    glyf, offsets = bytearray(), []
    for g in order:
        data = bytearray(glyphs[g])
        for o in components(glyphs[g]):
            data[o:o + 2] = struct.pack('>H', new[struct.unpack('>H', data[o:o + 2])[0]])
        offsets.append(len(glyf))
        glyf += data + b'\0' * (-len(data) % 4)
    offsets.append(len(glyf))

    groups = []
    for c in sorted(cmap):
        g = new[cmap[c]]
        if groups and groups[-1][1] == c - 1 and groups[-1][2] + (c - groups[-1][0]) == g:
            groups[-1][1] = c
        else:
            groups.append([c, c, g])
    sub = struct.pack('>HHIII', 12, 0, 16 + 12*len(groups), 0, len(groups))
    sub += b''.join(struct.pack('>III', *g) for g in groups)

    n = len(order)
    t[b'glyf'] = bytes(glyf)
    t[b'loca'] = struct.pack('>%dI' % (n + 1), *offsets)
    t[b'hmtx'] = b''.join(struct.pack('>Hh', *metrics[g]) for g in order)
    t[b'cmap'] = struct.pack('>HHHHI', 0, 1, 3, 10, 12) + sub
    t[b'head'] = head[:50] + struct.pack('>h', 1) + head[52:]
    t[b'hhea'] = hhea[:34] + struct.pack('>H', n) + hhea[36:]
    t[b'maxp'] = maxp[:4] + struct.pack('>H', n) + maxp[6:]
    t[b'post'] = struct.pack('>I', 0x00030000) + t[b'post'][4:32]
    return len(cmap), n


def write(t, dst):
    tags = sorted(tag for tag in t if tag in KEEP)
    out = bytearray(struct.pack('>IHHHH', 0x00010000, len(tags), 0, 0, 0))
    off = 12 + 16 * len(tags)
    body = bytearray()
    for tag in tags:
        data = t[tag]
        pad = data + b'\0' * (-len(data) % 4)
        csum = sum(struct.unpack('>%dI' % (len(pad) // 4), pad)) & 0xffffffff
        out += struct.pack('>4sIII', tag, csum, off + len(body), len(data))
        body += pad
    open(dst, 'wb').write(out + body)


def main(src, dst, ranges=None):
    t = tables_of(open(src, 'rb').read())
    if ranges:
        spans = []
        for part in ranges.split(','):
            a, _, b = part.partition('-')
            spans.append((int(a, 16), int(b or a, 16)))
        chars, glyphs = subset(t, spans)
        print('%s: %d characters, %d glyphs' % (dst, chars, glyphs))
    write(t, dst)


if __name__ == '__main__':
    main(*sys.argv[1:])
