#!/usr/bin/env python3
"""Render the Onesimus brand files in this directory, and the PDF reader's favicon.

    uv run --no-project --with fonttools doc/brand/render.py

Needs TeX Live's EB Garamond, found through kpsewhich.
The silhouette is the original Onesimus raster's; the inks are Cogitatum's tokens
and the type is Cogitatum's text face: its support teal carries the field and
its gold edges the V. Shading
borrows the Cogitatum cover's dither, sparingly. Each shadow is printed in a deeper
shade of the colour it falls on, as with a second ink, never in black: light comes
from the upper right, so the V and the sun cast down and left. Below about 48px dots turn to mud, so the small cut is flat.
"""
import math
from pathlib import Path
import re
import subprocess
import urllib.parse

from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent

# Cogitatum site/src/styles/global.css.
INK, SUPPORT, ACCENT, GOLD = '#18242a', '#357873', '#b4432d', '#c29a45'
# Second inks: each surface's own colour, deepened, for its shadow.
SUPPORT_SHADE, ACCENT_SHADE = '#1d4c48', '#7a2b1e'
SLEEVE, NIGHT_INK = '#f7f2e4', '#efe8d8'

# Geometry traced from the original raster logo, on a 750-unit square.
DIAMOND = (375, 332, 322)
CIRCLE = (215, 178, 138)
V = [(130, 105), (320, 105), (320, 150), (275, 150), (275, 385), (520, 150), (465, 150),
     (465, 105), (672, 105), (175, 598), (175, 150), (130, 150)]
BEVEL = [(672, 105), (175, 598), (175, 574), (652, 105)]
SHADOW = (-30, 30)
STEP = 6
MARK_BOX = (40, 0, 670, 670)
ADAPTIVE = f'<style>.word{{fill:{INK}}}@media(prefers-color-scheme:dark){{.word{{fill:{NIGHT_INK}}}}}</style>'


def font(name):
    path = subprocess.run(['kpsewhich', name], capture_output=True, text=True, check=True).stdout.strip()
    return TTFont(path)


def text_path(face, text, size, x, baseline):
    """Outline text so the files render identically without the font installed."""
    cmap, glyphs = face.getBestCmap(), face.getGlyphSet()
    scale = size / face['head'].unitsPerEm
    commands = []
    for char in text:
        name = cmap[ord(char)]
        pen = SVGPathPen(glyphs)
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, baseline)))
        commands.append(pen.getCommands())
        x += glyphs[name].width * scale
    return ''.join(commands), x


def fract(value):
    return value - math.floor(value)


def ign(x, y):
    """Interleaved gradient noise, the dither threshold of Cogitatum's night sky."""
    return fract(52.9829189 * fract(0.06711056 * x + 0.00583715 * y))


def in_v(x, y):
    hit = False
    for (x1, y1), (x2, y2) in zip(V, V[1:] + V[:1]):
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            hit = not hit
    return hit


def in_circle(x, y, grow=0.0):
    cx, cy, r = CIRCLE
    return (x - cx) ** 2 + (y - cy) ** 2 <= (r + grow) ** 2


def dots(density):
    """Square ink dots wherever density beats the threshold, on the cover's pixel grid."""
    out, size = [], STEP * 0.6
    for row in range(700 // STEP):
        for col in range(760 // STEP):
            x, y = col * STEP + STEP / 2, row * STEP + STEP / 2
            if density(x, y) > ign(col, row):
                out.append(f'M{x - size / 2:g} {y - size / 2:g}h{size:g}v{size:g}h-{size:g}z')
    return ''.join(out)


def cast(x, y, casters):
    return any(caster(x - SHADOW[0], y - SHADOW[1]) for caster in casters)


def mark_body(textured):
    cx, cy, r = DIAMOND
    ccx, ccy, cr = CIRCLE
    parts = [f'<path d="M{cx} {cy - r} {cx + r} {cy} {cx} {cy + r} {cx - r} {cy}Z" fill="{SUPPORT}"/>']
    if textured:
        def diamond(x, y):
            if abs(x - cx) + abs(y - cy) > r - STEP:
                return 0
            # The faces turned from the light deepen gently towards the far corner.
            away = max(0.0, ((cx - x) * 0.7 + (y - cy) * 0.7) / r)
            return max(0.22 * away ** 1.4, 0.62 if cast(x, y, (in_v, in_circle)) else 0)
        parts.append(f'<path d="{dots(diamond)}" fill="{SUPPORT_SHADE}"/>')
    parts.append(f'<circle cx="{ccx}" cy="{ccy}" r="{cr}" fill="{ACCENT}" stroke="{SLEEVE}" stroke-width="18"/>')
    if textured:
        def sun(x, y):
            if not in_circle(x, y, -STEP):
                return 0
            # A faint terminator on the side away from the light, plus the V's shadow.
            away = max(0.0, ((ccx - x) * 0.7 + (y - ccy) * 0.7) / cr)
            return max(0.3 * away ** 2, 0.4 if cast(x, y, (in_v,)) else 0)
        parts.append(f'<path d="{dots(sun)}" fill="{ACCENT_SHADE}"/>')
    v = ' '.join(f'{x},{y}' for x, y in V)
    bevel = ' '.join(f'{x},{y}' for x, y in BEVEL)
    parts += [f'<polygon points="{v}" fill="{SLEEVE}"/>',
              f'<polygon points="{bevel}" fill="{GOLD}"/>',
              # The small cut's outline must stay near a pixel wide at 16px.
              f'<polygon points="{v}" fill="none" stroke="{INK}" stroke-width="{7 if textured else 22}"/>']
    return ''.join(parts)


def svg(box, body, extra=''):
    view = ' '.join(f'{value:g}' for value in box)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}" role="img" aria-label="Onesimus">'
            f'<title>Onesimus</title>{extra}{body}</svg>\n')


def main():
    medium = font('EBGaramond-Medium.otf')
    mark, small = mark_body(True), svg(MARK_BOX, mark_body(False))
    (HERE / 'onesimus-mark.svg').write_text(svg(MARK_BOX, mark))
    (HERE / 'onesimus-mark-small.svg').write_text(small)

    greek = 'Ὀνήσιμος'
    natural = text_path(medium, greek, 100, 0, 0)[1]
    word, _ = text_path(medium, greek, 100 * 600 / natural, 75, 765)
    (HERE / 'onesimus-logo.svg').write_text(svg((20, 0, 710, 800), mark + f'<path class="word" d="{word}"/>', ADAPTIVE))
    update_favicon(small)


def update_favicon(mark):
    uri = 'data:image/svg+xml,' + urllib.parse.quote(mark.strip().replace('"', "'"), safe=" =:/,'")
    page = ROOT / 'packages/webpreview.vim/src/webpreview/assets/pdf.html'
    html, count = re.subn(r'<link rel="icon" href="[^\n]*">', lambda _: f'<link rel="icon" href="{uri}">', page.read_text())
    if count != 1:
        raise SystemExit('pdf.html: expected one favicon link')
    page.write_text(html)


if __name__ == '__main__':
    main()
