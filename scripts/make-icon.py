"""Draws the Sova app icon and writes Resources/AppIcon.icns (needs Pillow and iconutil)."""
import math, pathlib, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFilter

S = 2048  # drawn at 2x, downscaled for smooth edges
root = pathlib.Path(__file__).resolve().parent.parent

def icon():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # macOS icon grid: 824/1024 rounded square, radius ~185/1024.
    m, r = int(S * 100 / 1024), int(S * 185 / 1024)
    bg = Image.new("RGBA", (S, S))
    top, bot = (38, 48, 92), (12, 16, 36)
    gd = ImageDraw.Draw(bg)
    for y in range(S):
        t = y / S
        gd.line([(0, y), (S, y)], fill=tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3)) + (255,))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([m, m, S - m, S - m], r, fill=255)
    img.paste(bg, (0, 0), mask)
    d = ImageDraw.Draw(img)

    # Stars and a crescent moon: it's night, and the owl is up.
    for x, y, rr in [(560, 470, 9), (1500, 420, 7), (1640, 700, 6), (430, 760, 6), (1180, 330, 5)]:
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(255, 244, 214, 230))
    moon = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(moon)
    md.ellipse([1430, 330, 1650, 550], fill=255)
    md.ellipse([1490, 300, 1700, 510], fill=0)  # cut out, so the gradient shows through
    img.paste((255, 226, 150, 255), (0, 0), moon)

    # Owl perched on a branch. Coordinates are in 1024 units, scaled by k.
    k = S / 1024
    def P(*pts): return [(x * k, y * k) for x, y in pts]
    def box(cx, cy, rx, ry): return [(cx - rx) * k, (cy - ry) * k, (cx + rx) * k, (cy + ry) * k]
    def oval(cx, cy, rx, ry, angle=0, n=72):
        a = math.radians(angle)
        return [((cx + rx * math.cos(t) * math.cos(a) - ry * math.sin(t) * math.sin(a)) * k,
                 (cy + rx * math.cos(t) * math.sin(a) + ry * math.sin(t) * math.cos(a)) * k)
                for t in (2 * math.pi * i / n for i in range(n))]

    body, wing, light, dark = (150, 106, 70, 255), (112, 76, 48, 255), (236, 216, 180, 255), (62, 40, 24, 255)

    # Branch with a leaf.
    d.line(P((130, 812), (900, 790)), fill=(92, 62, 38, 255), width=int(34 * k))
    d.ellipse(box(130, 812, 17, 17), fill=(92, 62, 38, 255))
    d.polygon(oval(820, 760, 46, 18, -30), fill=(88, 150, 90, 255))

    # Ear tufts, angled outward, behind the head.
    d.polygon(P((322, 400), (276, 214), (316, 262), (420, 340)), fill=body)
    d.polygon(P((702, 400), (748, 214), (708, 262), (604, 340)), fill=body)

    # Egg-shaped body and the wings folded on the sides.
    d.ellipse(box(512, 560, 212, 250), fill=body)
    d.polygon(oval(338, 620, 74, 170, 12), fill=wing)
    d.polygon(oval(686, 620, 74, 170, -12), fill=wing)

    # Light belly with rows of feather chevrons.
    d.ellipse(box(512, 680, 132, 118), fill=(212, 182, 138, 255))
    for row, y in enumerate((632, 680, 728)):
        xs = (452, 512, 572) if row != 1 else (482, 542)
        for x in xs:
            d.line(P((x - 18, y), (x, y + 16), (x + 18, y)), fill=(150, 112, 74, 255), width=int(8 * k), joint="curve")

    # Facial disc: two pale overlapping rounds, the owl's "mask".
    d.ellipse(box(430, 470, 122, 118), fill=light)
    d.ellipse(box(594, 470, 122, 118), fill=light)
    # V notch at the top of the mask makes the heart-shaped owl face.
    d.polygon(P((452, 346), (572, 346), (512, 418)), fill=body)

    # Eyes: dark rim, green iris, pupil, glint.
    for ex in (432, 592):
        d.ellipse(box(ex, 476, 86, 86), fill=dark)
        d.ellipse(box(ex, 476, 72, 72), fill=(52, 199, 89, 255))
        d.ellipse(box(ex, 476, 36, 36), fill=(14, 18, 30, 255))
        d.ellipse(box(ex - 24, 452, 15, 15), fill=(255, 255, 255, 240))


    # Hooked beak.
    d.polygon(P((486, 502), (538, 502), (520, 572), (508, 586), (500, 560)), fill=(245, 170, 60, 255))

    # Talons gripping the branch.
    for fx in (456, 568):
        for dx in (-22, 0, 22):
            d.ellipse(box(fx + dx, 800, 13, 20), fill=(245, 170, 60, 255))
    return img.resize((1024, 1024), Image.LANCZOS)

def main():
    base = icon()
    base.save(root / "Resources/AppIcon-1024.png")
    with tempfile.TemporaryDirectory() as tmp:
        iconset = pathlib.Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for px in (16, 32, 128, 256, 512):
            base.resize((px, px), Image.LANCZOS).save(iconset / f"icon_{px}x{px}.png")
            base.resize((px * 2, px * 2), Image.LANCZOS).save(iconset / f"icon_{px}x{px}@2x.png")
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(root / "Resources/AppIcon.icns")], check=True)
    print("ok", root / "Resources/AppIcon.icns")

main()
