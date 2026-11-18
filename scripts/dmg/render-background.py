#!/usr/bin/env python3
"""Render the Seawall installer-DMG background at @1x (640x400) and @2x (1280x800).

Colors are sampled from Resources/AppIcon.svg: teal #38A6B6 → #1B7586, foam #BDE4EB,
wave #5FB7C6. The committed PNGs in this folder are what make-dmg.sh uses; run this
again only if you change the design.

  python3 scripts/dmg/render-background.py

Needs Pillow. For the typeface it looks for Inter (variable), then any Inter-Medium
or Inter-Regular, then the font at FONT_PATH. The DMG itself does not need the font
because the PNGs are committed.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Logical (1x) canvas and icon-view layout. make-dmg.sh uses the same numbers.
WIDTH, HEIGHT = 640, 400
ICON_SIZE = 128
ICON_LEFT = (160, 186)   # Finder icon centers: app on the left, Applications on the right
ICON_RIGHT = (480, 186)
TEXT = "Drag Seawall to Applications"

# AppIcon.svg
TEAL_LIGHT = (56, 166, 182)    # #38A6B6
TEAL_DARK = (27, 117, 134)     # #1B7586
FOAM = (189, 228, 235)         # #BDE4EB
WAVE = (95, 183, 198)          # #5FB7C6
CREAM = (246, 243, 236)        # warm page, close to seawall.work #F3F0E9
INK = (22, 72, 82)             # darker teal for type

OUT = Path(__file__).resolve().parent


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def find_font() -> str:
    env = os.environ.get("FONT_PATH")
    if env and Path(env).is_file():
        return env
    candidates = [
        "/usr/share/fonts/truetype/sand-box/google/Inter/Inter-VariableFont_opsz,wght.ttf",
        "/Library/Fonts/Inter-VariableFont_opsz,wght.ttf",
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFNSText.ttf",
        "/System/Library/Fonts/Supplemental/Arial Regular.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    # Homebrew Inter, user fonts
    home = Path.home()
    candidates += [
        str(p)
        for p in [
            home / "Library/Fonts/Inter-VariableFont_opsz,wght.ttf",
            Path("/opt/homebrew/share/fonts/Inter-VariableFont_opsz,wght.ttf"),
        ]
        if p.is_file()
    ]
    for path in candidates:
        if Path(path).is_file():
            return path
    raise SystemExit(
        "render-background: no Inter (or fallback) font found. Set FONT_PATH to a .ttf."
    )


def load_font(path: str, size: int, weight: int = 550) -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(path, size)
    try:
        axes = font.get_variation_axes()
        values = []
        for axis in axes:
            name = axis["name"]
            if name in (b"Weight", b"wght"):
                values.append(max(axis["minimum"], min(axis["maximum"], weight)))
            elif name in (b"Optical size", b"opsz"):
                # Prefer the point size, clamped to the axis.
                values.append(max(axis["minimum"], min(axis["maximum"], size)))
            else:
                values.append(axis["default"])
        font.set_variation_by_axes(values)
    except OSError:
        pass
    return font


def gradient_base(w: int, h: int) -> Image.Image:
    """Cream at the top, a soft teal wash toward the bottom."""
    img = Image.new("RGB", (w, h), CREAM)
    px = img.load()
    bottom = lerp(CREAM, FOAM, 0.55)
    for y in range(h):
        t = (y / (h - 1)) ** 1.15
        color = lerp(CREAM, bottom, t)
        for x in range(w):
            px[x, y] = color
    return img


def add_wave(img: Image.Image, scale: int) -> Image.Image:
    """A faint AppIcon-style wave along the bottom, well below the icons."""
    w, h = img.size
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    def wave_path(y0, amp, cycles, phase):
        pts = []
        for x in range(0, w + 1, max(1, scale)):
            # two soft humps, similar to the icon's double wave
            t = x / w
            y = y0 + amp * (
                0.55 * __import__("math").sin((t * cycles + phase) * 6.28318)
                + 0.45 * __import__("math").sin((t * (cycles + 1) + phase * 1.3) * 6.28318)
            )
            pts.append((x, y))
        pts += [(w, h), (0, h)]
        return pts

    y0 = int(h * 0.78)
    amp = 18 * scale
    draw.polygon(wave_path(y0, amp, 2.0, 0.15), fill=(*FOAM, 90))
    draw.polygon(wave_path(y0 + 14 * scale, amp * 0.85, 2.2, 0.6), fill=(*WAVE, 70))
    return Image.alpha_composite(img.convert("RGBA"), overlay)


def draw_arrow(draw: ImageDraw.ImageDraw, scale: int) -> None:
    """A clear horizontal arrow between the two icon slots."""
    lx, ly = ICON_LEFT
    rx, ry = ICON_RIGHT
    # Start/end just clear of the 128px icons (icon radius = 64).
    pad = 64 + 18
    x0 = (lx + pad) * scale
    x1 = (rx - pad) * scale
    y = ly * scale
    thickness = 7 * scale
    head = 20 * scale

    # Shaft with rounded cap on the left.
    draw.line([(x0, y), (x1 - head * 0.72, y)], fill=TEAL_DARK + (255,), width=thickness)
    r = thickness / 2
    draw.ellipse((x0 - r, y - r, x0 + r, y + r), fill=TEAL_DARK + (255,))
    # Arrowhead
    draw.polygon(
        [
            (x1, y),
            (x1 - head, y - head * 0.62),
            (x1 - head * 0.82, y),
            (x1 - head, y + head * 0.62),
        ],
        fill=TEAL_DARK + (255,),
    )


def draw_text(img: Image.Image, scale: int, font_path: str) -> None:
    # Draw on a slightly larger overlay so the letters don't clip, then alpha-composite.
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    size = 17 * scale
    font = load_font(font_path, size, weight=560)
    # Modest tracking, measured in pixels at this scale.
    tracking = 0.6 * scale
    # Width with tracking
    chars = list(TEXT)
    widths = [draw.textlength(ch, font=font) for ch in chars]
    total = sum(widths) + tracking * (len(chars) - 1)
    x = (img.width - total) / 2
    y = 36 * scale
    for ch, cw in zip(chars, widths):
        draw.text((x, y), ch, font=font, fill=INK + (255,))
        x += cw + tracking
    return Image.alpha_composite(img, overlay)


def render(scale: int, font_path: str) -> Image.Image:
    img = gradient_base(WIDTH * scale, HEIGHT * scale)
    img = add_wave(img, scale)
    draw = ImageDraw.Draw(img)
    draw_arrow(draw, scale)
    img = draw_text(img, scale, font_path)
    return img.convert("RGB")


def preview(bg2x: Image.Image, icon_path: Path, out: Path) -> None:
    """Composite the AppIcon (and a folder stand-in) so we can judge placement."""
    preview = bg2x.copy().convert("RGBA")
    # App icon at 128pt = 256px on @2x
    icon = Image.open(icon_path).convert("RGBA")
    icon = icon.resize((ICON_SIZE * 2, ICON_SIZE * 2), Image.Resampling.LANCZOS)
    # Slight drop shadow
    def paste_icon(base, im, center):
        cx, cy = center[0] * 2, center[1] * 2
        shadow = Image.new("RGBA", (im.width + 24, im.height + 24), (0, 0, 0, 0))
        s = Image.new("RGBA", im.size, (0, 0, 0, 70))
        # keep the icon's alpha
        s.putalpha(im.split()[-1].point(lambda a: int(a * 0.35)))
        shadow.paste(s, (14, 16), s)
        shadow = shadow.filter(ImageFilter.GaussianBlur(6))
        x = cx - im.width // 2
        y = cy - im.height // 2
        base.alpha_composite(shadow, (x - 8, y - 4))
        base.alpha_composite(im, (x, y))

    paste_icon(preview, icon, ICON_LEFT)

    # Simple Applications-folder stand-in (not used on the real DMG).
    folder = Image.new("RGBA", (ICON_SIZE * 2, ICON_SIZE * 2), (0, 0, 0, 0))
    fd = ImageDraw.Draw(folder)
    # tab
    fd.rounded_rectangle((28, 46, 120, 80), radius=12, fill=(90, 170, 230, 255))
    fd.rounded_rectangle((20, 66, 236, 230), radius=28, fill=(70, 150, 220, 255))
    fd.rounded_rectangle((20, 86, 236, 230), radius=24, fill=(110, 186, 240, 255))
    paste_icon(preview, folder, ICON_RIGHT)

    # Fake labels, like Finder's 12pt
    font = load_font(find_font(), 24, weight=500)
    d = ImageDraw.Draw(preview)
    for label, center in (("Seawall", ICON_LEFT), ("Applications", ICON_RIGHT)):
        tw = d.textlength(label, font=font)
        x = center[0] * 2 - tw / 2
        y = center[1] * 2 + ICON_SIZE + 8
        # Finder draws a slight white halo; skip, just ink
        d.text((x, y), label, font=font, fill=(40, 40, 40, 230))

    preview.convert("RGB").save(out, "PNG")
    print(f"wrote {out}")


def main() -> None:
    font_path = find_font()
    print(f"font: {font_path}")
    # Render each scale on its own so downsampling can't ring around the type.
    img1 = render(1, font_path)
    img2 = render(2, font_path)
    p1 = OUT / "background@1x.png"
    p2 = OUT / "background@2x.png"
    img1.save(p1, "PNG", optimize=True)
    img2.save(p2, "PNG", optimize=True)
    print(f"wrote {p1} {img1.size}")
    print(f"wrote {p2} {img2.size}")
    icon = Path(__file__).resolve().parents[2] / "Resources" / "AppIcon.icns"
    preview(img2, icon, OUT / "layout-preview@2x.png")


if __name__ == "__main__":
    sys.exit(main())
