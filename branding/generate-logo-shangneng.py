#!/usr/bin/env python3
"""Generate branding assets: 300x60 banner + 256x256 square icon."""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
BANNER_OUT = ROOT / "logo-shangneng-300x60.png"
ICON_OUT = ROOT / "icon-shangneng-256.png"
TEXT = "郑州熵能"
BG = (15, 76, 129, 255)
FG = (255, 255, 255, 255)


def _load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        Path(r"C:\Windows\Fonts\msyhbd.ttc"),
        Path(r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
        Path("/usr/share/fonts/truetype/noto/NotoSansCJK-Bold.ttc"),
        Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"),
    ]
    for path in candidates:
        if path.is_file():
            try:
                return ImageFont.truetype(str(path), size)
            except OSError:
                continue
    return ImageFont.load_default()


def _draw_centered_text(
    draw: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    text: str,
    font: ImageFont.FreeTypeFont | ImageFont.ImageFont,
    fill: tuple[int, int, int, int],
) -> None:
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x0, y0, x1, y1 = box
    x = x0 + (x1 - x0 - tw) // 2 - bbox[0]
    y = y0 + (y1 - y0 - th) // 2 - bbox[1]
    draw.text((x, y), text, font=font, fill=fill)


def generate_banner() -> None:
    w, h = 300, 60
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((2, 8, w - 3, h - 8), radius=10, fill=BG)
    font = _load_font(34)
    _draw_centered_text(draw, (0, 0, w, h), TEXT, font, FG)
    img.save(BANNER_OUT, format="PNG", optimize=True)


def generate_icon() -> None:
    size = 256
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle((16, 16, size - 17, size - 17), radius=48, fill=BG)
    font = _load_font(72)
    _draw_centered_text(draw, (0, 0, size, size), TEXT, font, FG)
    img.save(ICON_OUT, format="PNG", optimize=True)


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    generate_banner()
    generate_icon()
    print(f"wrote {BANNER_OUT} ({BANNER_OUT.stat().st_size} bytes)")
    print(f"wrote {ICON_OUT} ({ICON_OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
