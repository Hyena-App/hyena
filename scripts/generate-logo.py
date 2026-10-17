#!/usr/bin/env python3
"""Single source of truth for the Hyena mark.

Emits Resources/Hyena.svg (design reference) and Sources/Hyena/LogoArtwork.swift
(vector data drawn by the app, the menu-bar glyph and the rendered app icon).
All coordinates live on Apple's 1024-pt macOS icon grid (824-pt body at 100,100).
Run: python3 scripts/generate-logo.py
"""
import math, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent

def bez(p0, p1, p2, p3, t):
    u = 1 - t
    return tuple(u**3*a + 3*u*u*t*b + 3*u*t*t*c + t**3*d for a, b, c, d in zip(p0, p1, p2, p3))

def mane(curve, n=12, depth=44):
    pts = []
    for i in range(n * 2 + 1):
        t = i / (n * 2)
        x, y = bez(*curve, t)
        x2, y2 = bez(*curve, min(1, t + .01)); x1, y1 = bez(*curve, max(0, t - .01))
        tx, ty = x2 - x1, y2 - y1; l = math.hypot(tx, ty)
        nx, ny = -ty / l, tx / l
        d = depth * (1 - .55 * t) if i % 2 else -6
        lean = .7 * depth * (1 - .5 * t) if i % 2 else 0
        pts.append((x + nx * d - tx / l * lean, y + ny * d - ty / l * lean))
    inner = [bez(*curve, i / 40) for i in range(41)][::-1]
    pts += [(x + 40, y) for x, y in inner]
    return "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts) + " Z"

NECK_BACK = ((372, 318), (262, 520), (196, 760), (150, 980))

def lin(x1, y1, x2, y2, *stops): return ("linear", (x1, y1, x2, y2), stops)
def rad(cx, cy, r, *stops): return ("radial", (cx, cy, r), stops)
def solid(c, o=1.0): return ("solid", c, o)

HEAD = ("M352,352 C372,300 424,268 486,262 C566,256 626,290 670,330 C722,372 792,398 838,416 "
        "C874,428 888,468 864,494 C848,510 822,514 800,516 C802,542 790,570 760,586 "
        "C720,606 664,618 622,632 C600,690 608,800 640,980 L150,980 C196,760 262,520 352,352 Z")
BACK_EAR = "M500,300 C496,236 520,184 562,176 C604,170 620,210 610,250 C602,282 588,300 570,316 Z"
BACK_EAR_IN = "M520,292 C518,240 536,204 562,198 C588,194 596,222 590,250 C584,272 574,290 560,300 Z"
EAR = "M404,312 C380,250 384,176 432,152 C480,130 528,166 522,226 C518,266 504,296 492,316 Z"
EAR_IN = "M424,300 C410,250 414,196 442,182 C472,168 498,194 494,232 C490,262 480,286 470,300 Z"
EYE = "M604,372 C620,352 654,348 672,360 C658,378 628,384 604,372 Z"
GRIN = "M800,516 C756,526 700,530 652,520 C636,516 626,506 622,494"
NOSE = "M826,416 C866,420 892,460 868,492 C852,506 830,500 822,478 C816,456 814,430 826,416 Z"
MANE = mane(NECK_BACK)
SPOTS = [(330,560,18,14,-20),(410,610,16,12,15),(290,660,20,15,-10),(380,700,17,13,0),
         (490,690,15,12,30),(250,780,20,15,-25),(350,800,18,14,10),(460,790,16,12,0),
         (550,760,14,11,20),(300,890,19,14,0),(420,880,17,13,-15),(530,870,15,12,0)]

# (kind, data, fill, extra)
LAYERS = [
    ("path", "M100,100 L924,100 L924,924 L100,924 Z",
     rad(660, 397, 453, ("#FFB86B", .55), ("#FFB86B", 0)), None),
    ("path", BACK_EAR, solid("#9A5E27"), None),
    ("path", BACK_EAR_IN, solid("#3A2213"), None),
    ("path", MANE, lin(410, 300, 110, 980, ("#3B2213", 1), ("#1E110A", 1)), None),
    ("path", HEAD, lin(814, 328, 298, 908, ("#F7D29A", 1), ("#E2A55B", 1, .45), ("#B26E2C", 1)), None),
    ("path", "M622,632 C600,690 608,800 640,980 L150,980 C180,840 220,700 270,580 C380,640 520,650 622,632 Z",
     lin(395, 580, 395, 980, ("#7A4518", 0), ("#7A4518", .55)), None),
    ("path", "M800,516 C802,542 790,570 760,586 C720,606 664,618 622,632 C640,600 650,560 652,522 C700,530 760,526 800,516 Z",
     solid("#A9682A", .85), None),
    ("path", "M600,290 C640,300 660,320 670,330 C722,372 792,398 838,416 C874,428 888,468 864,494 "
             "C848,510 822,514 800,516 C760,524 700,528 652,520 C620,450 610,360 600,290 Z",
     lin(880, 440, 680, 470, ("#2A170C", 1), ("#4A2A14", .88, .4), ("#7A4A22", 0)), None),
    ("path", NOSE, solid("#160C06"), None),
    ("ellipse", (846, 436, 10, 6, 25), solid("#FFFFFF", .25), None),
    ("stroke", GRIN, solid("#140A05"), 10),
    ("path", EAR, lin(454, 132, 454, 316, ("#E9B470", 1), ("#C48440", 1)), None),
    ("path", EAR_IN, solid("#3A2213"), None),
    ("path", EYE, solid("#120904"), None),
    ("ellipse", (652, 362, 4.5, 4.5, 0), solid("#FFE7B8"), None),
] + [("ellipse", s, solid("#6A3A17", .9), None) for s in SPOTS]

# ---------- SVG ----------
def stop_attrs(s):
    off = s[2] if len(s) > 2 else None
    return s[0], s[1], off

def svg_fill(fill, gid):
    kind = fill[0]
    if kind == "solid":
        return f'fill="{fill[1]}" fill-opacity="{fill[2]}"', ""
    stops = fill[2]; n = len(stops); out = []
    for i, s in enumerate(stops):
        c, o, off = stop_attrs(s)
        off = off if off is not None else i / (n - 1)
        out.append(f'<stop offset="{off}" stop-color="{c}" stop-opacity="{o}"/>')
    if kind == "linear":
        x1, y1, x2, y2 = fill[1]
        d = f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{"".join(out)}</linearGradient>'
    else:
        cx, cy, r = fill[1]
        d = f'<radialGradient id="{gid}" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{r}">{"".join(out)}</radialGradient>'
    return f'fill="url(#{gid})"', d

defs, body = [], []
for i, (kind, data, fill, extra) in enumerate(LAYERS):
    attr, d = svg_fill(fill, f"g{i}")
    if d: defs.append(d)
    if kind == "path":
        body.append(f'<path d="{data}" {attr}/>')
    elif kind == "ellipse":
        cx, cy, rx, ry, rot = data
        body.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" transform="rotate({rot} {cx} {cy})" {attr}/>')
    else:
        body.append(f'<path d="{data}" fill="none" stroke="{fill[1]}" stroke-width="{extra}" stroke-linecap="round"/>')

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
<!-- Generated by scripts/generate-logo.py. Do not edit by hand. -->
<defs>
<linearGradient id="bg" gradientUnits="userSpaceOnUse" x1="265" y1="100" x2="594" y2="924"><stop offset="0" stop-color="#2C2F66"/><stop offset=".55" stop-color="#1A1B3F"/><stop offset="1" stop-color="#0C0D20"/></linearGradient>
<clipPath id="body"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
{chr(10).join(defs)}
</defs>
<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/>
<g clip-path="url(#body)">
{chr(10).join(body)}
</g>
<rect x="100.5" y="100.5" width="823" height="823" rx="185" fill="none" stroke="#FFFFFF" stroke-opacity=".12" stroke-width="2"/>
</svg>
'''
(ROOT / "Resources/Hyena.svg").write_text(svg)

# ---------- Swift ----------
def hexrgb(h):
    h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) / 255 for i in (0, 2, 4))

def swift_color(c, o):
    r, g, b = hexrgb(c); return f".init(red: {r:.4f}, green: {g:.4f}, blue: {b:.4f}, opacity: {o})"

def swift_fill(fill):
    if fill[0] == "solid":
        return f".solid({swift_color(fill[1], fill[2])})"
    stops = fill[2]; n = len(stops)
    st = ", ".join(f".init(color: {swift_color(s[0], s[1])}, location: {stop_attrs(s)[2] if stop_attrs(s)[2] is not None else i/(n-1)})" for i, s in enumerate(stops))
    if fill[0] == "linear":
        x1, y1, x2, y2 = fill[1]
        return f".linear([{st}], from: CGPoint(x: {x1}, y: {y1}), to: CGPoint(x: {x2}, y: {y2}))"
    cx, cy, r = fill[1]
    return f".radial([{st}], center: CGPoint(x: {cx}, y: {cy}), radius: {r})"

lines = []
for kind, data, fill, extra in LAYERS:
    if kind == "path":
        lines.append(f'        .init(shape: .path("{data}"), fill: {swift_fill(fill)}),')
    elif kind == "ellipse":
        cx, cy, rx, ry, rot = data
        lines.append(f'        .init(shape: .ellipse(center: CGPoint(x: {cx}, y: {cy}), rx: {rx}, ry: {ry}, degrees: {rot}), fill: {swift_fill(fill)}),')
    else:
        lines.append(f'        .init(shape: .path("{data}"), fill: {swift_fill(fill)}, strokeWidth: {extra}),')

swift = f'''// Generated by scripts/generate-logo.py. Do not edit by hand.
import SwiftUI

extension LogoArtwork {{
    /// Layers drawn inside the icon body, in 1024-pt icon-grid coordinates.
    static let layers: [LogoLayer] = [
{chr(10).join(lines)}
    ]

    /// Silhouette used for the template menu-bar glyph.
    static let glyphFill = ["{BACK_EAR}", "{MANE}", "{HEAD}", "{EAR}"]
    /// Details knocked out of the glyph so the face stays readable at 18 pt.
    static let glyphCutouts = ["{EYE}", "{EAR_IN}"]
    static let glyphGrin = "{GRIN}"
}}
'''
(ROOT / "Sources/Hyena/LogoArtwork.swift").write_text(swift)
print("Wrote Resources/Hyena.svg and Sources/Hyena/LogoArtwork.swift")
