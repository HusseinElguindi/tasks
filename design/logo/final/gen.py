"""Generates the 04 Log app icon masters from one set of geometry.

    uv run --with shapely python design/logo/final/gen.py

Writes, next to this file:
  svg/icon-dark.svg                  1024 master: Big Sur grid, 824 body at 100, mark at full detail
  svg/icon-dark-small.svg            the cut used below 60px: rings become dots, strokes thicken
  svg/mark-dark[-small].svg          the bare mark, no body
  AppIcon.icon/                      Icon Composer document (macOS 26+): background fill and four layers

The icon is dark only: the dark colours are the default in every appearance, light included. Tinted (and clear, which
follows it) has its own greys.

Geometry is in the 1024 canvas used on the design canvas (body 100..924). Everything is filled outlines (no strokes),
so every renderer, Icon Composer included, draws the same thing.
"""
import json
import os
from shapely.geometry import LineString, Point, box
from shapely.ops import unary_union

HERE = os.path.dirname(os.path.abspath(__file__))

COLORS = {
    'dark': {'top': '#2A2A2A', 'bot': '#161616', 'rim': 'rgba(255,255,255,0.10)', 'head': '#2F81F7', 'bar': '#E6EDF3', 'rings': '#A8ADB1', 'trail': '#6D7072'},
}


MONO = {'head': '#FFFFFF', 'bar': '#FFFFFF', 'rings': '#B8B8B8', 'trail': '#7A7A7A'}


def capsule(x, y, w, h):
    r = h / 2
    return LineString([(x + r, y + r), (x + w - r, y + r)]).buffer(r, quad_segs=32)


def check(cx, cy, s, half):
    pts = [(cx - 26 * s, cy + 2 * s), (cx - 8 * s, cy + 20 * s), (cx + 26 * s, cy - 18 * s)]
    return LineString(pts).buffer(half, quad_segs=32, cap_style='round', join_style='round')


def mark(small):
    """The four layers: the head (accent, check cut out), its bar, the older ops' rings, and the trail."""
    if not small:
        # Node centres are spaced so the gaps between node edges are equal (88), and the whole mark is centred on
        # the body both ways.
        cx, head_y, r1, r2, bar_x = 324, 314, 541, 739, 454
        head = Point(cx, head_y).buffer(84, quad_segs=64).difference(check(cx, head_y, 1.45, 11))
        rings = unary_union([Point(cx, y).buffer(55, quad_segs=64).difference(Point(cx, y).buffer(33, quad_segs=64)) for y in (r1, r2)])
        spine = [box(cx - 11, head_y + 84, cx + 11, r1 - 55), box(cx - 11, r1 + 55, cx + 11, r2 - 55)]
        bar = capsule(bar_x, head_y - 24, 330, 48)
        trail = unary_union(spine + [capsule(bar_x, r1 - 18, 260, 36), capsule(bar_x, r2 - 18, 200, 36)])
    else:
        cx, head_y, r1, r2, bar_x = 322, 336, 556, 732, 462
        head = Point(cx, head_y).buffer(100, quad_segs=64).difference(check(cx, head_y, 1.75, 15))
        rings = unary_union([Point(cx, y).buffer(56, quad_segs=64) for y in (r1, r2)])
        spine = [box(cx - 18, head_y + 100, cx + 18, r1 - 56), box(cx - 18, r1 + 56, cx + 18, r2 - 56)]
        bar = capsule(bar_x, head_y - 40, 340, 80)
        trail = unary_union(spine + [capsule(bar_x, r1 - 32, 280, 64), capsule(bar_x, r2 - 32, 220, 64)])
    return {'trail': trail, 'rings': rings, 'bar': bar, 'head': head}


def path_d(geom, xf=lambda x, y: (x, y)):
    def ring(coords):
        pts = [xf(x, y) for x, y in coords]
        return 'M' + 'L'.join('%.2f %.2f' % p for p in pts[:-1]) + 'Z'
    polys = getattr(geom, 'geoms', [geom])
    return ''.join(ring(p.exterior.coords) + ''.join(ring(i.coords) for i in p.interiors) for p in polys)


def squircle(x, y, w, h, r):
    X, Y = x + w, y + h
    k = [1.52866483, 1.08849299, 0.86840701, 0.63149399, 0.07491100, 0.37282401, 0.16905500]
    a, b, c, d, e, f, g = [v * r for v in k]
    f2 = lambda *v: ' '.join('%.2f' % n for n in v)
    return ('M' + f2(x + a, y) + 'H' + f2(X - a) +
            'C' + f2(X - b, y, X - c, y, X - d, y + e) + 'C' + f2(X - f, y + g, X - g, y + f, X - e, y + d) +
            'C' + f2(X, y + c, X, y + b, X, y + a) + 'V' + f2(Y - a) +
            'C' + f2(X, Y - b, X, Y - c, X - e, Y - d) + 'C' + f2(X - g, Y - f, X - f, Y - g, X - d, Y - e) +
            'C' + f2(X - c, Y, X - b, Y, X - a, Y) + 'H' + f2(x + a) +
            'C' + f2(x + b, Y, x + c, Y, x + d, Y - e) + 'C' + f2(x + f, Y - g, x + g, Y - f, x + e, Y - d) +
            'C' + f2(x, Y - c, x, Y - b, x, Y - a) + 'V' + f2(y + a) +
            'C' + f2(x, y + b, x, y + c, x + e, y + d) + 'C' + f2(x + g, y + f, x + f, y + g, x + d, y + e) +
            'C' + f2(x + c, y, x + b, y, x + a, y) + 'Z')


ORDER = ['trail', 'rings', 'bar', 'head']


def layers_svg(m, col):
    return '\n'.join('<path fill="%s" fill-rule="evenodd" d="%s"/>' % (col[k], path_d(m[k])) for k in ORDER)


def icon_svg(m, col):
    body = squircle(100, 100, 824, 824, 185.4)
    rim = squircle(102, 102, 820, 820, 184.5)
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
            '<defs><linearGradient id="b" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs>\n'
            '<path fill="url(#b)" d="%s"/>\n<path fill="none" stroke="%s" stroke-width="4" d="%s"/>\n%s\n</svg>\n'
            % (col['top'], col['bot'], body, col['rim'], rim, layers_svg(m, col)))


def mark_svg(m, col):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="724" height="724" viewBox="150 150 724 724">\n%s\n</svg>\n'
            % layers_svg(m, col))


def hex_to_ic(h):
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return 'srgb:%.5f,%.5f,%.5f,1.00000' % (r, g, b)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)


def main():
    for small in (False, True):
        m = mark(small)
        sfx = '-small' if small else ''
        for look, col in COLORS.items():
            write(os.path.join(HERE, 'svg', 'icon-%s%s.svg' % (look, sfx)), icon_svg(m, col))
            write(os.path.join(HERE, 'svg', 'mark-%s%s.svg' % (look, sfx)), mark_svg(m, col))

    # Icon Composer: the canvas is the body itself (full bleed, the system draws the shape), so the mark is scaled
    # from the 824 body to 1024. One layer per colour; each layer's fill is set per appearance in icon.json.
    m = mark(False)
    s = 1024 / 824
    xf = lambda x, y: ((x - 100) * s, (y - 100) * s)
    names = {'trail': 'trail', 'rings': 'rings', 'bar': 'head-bar', 'head': 'head'}
    ic = os.path.join(HERE, 'AppIcon.icon')
    for k in ORDER:
        write(os.path.join(ic, 'Assets', names[k] + '.svg'),
              '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
              '<path fill="#000000" fill-rule="evenodd" d="%s"/>\n</svg>\n' % path_d(m[k], xf))
    D = COLORS['dark']
    doc = {
        'fill-specializations': [
            {'value': {'linear-gradient': [hex_to_ic(D['top']), hex_to_ic(D['bot'])]}},
        ],
        'groups': [{
            # Icon Composer lists layers front to back.
            'layers': [{
                'fill-specializations': [
                    {'value': {'solid': hex_to_ic(D[k])}},
                    # Tinted is monochrome: the system reads each layer's lightness, so the head and its bar are white
                    # and the history steps down, the same order as in colour. (Icon Composer has no "clear" key.)
                    {'appearance': 'tinted', 'value': {'solid': hex_to_ic(MONO[k])}},
                ],
                'glass': False,
                'hidden': False,
                'image-name': names[k] + '.svg',
                'name': names[k],
            } for k in reversed(ORDER)],
            'shadow': {'kind': 'neutral', 'opacity': 0.3},
            'translucency': {'enabled': False, 'value': 0},
        }],
        'supported-platforms': {'squares': ['macOS']},
    }
    write(os.path.join(ic, 'icon.json'), json.dumps(doc, indent=2) + '\n')


main()
