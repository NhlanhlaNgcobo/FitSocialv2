"""Regenerate the Android 12+ splash mark and its pulse animators.

Android 12 replaced the plain launch window with the SplashScreen API, which
draws the launcher icon unless the theme names its own. res/values-v31 points
it at an AnimatedVectorDrawable so the boot image is the wave pulse from the
first frame the OS paints, rather than a static logo that sits there until the
Flutter engine starts.

That drawable has to be a vector, so this traces the mark PNG into paths and
writes the animators from the same constants FitSocialPulseMark uses --- one
source of truth for the timing, so the native pulse and the Dart one are the
same animation and the handoff is invisible.

    python tool/gen_splash_mark.py

Run it from fitsocial_app/ after changing the mark artwork or the pulse. Needs
Pillow (`pip install pillow`); nothing else in the build depends on it.
"""

import os
import sys
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "images", "fitsocial_f_mark.png")
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

# ── Icon canvas ────────────────────────────────────────────────────────────
# A splash icon with no icon background is a 288dp drawable whose content is
# meant to stay inside a 192dp circle. At 145dp the mark peaks at a radius of
# 95.7dp, just inside that, and lands within a few dp of the width the Flutter
# splash draws it at on a normal phone -- so the handoff barely changes size.
VIEWPORT = 288.0
MARK_W = 145.0

# ── Pulse, from FitSocialPulseMark ─────────────────────────────────────────
EXPAND, CONTRACT, STAGGER, REST = 0.55, 0.7, 0.3, 1.3
CYCLE = (STAGGER * 2) + EXPAND + CONTRACT + REST
SCALE_PEAK = 1.10
OPACITY_REST, OPACITY_PEAK = 0.78, 1.0

# PulseMarkGeometry.wavePlate's scale origins, given in the 1254 plate's units,
# and the box the mark occupies inside that plate. Both are converted to the
# trimmed mark's own units below, since that is what the traced paths use.
PLATE_ORIGINS = [(560, 770), (620, 555), (680, 340)]     # bottom, middle, top
PLATE_BOX = (239, 286, 820, 602)                          # x, y, w, h
PLATE_LIFT = -6                                           # plate units at peak

# Bands run bottom-first, as indices into the traced shapes (which come out
# ordered top to bottom): the bottom bar rides with the two accent squares.
BANDS = [("bottom", [3, 2, 4]), ("middle", [1]), ("top", [0])]

DECEL = "@android:interpolator/decelerate_cubic"        # easeOutCubic
INOUT = "@android:interpolator/accelerate_decelerate"   # easeInOutQuad
LINEAR = "@android:interpolator/linear"


# ── Tracing ────────────────────────────────────────────────────────────────
def load_mask(path):
    img = Image.open(path).convert("RGBA")
    w, h = img.size
    px = img.load()
    solid = [[px[x, y][3] > 128 for x in range(w)] for y in range(h)]
    return img, px, solid, w, h


def components(solid, w, h):
    """Four-connected blobs, largest first by area, ordered top to bottom."""
    label = [[-1] * w for _ in range(h)]
    found = []
    for y0 in range(h):
        for x0 in range(w):
            if not solid[y0][x0] or label[y0][x0] >= 0:
                continue
            idx = len(found)
            label[y0][x0] = idx
            queue = deque([(x0, y0)])
            pts = []
            while queue:
                x, y = queue.popleft()
                pts.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and solid[ny][nx] \
                            and label[ny][nx] < 0:
                        label[ny][nx] = idx
                        queue.append((nx, ny))
            found.append(pts)
    found = [c for c in found if len(c) > 40]
    found.sort(key=lambda c: min(p[1] for p in c))
    return found


def outline(pts):
    """Moore-neighbour boundary walk, clockwise from the topmost-leftmost."""
    members = set(pts)
    start = min(pts, key=lambda p: (p[1], p[0]))
    steps = [(-1, 0), (-1, -1), (0, -1), (1, -1),
             (1, 0), (1, 1), (0, 1), (-1, 1)]
    contour = [start]
    cur, back = start, 0
    while True:
        for k in range(1, 9):
            step = steps[(back + k) % 8]
            cand = (cur[0] + step[0], cur[1] + step[1])
            if cand in members:
                back = (steps.index(step) + 4) % 8
                cur = cand
                break
        else:
            break
        if cur == start and len(contour) > 2:
            break
        contour.append(cur)
    return contour


def simplify(points, eps):
    """Ramer-Douglas-Peucker. The mark's corners are barely rounded, so a
    1.2px tolerance holds it to better than 0.997 IoU against the source."""
    if len(points) < 3:
        return points
    (ax, ay), (bx, by) = points[0], points[-1]
    dx, dy = bx - ax, by - ay
    norm = (dx * dx + dy * dy) ** 0.5
    worst, worst_at = -1.0, 0
    for i in range(1, len(points) - 1):
        cx, cy = points[i]
        if norm == 0:
            dist = ((cx - ax) ** 2 + (cy - ay) ** 2) ** 0.5
        else:
            dist = abs(dy * cx - dx * cy + bx * ay - by * ax) / norm
        if dist > worst:
            worst, worst_at = dist, i
    if worst > eps:
        return (simplify(points[:worst_at + 1], eps)[:-1]
                + simplify(points[worst_at:], eps))
    return [points[0], points[-1]]


def trace(path):
    img, px, solid, w, h = load_mask(path)
    shapes = []
    for pts in components(solid, w, h):
        ring = simplify(outline(pts) + [pts[0]], 1.2)
        if ring[-1] == ring[0]:
            ring = ring[:-1]
        data = "M%d,%d" % ring[0] + "".join("L%d,%d" % p for p in ring[1:]) + "Z"

        ys = [p[1] for p in pts]
        top, bottom = min(ys), max(ys)

        def sample(fraction):
            y = int(top + (bottom - top) * fraction)
            row = sorted(x for x, yy in pts if yy == y)
            r, g, b, _ = px[row[len(row) // 2], y]
            return "#%02X%02X%02X" % (r, g, b)

        # Each bar carries its own vertical orange gradient, light to deep.
        shapes.append({"d": data, "top": top, "bottom": bottom,
                       "start": sample(0.06), "end": sample(0.94)})
    return shapes, w, h


# ── Emitting ───────────────────────────────────────────────────────────────
def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)
    print("wrote", os.path.relpath(path, ROOT))


def keyframes(rest, peak, start):
    """One band's value across a full cycle: wait, swell, settle, wait."""
    at = lambda seconds: round(seconds / CYCLE, 6)
    frames = []
    if start > 0:
        frames.append((0.0, rest, LINEAR))
    frames.append((at(start), rest, LINEAR))
    frames.append((at(start + EXPAND), peak, DECEL))
    frames.append((at(start + EXPAND + CONTRACT), rest, INOUT))
    frames.append((1.0, rest, LINEAR))
    return frames


def holder(prop, frames):
    lines = ['    <propertyValuesHolder',
             '        android:propertyName="%s"' % prop,
             '        android:valueType="floatType">']
    lines += ['        <keyframe android:fraction="%s" android:value="%s"'
              ' android:interpolator="%s" />' % f for f in frames]
    lines.append('    </propertyValuesHolder>')
    return "\n".join(lines)


def animator(body):
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<!-- Generated by tool/gen_splash_mark.py; matches '
            'FitSocialPulseMark. -->\n'
            '<objectAnimator '
            'xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:duration="%d"\n'
            '    android:repeatCount="infinite">\n%s\n</objectAnimator>\n'
            % (int(round(CYCLE * 1000)), body))


def main():
    if not os.path.exists(SRC):
        sys.exit("missing artwork: %s" % SRC)

    shapes, mark_w, mark_h = trace(SRC)
    if len(shapes) != 5:
        sys.exit("expected 5 shapes (3 bars + 2 accents), traced %d"
                 % len(shapes))

    scale = MARK_W / mark_w
    tx = (VIEWPORT - MARK_W) / 2
    ty = (VIEWPORT - mark_h * scale) / 2

    box_x, box_y, box_w, box_h = PLATE_BOX
    pivots = [(round((ox - box_x) * mark_w / box_w, 1),
               round((oy - box_y) * mark_h / box_h, 1))
              for ox, oy in PLATE_ORIGINS]
    # The lift is 6 units of a 1254 plate whose mark is box_h tall, expressed
    # as a fraction of the mark's own height.
    lift = round(PLATE_LIFT / box_h * mark_h, 2)

    # The vector.
    out = ['<?xml version="1.0" encoding="utf-8"?>',
           '<!--',
           '    The FitSocial F traced onto a 288dp splash-icon canvas, one group',
           '    per bar, each pivoting where its pulse scales about.',
           '',
           '    Generated by tool/gen_splash_mark.py. Animated by',
           '    splash_pulse_mark.xml; edit those, not this.',
           '-->',
           '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
           '    xmlns:aapt="http://schemas.android.com/aapt"',
           '    android:width="288dp"',
           '    android:height="288dp"',
           '    android:viewportWidth="288"',
           '    android:viewportHeight="288">',
           '',
           '    <!-- Fits the traced %dx%d mark into the icon canvas. -->'
           % (mark_w, mark_h),
           '    <group',
           '        android:name="mark"',
           '        android:translateX="%s"' % round(tx, 2),
           '        android:translateY="%s"' % round(ty, 2),
           '        android:scaleX="%s"' % round(scale, 6),
           '        android:scaleY="%s">' % round(scale, 6),
           '']

    for band_index, (band, indices) in enumerate(BANDS):
        pivot_x, pivot_y = pivots[band_index]
        out += ['        <group',
                '            android:name="band_%s"' % band,
                '            android:pivotX="%s"' % pivot_x,
                '            android:pivotY="%s">' % pivot_y]
        for n, index in enumerate(indices):
            shape = shapes[index]
            out += ['            <path',
                    '                android:name="%s_%d"' % (band, n),
                    '                android:fillAlpha="%s"' % OPACITY_REST,
                    '                android:pathData="%s">' % shape["d"],
                    '                <aapt:attr name="android:fillColor">',
                    '                    <gradient',
                    '                        android:type="linear"',
                    '                        android:startX="0"',
                    '                        android:startY="%d"' % shape["top"],
                    '                        android:endX="0"',
                    '                        android:endY="%d"' % shape["bottom"],
                    '                        android:startColor="%s"' % shape["start"],
                    '                        android:endColor="%s" />' % shape["end"],
                    '                </aapt:attr>',
                    '            </path>']
        out += ['        </group>', '']
    out += ['    </group>', '</vector>', '']
    write(os.path.join(RES, "drawable", "splash_mark.xml"), "\n".join(out))

    # The animators: one per band for the group transform, one for path alpha.
    for band_index, (band, _) in enumerate(BANDS):
        start = band_index * STAGGER
        write(os.path.join(RES, "animator", "splash_pulse_%s.xml" % band),
              animator("\n".join([
                  holder("scaleX", keyframes(1.0, SCALE_PEAK, start)),
                  holder("scaleY", keyframes(1.0, SCALE_PEAK, start)),
                  holder("translateY", keyframes(0.0, lift, start)),
              ])))
        write(os.path.join(RES, "animator", "splash_pulse_%s_alpha.xml" % band),
              animator(holder("fillAlpha",
                              keyframes(OPACITY_REST, OPACITY_PEAK, start))))

    # The animated vector wiring the two together.
    out = ['<?xml version="1.0" encoding="utf-8"?>',
           '<!--',
           "    The app's loading signature as a native splash icon: the three bars",
           '    of the F brighten and swell from the bottom up, on a loop.',
           '',
           '    Same cycle, stagger, scale peak, lift and opacities as',
           '    FitSocialPulseMark, so the pulse the system splash starts is the one',
           '    SplashScreen carries on with once Flutter draws its first frame.',
           '',
           '    Generated by tool/gen_splash_mark.py.',
           '-->',
           '<animated-vector '
           'xmlns:android="http://schemas.android.com/apk/res/android"',
           '    android:drawable="@drawable/splash_mark">',
           '']
    for band, indices in BANDS:
        out += ['    <target',
                '        android:name="band_%s"' % band,
                '        android:animation="@animator/splash_pulse_%s" />' % band]
        # Groups carry no alpha of their own, so each path breathes separately.
        for n in range(len(indices)):
            out += ['    <target',
                    '        android:name="%s_%d"' % (band, n),
                    '        android:animation="@animator/splash_pulse_%s_alpha" />'
                    % band]
        out += ['']
    out += ['</animated-vector>', '']
    write(os.path.join(RES, "drawable", "splash_pulse_mark.xml"), "\n".join(out))


if __name__ == "__main__":
    main()
