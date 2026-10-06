#!/usr/bin/env python3
"""Gloom's Unit Frames — the FILL art (2026-09-29, the owner: shaped bar fills).

The pieces that ride a bar's moving edge (Media/art/fill/):

  end-angled-<r|l|t|b>.png   a FILL END: the fill's end cut on a slant —
  end-point-<r|l|t|b>.png    ... or to a point (an arrow head).
  end-angledpar-<r|l|t|b>.png  the angled end turned half round (not mirrored):
                             a fill running away from an ANGLED bar end leans
                             parallel to it (End Shape, 2026-10-04).
  cap-<angled|point>-<r|l|t|b>.png  the same ends with the INNER edge solid to
                             the corner — the Shaped Ends' cap masks (CLAMPed
                             along the bar; 2026-10-05).
                             64 x 128 for r / l (a flat bar's end: half as wide
                             as the bar is tall), 128 x 64 for t / b; white,
                             tinted by the engine. (The round end is the
                             half-disc the Rounded Ends masks already use,
                             art/cap-<r|l|t|b>.png.)
  marker-knob.png            MARKERS: a disc with a soft rim — 128 x 128
  marker-diamond.png         a diamond — 128 x 128
  marker-glow.png            a soft round glow (drawn with ADD) — 128 x 128
  marker-spark.png           a tall soft spark (ADD), for a flat bar — 64 x 256

Supersampled 4x and reduced, so every edge carries anti-aliasing.
"""
import os, math
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "Media", "art", "fill")
os.makedirs(OUT, exist_ok=True)
S = 4

def white(alpha):
    im = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    im.putalpha(alpha)
    return im

def poly(w, h, pts):
    a = Image.new("L", (w * S, h * S), 0)
    ImageDraw.Draw(a).polygon([(x * S, y * S) for x, y in pts], fill=255)
    return a.resize((w, h), Image.LANCZOS)

def save(name, alpha):
    white(alpha).save(os.path.join(OUT, name))

# the ends, drawn for a RIGHT end (the fill is to the left, x = 0), y down
W, H = 64, 128
ends = {
    "angled": [(0, 0), (W, 0), (0, H)],          # the top runs on, the bottom stops: "/"
    "point":  [(0, 0), (W, H / 2), (0, H)],      # an arrow head
}
for kind, pts in ends.items():
    r = poly(W, H, pts)
    save(f"end-{kind}-r.png", r)
    save(f"end-{kind}-l.png", r.transpose(Image.FLIP_LEFT_RIGHT))
    # a standing bar: the TOP end is the right end turned a quarter to the left
    t = r.transpose(Image.ROTATE_90)
    save(f"end-{kind}-t.png", t)
    save(f"end-{kind}-b.png", t.transpose(Image.FLIP_TOP_BOTTOM))

# PARALLEL angled ends (2026-10-04, the owner): a fill running AWAY from an
# angled bar end leans the SAME way as that end — the end turned half round,
# not mirrored — so the two slants are parallel (a parallelogram).
# end-angledpar-<side> = the opposite side's end-angled, rotated 180.
r = poly(W, H, ends["angled"])
t = r.transpose(Image.ROTATE_90)
opp = {"r": r.transpose(Image.FLIP_LEFT_RIGHT), "l": r, "t": t.transpose(Image.FLIP_TOP_BOTTOM), "b": t}
for side, img in opp.items():
    save(f"end-angledpar-{side}.png", img.transpose(Image.ROTATE_180))

# CAP versions of the angled / point ends, for a bar's SHAPED ENDS (2026-10-05):
# the same shape with the inner edge (the side toward the bar) fully opaque to
# the corner. A cap mask is CLAMPed along the whole bar, so the anti-aliased
# corner pixel of the end art became a half-strength row along the bar's edge.
def solid_inner(img, side):
    px = img.load(); w, h = img.size
    if side in ("r", "l"):
        x = 0 if side == "r" else w - 1
        for y in range(h): px[x, y] = 255
    else:
        y = h - 1 if side == "t" else 0
        for x in range(w): px[x, y] = 255
    return img
for kind, pts in ends.items():
    r = poly(W, H, pts)
    t = r.transpose(Image.ROTATE_90)
    for side, img in (("r", r), ("l", r.transpose(Image.FLIP_LEFT_RIGHT)), ("t", t), ("b", t.transpose(Image.FLIP_TOP_BOTTOM))):
        save(f"cap-{kind}-{side}.png", solid_inner(img.copy(), side))

# markers
N = 128
def disc(n, r, soft):
    a = Image.new("L", (n * S, n * S), 0)
    c = n * S / 2
    ImageDraw.Draw(a).ellipse([c - r * S, c - r * S, c + r * S, c + r * S], fill=255)
    if soft: a = a.filter(ImageFilter.GaussianBlur(soft * S))
    return a.resize((n, n), Image.LANCZOS)

save("marker-knob.png", disc(N, 58, 1.5))
save("marker-diamond.png", poly(N, N, [(N / 2, 4), (N - 4, N / 2), (N / 2, N - 4), (4, N / 2)]))
g = Image.new("L", (N, N), 0)
for y in range(N):
    for x in range(N):
        d = math.hypot(x + 0.5 - N / 2, y + 0.5 - N / 2) / (N / 2)
        g.putpixel((x, y), int(255 * max(0.0, 1 - d) ** 2))
save("marker-glow.png", g)
sw, sh = 64, 256
sp = Image.new("L", (sw, sh), 0)
for y in range(sh):
    for x in range(sw):
        dx = (x + 0.5 - sw / 2) / (sw / 2)
        dy = (y + 0.5 - sh / 2) / (sh / 2)
        d = math.sqrt(dx * dx + dy * dy)
        sp.putpixel((x, y), int(255 * max(0.0, 1 - d) ** 1.5))
save("marker-spark.png", sp)
print("wrote", sorted(os.listdir(OUT)))
