"""Compose a Sky Ace App Store screenshot.

Takes a raw simulator screenshot at the device's native resolution and
produces a final App Store-ready image at the same resolution, with a
sky-blue gradient background, a punchy caption at the top, and the
screenshot framed with rounded corners and a soft shadow.

Usage:
    python3 _compose.py <raw_input.png> <caption> <output.png> [--device iphone|ipad]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Device target resolutions Apple requires.
DEVICE_SIZES = {
    "iphone": (1284, 2778),  # iPhone 6.7" (iPhone 14/15/16 Pro Max class)
    "ipad": (2064, 2752),    # iPad 13" (iPad Pro 13-inch M5)
}

# Sky Ace brand palette (sampled from the app's menu screen).
SKY_TOP = (110, 195, 240)
SKY_BOTTOM = (200, 235, 250)
INK = (20, 50, 90)
SHADOW = (0, 30, 70)

FONT_DIR = Path("/Users/briankelleher/SkyAce/SkyAce/Resources")
FONT_BOLD = FONT_DIR / "PlusJakartaSans-ExtraBold.ttf"


def make_gradient(size: tuple[int, int]) -> Image.Image:
    """Vertical gradient from SKY_TOP to SKY_BOTTOM."""
    w, h = size
    img = Image.new("RGB", (w, h), SKY_TOP)
    pixels = img.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        c = tuple(int(SKY_TOP[i] + (SKY_BOTTOM[i] - SKY_TOP[i]) * t) for i in range(3))
        for x in range(w):
            pixels[x, y] = c
    return img


def rounded_rect_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (size[0] - 1, size[1] - 1)], radius=radius, fill=255
    )
    return mask


def fit_text(text: str, max_width: int, max_size: int, min_size: int = 60) -> ImageFont.FreeTypeFont:
    """Find the largest font size where text fits within max_width."""
    size = max_size
    while size > min_size:
        font = ImageFont.truetype(str(FONT_BOLD), size)
        bbox = font.getbbox(text)
        if bbox[2] - bbox[0] <= max_width:
            return font
        size -= 4
    return ImageFont.truetype(str(FONT_BOLD), min_size)


def compose(raw_path: Path, caption: str, output_path: Path, device: str) -> None:
    target_w, target_h = DEVICE_SIZES[device]

    # Load and confirm the raw screenshot is the right resolution.
    raw = Image.open(raw_path).convert("RGB")
    if raw.size != (target_w, target_h):
        raw = raw.resize((target_w, target_h), Image.LANCZOS)

    # Background gradient.
    canvas = make_gradient((target_w, target_h))

    # Layout: caption in the top ~22%, screenshot fills the rest with insets.
    caption_band_h = int(target_h * 0.22)
    inset_x = int(target_w * 0.055)
    inset_top = caption_band_h
    inset_bottom = int(target_h * 0.045)
    shot_w = target_w - 2 * inset_x
    shot_h = target_h - inset_top - inset_bottom

    # Resize the raw screenshot to fit the inset, preserving aspect.
    raw_ratio = raw.width / raw.height
    target_ratio = shot_w / shot_h
    if raw_ratio > target_ratio:
        # Raw is wider than target; fit by width.
        new_w = shot_w
        new_h = int(shot_w / raw_ratio)
    else:
        new_h = shot_h
        new_w = int(shot_h * raw_ratio)
    shot = raw.resize((new_w, new_h), Image.LANCZOS)

    # Round the corners of the screenshot.
    radius = int(min(new_w, new_h) * 0.04)
    mask = rounded_rect_mask((new_w, new_h), radius)

    # Drop shadow under the screenshot.
    shadow_offset = 18
    shadow_blur = 32
    shadow_layer = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
    shadow_block = Image.new(
        "RGBA",
        (new_w + 2 * shadow_blur, new_h + 2 * shadow_blur),
        (0, 0, 0, 0),
    )
    sdraw = ImageDraw.Draw(shadow_block)
    sdraw.rounded_rectangle(
        [
            (shadow_blur, shadow_blur),
            (shadow_blur + new_w - 1, shadow_blur + new_h - 1),
        ],
        radius=radius,
        fill=(0, 30, 70, 110),
    )
    shadow_block = shadow_block.filter(ImageFilter.GaussianBlur(shadow_blur / 2))
    shot_x = inset_x + (shot_w - new_w) // 2
    shot_y = inset_top + (shot_h - new_h) // 2
    shadow_layer.paste(
        shadow_block,
        (shot_x - shadow_blur, shot_y - shadow_blur + shadow_offset),
        shadow_block,
    )
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow_layer)

    # Paste the rounded screenshot.
    canvas.paste(shot, (shot_x, shot_y), mask)

    # Caption.
    draw = ImageDraw.Draw(canvas)
    max_caption_w = int(target_w * 0.86)
    max_size = int(target_h * 0.06)
    font = fit_text(caption, max_caption_w, max_size)
    bbox = font.getbbox(caption)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    text_x = (target_w - text_w) // 2 - bbox[0]
    text_y = (caption_band_h - text_h) // 2 - bbox[1] + int(target_h * 0.025)

    # Subtle drop shadow on the text.
    shadow_text = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow_text).text(
        (text_x + 4, text_y + 6), caption, font=font, fill=(0, 30, 70, 130)
    )
    shadow_text = shadow_text.filter(ImageFilter.GaussianBlur(3))
    canvas = Image.alpha_composite(canvas, shadow_text)
    draw = ImageDraw.Draw(canvas)
    draw.text((text_x, text_y), caption, font=font, fill=(255, 255, 255, 255))

    canvas.convert("RGB").save(output_path, "PNG", optimize=True)
    print(f"Wrote {output_path} ({target_w}x{target_h})")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("raw")
    parser.add_argument("caption")
    parser.add_argument("output")
    parser.add_argument("--device", choices=DEVICE_SIZES.keys(), default="iphone")
    args = parser.parse_args()

    compose(Path(args.raw), args.caption, Path(args.output), args.device)
    return 0


if __name__ == "__main__":
    sys.exit(main())
