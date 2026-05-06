"""Build a labeled contact sheet from extracted gameplay frames."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SRC_DIR = Path("/tmp/skyace-frames")
OUT = Path("/Users/briankelleher/SkyAce/docs/app-store-screenshots/video/contact-sheet.jpg")
FONT = Path("/Users/briankelleher/SkyAce/SkyAce/Resources/PlusJakartaSans-Bold.ttf")

THUMB_W = 220
COLS = 10
PAD = 12
LABEL_H = 36
BG = (245, 247, 250)
INK = (20, 50, 90)


def main() -> None:
    frames = sorted(SRC_DIR.glob("frame_*.jpg"))
    if not frames:
        raise SystemExit("No frames found in /tmp/skyace-frames")

    sample = Image.open(frames[0])
    aspect = sample.height / sample.width
    thumb_h = int(THUMB_W * aspect)
    cell_w = THUMB_W + PAD
    cell_h = thumb_h + LABEL_H + PAD

    rows = (len(frames) + COLS - 1) // COLS
    sheet_w = cell_w * COLS + PAD
    sheet_h = cell_h * rows + PAD

    sheet = Image.new("RGB", (sheet_w, sheet_h), BG)
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(str(FONT), 22)

    for i, frame_path in enumerate(frames):
        col = i % COLS
        row = i // COLS
        x = PAD + col * cell_w
        y = PAD + row * cell_h

        thumb = Image.open(frame_path).resize((THUMB_W, thumb_h), Image.LANCZOS)
        sheet.paste(thumb, (x, y))

        # Frame number under the thumbnail.
        label = f"#{i + 1}"
        draw.text(
            (x + 6, y + thumb_h + 6),
            label,
            font=font,
            fill=INK,
        )

    sheet.save(OUT, "JPEG", quality=85, optimize=True)
    print(f"Wrote {OUT} ({sheet_w}x{sheet_h}, {len(frames)} frames)")


if __name__ == "__main__":
    main()
