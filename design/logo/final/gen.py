"""Generates the app icon masters, 02a Lit body, from one set of geometry.

    python3 design/logo/final/gen.py          (export.sh runs it, then renders the PNGs)

The user, 2026-11-08: "let's go with lit body (2a), but when the logo shows in the app, it's a list mark." So the
icon's whole body is a lit Ember tile with a white check, in light and in dark; inside the app the mark is the list
mark, drawn by TileArt itself (app/Tasks/Sidebar/SidebarHeader.swift), so nothing here feeds it.

The finish is the list marks' (app/TasksCore/Sources/TasksTheme/TileArt.swift), at the reference tile's own scale
(docs/feedback/reference-tile.svg): one unit is 1/45.54 of the body's height. Bottom to top:
  halo      0.5 unit just outside the edge, black at HALO (one PNG serves both appearances; see README)
  fill      the flat accent, #E6683D
  light     radial from the top middle, radii 1.4 × width and 1.1 × height, TileArt.light(d) at its 15 stops
  specular  a 1-unit strip along the top, white, TileArt.specularHalf mirrored, at the source's 1-unit amounts (×1.44)
  ring      1 unit just inside the edge, white 10%
  check     white, flat, as a tile's glyph
Below 60px (the small cut) the check is heavier and the ring and strip go, being under a pixel there.

Writes, next to this file (geometry in the 1024 canvas, macOS body 100..924):
  svg/icon.svg, svg/icon-small.svg      the macOS masters (Big Sur grid, 824 body at 100)
  svg/ios.svg, svg/ios-tinted.svg       the iOS 1024 masters (full bleed; the system masks the corners)
  AppIcon.icon/                         the Icon Composer document (macOS 26+): the Ember fill, the finish, the check
No dependencies beyond Python 3: the check is two capsules, whose union a nonzero fill draws.
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

EMBER = '#E6683D'
HALO = 0.18
UNIT = 824 / 45.54          # one reference-tile unit on the macOS body
# The check, on the macOS grid (the canvas's `ember-lit`), and its stroke width: full and the small cut.
CHECK = [(318, 530), (448, 660), (712, 380)]
CHECK_W = {False: 100, True: 120}


def smootherstep(u):
    u = min(max(u, 0), 1)
    return u * u * u * (u * (u * 6 - 15) + 10)


def light(d):
    """TileArt.light: white while positive, black while negative."""
    return 0.216 * (1 - smootherstep(d / 0.58)) if d <= 0.58 else -0.072 * smootherstep((d - 0.58) / 0.42)


LIGHT_LOCATIONS = [0, 0.0725, 0.145, 0.2175, 0.29, 0.3625, 0.435, 0.5075, 0.58, 0.65, 0.72, 0.79, 0.86, 0.93, 1]
SPECULAR_HALF = [0, 0.003, 0.058, 0.111, 0.157, 0.196, 0.226, 0.244, 0.25]


def light_stops():
    out = []
    for d in LIGHT_LOCATIONS:
        if d == 0.58:
            out += ['<stop offset="0.58" stop-color="#FFFFFF" stop-opacity="0"/>', '<stop offset="0.58" stop-color="#000000" stop-opacity="0"/>']
        else:
            a = light(d)
            out.append('<stop offset="%g" stop-color="%s" stop-opacity="%.4f"/>' % (d, '#FFFFFF' if a >= 0 else '#000000', abs(a)))
    return ''.join(out)


def specular_stops():
    alphas = SPECULAR_HALF + SPECULAR_HALF[-2::-1]
    return ''.join('<stop offset="%.4f" stop-color="#FFFFFF" stop-opacity="%.4f"/>' % (i / 16, a * 1.44) for i, a in enumerate(alphas))


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


def body(inset=0):
    """The macOS body (824 at 100, radius 185.4), grown or shrunk by `inset` on every side."""
    w = 824 - 2 * inset
    return squircle(100 + inset, 100 + inset, w, w, 185.4 * w / 824)


def capsule(p, q, r):
    """A segment's stadium: both ends round, so two of them meeting at a point make a round join."""
    (x1, y1), (x2, y2) = p, q
    L = math.hypot(x2 - x1, y2 - y1)
    nx, ny = -(y2 - y1) / L * r, (x2 - x1) / L * r
    f = lambda *v: ' '.join('%.2f' % n for n in v)
    return ('M' + f(x1 + nx, y1 + ny) + 'L' + f(x2 + nx, y2 + ny) + 'A' + f(r, r) + ' 0 0 0 ' + f(x2 - nx, y2 - ny) +
            'L' + f(x1 - nx, y1 - ny) + 'A' + f(r, r) + ' 0 0 0 ' + f(x1 + nx, y1 + ny) + 'Z')


def check_d(small, xf=lambda x, y: (x, y), k=1.0):
    pts = [xf(*p) for p in CHECK]
    r = CHECK_W[small] * k / 2
    return capsule(pts[0], pts[1], r) + capsule(pts[1], pts[2], r)


def defs(cx, top, w, h, sx, sw):
    """The light (radial from the top middle of a body w × h) and the specular strip's gradient (sx .. sx + sw)."""
    return ('<defs><radialGradient id="light" gradientUnits="userSpaceOnUse" cx="0" cy="0" r="1" '
            'gradientTransform="translate(%.2f %.2f) scale(%.2f %.2f)">%s</radialGradient>'
            '<linearGradient id="spec" gradientUnits="userSpaceOnUse" x1="%.2f" y1="0" x2="%.2f" y2="0">%s</linearGradient></defs>'
            % (cx, top, 1.4 * w, 1.1 * h, light_stops(), sx, sx + sw, specular_stops()))


def svg(content):
    return '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n%s\n</svg>\n' % content


def mac_icon(small):
    u = UNIT
    parts = [defs(512, 100, 824, 824, 226, 572),
             '<path fill="none" stroke="#000000" stroke-opacity="%.2f" stroke-width="%.2f" d="%s"/>' % (HALO, u / 2, body(-u / 4)),
             '<path fill="%s" d="%s"/>' % (EMBER, body()),
             '<path fill="url(#light)" d="%s"/>' % body()]
    if not small:
        parts += ['<rect x="226" y="100" width="572" height="%.2f" rx="%.2f" fill="url(#spec)"/>' % (u, u / 2),
                  '<path fill="none" stroke="#FFFFFF" stroke-opacity="0.10" stroke-width="%.2f" d="%s"/>' % (u, body(u / 2))]
    parts.append('<path fill="#FFFFFF" d="%s"/>' % check_d(small))
    return svg('\n'.join(parts))


# iOS and Icon Composer: the canvas is the body itself (full bleed), so the macOS geometry scales from 824 to 1024.
S = 1024 / 824
TO_BLEED = lambda x, y: ((x - 100) * S, (y - 100) * S)


def ios_icon():
    u = UNIT * S
    return svg('\n'.join([
        defs(512, 0, 1024, 1024, 160, 704),
        '<rect width="1024" height="1024" fill="%s"/>' % EMBER,
        '<rect width="1024" height="1024" fill="url(#light)"/>',
        '<rect x="160" y="0" width="704" height="%.2f" rx="%.2f" fill="url(#spec)"/>' % (u, u / 2),
        '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="%.2f" fill="none" stroke="#FFFFFF" stroke-opacity="0.10" stroke-width="%.2f"/>'
        % (u / 2, u / 2, 1024 - u, 1024 - u, 230 - u / 2, u),
        '<path fill="#FFFFFF" d="%s"/>' % check_d(False, TO_BLEED, S)]))


def ios_tinted():
    """iOS 18+ Tinted: a greyscale icon the system tints; the check is the bright part, on black."""
    return svg('<rect width="1024" height="1024" fill="#000000"/>\n<path fill="#FFFFFF" d="%s"/>' % check_d(False, TO_BLEED, S))


def hex_to_ic(h, a=1.0):
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return 'srgb:%.5f,%.5f,%.5f,%.5f' % (r, g, b, a)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)


def main():
    write(os.path.join(HERE, 'svg', 'icon.svg'), mac_icon(False))
    write(os.path.join(HERE, 'svg', 'icon-small.svg'), mac_icon(True))
    write(os.path.join(HERE, 'svg', 'ios.svg'), ios_icon())
    write(os.path.join(HERE, 'svg', 'ios-tinted.svg'), ios_tinted())

    # Icon Composer. The system draws the shape, its edge and shadow; the document gives the fill and two layers.
    ic = os.path.join(HERE, 'AppIcon.icon')
    u = UNIT * S
    write(os.path.join(ic, 'Assets', 'check.svg'), svg('<path fill="#FFFFFF" d="%s"/>' % check_d(False, TO_BLEED, S)))
    write(os.path.join(ic, 'Assets', 'finish.svg'), svg('\n'.join([
        defs(512, 0, 1024, 1024, 160, 704),
        '<rect width="1024" height="1024" fill="url(#light)"/>',
        '<rect x="160" y="0" width="704" height="%.2f" rx="%.2f" fill="url(#spec)"/>' % (u, u / 2)])))
    doc = {
        # Dark is given explicitly: left out, the system draws its own dark (a dark body and an Ember check), and the
        # user asked for the lit body in light and dark.
        'fill-specializations': [{'value': {'solid': hex_to_ic(EMBER)}},
                                 {'appearance': 'dark', 'value': {'solid': hex_to_ic(EMBER)}}],
        'groups': [{
            # Icon Composer lists layers front to back. The finish keeps its own colours (no fill); in Tinted the
            # check is white, the brightest part, as the system reads each layer's lightness.
            'layers': [
                {'fill-specializations': [{'value': {'solid': hex_to_ic('#FFFFFF')}},
                                          {'appearance': 'dark', 'value': {'solid': hex_to_ic('#FFFFFF')}},
                                          {'appearance': 'tinted', 'value': {'solid': hex_to_ic('#FFFFFF')}}],
                 'glass': False, 'hidden': False, 'image-name': 'check.svg', 'name': 'check'},
                {'glass': False, 'hidden': False, 'image-name': 'finish.svg', 'name': 'finish'},
            ],
            'shadow': {'kind': 'neutral', 'opacity': 0.3},
            'translucency': {'enabled': False, 'value': 0},
        }],
        'supported-platforms': {'squares': ['macOS']},
    }
    write(os.path.join(ic, 'icon.json'), json.dumps(doc, indent=2) + '\n')


main()
