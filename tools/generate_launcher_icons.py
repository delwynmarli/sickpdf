"""Generate sickPDF launcher artwork from the canonical S monogram geometry.

Standard-library only, so the Android launcher PNGs can be regenerated on a
clean checkout without Pillow or ImageMagick.

The monogram is defined once as a single continuous ribbon spine and rendered
as a round-capped, round-joined stroke. That guarantees the S stays one
unbroken shape at every size: there are no self-intersections, no detached
terminals, and no fill-rule differences between the PNG and the Android
vectors.

Sizing is explicit and shared with the Android vectors:
  - launcher: S width is ~67% of the 66dp adaptive safe circle
  - splash:   the same mark, scaled down for the 72dp Android 12 splash mask
  - PNG:      scaled so a legacy icon shows the S at the same apparent size as
              the masked adaptive icon

Keep these numbers in sync with:
  - assets/branding/sickpdf-s-monogram.svg
  - android/app/src/main/res/drawable/ic_launcher_foreground.xml
  - android/app/src/main/res/drawable/ic_launcher_monochrome.xml
  - android/app/src/main/res/drawable/ic_splash_logo.xml

Run from the project root:

    python tools/generate_launcher_icons.py
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RES = PROJECT_ROOT / "android" / "app" / "src" / "main" / "res"
BRANDING = PROJECT_ROOT / "assets" / "branding"

# Brand palette. Keep aligned with the Android vectors and Flutter tokens.
CHARCOAL = (0x20, 0x23, 0x21)
TEAL = (0x14, 0x7D, 0x73)
WHITE = (0xFF, 0xFF, 0xFF)

CANVAS = 108.0
CENTER = (54.0, 54.0)
ADAPTIVE_SAFE_RADIUS = 33.0  # guaranteed-safe circle: 66dp of 108dp
SPLASH_MASK_RADIUS = 36.0  # Android 12 splash mask: 72dp of 108dp

# --- Monogram geometry -------------------------------------------------------
# One continuous ribbon spine, drawn as an S. Stroked with a round cap and
# round joins, so the terminals read as folded ribbon ends.
SPINE_START = (69.25, 40.0)
SPINE_CURVES = (
    # top hook, sweeping left along the upper edge
    ((69.25, 35.5), (65.25, 35.5), (59.25, 35.5)),
    # down the left shoulder
    ((51.25, 35.5), (44.25, 38.0), (41.25, 44.0)),
    # through the waist, heading right
    ((38.75, 49.0), (41.25, 54.0), (47.25, 57.0)),
    # across to the right hip
    ((55.25, 60.0), (63.25, 62.0), (66.25, 67.0)),
    # down the right side
    ((69.25, 71.0), (66.25, 72.5), (60.25, 72.5)),
    # bottom hook, sweeping left
    ((52.25, 72.5), (44.25, 70.0), (40.25, 65.0)),
)

STROKE_WIDTH = 14.0
HALF_STROKE = STROKE_WIDTH / 2.0

# Small white folded-paper cue, tucked inside the upper ribbon so it can never
# bleed onto the charcoal background or outside the safe zone.
FOLD_QUAD = (
    (59.0, 31.5),
    (66.5, 31.5),
    (63.5, 38.5),
    (56.0, 38.5),
)

# Scales, derived from the geometry rather than hard-coded.
_SPINE_X = [SPINE_START[0]] + [c[0] for curve in SPINE_CURVES for c in curve]
_SPINE_Y = [SPINE_START[1]] + [c[1] for curve in SPINE_CURVES for c in curve]
SPINE_WIDTH = max(_SPINE_X) - min(_SPINE_X)
S_WIDTH = SPINE_WIDTH + STROKE_WIDTH
S_HEIGHT = (max(_SPINE_Y) - min(_SPINE_Y)) + STROKE_WIDTH
S_MAX_RADIUS = max(
    ((x - CENTER[0]) ** 2 + (y - CENTER[1]) ** 2) ** 0.5
    for x, y in zip(_SPINE_X, _SPINE_Y)
) + HALF_STROKE

LAUNCHER_SCALE = 1.0  # geometry above is already authored at launcher size
# Legacy PNGs show the whole 108 canvas, while the adaptive icon shows only its
# central 72dp. Scaling by 108/72 keeps the apparent size identical.
PNG_SCALE = CANVAS / 72.0
# Splash leaves extra breathing room inside the 72dp splash mask.
SPLASH_SCALE = 0.87

SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def _cubic(p0, p1, p2, p3, t):
    u = 1.0 - t
    return (
        u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0],
        u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1],
    )


def spine_points(steps_per_curve=28):
    """Sample the spine densely enough that stamped discs overlap seamlessly."""
    points = [SPINE_START]
    current = SPINE_START
    for control_1, control_2, end in SPINE_CURVES:
        for step in range(1, steps_per_curve + 1):
            points.append(_cubic(current, control_1, control_2, end, step / steps_per_curve))
        current = end
    return points


def path_data(scale=1.0):
    """Android/SVG path data for the spine, optionally scaled about the centre."""
    def tx(point):
        return (
            CENTER[0] + (point[0] - CENTER[0]) * scale,
            CENTER[1] + (point[1] - CENTER[1]) * scale,
        )

    def fmt(value):
        text = f"{value:.2f}"
        if text.endswith("0"):
            text = text[:-1]
        if text.endswith("."):
            text = text[:-1]
        return text

    start = tx(SPINE_START)
    out = [f"M{fmt(start[0])},{fmt(start[1])}"]
    for control_1, control_2, end in SPINE_CURVES:
        a, b, c = tx(control_1), tx(control_2), tx(end)
        out.append(
            f"C{fmt(a[0])},{fmt(a[1])} {fmt(b[0])},{fmt(b[1])} {fmt(c[0])},{fmt(c[1])}"
        )
    return " ".join(out)


def fold_path_data(scale=1.0):
    def tx(point):
        return (
            CENTER[0] + (point[0] - CENTER[0]) * scale,
            CENTER[1] + (point[1] - CENTER[1]) * scale,
        )

    def fmt(value):
        text = f"{value:.2f}"
        if text.endswith("0"):
            text = text[:-1]
        if text.endswith("."):
            text = text[:-1]
        return text

    points = [tx(p) for p in FOLD_QUAD]
    body = " ".join(f"L{fmt(x)},{fmt(y)}" for x, y in points[1:])
    first = points[0]
    return f"M{fmt(first[0])},{fmt(first[1])} {body} Z"


def _stamp_disc(pixels, width, height, cx, cy, radius, color):
    """Fill a disc into a flat RGB bytearray."""
    x0 = max(0, int(cx - radius) - 1)
    x1 = min(width - 1, int(cx + radius) + 1)
    y0 = max(0, int(cy - radius) - 1)
    y1 = min(height - 1, int(cy + radius) + 1)
    r2 = radius * radius
    for py in range(y0, y1 + 1):
        dy = py + 0.5 - cy
        base = py * width
        for px in range(x0, x1 + 1):
            dx = px + 0.5 - cx
            if dx * dx + dy * dy <= r2:
                index = (base + px) * 3
                pixels[index] = color[0]
                pixels[index + 1] = color[1]
                pixels[index + 2] = color[2]


def _fill_polygon(pixels, width, height, polygon, color):
    xs = [p[0] for p in polygon]
    ys = [p[1] for p in polygon]
    x0 = max(0, int(min(xs)) - 1)
    x1 = min(width - 1, int(max(xs)) + 1)
    y0 = max(0, int(min(ys)) - 1)
    y1 = min(height - 1, int(max(ys)) + 1)
    for py in range(y0, y1 + 1):
        y = py + 0.5
        for px in range(x0, x1 + 1):
            x = px + 0.5
            inside = False
            previous = polygon[-1]
            for current in polygon:
                x1p, y1p = current
                x2p, y2p = previous
                if (y1p > y) != (y2p > y) and x < (x2p - x1p) * (y - y1p) / (y2p - y1p) + x1p:
                    inside = not inside
                previous = current
            if inside:
                index = (py * width + px) * 3
                pixels[index] = color[0]
                pixels[index + 1] = color[1]
                pixels[index + 2] = color[2]


def _mask_allows(mask, u, v):
    return True if mask is None else mask(u, v)


def rasterize(size, scale=1.0, mask=None, ss=4):
    """Render the monogram to RGB rows, supersampled then box-filtered.

    ``mask`` receives normalized (u, v) in [0, 1] and returns whether the pixel
    is inside the launcher/splash mask. Masked-out pixels become charcoal, which
    is what an opaque launcher icon looks like under a launcher mask.
    """
    hi = size * ss
    pixels = bytearray(bytes(CHARCOAL) * (hi * hi))

    points = [
        (
            CENTER[0] + (p[0] - CENTER[0]) * scale,
            CENTER[1] + (p[1] - CENTER[1]) * scale,
        )
        for p in spine_points()
    ]
    radius = HALF_STROKE * scale
    for x, y in points:
        _stamp_disc(pixels, hi, hi, x / CANVAS * hi, y / CANVAS * hi, radius / CANVAS * hi, TEAL)

    fold = [
        (
            CENTER[0] + (p[0] - CENTER[0]) * scale,
            CENTER[1] + (p[1] - CENTER[1]) * scale,
        )
        for p in FOLD_QUAD
    ]
    _fill_polygon(
        pixels,
        hi,
        hi,
        [(x / CANVAS * hi, y / CANVAS * hi) for x, y in fold],
        WHITE,
    )

    rows = []
    block = ss * ss
    for py in range(size):
        row = bytearray()
        for px in range(size):
            if not _mask_allows(mask, (px + 0.5) / size, (py + 0.5) / size):
                row += bytes(CHARCOAL)
                continue
            r = g = b = 0
            for sy in range(ss):
                ybase = (py * ss + sy) * hi
                for sx in range(ss):
                    index = (ybase + px * ss + sx) * 3
                    r += pixels[index]
                    g += pixels[index + 1]
                    b += pixels[index + 2]
            row += bytes((r // block, g // block, b // block))
        rows.append(bytes(row))
    return rows


def write_png(path, rows, size):
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    # Opaque RGB: legacy launcher icons must fill their whole square.
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def report():
    print(
        f"monogram: width {S_WIDTH:.2f}dp, height {S_HEIGHT:.2f}dp, "
        f"max radius {S_MAX_RADIUS:.2f}dp from centre"
    )
    print(
        f"  launcher: {S_WIDTH / (2 * ADAPTIVE_SAFE_RADIUS) * 100:.1f}% of safe-zone width, "
        f"safe-circle margin {ADAPTIVE_SAFE_RADIUS - S_MAX_RADIUS:.2f}dp"
    )
    splash_radius = S_MAX_RADIUS * SPLASH_SCALE
    print(
        f"  splash:   scale {SPLASH_SCALE}, radius {splash_radius:.2f}dp, "
        f"mask margin {SPLASH_MASK_RADIUS - splash_radius:.2f}dp"
    )


def main():
    report()
    for folder, size in SIZES.items():
        target = RES / folder / "ic_launcher.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        write_png(target, rasterize(size, PNG_SCALE, ss=4), size)
        print(f"wrote {target} ({size}x{size})")

    BRANDING.mkdir(parents=True, exist_ok=True)
    preview = BRANDING / "sickpdf-icon-1024.png"
    write_png(preview, rasterize(1024, PNG_SCALE, ss=1), 1024)
    print(f"wrote {preview} (1024x1024)")

    print()
    print("launcher pathData:", path_data(LAUNCHER_SCALE))
    print("launcher fold:", fold_path_data(LAUNCHER_SCALE))


if __name__ == "__main__":
    main()
