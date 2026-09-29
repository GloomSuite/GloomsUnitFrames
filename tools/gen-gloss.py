#!/usr/bin/env python3
"""Gloom's Unit Frames — the GLOSS art (the owner's Figma mock, 2026-09-29).

The mock's bar ("Rectangle 220", 290 x 40, right end fully round) takes its
gloss from ONE effect: an INNER SHADOW, white 65%, offset (0, 4), blur 4,
spread 0 — Figma's (CSS's) inset box-shadow. This renders exactly that, at
4 texels per UI unit:

  gloss-band.png         the straight run's profile: the rim along a top edge,
                         32 units tall (it depends only on the distance from
                         the top edge, never on the bar's height), stretched
                         along the bar
  gloss-cap-r-<h>.png    a flat bar's round RIGHT end at height <h> (h/2 x h);
  gloss-cap-l-<h>.png    its mirror, the LEFT end
  gloss-cap-t-<w>.png    a standing bar's round TOP end at width <w> (w x w/2)

(A standing bar lit from above has no rim on its long sides and none at the
bottom — the offset is downward — so only its top end glosses.)
Heights 8..96 in steps of 4; the engine takes the nearest and scales the rest.
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

OUT = os.path.join(os.path.dirname(__file__), "..", "Media", "art", "gloss")
T = 4                      # texels per UI unit
OFF, BLUR, ALPHA = 4, 4, 0.65
os.makedirs(OUT, exist_ok=True)

def inner_shadow(inside, bleed=False):
    """inside: L mask (255 = shape), T texels per unit. Returns the rim's alpha.
    bleed: the rim is NOT cut to the shape — it runs on past the edge, and the
    bar's own cap mask (the one cutting the fill) cuts it in the game, so the
    rim and the bar end at the very same edge. Cut here, the rim stopped a hair
    inside the mask's softer edge and a sliver of the bar showed (the owner,
    2026-09-29)."""
    outside = ImageChops.invert(inside)
    shifted = ImageChops.offset(outside, 0, OFF * T)
    # ImageChops.offset wraps: the rows that wrapped in at the top are outside anyway
    d = ImageDraw.Draw(shifted); d.rectangle([0, 0, shifted.size[0], OFF * T], fill=255)
    blurred = shifted.filter(ImageFilter.GaussianBlur(BLUR / 2 * T))    # CSS blur b → sigma b/2
    if bleed:
        # grow the shape by 2 units so the rim covers the mask's soft edge and beyond
        grown = inside.filter(ImageFilter.MaxFilter(4 * T + 1))
        return ImageChops.multiply(blurred, grown).point(lambda v: int(v * ALPHA + 0.5))
    return ImageChops.multiply(blurred, inside).point(lambda v: int(v * ALPHA + 0.5))

def save(alpha, name):
    w, h = alpha.size
    Image.merge("RGBA", [Image.new("L", (w, h), 255)] * 3 + [alpha]).save(os.path.join(OUT, name))

PAD = 16                   # units of room above the shape (outside, so the shadow has something to cast from)

# the straight run: a wide flat bar, its middle column
L, H = 200, 64
img = Image.new("L", ((L + 2 * PAD) * T, (H + 2 * PAD) * T), 0)
ImageDraw.Draw(img).rectangle([PAD * T, PAD * T, (PAD + L) * T - 1, (PAD + H) * T - 1], fill=255)
rim = inner_shadow(img)
col = rim.crop(((PAD + L // 2) * T, PAD * T, (PAD + L // 2) * T + T, (PAD + 32) * T))
save(col, "gloss-band.png")

for h in range(8, 97, 4):
    r = h / 2
    # a flat bar, right end round: rectangle + disc
    L = 4 * h
    W_, H_ = int((L + 2 * PAD) * T), int((h + 2 * PAD) * T)
    img = Image.new("L", (W_, H_), 0); d = ImageDraw.Draw(img)
    x0, y0 = PAD * T, PAD * T
    xr = (PAD + L - r) * T                    # where the round end begins
    d.rectangle([x0, y0, xr, y0 + h * T - 1], fill=255)
    d.ellipse([xr - r * T, y0, xr + r * T - 1, y0 + h * T - 1], fill=255)
    rim = inner_shadow(img, bleed=True)
    cap = rim.crop((int(xr), y0, int(xr + r * T), y0 + h * T))
    save(cap, f"gloss-cap-r-{h}.png")
    save(cap.transpose(Image.FLIP_LEFT_RIGHT), f"gloss-cap-l-{h}.png")
    # a standing bar, top end round (width h)
    W_, H_ = int((h + 2 * PAD) * T), int((L + 2 * PAD) * T)
    img = Image.new("L", (W_, H_), 0); d = ImageDraw.Draw(img)
    yt = (PAD + r) * T                         # the dome's centre row
    d.ellipse([x0, PAD * T, x0 + h * T - 1, PAD * T + h * T - 1], fill=255)
    d.rectangle([x0, yt, x0 + h * T - 1, (PAD + L) * T - 1], fill=255)
    rim = inner_shadow(img, bleed=True)
    save(rim.crop((x0, PAD * T, x0 + h * T, int(yt))), f"gloss-cap-t-{h}.png")
print("gloss art written to", os.path.normpath(OUT))
