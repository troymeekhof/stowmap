#!/usr/bin/env python3
"""Generates Stowmap.icns (no macOS tools needed). ICNS = header + PNG-embedded entries."""
import struct, io, os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def arc(d, S, radius, width, start, sweep, c0, c1, steps=160):
    cx = cy = S / 2
    box = [cx - radius, cy - radius, cx + radius, cy + radius]
    for i in range(steps):
        t = i / steps
        a0 = start + sweep * t
        d.arc(box, a0, a0 + sweep / steps + 0.8, fill=lerp(c0, c1, t) + (255,), width=width)
    # round caps
    import math
    for ang, col in ((start, c0), (start + sweep, c1)):
        r = radius - width / 2
        x = cx + r * math.cos(math.radians(ang)); y = cy + r * math.sin(math.radians(ang))
        d.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2], fill=col + (255,))

def render(size):
    S = size * 4
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    m = int(S * 0.08); r = int(S * 0.225)
    grad = Image.new("RGBA", (S, S)); gd = ImageDraw.Draw(grad)
    for y in range(S):
        gd.line([(0, y), (S, y)], fill=lerp((30, 28, 52), (9, 9, 16), y / S) + (255,))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([m, m, S - m, S - m], radius=r, fill=255)
    img.paste(grad, (0, 0), mask)

    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0)); gg = ImageDraw.Draw(glow)
    gg.ellipse([S*0.10, S*0.05, S*0.70, S*0.65], fill=(140, 92, 255, 105))
    gg.ellipse([S*0.45, S*0.50, S*0.95, S*0.98], fill=(64, 217, 255, 60))
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.11))
    img.alpha_composite(Image.composite(glow, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))

    d = ImageDraw.Draw(img)
    violet, cyan = (140, 92, 255), (64, 217, 255)
    coral, amber = (255, 115, 102), (255, 199, 77)
    green, mint = (72, 226, 150), (130, 245, 190)
    w = int(S * 0.085)
    # outer ring: one long sweep + a short one (a map of a full disk)
    arc(d, S, S * 0.345, w, -90, 205, violet, cyan)
    arc(d, S, S * 0.345, w, 142, 96, coral, amber)
    # inner ring: the folder you drilled into
    arc(d, S, S * 0.225, w, -90, 118, green, mint)
    arc(d, S, S * 0.225, w, 58, 150, (255, 255, 255), (255, 255, 255))
    # the hub
    c = S / 2; hub = S * 0.052
    d.ellipse([c - hub, c - hub, c + hub, c + hub], fill=(255, 255, 255, 245))

    # soften the plain white inner arc so the colour reads first
    out = img.resize((size, size), Image.LANCZOS)
    return out

TYPES = {16: b"icp4", 32: b"icp5", 64: b"icp6", 128: b"ic07", 256: b"ic08", 512: b"ic09", 1024: b"ic10"}

def main():
    entries = b""
    for size, tag in TYPES.items():
        buf = io.BytesIO(); render(size).save(buf, "PNG"); data = buf.getvalue()
        entries += tag + struct.pack(">I", len(data) + 8) + data
    icns = b"icns" + struct.pack(">I", len(entries) + 8) + entries
    out = os.path.join(HERE, "Stowmap.icns")
    with open(out, "wb") as f: f.write(icns)
    render(512).save(os.path.join(HERE, "icon_preview.png"))
    print("wrote", out, len(icns), "bytes")

if __name__ == "__main__":
    main()
