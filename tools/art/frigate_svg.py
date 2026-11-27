#!/usr/bin/env python3
"""Generates the KESTREL-class frigate art and its shape data.

    python3 tools/art/frigate_svg.py
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import

Writes (all from the same geometry, so art, collision, docking hardpoints,
the hangar bay and the deck plan can never drift apart):
    assets/art/ship/frigate_hull.svg     painted hull (pearl plating, details)
    assets/art/ship/frigate_livery.svg   livery stripes in white (tinted at runtime)
    assets/art/ship/frigate_lights.svg   emissive bits (windows, lamps), drawn additive
    scripts/ship/frigate_shape.gd        collision parts + key points (GDScript consts)

Units: the ship is designed in metres, bow = +X, starboard = +Y (Godot's
y-down screen space). SVG units are world pixels (1 m = 10 px) with the ship
origin (its centre of mass) at the SVG origin, so a Sprite2D at scale 1/import
scale lines up with the body without any offset.

Design: an original "civil exploration carrier-frigate" in the station's
palette. A long arrowhead hull (bridge near the bow, rows of warm windows
along the rim) narrows to a waist and flares into the hangar block. The
stern is an open FLIGHT DECK: a 29 m wide landing bay recessed between two
engine arms, where the WREN and the PETREL fly in and set down. Either side
of the hangar block a DRIVE RING hangs on two short pylons: closed hoops with
an emitter channel that lights up when the quantum drive runs (small ships
can thread them). Plating is a low-contrast mosaic of strakes so the hull
reads as huge and built, not flat.
"""
import math
import os
import random

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ART = os.path.join(ROOT, "assets", "art", "ship")
GD = os.path.join(ROOT, "scripts", "ship", "frigate_shape.gd")
PX = 10.0
VIEW = (-860, -480, 1720, 960)

# ----------------------------------------------------------- geometry (m) --
BOW_X = 84.0
# Half beam of the forward hull at x (control points, bow to waist).
PROFILE = [(-18.0, 14.2), (-10.0, 15.2), (0.0, 17.0), (10.0, 18.5), (22.0, 19.2), (32.0, 18.8), (44.0, 17.0),
           (56.0, 14.0), (66.0, 10.4), (74.0, 6.8), (80.0, 3.6), (82.4, 2.3), (83.5, 1.2)]
WAIST_X = -18.0
BLOCK_X0 = -29.0          # hangar block: forward end (after the flare)
BLOCK_HW = 18.0
STERN_X = -66.0
BAY_X1 = -37.0            # bay front wall (the hangar door is here)
BAY_HW = 14.5             # bay half width: a 29 m wide flight deck
LOOP_C = (-38.0, 34.0)    # starboard drive ring centre
LOOP_A = 30.0             # outer semi-axis fore/aft
LOOP_B = 10.4             # outer semi-axis across
LOOP_T = 3.4              # band thickness
PYLONS = [(-35.0, -29.5), (-52.0, -46.0)]   # x spans of the two ring pylons
PAD_X = -51.5
PAD_Y = 7.25
PAD_SIZE = (17.0, 11.0)
BRIDGE = (58.0, 0.0)


def _pchip_slopes(xs, ys):
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    m[0], m[-1] = d[0], d[-1]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] <= 0.0:
            m[i] = 0.0
        else:
            w1 = 2 * h[i] + h[i - 1]
            w2 = h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    return m


_PX = [p[0] for p in PROFILE]
_PY = [p[1] for p in PROFILE]
_PM = _pchip_slopes(_PX, _PY)


def hw(x):
    """Half beam of the main body at x (smooth, shape-preserving)."""
    if x >= BOW_X:
        return 0.0
    if x >= _PX[-1]:
        # rounded nose: a quarter ellipse from the last control point to the tip
        t = (x - _PX[-1]) / (BOW_X - _PX[-1])
        return _PY[-1] * math.sqrt(max(0.0, 1.0 - t * t))
    if x <= BLOCK_X0:
        return BLOCK_HW
    if x <= WAIST_X:
        t = (x - BLOCK_X0) / (WAIST_X - BLOCK_X0)
        return BLOCK_HW + (_PY[0] - BLOCK_HW) * t
    i = 0
    while i < len(_PX) - 2 and x > _PX[i + 1]:
        i += 1
    h = _PX[i + 1] - _PX[i]
    t = (x - _PX[i]) / h
    h00 = 2 * t ** 3 - 3 * t ** 2 + 1
    h10 = t ** 3 - 2 * t ** 2 + t
    h01 = -2 * t ** 3 + 3 * t ** 2
    h11 = t ** 3 - t ** 2
    return h00 * _PY[i] + h10 * h * _PM[i] + h01 * _PY[i + 1] + h11 * h * _PM[i + 1]


def side_points(x0, x1, step):
    """Starboard rim points from x1 down to x0 (bow to stern order)."""
    pts = []
    x = x1
    while x > x0 + 1e-6:
        pts.append((x, hw(x)))
        x -= step
    pts.append((x0, hw(x0)))
    return pts


def forward_side(step=1.5):
    """Starboard rim of the forward hull, tip to waist."""
    pts = [(BOW_X, 0.0)]
    for x in (83.85, 83.5, 83.0, 82.4, 81.4):
        pts.append((x, hw(x)))
    pts += side_points(WAIST_X, 80.0, step)
    return pts


def body_outline(step=1.5):
    """The main body's silhouette (hull + hangar block, with the bay notch)."""
    s = forward_side(step)
    s += [(BLOCK_X0, BLOCK_HW), (-63.0, BLOCK_HW), (STERN_X, 16.4), (STERN_X, BAY_HW), (BAY_X1, BAY_HW)]
    return s + [(x, -y) for x, y in reversed(s[1:])]


def hull_only(step=1.5):
    """The forward hull + block as one solid (no bay notch): plating clip."""
    s = forward_side(step) + [(BLOCK_X0, BLOCK_HW), (-63.0, BLOCK_HW), (STERN_X, 16.4)]
    return s + [(x, -y) for x, y in reversed(s[1:])]


def ellipse(c, a, b, n, a0=0.0):
    return [(c[0] + a * math.cos(a0 + 2 * math.pi * i / n), c[1] + b * math.sin(a0 + 2 * math.pi * i / n)) for i in range(n)]


def loop_outer(side, n=64):
    return ellipse((LOOP_C[0], LOOP_C[1] * side), LOOP_A, LOOP_B, n)


def loop_inner(side, n=64):
    return ellipse((LOOP_C[0], LOOP_C[1] * side), LOOP_A - LOOP_T, LOOP_B - LOOP_T, n)


def loop_mid(side, n=40):
    return ellipse((LOOP_C[0], LOOP_C[1] * side), LOOP_A - LOOP_T * 0.5, LOOP_B - LOOP_T * 0.5, n)


def loop_pieces(side, n=16):
    """The ring as n convex quads (collision)."""
    o = loop_outer(side, n)
    i = loop_inner(side, n)
    return [[o[k], o[(k + 1) % n], i[(k + 1) % n], i[k]] for k in range(n)]


def loop_y_at(x):
    """Outer edge of the starboard ring facing the hull, at x."""
    t = (x - LOOP_C[0]) / LOOP_A
    return LOOP_C[1] - LOOP_B * math.sqrt(max(0.0, 1.0 - t * t))


def pylon(side, k):
    x0, x1 = PYLONS[k]
    return [(x0, 16.8 * side), (x1, 16.8 * side), (x1 - 0.8, (loop_y_at(x1) + 1.6) * side), (x0 + 0.8, (loop_y_at(x0) + 1.6) * side)]


def arm(side):
    return [(BAY_X1, BAY_HW * side), (BAY_X1, BLOCK_HW * side), (-63.0, BLOCK_HW * side), (STERN_X, 16.4 * side), (STERN_X, BAY_HW * side)]


def mirror_y(pts):
    return [(x, -y) for x, y in pts]


def slab(x0, x1, step=4.0):
    """Convex slice of the forward hull between x0 < x1 (both sides)."""
    xs = []
    x = x1
    while x > x0 + 1e-6:
        xs.append(x)
        x -= step
    xs.append(x0)
    top = [(x, hw(x)) for x in xs]
    return convex_hull(top + mirror_y(top))


def convex_hull(pts):
    pts = sorted(set((round(x, 3), round(y, 3)) for x, y in pts))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def bow_part():
    tip = [(BOW_X, 0.0), (83.5, hw(83.5)), (82.4, hw(82.4)), (80.0, hw(80.0))]
    return convex_hull(tip + mirror_y(tip) + slab(22.0, 76.0, 6.0))


# Key points (m), starboard side; port is the mirror image.
CLAMP_FWD_X = 26.0
AIRLOCK_X = 12.0
CLAMP_FWD = (CLAMP_FWD_X, hw(CLAMP_FWD_X))
CLAMP_AFT = (LOOP_C[0], LOOP_C[1] + LOOP_B)
AIRLOCK = (AIRLOCK_X, hw(AIRLOCK_X))
IMPULSE_Y = [15.45, 17.0]
RCS_BOW = [(68.0, hw(68.0) - 0.9), (30.0, hw(30.0) - 1.0)]
RCS_STERN = [(-58.0, BLOCK_HW - 0.9), (LOOP_C[0] - LOOP_A + 2.6, LOOP_C[1])]
RCS_FORE = (77.0, 2.6)
RCS_AFT = (LOOP_C[0] - LOOP_A + 0.6, LOOP_C[1])


# ------------------------------------------------------------- svg utils --
def P(p):
    return "%.1f,%.1f" % (p[0] * PX, p[1] * PX)


def path(pts, fill="none", stroke=None, sw=0.0, op=1.0, extra=""):
    d = "M" + " L".join(P(p) for p in pts) + " Z"
    s = '<path d="%s" fill="%s"' % (d, fill)
    if stroke:
        s += ' stroke="%s" stroke-width="%.2f" stroke-linejoin="round"' % (stroke, sw)
    if op < 1.0:
        s += ' opacity="%.3f"' % op
    return s + extra + "/>"


def ring_path(outer, inner, fill, stroke=None, sw=0.0, op=1.0):
    d = "M" + " L".join(P(p) for p in outer) + " Z M" + " L".join(P(p) for p in inner) + " Z"
    s = '<path d="%s" fill="%s" fill-rule="evenodd"' % (d, fill)
    if stroke:
        s += ' stroke="%s" stroke-width="%.2f" stroke-linejoin="round"' % (stroke, sw)
    if op < 1.0:
        s += ' opacity="%.3f"' % op
    return s + "/>"


def polyline(pts, stroke, sw, op=1.0, cap="round", closed=False):
    d = "M" + " L".join(P(p) for p in pts) + (" Z" if closed else "")
    return '<path d="%s" fill="none" stroke="%s" stroke-width="%.2f" stroke-linecap="%s" stroke-linejoin="round" opacity="%.3f"/>' % (d, stroke, sw, cap, op)


def line(a, b, stroke, sw, op=1.0):
    return polyline([a, b], stroke, sw, op)


def rect_c(c, w, h, rot_deg, fill, op=1.0, rx=0.0, stroke=None, sw=0.0):
    """Rect of w x h metres centred on c, rotated."""
    x, y = c[0] * PX, c[1] * PX
    s = '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%.1f" fill="%s" opacity="%.3f"' % (
        -w * PX * 0.5, -h * PX * 0.5, w * PX, h * PX, rx * PX, fill, op)
    if stroke:
        s += ' stroke="%s" stroke-width="%.2f"' % (stroke, sw)
    return s + ' transform="translate(%.1f %.1f) rotate(%.2f)"/>' % (x, y, rot_deg)


def rect_xy(x0, y0, x1, y1, fill, op=1.0, rx=0.0, stroke=None, sw=0.0):
    return rect_c(((x0 + x1) * 0.5, (y0 + y1) * 0.5), abs(x1 - x0), abs(y1 - y0), 0, fill, op, rx, stroke, sw)


def circle(c, r, fill, op=1.0, stroke=None, sw=0.0):
    s = '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" opacity="%.3f"' % (c[0] * PX, c[1] * PX, r * PX, fill, op)
    if stroke:
        s += ' stroke="%s" stroke-width="%.2f"' % (stroke, sw)
    return s + "/>"


def text(c, s, size_m, fill, op=1.0, rot=0.0, weight=700, spacing=0.0):
    return ('<text x="0" y="0" font-family="Helvetica, Arial, sans-serif" font-size="%.1f" font-weight="%d" '
            'letter-spacing="%.1f" text-anchor="middle" dominant-baseline="central" fill="%s" opacity="%.3f" '
            'transform="translate(%.1f %.1f) rotate(%.2f)">%s</text>') % (
        size_m * PX, weight, spacing * PX, fill, op, c[0] * PX, c[1] * PX, rot, s)


def svg(body, defs=""):
    x, y, w, h = VIEW
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%d %d %d %d">\n'
            '<defs>%s</defs>\n%s\n</svg>\n') % (w, h, x, y, w, h, defs, "\n".join(body))


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


DEFS = """
<linearGradient id="pearl" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#F7F9FB"/><stop offset="0.55" stop-color="#E6ECF1"/><stop offset="1" stop-color="#C4CED9"/>
</linearGradient>
<linearGradient id="shade" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.5"/><stop offset="0.42" stop-color="#FFFFFF" stop-opacity="0"/>
  <stop offset="0.62" stop-color="#0A1424" stop-opacity="0"/><stop offset="1" stop-color="#0A1424" stop-opacity="0.34"/>
</linearGradient>
<linearGradient id="ring" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#DCE3EA"/><stop offset="0.5" stop-color="#B4BFCC"/><stop offset="1" stop-color="#8794A5"/>
</linearGradient>
<linearGradient id="grey" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#DCE3EA"/><stop offset="1" stop-color="#A5B1BF"/>
</linearGradient>
<linearGradient id="deck" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" stop-color="#1A2330"/><stop offset="1" stop-color="#27344A"/>
</linearGradient>
<radialGradient id="dome" cx="0.4" cy="0.35" r="0.7">
  <stop offset="0" stop-color="#4C86A8"/><stop offset="0.6" stop-color="#1D3557"/><stop offset="1" stop-color="#0E1C30"/>
</radialGradient>
<radialGradient id="halo" cx="0.5" cy="0.5" r="0.5">
  <stop offset="0" stop-color="#FFFFFF" stop-opacity="1"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
</radialGradient>
<clipPath id="hullclip"><path d="%s"/></clipPath>
""" % ("M" + " L".join(P(p) for p in hull_only()) + " Z")

INK = "#3E4A5A"
SEAM = "#AEB9C6"
NAVY = "#1D3557"
TEAL = "#2A9D8F"
DARK = "#1B2635"
WARM = "#FFE2A0"
AMBER = "#FFB000"


# ------------------------------------------------------------------ hull --
def hull_layer(rng):
    b = []
    # ---- drop-in order: pylons, drive rings, main body
    for side in (1, -1):
        for k in range(2):
            py = pylon(side, k)
            b.append(path(py, "url(#grey)", INK, 2.6))
            b.append(line(lerp(py[0], py[1], 0.5), lerp(py[3], py[2], 0.5), NAVY, 9.0, 0.9))
            b.append(line(lerp(py[0], py[1], 0.5), lerp(py[3], py[2], 0.5), TEAL, 2.0, 0.9))
            for t in (0.35, 0.7):
                b.append(line(lerp(py[0], py[3], t), lerp(py[1], py[2], t), SEAM, 1.3, 0.9))
    for side in (1, -1):
        b += ring_art(side)
    body = body_outline()
    solid = hull_only()
    b.append(path(solid, "url(#pearl)"))
    b.append('<g clip-path="url(#hullclip)">')
    b += plating(rng)
    b += block_plating(rng)
    b.append("</g>")
    b.append(path(solid, "url(#shade)"))
    # rim band (a slightly darker bevel just inside the edge)
    rim_o = forward_side()
    rim_i = [(x - 0.2, max(0.0, y - 0.85)) for x, y in rim_o]
    for s in (1, -1):
        band = [(x, y * s) for x, y in rim_o] + [(x, y * s) for x, y in reversed(rim_i)]
        b.append(path(band, "#B9C4D0", None, 0, 0.85))
    b += hull_details(rng)
    b += bay_art()
    b += arm_art()
    b.append(path(body, "none", INK, 3.4))
    inner = [(x - 0.25 if x > 0 else x, y - 0.42 if y > 0 else y + 0.42) for x, y in forward_side()[3:]]
    b.append(polyline(inner, "#FFFFFF", 1.5, 0.5))
    b.append(polyline(mirror_y(inner), "#FFFFFF", 1.5, 0.3))
    return b


def plating(rng):
    """Low-contrast strake mosaic on the forward hull: rows that follow the
    rim, bricks staggered row to row (reads as built plating)."""
    out = []
    tones = ["#EEF2F6", "#E4EAF0", "#F4F7FA", "#DCE4EB", "#E9EEF3", "#E1E8EE"]
    rows = [0.0, 0.17, 0.33, 0.48, 0.62, 0.74, 0.84, 0.92, 0.975]
    for side in (1, -1):
        for ri in range(len(rows) - 1):
            f0, f1 = rows[ri], rows[ri + 1]
            x = 82.0 - rng.random() * 3.0
            while x > WAIST_X - 12.0:
                ln = rng.uniform(3.4, 6.6) * (1.0 + 0.5 * (1.0 - f1))
                x1 = x - ln
                q = []
                n = 3
                for k in range(n + 1):
                    xx = x + (x1 - x) * k / n
                    q.append((xx, f0 * hw(xx) * side))
                for k in range(n, -1, -1):
                    xx = x + (x1 - x) * k / n
                    q.append((xx, f1 * hw(xx) * side))
                if rng.random() < 0.86:
                    out.append(path(q, rng.choice(tones), SEAM, 0.9, 0.95))
                else:
                    out.append(path(q, "#D3DBE3", SEAM, 0.9, 0.95))
                    cx = (x + x1) * 0.5
                    out.append(circle((cx, (f0 + f1) * 0.5 * hw(cx) * side), 0.18, "#9AA6B4"))
                x = x1
    return out


def block_plating(rng):
    """Panel grid on the hangar block's roof (either side of the bay)."""
    out = []
    for x in range(-66, -29, 4):
        for yy in (15.3, 16.9):
            for s in (1, -1):
                tone = rng.choice(["#E9EEF3", "#E1E8EE", "#F2F5F8", "#D8E0E8"])
                out.append(rect_c((x + 2.0, yy * s), 3.8, 1.5, 0, tone, 0.95, 0.1, SEAM, 0.8))
    for x in range(-37, -29, 4):
        for k in range(-7, 8):
            tone = rng.choice(["#E9EEF3", "#E1E8EE", "#F2F5F8", "#D8E0E8"])
            out.append(rect_c((x + 2.0, k * 2.1), 3.8, 2.0, 0, tone, 0.95, 0.1, SEAM, 0.8))
    return out


def hull_details(rng):
    b = []
    # sensor strip: a dark band with a pale core that follows the rim (forward arc)
    for s in (1, -1):
        strip = [(x, 0.66 * hw(x) * s) for x in [72 - k * 2.0 for k in range(20)]]
        b.append(polyline(strip, "#3A4656", 6.0, 0.9))
        b.append(polyline(strip, "#9FB3C8", 1.8, 0.9))
    # dorsal spine from the bridge to the hangar block
    b.append(path([(50.0, -2.6), (50.0, 2.6), (-28.0, 4.6), (-28.0, -4.6)], "url(#grey)", INK, 1.6))
    b.append(path([(50.0, -2.6), (50.0, 0.0), (-28.0, 0.0), (-28.0, -4.6)], "#F4F7FA", None, 0, 0.55))
    b.append(polyline([(49.0, 0.0), (-27.0, 0.0)], NAVY, 3.2, 0.95))
    b.append(polyline([(49.0, 0.0), (-27.0, 0.0)], "#7FE6FF", 0.8, 0.8))
    for x in range(-24, 49, 4):
        w = 2.5 + (50.0 - x) / 78.0 * 1.9
        b.append(line((x, -w), (x, -0.8), "#9AA6B4", 0.9))
        b.append(line((x, 0.8), (x, w), "#9AA6B4", 0.9))
    # radiator fins either side of the spine, over engineering
    for s in (1, -1):
        for x in range(-26, -6, 2):
            b.append(line((x, 6.0 * s), (x, 11.0 * s), "#8E9AA8", 1.1, 0.9))
        b.append(path([(-6.0, 5.6 * s), (-6.0, 11.4 * s), (-27.0, 11.4 * s), (-27.0, 5.6 * s)], "none", "#6D7A8A", 1.3))
    # bridge module + dome
    bx = BRIDGE[0]
    b.append('<ellipse cx="%.1f" cy="0" rx="%.1f" ry="%.1f" fill="url(#grey)" stroke="%s" stroke-width="2.4"/>' % (bx * PX, 8.0 * PX, 5.6 * PX, INK))
    b.append('<ellipse cx="%.1f" cy="0" rx="%.1f" ry="%.1f" fill="#E9EEF3" stroke="#AEB9C6" stroke-width="1.2"/>' % ((bx + 0.5) * PX, 6.2 * PX, 4.1 * PX))
    b.append(circle((bx + 1.0, 0.0), 3.0, "url(#dome)", 1.0, "#0E1C30", 1.6))
    b.append(circle((bx, -0.9), 0.9, "#FFFFFF", 0.22))
    # navigational deflector: a dark crescent housing in the nose (glows at runtime)
    hous = [(77.0 + 2.6 * math.cos(a), 4.2 * math.sin(a)) for a in [math.radians(d) for d in range(-70, 71, 10)]]
    hous += [(75.2 + 1.5 * math.cos(a), 3.2 * math.sin(a)) for a in [math.radians(d) for d in range(70, -71, -10)]]
    b.append(path(hous, "#2B3440", INK, 1.2))
    # escape pods (pairs) along the flanks
    for x in range(-12, 62, 7):
        for s in (1, -1):
            y = 0.8 * hw(x + 0.0) * s
            p1 = (x + 0.4, 0.8 * hw(x + 0.4) * s)
            ang = math.degrees(math.atan2(p1[1] - y, 0.4))
            if abs(x - CLAMP_FWD_X) < 4.0 or abs(x - AIRLOCK_X) < 4.0:
                continue
            b.append(rect_c((x, y), 1.5, 0.95, ang, "#8693A3", 1.0, 0.25, INK, 0.8))
    # RCS quads
    for p in RCS_BOW + [RCS_STERN[0]]:
        for s in (1, -1):
            b.append(rect_c((p[0], p[1] * s), 1.4, 1.4, 0, "#5C6878", 1.0, 0.2, INK, 0.8))
            b.append(circle((p[0], p[1] * s), 0.35, "#2B3440"))
    for s in (1, -1):
        b.append(rect_c((RCS_FORE[0], RCS_FORE[1] * s), 1.2, 1.2, 0, "#5C6878", 1.0, 0.2, INK, 0.8))
    # docking hardpoints (both sides) + airlock hatches
    for s in (1, -1):
        b += hardpoint((CLAMP_FWD[0], (CLAMP_FWD[1] - 1.9) * s))
        a = (AIRLOCK[0], (AIRLOCK[1] - 1.0) * s)
        b.append(rect_c(a, 3.0, 1.6, 0, "#C9D2DC", 1.0, 0.3, INK, 1.2))
        b.append(rect_c(a, 2.0, 0.7, 0, "#2B3440", 1.0, 0.15))
        b.append(rect_c((a[0], a[1] - 1.0 * s), 3.4, 0.35, 0, AMBER, 0.9))
    # forward "keel" chevrons in navy
    for s in (1, -1):
        b.append(polyline([(74.0, 0.8 * s), (68.0, 3.6 * s), (60.0, 5.6 * s)], NAVY, 3.0, 0.75))
    # the flare: where the hull widens into the hangar block (structural ribs)
    for s in (1, -1):
        for k in range(4):
            x = WAIST_X - 1.5 - k * 2.6
            b.append(line((x, 5.5 * s), (x, (hw(x) - 1.0) * s), "#9AA6B4", 1.0, 0.8))
    return b


def hardpoint(c):
    """Clamp hardpoint: a reinforced square with hazard chevrons."""
    b = [rect_c(c, 3.2, 3.2, 0, "#2B3440", 1.0, 0.3, INK, 1.2)]
    for k in range(4):
        x = c[0] - 1.2 + k * 0.8
        b.append(polyline([(x, c[1] - 1.3), (x + 0.6, c[1] + 1.3)], AMBER, 2.2, 0.95, "butt"))
    b.append(rect_c(c, 1.4, 1.4, 0, "#5C6878", 1.0, 0.2, "#11161E", 0.8))
    b.append(circle(c, 0.35, "#9AA6B4"))
    return b


def ring_art(side):
    """A drive ring: a hull-grey hoop with a dark emitter channel along its
    middle (lit and animated by FrigateVisuals) and radial panel seams."""
    b = []
    o = loop_outer(side)
    i = loop_inner(side)
    b.append(ring_path(o, i, "url(#ring)", INK, 2.8))
    b.append(polyline(loop_mid(side, 64), "#13223A", 13.0, 1.0, "round", True))
    b.append(polyline(loop_mid(side, 64), "#2E4565", 1.2, 0.9, "round", True))
    n = 40
    for k in range(n):
        a = 2 * math.pi * (k + 0.5) / n
        c = (LOOP_C[0], LOOP_C[1] * side)
        p0 = (c[0] + (LOOP_A - 0.35) * math.cos(a), c[1] + (LOOP_B - 0.35) * math.sin(a))
        p1 = (c[0] + (LOOP_A - LOOP_T + 0.35) * math.cos(a), c[1] + (LOOP_B - LOOP_T + 0.35) * math.sin(a))
        b.append(line(p0, lerp(p0, p1, 0.24), "#8794A5", 1.2))
        b.append(line(lerp(p0, p1, 0.76), p1, "#8794A5", 1.2))
    # reinforced collars where the pylons meet the ring, and at the two tips
    for x in (LOOP_C[0] - LOOP_A + 1.7, LOOP_C[0] + LOOP_A - 1.7):
        b.append(rect_c((x, LOOP_C[1] * side), 3.0, 4.6, 0, "#5C6878", 1.0, 0.5, INK, 1.2))
        b.append(rect_c((x, LOOP_C[1] * side), 1.2, 3.2, 0, "#2B3440", 1.0, 0.3))
    # aft hardpoint on the outer face
    b += hardpoint((CLAMP_AFT[0], (CLAMP_AFT[1] - 1.7) * side))
    return b


def bay_art():
    """The flight deck: a dark recessed deck with two landing pads, a centre
    line, hazard chevrons at the mouth and the hangar door in the front wall."""
    b = []
    b.append(rect_xy(STERN_X, -BAY_HW, BAY_X1, BAY_HW, "url(#deck)"))
    # deck plates
    for x in range(int(STERN_X), int(BAY_X1), 3):
        b.append(line((x, -BAY_HW + 0.4), (x, BAY_HW - 0.4), "#34445C", 0.8, 0.8))
    for k in range(-4, 5):
        b.append(line((STERN_X, k * 3.0), (BAY_X1, k * 3.0), "#34445C", 0.8, 0.6))
    # shadow under the walls (the deck sits below the hull's roof line)
    b.append(rect_xy(BAY_X1 - 2.2, -BAY_HW, BAY_X1, BAY_HW, "#05080E", 0.5))
    b.append(rect_xy(STERN_X, -BAY_HW, BAY_X1, -BAY_HW + 1.6, "#05080E", 0.42))
    b.append(rect_xy(STERN_X, BAY_HW - 0.8, BAY_X1, BAY_HW, "#05080E", 0.2))
    # mouth: hazard chevrons
    for k in range(-9, 9):
        y = k * 1.6 + 0.2
        b.append(path([(STERN_X + 0.3, y), (STERN_X + 0.3, y + 0.8), (STERN_X + 2.2, y + 1.6), (STERN_X + 2.2, y + 0.8)], AMBER, None, 0, 0.9))
    b.append(line((STERN_X + 2.6, -BAY_HW + 0.5), (STERN_X + 2.6, BAY_HW - 0.5), "#E9EEF3", 1.6, 0.8))
    # centre line (dashed) between the two pads
    x = STERN_X + 4.0
    while x < BAY_X1 - 3.0:
        b.append(line((x, 0.0), (x + 1.6, 0.0), "#E9EEF3", 1.8, 0.7))
        x += 3.2
    # pads: corner brackets, a ring and the pad letter
    for s, name in ((-1, "A"), (1, "B")):
        c = (PAD_X, PAD_Y * s)
        w, h = PAD_SIZE[0] * 0.5, PAD_SIZE[1] * 0.5
        for sx in (-1, 1):
            for sy in (-1, 1):
                cx, cy = c[0] + sx * w, c[1] + sy * h
                b.append(polyline([(cx - sx * 2.4, cy), (cx, cy), (cx, cy - sy * 2.4)], AMBER, 2.4, 0.95, "square"))
        b.append(circle(c, 3.4, "none", 0.85, "#E9EEF3", 1.6))
        b.append(circle(c, 2.5, "#1D3557", 0.75))
        b.append(text(c, name, 3.2, "#E9EEF3", 0.95, 90.0))
        b.append(line((c[0] - w + 1.0, c[1]), (c[0] - 4.4, c[1]), "#7FE6FF", 1.2, 0.6))
        b.append(line((c[0] + 4.4, c[1]), (c[0] + w - 1.0, c[1]), "#7FE6FF", 1.2, 0.6))
    # front wall: the hangar door and the flight-control windows above it
    b.append(rect_xy(BAY_X1 - 0.2, -3.2, BAY_X1 + 1.3, 3.2, "#C9D2DC", 1.0, 0.2, INK, 1.2))
    b.append(rect_xy(BAY_X1 + 0.1, -2.4, BAY_X1 + 1.0, 2.4, "#2B3440", 1.0, 0.1))
    b.append(line((BAY_X1 + 0.55, -2.4), (BAY_X1 + 0.55, 2.4), AMBER, 1.4, 0.9))
    for s in (1, -1):
        b.append(rect_xy(BAY_X1 + 0.3, 5.0 * s, BAY_X1 + 1.5, 12.0 * s, "#10203A", 1.0, 0.2, "#33465F", 1.0))
    # walkway from the pads to the door
    for s in (1, -1):
        b.append(polyline([(PAD_X + 4.0, PAD_Y * s - 4.6 * s), (BAY_X1 - 3.0, 1.6 * s), (BAY_X1 - 0.6, 1.6 * s)], "#E9EEF3", 1.0, 0.35))
    return b


def arm_art():
    """The two engine arms either side of the bay: impulse exhausts in their
    stern faces, a navy cap stripe, and the bay-edge light rail."""
    b = []
    for s in (1, -1):
        b.append(rect_xy(STERN_X - 0.1, BAY_HW * s, STERN_X + 2.6, 18.0 * s, "#5C6878", 1.0, 0.0, INK, 1.4))
        for y in IMPULSE_Y:
            b.append(rect_c((STERN_X + 0.5, y * s), 1.3, 1.1, 0, "#2A1712", 1.0, 0.2))
        b.append(line((STERN_X + 3.4, (BAY_HW + 0.5) * s), (STERN_X + 3.4, 17.5 * s), "#8E9AA8", 1.3))
        b.append(polyline([(BAY_X1 - 0.5, (BAY_HW + 0.55) * s), (STERN_X + 3.0, (BAY_HW + 0.55) * s)], NAVY, 5.0, 0.9, "butt"))
    return b


def windows(rng, lights):
    """Rows of crew-deck windows along the forward hull's rim (warm). In the
    lights layer they get a soft halo so they glow from a distance."""
    b = []
    rows = [(0.93, -16.0, 76.0, 1.4), (0.845, -12.0, 68.0, 1.6), (0.52, 2.0, 44.0, 2.0)]
    for f, x0, x1, step in rows:
        x = x1
        while x > x0:
            for s in (1, -1):
                c = (x, f * hw(x) * s)
                p1 = (x + 0.3, f * hw(x + 0.3) * s)
                ang = math.degrees(math.atan2(p1[1] - c[1], 0.3))
                skip = (abs(x - CLAMP_FWD_X) < 3.0 or abs(x - AIRLOCK_X) < 3.0) and f > 0.8
                skip = skip or (f < 0.6 and abs(c[1]) < 5.5)
                lit = rng.random() > 0.22
                if skip:
                    continue
                if lights:
                    if lit:
                        b.append(rect_c(c, 1.8, 1.2, ang, WARM, 0.06, 0.5))
                        b.append(rect_c(c, 0.62, 0.3, ang, WARM, 0.6, 0.1))
                else:
                    b.append(rect_c(c, 1.0, 0.56, ang, "#2B3440", 1.0, 0.12))
                    b.append(rect_c(c, 0.72, 0.32, ang, "#FFD98A" if lit else "#3E5066", 1.0, 0.08))
            x -= step
    # bridge windows (ring around the module)
    for a in range(-150, 151, 15):
        t = math.radians(a)
        c = (BRIDGE[0] + 0.5 + 5.5 * math.cos(t), 3.6 * math.sin(t))
        if lights:
            b.append(rect_c(c, 1.0, 0.8, a + 90, "#BFEFFF", 0.08, 0.4))
            b.append(rect_c(c, 0.5, 0.3, a + 90, "#BFEFFF", 0.6, 0.1))
        else:
            b.append(rect_c(c, 0.7, 0.4, a + 90, "#BFEFFF", 1.0, 0.1))
    # flight-control windows over the hangar door
    for s in (1, -1):
        for k in range(4):
            c = (BAY_X1 + 0.9, (5.9 + k * 1.75) * s)
            if lights:
                b.append(rect_c(c, 1.6, 2.2, 0, "#7FE6FF", 0.07, 0.5))
                b.append(rect_c(c, 0.5, 1.2, 0, "#BFEFFF", 0.55, 0.1))
            else:
                b.append(rect_c(c, 0.7, 1.4, 0, "#7FE6FF", 0.9, 0.1))
    return b


def lights_layer(rng):
    b = windows(rng, True)
    # bridge dome glow
    b.append(circle((BRIDGE[0] + 1.0, 0.0), 3.9, "url(#halo)", 0.16))
    for s in (1, -1):
        # hardpoint guide lamps
        for p in [(CLAMP_FWD[0] - 1.6, (CLAMP_FWD[1] - 1.9) * s), (CLAMP_FWD[0] + 1.6, (CLAMP_FWD[1] - 1.9) * s),
                  (CLAMP_AFT[0] - 1.6, (CLAMP_AFT[1] - 1.7) * s), (CLAMP_AFT[0] + 1.6, (CLAMP_AFT[1] - 1.7) * s)]:
            b.append(circle(p, 0.9, AMBER, 0.25))
            b.append(circle(p, 0.3, "#FFD27A", 1.0))
        # airlock lamps
        a = (AIRLOCK[0], (AIRLOCK[1] - 1.0) * s)
        b.append(circle((a[0] - 1.8, a[1]), 0.8, "#3BFF7A", 0.25))
        b.append(circle((a[0] - 1.8, a[1]), 0.28, "#9BFFC0", 1.0))
        # bay edge lights: a rail of small lamps down both walls
        x = STERN_X + 1.5
        while x < BAY_X1 - 1.0:
            b.append(circle((x, (BAY_HW - 0.45) * s), 0.75, "#7FE6FF", 0.2))
            b.append(circle((x, (BAY_HW - 0.45) * s), 0.2, "#D8F6FF", 1.0))
            x += 2.6
    # hangar door lamp + pad centre lamps
    b.append(circle((BAY_X1 - 0.8, 0.0), 1.6, AMBER, 0.2))
    for s in (1, -1):
        for dx in (-PAD_SIZE[0] * 0.5, PAD_SIZE[0] * 0.5):
            for dy in (-PAD_SIZE[1] * 0.5, PAD_SIZE[1] * 0.5):
                b.append(circle((PAD_X + dx, PAD_Y * s + dy), 0.7, AMBER, 0.28))
                b.append(circle((PAD_X + dx, PAD_Y * s + dy), 0.22, "#FFD27A", 1.0))
    return b


def livery_layer():
    """White shapes, tinted with the ship's livery colour at runtime."""
    b = []
    # coloured rim band on the forward hull, tapering toward the waist
    for s in (1, -1):
        o, i = [], []
        for k in range(0, 46):
            x = 80.0 - k * 2.0
            w = 0.9 * max(0.0, 1.0 - k / 50.0) ** 0.6 + 0.25
            o.append((x, (hw(x) - 0.12) * s))
            i.append((x, (hw(x) - 0.12 - w) * s))
        b.append(path(o + list(reversed(i)), "#FFFFFF"))
        # twin swept accent lines from the bridge aft (thin, tapered)
        b.append(path([(66.0, 2.4 * s), (48.0, 8.6 * s), (30.0, 11.4 * s), (12.0, 12.2 * s),
                       (12.0, 11.7 * s), (30.0, 10.6 * s), (47.0, 7.6 * s), (65.0, 2.0 * s)], "#FFFFFF", None, 0, 0.95))
        b.append(path([(62.0, 4.6 * s), (49.0, 9.6 * s), (40.0, 11.0 * s), (40.0, 10.6 * s), (48.5, 9.0 * s), (61.5, 4.2 * s)], "#FFFFFF", None, 0, 0.7))
        # hangar block side stripe
        b.append(rect_xy(-62.0, 17.3 * s, -30.0, 17.9 * s, "#FFFFFF"))
        # drive ring: a stripe round the outer face
        outer = ellipse((LOOP_C[0], LOOP_C[1] * s), LOOP_A - 0.35, LOOP_B - 0.35, 96)
        inner = ellipse((LOOP_C[0], LOOP_C[1] * s), LOOP_A - 0.95, LOOP_B - 0.95, 96)
        b.append(ring_path(outer, inner, "#FFFFFF", None, 0, 0.95))
    return b


# ------------------------------------------------------------- gdscript --
def gd_arr(pts):
    return "[" + ", ".join("Vector2(%.1f, %.1f)" % (x * PX, y * PX) for x, y in pts) + "]"


def gd_m(pts):
    return "[" + ", ".join("Vector2(%.2f, %.2f)" % (x, y) for x, y in pts) + "]"


def is_convex(pts):
    n = len(pts)
    sign = 0
    for i in range(n):
        a, b_, c = pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        cr = (b_[0] - a[0]) * (c[1] - b_[1]) - (b_[1] - a[1]) * (c[0] - b_[0])
        if abs(cr) < 1e-6:
            continue
        s = 1 if cr > 0 else -1
        if sign == 0:
            sign = s
        elif s != sign:
            return False
    return True


def collision_parts():
    parts = [("bow", bow_part()), ("mid", slab(-10.0, 22.0)), ("waist", slab(WAIST_X, -10.0)),
             ("flare", [(WAIST_X, hw(WAIST_X)), (BLOCK_X0, BLOCK_HW), (BLOCK_X0, -BLOCK_HW), (WAIST_X, -hw(WAIST_X))]),
             ("block", [(BLOCK_X0, BLOCK_HW), (BAY_X1, BLOCK_HW), (BAY_X1, -BLOCK_HW), (BLOCK_X0, -BLOCK_HW)]),
             ("arm_s", arm(1)), ("arm_p", arm(-1))]
    for side, tag in ((1, "s"), (-1, "p")):
        for k in range(2):
            parts.append(("pylon_%s%d" % (tag, k), pylon(side, k)))
        for k, q in enumerate(loop_pieces(side)):
            parts.append(("ring_%s%02d" % (tag, k), q))
    for name, pts in parts:
        assert is_convex(pts), "part %s is not convex" % name
    return parts


def write_gd():
    parts = collision_parts()
    lines = [
        "class_name FrigateShape",
        "extends RefCounted",
        "## GENERATED by tools/art/frigate_svg.py from the same geometry as the frigate",
        "## art (frigate_hull.svg). Do not edit by hand: change the generator and rerun it.",
        "## Units: PARTS and the outlines in local px (1 m = 10 px), the points below in",
        "## metres. Bow = +X, starboard = +Y. Every part is convex (one CollisionPolygon2D each).",
        "",
        "const PARTS := {",
    ]
    for name, pts in parts:
        lines.append('\t"%s": %s,' % (name, gd_arr(pts)))
    lines += [
        "}",
        "## The main body's silhouette (forward hull + hangar block, with the bay notch).",
        "const BODY := %s" % gd_arr(body_outline(3.0)),
        "## Starboard drive ring: outer and inner edge (the hole small ships can thread).",
        "## The port ring is the mirror image (y negated).",
        "const RING_OUTER := %s" % gd_arr(loop_outer(1, 28)),
        "const RING_INNER := %s" % gd_arr(loop_inner(1, 28)),
        "## Emitter channel centre line of the starboard ring (m), a closed loop.",
        "const RING_MID := %s" % gd_m(loop_mid(1, 40)),
        "const RING_CENTRE := Vector2(%.2f, %.2f)" % LOOP_C,
        "const RING_HALF := Vector2(%.2f, %.2f)" % (LOOP_A, LOOP_B),
        "## Forward clamp hardpoint on the hull's rim (starboard; port mirrors y).",
        "const CLAMP_FWD := Vector2(%.2f, %.2f)" % CLAMP_FWD,
        "## Aft clamp hardpoint on the outer face of the starboard drive ring.",
        "const CLAMP_AFT := Vector2(%.2f, %.2f)" % CLAMP_AFT,
        "## Personnel airlock on the hull's rim (starboard).",
        "const AIRLOCK := Vector2(%.2f, %.2f)" % AIRLOCK,
        "## Impulse engine exits in the stern faces of the bay arms: x, and |y| per slot (m).",
        "const IMPULSE_X := %.1f" % STERN_X,
        "const IMPULSE_Y := %s" % ("[" + ", ".join("%.2f" % y for y in IMPULSE_Y) + "]"),
        "## The flight deck (m): the open landing bay in the stern. x = mouth .. front wall.",
        "const BAY := Rect2(%.1f, %.1f, %.1f, %.1f)" % (STERN_X, -BAY_HW, BAY_X1 - STERN_X, BAY_HW * 2.0),
        "## Landing pad centres in the bay (m): pad A to port, pad B to starboard.",
        "const BAY_PADS := [Vector2(%.2f, %.2f), Vector2(%.2f, %.2f)]" % (PAD_X, -PAD_Y, PAD_X, PAD_Y),
        "const BAY_PAD_SIZE := Vector2(%.1f, %.1f)" % PAD_SIZE,
        "## The hangar door in the bay's front wall (m).",
        "const BAY_DOOR := Vector2(%.1f, 0.0)" % BAY_X1,
        "## RCS quads (m, starboard; port mirrors y): two lateral pairs forward, two aft,",
        "## the fore quads (fire forward) and the aft quads (fire aft, on the ring tails).",
        "const RCS_BOW := %s" % gd_m(RCS_BOW),
        "const RCS_STERN := %s" % gd_m(RCS_STERN),
        "const RCS_FORE := Vector2(%.2f, %.2f)" % RCS_FORE,
        "const RCS_AFT := Vector2(%.2f, %.2f)" % RCS_AFT,
        "## Bridge dome and the navigational deflector in the nose (m).",
        "const BRIDGE := Vector2(%.1f, %.1f)" % BRIDGE,
        "const DEFLECTOR := Vector2(77.0, 0.0)",
        "## Bounding ellipse for the shield bubble and the camera (m): centre x, half",
        "## length, half beam.",
        "const CENTRE_X := %.1f" % ((BOW_X + LOOP_C[0] - LOOP_A) * 0.5),
        "const HALF_LENGTH := %.1f" % ((BOW_X - (LOOP_C[0] - LOOP_A)) * 0.5),
        "const HALF_BEAM := %.1f" % (LOOP_C[1] + LOOP_B),
        "const BOW_X := %.1f" % BOW_X,
        "",
        "",
        "## Half beam (m) of the main body at x (m): piecewise linear through BODY.",
        "static func half_beam(x_m: float) -> float:",
        "\tvar best := 0.0",
        "\tvar n := BODY.size()",
        "\tfor i in n:",
        "\t\tvar a: Vector2 = BODY[i]",
        "\t\tvar b: Vector2 = BODY[(i + 1) % n]",
        "\t\tvar x := x_m * 10.0",
        "\t\tif (a.x - x) * (b.x - x) > 0.0 or is_equal_approx(a.x, b.x):",
        "\t\t\tcontinue",
        "\t\tvar y := lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))",
        "\t\tbest = maxf(best, absf(y))",
        "\treturn best / 10.0",
        "",
        "",
        "## Outlines for radar, guidance ghosts and diagrams (local px): the body, then",
        "## both rings' outer and inner edges.",
        "static func outlines() -> Array[PackedVector2Array]:",
        "\tvar out: Array[PackedVector2Array] = [PackedVector2Array(BODY)]",
        "\tfor s: float in [1.0, -1.0]:",
        "\t\tfor src: Array in [RING_OUTER, RING_INNER]:",
        "\t\t\tvar p := PackedVector2Array()",
        "\t\t\tfor v: Vector2 in src:",
        "\t\t\t\tp.append(Vector2(v.x, v.y * s))",
        "\t\t\tout.append(p)",
        "\treturn out",
        "",
    ]
    with open(GD, "w") as f:
        f.write("\n".join(lines))


def main():
    rng = random.Random(7)
    os.makedirs(ART, exist_ok=True)
    hull = hull_layer(rng) + windows(random.Random(21), False)
    with open(os.path.join(ART, "frigate_hull.svg"), "w") as f:
        f.write(svg(hull, DEFS))
    with open(os.path.join(ART, "frigate_lights.svg"), "w") as f:
        f.write(svg(lights_layer(random.Random(21)), DEFS))
    with open(os.path.join(ART, "frigate_livery.svg"), "w") as f:
        f.write(svg(livery_layer(), DEFS))
    write_gd()
    print("frigate art written; clamp fwd %s aft %s airlock %s" % (
        tuple(round(v, 2) for v in CLAMP_FWD), CLAMP_AFT, tuple(round(v, 2) for v in AIRLOCK)))


if __name__ == "__main__":
    main()
