#!/usr/bin/env python3
"""720x480 overscan ruler.

Reads out directly how many pixels the TV hides on each edge, instead of
iterating by trial and error. Each edge carries a staircase of markers at
5px intervals, every marker labelled with its distance from the true edge.
The smallest number still visible on an edge is how much that edge is losing.

Everything is >=3px thick so it survives interlace: a 1px horizontal line
lives in only one field and flickers at 30Hz, which is unreadable.
"""
import glob
import sys

from PIL import Image, ImageDraw, ImageFont

W, H = 720, 480
DEPTHS = list(range(5, 65, 5))          # 5..60


def pick_font(size=20):
    """Batocera ships no system font directory, so search for any TrueType."""
    for pattern in (
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            "/usr/share/fonts/**/*Bold*.ttf",
            "/usr/lib/python3*/site-packages/pygame/freesansbold.ttf",
            "/usr/share/fonts/**/*.ttf",
            "/usr/**/*Bold*.ttf"):
        for path in sorted(glob.glob(pattern, recursive=True)):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    # Last resort: the built-in bitmap font. Small, but the numbers are still
    # legible, and a ruler with no labels would be useless.
    return ImageFont.load_default()


FONT = pick_font()

img = Image.new("RGB", (W, H), (0, 0, 0))
d = ImageDraw.Draw(img)

# Alternate colours so adjacent markers never blur together on a CRT.
COLS = [(255, 255, 255), (255, 210, 0), (0, 230, 90), (0, 180, 255),
        (255, 90, 90), (230, 120, 255)]


def label(x, y, text, colour, anchor):
    d.text((x, y), text, fill=colour, font=FONT, anchor=anchor)


# --- top and bottom: horizontal markers, staircase left to right ---
for i, dep in enumerate(DEPTHS):
    c = COLS[i % len(COLS)]
    x0 = 30 + i * 56
    x1 = x0 + 48
    d.rectangle([x0, dep, x1, dep + 2], fill=c)              # top
    label(x0 + 24, dep + 6, str(dep), c, "ma")
    y = H - 1 - dep
    d.rectangle([x0, y - 2, x1, y], fill=c)                  # bottom
    label(x0 + 24, y - 6, str(dep), c, "md")

# --- left and right: vertical markers, staircase top to bottom ---
for i, dep in enumerate(DEPTHS):
    c = COLS[i % len(COLS)]
    y0 = 90 + i * 26
    y1 = y0 + 20
    d.rectangle([dep, y0, dep + 2, y1], fill=c)              # left
    label(dep + 7, (y0 + y1) // 2, str(dep), c, "lm")
    x = W - 1 - dep
    d.rectangle([x - 2, y0, x, y1], fill=c)                  # right
    label(x - 7, (y0 + y1) // 2, str(dep), c, "rm")

# Centre cross, for V-Centre / H-Centre.
d.rectangle([W // 2 - 1, H // 2 - 50, W // 2 + 1, H // 2 + 50], fill="white")
d.rectangle([W // 2 - 50, H // 2 - 1, W // 2 + 50, H // 2 + 1], fill="white")

label(W // 2, H // 2 - 70, "READ THE SMALLEST", (170, 170, 170), "ms")
label(W // 2, H // 2 + 60, "VISIBLE NUMBER PER EDGE", (170, 170, 170), "ms")

out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/crt-ruler.png"
img.save(out)
print(out)
