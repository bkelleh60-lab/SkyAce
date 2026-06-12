#!/usr/bin/env python3
"""SKY-83: convert raw Stitch exports into game-ready transparent PNGs.

The Stitch exports in ~/Documents/Sky-83 have their "transparency" baked in
as opaque pixels — either a white matte or the grey transparency-checkerboard
pattern. This script removes that background with a border-connected flood
fill (so white/grey *inside* the artwork survives), crops to content, and for
the three landing-gear variants registers the plane against its bundled
gear-up counterpart so the in-game sprite swap doesn't visibly resize or
shift the fuselage.

Registration contract relied on by PlaneNode.setLandingGear(deployed:):
  * gear-down canvas width == gear-up canvas width
  * the plane body is scaled and positioned to match the gear-up content
    bbox, top-aligned, with any extra canvas height hanging below (gear)
so the displayed gear-down height is 45 * (texD.h/texD.w)/(texU.h/texU.w)
with the sprite shifted down by half the extra height.

Two background styles in this batch:
  * cell-shaded exports (shadow dart, night hawk, all scene/UI art) sit on
    white or light checker — a "bright and chroma-flat" key works.
  * the 3D-render Blue Sky Chaser has a white fuselage that overlaps those
    tones, so it is keyed strictly against the two sampled checker colours.

Usage: python3 scripts/process_sky83_assets.py
"""

from collections import Counter, deque
from pathlib import Path

from PIL import Image

SRC = Path.home() / "Documents" / "Sky-83"
REPO = Path(__file__).resolve().parent.parent
DST = REPO / "SkyAce" / "Resources" / "Sprites"

BG_MIN_BRIGHTNESS = 150
BG_MAX_CHROMA = 16
DARK_MAX = 110  # outline/body pixels — used for registration bboxes


def is_chroma_flat_bg(px):
    """True if the pixel reads as matte background: bright and chroma-flat.

    Covers white mattes and every grey checker tone in the cell-shaded
    exports, while stopping at the artwork's saturated fills and dark
    outlines.
    """
    r, g, b = px[:3]
    if min(r, g, b) < BG_MIN_BRIGHTNESS:
        return False
    return max(r, g, b) - min(r, g, b) <= BG_MAX_CHROMA


def sample_checker_tones(img, n=2):
    """The two most common colors in the border band are the checker pair."""
    w, h = img.size
    px = img.convert("RGB").load()
    counts = Counter()
    band = 6
    for x in range(w):
        for y in list(range(band)) + list(range(h - band, h)):
            counts[px[x, y]] += 1
    for y in range(h):
        for x in list(range(band)) + list(range(w - band, w)):
            counts[px[x, y]] += 1
    return [c for c, _ in counts.most_common(n)]


def near(px, tone, tol):
    """True if every RGB channel of `px` is within `tol` of `tone`."""
    return all(abs(px[i] - tone[i]) <= tol for i in range(3))


def knock_out(img, is_background):
    """Flood-fill from every border pixel through background pixels, setting
    them transparent; then fade the anti-aliased fringe along the cut."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()

    removed = bytearray(w * h)
    queue = deque()
    for x in range(w):
        queue.append((x, 0))
        queue.append((x, h - 1))
    for y in range(h):
        queue.append((0, y))
        queue.append((w - 1, y))

    while queue:
        x, y = queue.popleft()
        idx = y * w + x
        if removed[idx]:
            continue
        if not is_background(px[x, y]):
            continue
        removed[idx] = 1
        r, g, b, _ = px[x, y]
        px[x, y] = (r, g, b, 0)
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not removed[ny * w + nx]:
                queue.append((nx, ny))

    # Fringe pass: opaque pixels on the cut that still read as background
    # were blended with the checker — fade them instead of leaving a halo.
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if max(r, g, b) - min(r, g, b) > 30 or min(r, g, b) < 140:
                continue
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < w and 0 <= ny < h and removed[ny * w + nx]:
                    px[x, y] = (r, g, b, 110)
                    break
    return img


def component_bboxes(img, min_alpha=1):
    """Connected components of opaque pixels → (count, bbox, dark, grey)."""
    w, h = img.size
    px = img.load()
    seen = bytearray(w * h)
    comps = []
    for sy in range(h):
        for sx in range(w):
            if seen[sy * w + sx] or px[sx, sy][3] < min_alpha:
                continue
            q = deque([(sx, sy)])
            seen[sy * w + sx] = 1
            n = dark = grey = 0
            minx = miny = 10 ** 9
            maxx = maxy = -1
            while q:
                x, y = q.popleft()
                r, g, b, _ = px[x, y]
                n += 1
                minx, maxx = min(minx, x), max(maxx, x)
                miny, maxy = min(miny, y), max(maxy, y)
                if max(r, g, b) < DARK_MAX:
                    dark += 1
                if max(r, g, b) - min(r, g, b) <= 18 and 110 <= max(r, g, b) <= 230:
                    grey += 1
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] \
                            and px[nx, ny][3] >= min_alpha:
                        seen[ny * w + nx] = 1
                        q.append((nx, ny))
            comps.append({
                "n": n, "bbox": (minx, miny, maxx + 1, maxy + 1),
                "dark": dark / n, "grey": grey / n,
            })
    return comps


def erase_components(img, keep):
    """Zero the alpha of every component for which keep(comp) is False."""
    px = img.load()
    for comp in component_bboxes(img):
        if keep(comp):
            continue
        x0, y0, x1, y1 = comp["bbox"]
        for y in range(y0, y1):
            for x in range(x0, x1):
                r, g, b, a = px[x, y]
                if a:
                    px[x, y] = (r, g, b, 0)
    # bbox-based erase can clip an overlapping kept component's pixels only
    # if bboxes intersect — the shadow/speck bboxes here sit clear of the
    # body, so a per-bbox wipe is safe and much faster than re-labelling.
    return img


def dark_bbox(img):
    """Bbox of outline-dark pixels — the plane body without flame/shadow."""
    w, h = img.size
    px = img.load()
    minx = miny = 10 ** 9
    maxx = maxy = -1
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a and max(r, g, b) < DARK_MAX:
                minx, maxx = min(minx, x), max(maxx, x)
                miny, maxy = min(miny, y), max(maxy, y)
    if maxx < 0:
        return None
    return (minx, miny, maxx + 1, maxy + 1)


def cropped_content(img, pad=4):
    """Crop to the alpha bounding box plus `pad` transparent pixels."""
    bbox = img.split()[3].getbbox()
    if bbox is None:
        raise ValueError("image is fully transparent after knockout")
    left, top, right, bottom = bbox
    w, h = img.size
    return img.crop((
        max(0, left - pad), max(0, top - pad),
        min(w, right + pad), min(h, bottom + pad),
    ))


def process_simple(name, out_name=None):
    """Convert one scene/UI export to a cropped, true-alpha sprite PNG."""
    img = Image.open(SRC / f"{name}.png").convert("RGBA")
    # Later Stitch re-exports ship with a real alpha channel (transparent
    # corners) — those only need cropping, and keying them would eat
    # light-grey artwork. Knock out the matte only on opaque exports.
    alpha = img.split()[3]
    w, h = img.size
    corners = [alpha.getpixel(p) for p in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]]
    if max(corners) > 0:
        img = knock_out(img, is_chroma_flat_bg)
    out = cropped_content(img)
    out_path = DST / f"{out_name or name}.png"
    out.save(out_path)
    print(f"{out_path.name}: {out.size[0]}x{out.size[1]}")


def process_gear_down(name, gear_up_path, strict_checker=False,
                      register_on_dark=True):
    src = Image.open(SRC / f"{name}.png")

    if strict_checker:
        tones = sample_checker_tones(src)
        img = knock_out(src, lambda p: any(near(p, t, 12) for t in tones))
        # 3D-render style: the soft ground shadow survives strict keying and
        # touches the tires, so component logic can't isolate it. Everything
        # below the lowest dark pixel (tire bottoms) is shadow — cut it.
        img = erase_components(img, keep=lambda c: c["n"] >= 100)
        body = dark_bbox(img)
        if body is not None:
            px = img.load()
            for y in range(body[3] + 2, img.size[1]):
                for x in range(img.size[0]):
                    r, g, b, a = px[x, y]
                    if a:
                        px[x, y] = (r, g, b, 0)
    else:
        img = knock_out(src, is_chroma_flat_bg)
        # Cell-shaded style: the painted ground shadow is a detached blob
        # with almost no outline-dark pixels, unlike the plane (and its
        # attached exhaust flame). Keep the plane, drop shadow and specks.
        largest = max(c["n"] for c in component_bboxes(img))
        img = erase_components(
            img,
            keep=lambda c: c["n"] == largest or (c["n"] >= 100 and c["dark"] >= 0.2),
        )

    gear_up = Image.open(REPO / gear_up_path).convert("RGBA")
    up_left, up_top, up_right, _ = gear_up.split()[3].getbbox()
    up_w = up_right - up_left

    full = img.split()[3].getbbox()
    body = dark_bbox(img) if register_on_dark else full
    body_w = body[2] - body[0]

    # Scale so the body matches the gear-up content width; if the flame
    # overhangs the canvas at that scale, shrink the whole thing to fit
    # (a few percent at most — imperceptible at 90pt display width).
    canvas_w = gear_up.size[0]
    scale = up_w / body_w
    full_w = full[2] - full[0]
    scale = min(scale, canvas_w / full_w)

    content = img.crop(full)
    scaled = content.resize(
        (max(1, round(full_w * scale)),
         max(1, round((full[3] - full[1]) * scale))),
        Image.LANCZOS,
    )

    # Paste so the body lands at the gear-up content's top-left.
    paste_x = round(up_left - (body[0] - full[0]) * scale)
    paste_y = round(up_top - (body[1] - full[1]) * scale)
    paste_x = max(0, min(paste_x, canvas_w - scaled.size[0]))
    paste_y = max(0, paste_y)

    canvas_h = max(gear_up.size[1], paste_y + scaled.size[1])
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    canvas.paste(scaled, (paste_x, paste_y), scaled)

    out_path = DST / f"{name}.png"
    canvas.save(out_path)
    print(f"{out_path.name}: {canvas_w}x{canvas_h} "
          f"(gear-up {gear_up.size[0]}x{gear_up.size[1]}, "
          f"+{canvas_h - gear_up.size[1]}px gear, body scale {scale:.3f})")


def main():
    """Process all eight SKY-83 Stitch exports into Resources/Sprites."""
    process_simple("runway_strip")
    process_simple("landing_zone_indicator")
    process_simple("badge_smooth_landing")
    process_simple("sfx_dust_cloud", out_name="dust_cloud")
    process_simple("free_flight_landing_practice_card")

    process_gear_down(
        "shadow_dart_gear_down",
        "SkyAce/Resources/Assets.xcassets/shadow_dart.imageset/shadow_dart.png",
    )
    process_gear_down(
        "night_hawk_gear_down",
        "SkyAce/Resources/Assets.xcassets/night_hawk.imageset/night_hawk.png",
    )
    process_gear_down(
        "blue_sky_chaser_gear_down",
        "SkyAce/Resources/Sprites/plane_jet.png",
        strict_checker=True,      # white fuselage overlaps the loose grey key
        register_on_dark=False,   # white body has no reliable dark outline
    )


if __name__ == "__main__":
    main()
