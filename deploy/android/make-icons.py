#!/usr/bin/env python3
"""Generate the Android desktop icons (flat, matches the kit's dark style).
Run with the host venv python (PIL required): /home/z/.venv/bin/python3 make-icons.py
"""
from PIL import Image, ImageDraw
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icons")
os.makedirs(OUT, exist_ok=True)

NAVY = (29, 36, 46, 255)        # dark card bg, matches taskbar tone
GREEN = (61, 220, 132, 255)     # Android brand green
WHITE = (238, 242, 245, 255)
BLUE = (62, 133, 218, 255)


def rounded_card(size, color):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = size // 6
    d.rounded_rectangle([4, 4, size - 4, size - 4], radius=r, fill=color)
    return img, d


def make_android_icon(path):
    S = 256
    img, d = rounded_card(S, NAVY)
    # robot head: half-rounded green bar
    hw, hh = 132, 74
    x0, y0 = (S - hw) // 2, 104
    d.rounded_rectangle([x0, y0, x0 + hw, y0 + hh], radius=hh // 2, fill=GREEN)
    # eyes
    er = 9
    for ex in (x0 + 38, x0 + hw - 38):
        d.ellipse([ex - er, y0 + 26 - er, ex + er, y0 + 26 + er], fill=NAVY)
    # antennae
    aw = 7
    for sx, sy in ((x0 + 26, y0), (x0 + hw - 26, y0)):
        d.line([sx, sy, sx - 16, sy - 26], fill=GREEN, width=aw)
    # chin dots (body hint)
    for i, cy in enumerate((206, 218)):
        dot = 5 - i
        d.ellipse([S // 2 - dot, cy - dot, S // 2 + dot, cy + dot], fill=GREEN)
    img.save(path)


def make_apk_icon(path):
    S = 256
    img, d = rounded_card(S, NAVY)
    # box (open tray)
    bw, bh = 150, 96
    x0, y0 = (S - bw) // 2, 128
    d.rounded_rectangle([x0, y0, x0 + bw, y0 + bh], radius=12, outline=WHITE, width=10)
    d.rectangle([x0 + 55, y0 - 8, x0 + 95, y0 + 30], fill=NAVY)  # slot gap
    # down arrow
    ax = S // 2
    d.polygon([(ax - 22, 46), (ax + 22, 46), (ax + 22, 92), (ax + 44, 92),
               (ax, 128), (ax - 44, 92), (ax - 22, 92)], fill=GREEN)
    # APK badge
    bx, by, pad = x0 + bw - 58, y0 - 30, 10
    d.rounded_rectangle([bx - 30, by - 16, bx + 30, by + 16], radius=14, fill=BLUE)
    img.save(path)


make_android_icon(os.path.join(OUT, "android-emulator.png"))
make_apk_icon(os.path.join(OUT, "apk-install.png"))
print("icons written to", OUT)
for f in sorted(os.listdir(OUT)):
    print(" ", f, os.path.getsize(os.path.join(OUT, f)), "bytes")
