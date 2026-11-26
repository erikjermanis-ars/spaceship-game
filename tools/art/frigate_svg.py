#!/usr/bin/env python3
"""Generates the KESTREL-class frigate art and its shape data.

    python3 tools/art/frigate_svg.py
    /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import

Writes (all from the same geometry, so art, collision and docking hardpoints
can never drift apart):
    assets/art/ship/frigate_hull.svg     painted hull (pearl plating, details)
    assets/art/ship/frigate_livery.svg   livery stripes in white (tinted at runtime)
    assets/art/ship/frigate_lights.svg   emissive bits (windows, lamps), drawn additive
    scripts/ship/frigate_shape.gd        collision parts + hardpoints (GDScript consts)

Units: the ship is designed in metres, bow = +X, starboard = +Y (Godot's
y-down screen space). SVG units are world pixels (1 m = 10 px) with the ship
origin (its centre of mass) at the SVG origin, so a Sprite2D at scale 1/import
scale lines up with the body without any offset.

Design: an original "civil exploration frigate" in the station's palette.
An elongated lens-shaped primary hull carries the bridge and the crew decks
(rows of warm windows along the rim), a slim neck joins it to the engineering
hull, and two long drive nacelles sit out on swept pylons with blue drive
grilles. Impulse engines glow at the back of the primary hull. Plating uses a
low-contrast mosaic of panels so the hull reads as huge and built, not flat.
"""
import math
import os
import random

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ART = os.path.join(ROOT, "assets", "art", "ship")
GD = os.path.join(ROOT, "scripts", "ship", "frigate_shape.gd")
PX = 10.0
VIEW = (-820, -340, 1640, 680)

# ----------------------------------------------------------- geometry (m) --
PRI_C = (36.0, 0.0)       # primary hull: stretched lens
PRI_A = 42.0
PRI_B = 23.5
NAC_Y = 28.0              # nacelle centre line
NAC_R = 3.8
NAC_X0 = -16.2            # nacelle front (bussard tip)
NAC_X1 = -77.0            # nacelle tail


def pri_point(s, t):
    """Point on the primary hull at ring scale s (0..1) and angle t."""
    c = math.cos(t)
    pinch = 1.0 - 0.18 * max(0.0, c) ** 4     # slightly pointier nose
    return (PRI_C[0] + s * PRI_A * c, PRI_C[1] + s * PRI_B * math.sin(t) * pinch)


def pri_half_width(x):
    """Half beam of the primary hull at x (by bisection on the outline)."""
    lo, hi = 0.0, math.pi * 0.5 if x >= PRI_C[0] else math.pi
    # outline x(t) is monotonic on [0, pi]; find t with x(t) = x
    lo, hi = 0.0, math.pi
    for _ in range(60):
        mid = (lo + hi) * 0.5
        if pri_point(1.0, mid)[0] > x:
            lo = mid
        else:
            hi = mid
    return pri_point(1.0, (lo + hi) * 0.5)[1]


def primary(n=72):
    return [pri_point(1.0, 2.0 * math.pi * i / n) for i in range(n)]


def arc(cx, cy, r, a0, a1, n):
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / (n - 1)), cy + r * math.sin(a0 + (a1 - a0) * i / (n - 1))) for i in range(n)]


def neck():
    return [(6.0, 7.5), (-17.0, 5.5), (-17.0, -5.5), (6.0, -7.5)]


def secondary():
    pts = arc(-22.0, 0.0, 10.0, -math.pi * 0.5, math.pi * 0.5, 13)
    pts += [(-52.0, 10.0), (-60.0, 8.5), (-65.0, 5.5), (-65.0, -5.5), (-60.0, -8.5), (-52.0, -10.0)]
    return pts


def pylon(side):
    return [(-30.0, 8.0 * side), (-42.0, 25.5 * side), (-50.0, 25.5 * side), (-44.0, 8.0 * side)]


def nacelle(side):
    cy = NAC_Y * side
    pts = arc(NAC_X0 - NAC_R, cy, NAC_R, -math.pi * 0.5, math.pi * 0.5, 9)
    pts += [(-70.0, cy + NAC_R), (NAC_X1, cy + NAC_R * 0.62), (NAC_X1, cy - NAC_R * 0.62), (-70.0, cy - NAC_R)]
    return pts


def impulse(side):
    return [(4.0, 7.5 * side), (4.0, 15.0 * side), (-4.5, 14.0 * side), (-4.5, 7.5 * side)]


ARC_IN = (-64.0, -80.0)      # field arc: inner/outer x on the centre line
ARC_Y = NAC_Y                 # it meets the nacelles' inner faces


def field_arc_pieces(n=4):
    """Crescent joining the two nacelle tails, as n convex pieces (port to
    starboard). Inner edge: an elliptical arc from (-62, -24.6) through
    (-74, 0); outer edge 3.6 m further aft."""
    pts_in, pts_out = [], []
    for i in range(n + 1):
        t = -math.pi * 0.5 + math.pi * i / n
        y = math.sin(t) * (ARC_Y - NAC_R * 0.4)
        k = math.cos(t)
        pts_in.append((-62.0 - 12.0 * k, y))
        pts_out.append((-65.6 - 14.4 * k, y * 1.0))
    return [[pts_in[i], pts_in[i + 1], pts_out[i + 1], pts_out[i]] for i in range(n)]


def mirror_y(pts):
    return [(x, -y) for x, y in pts]


# Key points (m), starboard side; port is the mirror image.
CLAMP_FWD_X = 24.0
CLAMP_AFT_X = -46.0
AIRLOCK_X = 12.0
CLAMP_FWD = (CLAMP_FWD_X, pri_half_width(CLAMP_FWD_X))
CLAMP_AFT = (CLAMP_AFT_X, NAC_Y + NAC_R)
AIRLOCK = (AIRLOCK_X, pri_half_width(AIRLOCK_X))


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


def polyline(pts, stroke, sw, op=1.0, cap="round"):
    d = "M" + " L".join(P(p) for p in pts)
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


def circle(c, r, fill, op=1.0, stroke=None, sw=0.0):
    s = '<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" opacity="%.3f"' % (c[0] * PX, c[1] * PX, r * PX, fill, op)
    if stroke:
        s += ' stroke="%s" stroke-width="%.2f"' % (stroke, sw)
    return s + "/>"


def svg(body, defs=""):
    x, y, w, h = VIEW
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%d %d %d %d">\n'
            '<defs>%s</defs>\n%s\n</svg>\n') % (w, h, x, y, w, h, defs, "\n".join(body))


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def inside(pt, poly):
    x, y = pt
    c = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            c = not c
        j = i
    return c


DEFS = """
<linearGradient id="pearl" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#F7F9FB"/><stop offset="0.55" stop-color="#E6ECF1"/><stop offset="1" stop-color="#C4CED9"/>
</linearGradient>
<linearGradient id="shade" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.55"/><stop offset="0.45" stop-color="#FFFFFF" stop-opacity="0"/>
  <stop offset="0.7" stop-color="#0A1424" stop-opacity="0"/><stop offset="1" stop-color="#0A1424" stop-opacity="0.32"/>
</linearGradient>
<linearGradient id="nacelle" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#D2DAE3"/><stop offset="0.5" stop-color="#A9B5C3"/><stop offset="1" stop-color="#7D8A9B"/>
</linearGradient>
<linearGradient id="grey" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#DCE3EA"/><stop offset="1" stop-color="#A5B1BF"/>
</linearGradient>
<radialGradient id="dome" cx="0.4" cy="0.35" r="0.7">
  <stop offset="0" stop-color="#4C86A8"/><stop offset="0.6" stop-color="#1D3557"/><stop offset="1" stop-color="#0E1C30"/>
</radialGradient>
<radialGradient id="halo" cx="0.5" cy="0.5" r="0.5">
  <stop offset="0" stop-color="#FFFFFF" stop-opacity="1"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
</radialGradient>
"""

INK = "#3E4A5A"
SEAM = "#AEB9C6"
NAVY = "#1D3557"
TEAL = "#2A9D8F"
DARK = "#1B2635"
WARM = "#FFE2A0"


# ------------------------------------------------------------------ hull --
def hull_layer(rng):
    b = []
    pri = primary()
    sec = secondary()
    nk = neck()
    # ---- drop-in order: pylons, nacelles, engineering hull, neck, impulse, primary
    for side in (1, -1):
        py = pylon(side)
        b.append(path(py, "url(#grey)", INK, 3.0))
        for k in range(1, 4):
            t = k / 4.0
            b.append(line(lerp(py[0], py[3], t), lerp(py[1], py[2], t), SEAM, 1.6, 0.9))
        b.append(line(lerp(py[0], py[1], 0.5), lerp(py[3], py[2], 0.5), "#8794A5", 1.2, 0.9))
        b.append(polyline([lerp(py[0], py[3], 0.5), lerp(py[1], py[2], 0.5)], NAVY, 7.0, 0.85))
    b += field_arc_art()
    for side in (1, -1):
        b += nacelle_art(side, rng)
    b.append(path(sec, "url(#pearl)", INK, 3.0))
    b += secondary_art(rng, sec)
    b.append(path(nk, "url(#grey)", INK, 2.5))
    for k in range(1, 6):
        x = 6.0 - k * 3.8
        b.append(line((x, -5.8), (x, 5.8), SEAM, 1.4))
    b.append(polyline([(5.0, 0.0), (-16.0, 0.0)], NAVY, 10.0, 0.9))
    b.append(polyline([(5.0, 0.0), (-16.0, 0.0)], TEAL, 2.4, 0.9))
    for side in (1, -1):
        ip = impulse(side)
        b.append(path(ip, "#5C6878", INK, 2.5))
        for k in range(3):
            y0 = (8.6 + k * 2.0) * side
            b.append(rect_c((-4.0, y0), 1.2, 1.4, 0, "#2A1712", 1.0, 0.2))
        b.append(line((3.0, 8.0 * side), (3.0, 14.6 * side), "#8E9AA8", 1.4))
    # primary hull: base + mosaic plating + shading
    b.append(path(pri, "url(#pearl)"))
    b += plating(rng, pri)
    b.append(path(pri, "url(#shade)"))
    rim = [pri_point(1.0, 2 * math.pi * i / 96) for i in range(96)]
    rim += [pri_point(0.965, 2 * math.pi * i / 96) for i in range(96, -1, -1)]
    b.append(path(rim, "#B9C4D0", None, 0, 0.9))
    b += primary_details(rng)
    b.append(path(pri, "none", INK, 3.4))
    inner = [pri_point(0.985, 2.0 * math.pi * i / 72) for i in range(72)]
    b.append(path(inner, "none", "#FFFFFF", 1.6, 0.55))
    return b


def plating(rng, pri):
    """Low-contrast panel mosaic in elliptical rings (reads as built plating)."""
    out = []
    tones = ["#EEF2F6", "#E4EAF0", "#F4F7FA", "#DCE4EB", "#E9EEF3", "#E1E8EE"]
    rings = [0.12, 0.24, 0.36, 0.47, 0.57, 0.66, 0.745, 0.82, 0.885, 0.94, 1.0]
    for ri in range(len(rings) - 1):
        s0, s1 = rings[ri], rings[ri + 1]
        segs = max(8, int(16 + 70 * s1))
        off = rng.random()
        for k in range(segs):
            t0 = 2 * math.pi * (k + off) / segs
            t1 = 2 * math.pi * (k + 1 + off) / segs
            q = [pri_point(s0, t0), pri_point(s0, t1), pri_point(s1, t1), pri_point(s1, t0)]
            if rng.random() < 0.85:
                out.append(path(q, rng.choice(tones), SEAM, 0.9, 0.95))
            else:
                # inset service panel: slightly darker with fasteners
                out.append(path(q, "#D3DBE3", SEAM, 0.9, 0.95))
                c = pri_point((s0 + s1) * 0.5, (t0 + t1) * 0.5)
                out.append(circle(c, 0.18, "#9AA6B4"))
    return out


def primary_details(rng):
    b = []
    n = 72
    # sensor strip ring (forward arc)
    ring = [pri_point(0.70, math.radians(a)) for a in range(-118, 119, 4)]
    b.append(polyline(ring, "#3A4656", 6.0, 0.9))
    b.append(polyline(ring, "#9FB3C8", 1.8, 0.9))
    # dorsal spine from the bridge to the neck
    b.append(path([(46.0, -2.8), (46.0, 2.8), (2.0, 4.2), (2.0, -4.2)], "url(#grey)", INK, 1.6))
    b.append(path([(46.0, -2.8), (46.0, 0.0), (2.0, 0.0), (2.0, -4.2)], "#F4F7FA", None, 0, 0.55))
    b.append(polyline([(45.0, 0.0), (3.0, 0.0)], NAVY, 3.2, 0.95))
    b.append(polyline([(45.0, 0.0), (3.0, 0.0)], "#7FE6FF", 0.8, 0.8))
    for x in range(6, 45, 4):
        w = 2.8 + (46.0 - x) / 44.0 * 1.4
        b.append(line((x, -w), (x, -0.8), "#9AA6B4", 0.9))
        b.append(line((x, 0.8), (x, w), "#9AA6B4", 0.9))
    # bridge module + dome
    b.append('<ellipse cx="%.1f" cy="0" rx="%.1f" ry="%.1f" fill="url(#grey)" stroke="%s" stroke-width="2.4"/>' % (52 * PX, 8.5 * PX, 6.2 * PX, INK))
    b.append('<ellipse cx="%.1f" cy="0" rx="%.1f" ry="%.1f" fill="#E9EEF3" stroke="#AEB9C6" stroke-width="1.2"/>' % (52.5 * PX, 6.6 * PX, 4.6 * PX))
    b.append(circle((53.0, 0.0), 3.3, "url(#dome)", 1.0, "#0E1C30", 1.6))
    b.append(circle((52.0, -1.0), 1.0, "#FFFFFF", 0.22))
    # escape pods (pairs) around the ring
    for a in range(-150, 151, 14):
        if abs(a) < 14:
            continue
        t = math.radians(a)
        c = pri_point(0.84, t)
        tang = pri_point(0.84, t + 0.01)
        ang = math.degrees(math.atan2(tang[1] - c[1], tang[0] - c[0]))
        b.append(rect_c(c, 1.5, 0.95, ang, "#8693A3", 1.0, 0.25, INK, 0.8))
    # RCS quads
    for p in [(68.0, 5.2), (36.0, 22.4), (8.0, 15.8)]:
        for s in (1, -1):
            b.append(rect_c((p[0], p[1] * s), 1.4, 1.4, 0, "#5C6878", 1.0, 0.2, INK, 0.8))
            b.append(circle((p[0], p[1] * s), 0.35, "#2B3440"))
    # docking hardpoints (both sides) + airlock hatches
    for s in (1, -1):
        b += hardpoint((CLAMP_FWD[0], CLAMP_FWD[1] * s - 1.0 * s), s)
        a = (AIRLOCK[0], AIRLOCK[1] * s - 0.9 * s)
        b.append(rect_c(a, 3.0, 1.6, 0, "#C9D2DC", 1.0, 0.3, INK, 1.2))
        b.append(rect_c(a, 2.0, 0.7, 0, "#2B3440", 1.0, 0.15))
        b.append(rect_c((a[0], a[1] - 0.95 * s), 3.4, 0.35, 0, "#FFB000", 0.9))
    # forward "keel" chevrons in navy
    for s in (1, -1):
        b.append(polyline([(70.0, 0.6 * s), (60.0, 5.0 * s), (50.0, 6.8 * s)], NAVY, 3.0, 0.75))
    return b


def hardpoint(c, side):
    """Clamp hardpoint: a reinforced square with hazard chevrons."""
    b = [rect_c(c, 3.2, 3.2, 0, "#2B3440", 1.0, 0.3, INK, 1.2)]
    for k in range(4):
        x = c[0] - 1.2 + k * 0.8
        b.append(polyline([(x, c[1] - 1.3), (x + 0.6, c[1] + 1.3)], "#FFB000", 2.2, 0.95, "butt"))
    b.append(rect_c(c, 1.4, 1.4, 0, "#5C6878", 1.0, 0.2, "#11161E", 0.8))
    b.append(circle(c, 0.35, "#9AA6B4"))
    return b


def field_arc_art():
    """The field arc: a swept crescent of emitter segments (glow at runtime)."""
    b = []
    pieces = field_arc_pieces(8)
    inner = [q[0] for q in pieces] + [pieces[-1][1]]
    outer = [q[3] for q in pieces] + [pieces[-1][2]]
    b.append(path(inner + list(reversed(outer)), "url(#grey)", INK, 2.6))
    # emitter channel along the middle (dark, lit by FrigateVisuals)
    mid = [lerp(a, c, 0.5) for a, c in zip(inner, outer)]
    b.append(polyline(mid, "#13223A", 14.0, 1.0))
    for q in pieces:
        b.append(line(q[0], q[3], "#8794A5", 1.4))
    return b


def nacelle_art(side, rng):
    b = []
    nc = nacelle(side)
    cy = NAC_Y * side
    b.append(path(nc, "url(#nacelle)", INK, 3.0))
    # drive grille channel (glows at runtime)
    b.append(path([(-22.0, cy - 1.45), (-66.0, cy - 1.25), (-66.0, cy + 1.25), (-22.0, cy + 1.45)], "#13223A", "#33465F", 1.2))
    for k in range(22):
        x = -23.0 - k * 2.0
        b.append(line((x, cy - 1.3), (x, cy + 1.3), "#2E4565", 1.0))
    # bussard cap (front) dark glass
    cap = arc(NAC_X0 - NAC_R, cy, NAC_R * 0.86, -math.pi * 0.5, math.pi * 0.5, 9)
    b.append(path(cap, "#10203A", "#33465F", 1.2))
    # outer and inner panel bands
    for k in range(6):
        x = -24.0 - k * 8.0
        b.append(line((x, cy - NAC_R + 0.3), (x, cy - 1.6), SEAM, 1.2))
        b.append(line((x, cy + 1.6), (x, cy + NAC_R - 0.3), SEAM, 1.2))
    # tail cap with radiator vanes
    b.append(path([(-70.0, cy - 3.2), (-76.4, cy - 2.2), (-76.4, cy + 2.2), (-70.0, cy + 3.2)], "#5C6878", INK, 1.4))
    for k in range(4):
        b.append(line((-71.0 - k * 1.4, cy - 2.4), (-71.0 - k * 1.4, cy + 2.4), "#8E9AA8", 0.9))
    # aft hardpoint on the outer side
    b += hardpoint((CLAMP_AFT[0], (CLAMP_AFT[1] - 1.0) * side), side)
    # RCS at the tail
    b.append(rect_c((-68.0, cy + 3.0 * side), 1.2, 1.2, 0, "#5C6878", 1.0, 0.2, INK, 0.8))
    return b


def secondary_art(rng, sec):
    b = []
    # panel grid
    for x in range(-56, -14, 6):
        for yy in (-6.5, -2.0, 2.0, 6.5):
            c = (x - 3.0, yy)
            if inside(c, sec):
                tone = rng.choice(["#E9EEF3", "#E1E8EE", "#F2F5F8", "#D8E0E8"])
                b.append(rect_c(c, 5.6, 4.0, 0, tone, 0.95, 0.15, SEAM, 0.9))
    # dorsal radiator fins
    for x in range(-50, -26, 2):
        b.append(line((x, -4.0), (x, 4.0), "#8E9AA8", 1.1, 0.9))
    b.append(path([(-26.0, -4.6), (-26.0, 4.6), (-51.0, 4.6), (-51.0, -4.6)], "none", "#6D7A8A", 1.4))
    # navigational deflector housing (front of the engineering hull)
    dish = arc(-22.0, 0.0, 9.0, -math.pi * 0.42, math.pi * 0.42, 11)
    dish2 = arc(-22.0, 0.0, 6.6, math.pi * 0.42, -math.pi * 0.42, 11)
    b.append(path(dish + dish2, "#2B3440", INK, 1.2))
    # shuttle bay at the stern
    b.append(rect_c((-64.0, 0.0), 1.6, 8.4, 0, "#1B2635", 1.0, 0.2, INK, 1.2))
    for k in range(5):
        b.append(line((-64.8, -3.6 + k * 1.8), (-63.2, -3.6 + k * 1.8), "#3A4656", 0.9))
    b.append(rect_c((-61.0, 0.0), 3.0, 9.6, 0, "none", 1.0, 0.2, "#FFB000", 1.0))
    # RCS
    for s in (1, -1):
        b.append(rect_c((-58.0, 8.4 * s), 1.3, 1.3, 0, "#5C6878", 1.0, 0.2, INK, 0.8))
    return b


def windows(rng, lights):
    """Rows of crew-deck windows along the primary hull rim (warm). In the
    lights layer they get a soft halo so they glow from a distance."""
    b = []
    rows = [(0.935, -168, 168, 1.35), (0.87, -120, 120, 1.55), (0.62, -70, 70, 1.9)]
    for s, a0, a1, step_m in rows:
        # walk the ring at ~step_m spacing
        ts = []
        t = math.radians(a0)
        while t < math.radians(a1):
            ts.append(t)
            p0 = pri_point(s, t)
            p1 = pri_point(s, t + 0.001)
            d = math.hypot(p1[0] - p0[0], p1[1] - p0[1]) / 0.001
            t += step_m / max(d, 1e-3)
        for i, t in enumerate(ts):
            c = pri_point(s, t)
            p1 = pri_point(s, t + 0.002)
            ang = math.degrees(math.atan2(p1[1] - c[1], p1[0] - c[0]))
            # skip windows under the bridge module, the spine and pods
            if abs(c[1]) < 4.0 and c[0] > 2.0:
                continue
            lit = rng.random() > 0.22
            if lights:
                if lit:
                    b.append(rect_c(c, 1.8, 1.2, ang, WARM, 0.06, 0.5))
                    b.append(rect_c(c, 0.62, 0.3, ang, WARM, 0.6, 0.1))
            else:
                b.append(rect_c(c, 1.0, 0.56, ang, "#2B3440", 1.0, 0.12))
                b.append(rect_c(c, 0.72, 0.32, ang, "#FFD98A" if lit else "#3E5066", 1.0, 0.08))
    # bridge windows (ring around the module)
    for a in range(-150, 151, 15):
        t = math.radians(a)
        c = (52.5 + 5.9 * math.cos(t), 4.0 * math.sin(t))
        if lights:
            b.append(rect_c(c, 1.0, 0.8, a + 90, "#BFEFFF", 0.08, 0.4))
            b.append(rect_c(c, 0.5, 0.3, a + 90, "#BFEFFF", 0.6, 0.1))
        else:
            b.append(rect_c(c, 0.7, 0.4, a + 90, "#BFEFFF", 1.0, 0.1))
    return b


def lights_layer(rng):
    b = windows(rng, True)
    # bridge dome glow
    b.append(circle((53.0, 0.0), 4.2, "url(#halo)", 0.16))
    for s in (1, -1):
        # hardpoint guide lamps
        for p in [(CLAMP_FWD[0] - 1.6, CLAMP_FWD[1] * s - 1.0 * s), (CLAMP_FWD[0] + 1.6, CLAMP_FWD[1] * s - 1.0 * s),
                  (CLAMP_AFT[0] - 1.6, (CLAMP_AFT[1] - 1.0) * s), (CLAMP_AFT[0] + 1.6, (CLAMP_AFT[1] - 1.0) * s)]:
            b.append(circle(p, 0.9, "#FFB000", 0.25))
            b.append(circle(p, 0.3, "#FFD27A", 1.0))
        # airlock lamps
        a = (AIRLOCK[0], AIRLOCK[1] * s - 0.9 * s)
        b.append(circle((a[0] - 1.8, a[1]), 0.8, "#3BFF7A", 0.25))
        b.append(circle((a[0] - 1.8, a[1]), 0.28, "#9BFFC0", 1.0))
        # shuttle bay lights
    for k in range(5):
        b.append(circle((-62.4, -3.6 + k * 1.8), 0.25, "#FFD27A", 0.9))
    return b


def livery_layer():
    """White shapes, tinted with the ship's livery colour at runtime."""
    b = []
    # coloured rim band on the forward two-thirds of the primary hull
    band = []
    for a in range(-132, 133, 3):
        w = 0.035 * (1.0 - abs(a) / 150.0) ** 0.5     # tapers towards the aft
        band.append(pri_point(0.995, math.radians(a)))
    for a in range(132, -133, -3):
        w = 0.035 * (1.0 - abs(a) / 150.0) ** 0.5
        band.append(pri_point(0.995 - w, math.radians(a)))
    b.append(path(band, "#FFFFFF"))
    # twin swept accent lines from the bridge aft (thin, tapered)
    for s in (1, -1):
        b.append(path([(61.0, 2.6 * s), (46.0, 9.8 * s), (30.0, 13.6 * s), (16.0, 15.2 * s),
                       (16.0, 14.7 * s), (30.0, 12.8 * s), (45.0, 8.8 * s), (60.0, 2.2 * s)], "#FFFFFF", None, 0, 0.95))
        b.append(path([(58.0, 4.6 * s), (47.0, 10.6 * s), (40.0, 12.2 * s), (40.0, 11.8 * s), (46.5, 10.0 * s), (57.5, 4.2 * s)], "#FFFFFF", None, 0, 0.7))
        # nacelle outer stripe
        cy = NAC_Y * s
        b.append(path([(-24.0, cy + 2.4 * s), (-68.0, cy + 2.4 * s), (-68.0, cy + 3.2 * s), (-24.0, cy + 3.2 * s)], "#FFFFFF"))
        # pylon flash
        b.append(path([(-33.5, 10.0 * s), (-41.0, 21.0 * s), (-42.8, 21.0 * s), (-35.3, 10.0 * s)], "#FFFFFF", None, 0, 0.9))
    # engineering hull band
    b.append(path([(-28.0, -10.4), (-50.0, -10.2), (-50.0, -9.5), (-28.0, -9.7)], "#FFFFFF"))
    b.append(path([(-28.0, 10.4), (-50.0, 10.2), (-50.0, 9.5), (-28.0, 9.7)], "#FFFFFF"))
    return b


# ------------------------------------------------------------- gdscript --
def gd_arr(pts):
    return "[" + ", ".join("Vector2(%.1f, %.1f)" % (x * PX, y * PX) for x, y in pts) + "]"


def gd_m(pts):
    return "[" + ", ".join("Vector2(%.2f, %.2f)" % (x, y) for x, y in pts) + "]"


def write_gd():
    parts = [("primary", primary(28)), ("neck", neck()), ("secondary", secondary()),
             ("pylon_s", pylon(1)), ("pylon_p", pylon(-1)), ("nacelle_s", nacelle(1)), ("nacelle_p", nacelle(-1)),
             ("impulse_s", impulse(1)), ("impulse_p", impulse(-1))]
    for i, q in enumerate(field_arc_pieces(4)):
        parts.append(("arc_%d" % i, q))
    lines = [
        "class_name FrigateShape",
        "extends RefCounted",
        "## GENERATED by tools/art/frigate_svg.py from the same geometry as the frigate",
        "## art (frigate_hull.svg). Do not edit by hand: change the generator and rerun it.",
        "## Units: PARTS in local px (1 m = 10 px), the points below in metres.",
        "## Bow = +X, starboard = +Y. Every part is convex (one CollisionPolygon2D each).",
        "",
        "const PARTS := {",
    ]
    for name, pts in parts:
        lines.append('\t"%s": %s,' % (name, gd_arr(pts)))
    lines += [
        "}",
        "## Forward clamp hardpoint on the primary hull's rim (starboard; port mirrors y).",
        "const CLAMP_FWD := Vector2(%.2f, %.2f)" % CLAMP_FWD,
        "## Aft clamp hardpoint on the outer face of the starboard nacelle.",
        "const CLAMP_AFT := Vector2(%.2f, %.2f)" % CLAMP_AFT,
        "## Personnel airlock on the primary hull's rim (starboard).",
        "const AIRLOCK := Vector2(%.2f, %.2f)" % AIRLOCK,
        "## Nacelle centre line (y, m), drive grille span (x, m) and bussard tip.",
        "const NACELLE_Y := %.1f" % NAC_Y,
        "const GRILLE_X := Vector2(-66.0, -22.0)",
        "const BUSSARD_X := %.1f" % (NAC_X0 - 1.2),
        "const NACELLE_TAIL_X := %.1f" % NAC_X1,
        "## Impulse engine exits (x, m) and slot centres (|y|, m).",
        "const IMPULSE_X := -4.6",
        "const IMPULSE_Y := [8.6, 10.6, 12.6]",
        "## Field arc emitter centre line (m), port to starboard, for the glow.",
        "const ARC_MID := %s" % gd_m([lerp(q[0], q[3], 0.5) for q in field_arc_pieces(8)] + [lerp(field_arc_pieces(8)[-1][1], field_arc_pieces(8)[-1][2], 0.5)]),
        "## Half length / half beam (m) for the shield bubble and the camera.",
        "const HALF_LENGTH := 80.0",
        "const HALF_BEAM := %.1f" % (NAC_Y + NAC_R),
        "## Bow and length of the hull centre line (for the name and lights).",
        "const BOW_X := %.1f" % (PRI_C[0] + PRI_A),
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
