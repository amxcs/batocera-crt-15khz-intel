#!/usr/bin/env python3
"""720x480 overscan pattern with true 1px markers.

Unlike the 8px-band version, every frame here is exactly one pixel thick, so
the outermost white line marks the literal edge of the 720x480 raster. In an
interlaced mode the left/right verticals are solid (they appear on every
scanline) while the top/bottom horizontals live in a single field and will
flicker at 30Hz - that is expected, not a fault.
"""
from PIL import Image, ImageDraw

W, H = 720, 480
img = Image.new("RGB", (W, H), "black")
d = ImageDraw.Draw(img)

# Nested 1px frames. Seeing a colour means that many pixels in from the true
# edge are still visible.
frames = [
    (0,  (255, 255, 255)),   # edge
    (2,  (255, 0, 0)),
    (4,  (255, 200, 0)),
    (6,  (0, 220, 0)),
    (8,  (0, 160, 255)),
    (16, (255, 0, 255)),
    (24, (120, 120, 120)),
]
for o, colour in frames:
    d.rectangle([o, o, W - 1 - o, H - 1 - o], outline=colour, width=1)

# Corner tick marks: 20px arms just inside the edge, so a clipped corner is
# obvious even when the 1px frame itself is lost to overscan.
for cx, cy, dx, dy in ((0, 0, 1, 1), (W - 1, 0, -1, 1),
                       (0, H - 1, 1, -1), (W - 1, H - 1, -1, -1)):
    d.line([(cx, cy), (cx + dx * 20, cy)], fill="white")
    d.line([(cx, cy), (cx, cy + dy * 20)], fill="white")

# Sparse grid for linearity.
for x in range(40, W - 39, 40):
    d.line([(x, 32), (x, H - 33)], fill=(40, 40, 40))
for y in range(40, H - 39, 40):
    d.line([(32, y), (W - 33, y)], fill=(40, 40, 40))

# Centre cross.
d.line([(W // 2, H // 2 - 40), (W // 2, H // 2 + 40)], fill="white")
d.line([(W // 2 - 40, H // 2), (W // 2 + 40, H // 2)], fill="white")

d.text((W // 2 - 20, 34), "TOP", fill="white")
d.text((W // 2 - 30, H - 44), "BOTTOM", fill="white")
d.text((34, H // 2 - 4), "L", fill="white")
d.text((W - 40, H // 2 - 4), "R", fill="white")
d.text((W // 2 - 95, H // 2 + 60), "1px frames: white=0 red=2 yellow=4",
       fill=(170, 170, 170))
d.text((W // 2 - 95, H // 2 + 76), "green=6 blue=8 magenta=16 grey=24",
       fill=(170, 170, 170))

out = ("/tmp/claude-1000/-home-retro/00dc9f80-e78a-466b-809f-f5896d292283"
       "/scratchpad/crt-test-1px.png")
img.save(out)
print(out)
