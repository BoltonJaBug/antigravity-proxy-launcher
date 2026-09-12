#!/usr/bin/env python3
"""Generate the launcher's macOS icon without using Google's artwork."""

from __future__ import annotations

import math
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError as exc:  # pragma: no cover - developer tooling
    raise SystemExit("Pillow is required: python3 -m pip install Pillow") from exc


SIZE = 2048
ROOT = Path(__file__).resolve().parents[1]
PACKAGING = ROOT / "packaging"
MASTER = PACKAGING / "AppIcon.png"
ICNS = PACKAGING / "AppIcon.icns"


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))  # type: ignore[return-value]


def gradient_color(t: float) -> tuple[int, int, int]:
    stops = [
        (0.00, (255, 86, 92)),
        (0.24, (255, 173, 65)),
        (0.48, (75, 201, 174)),
        (0.72, (53, 133, 255)),
        (1.00, (111, 79, 255)),
    ]
    for (pos_a, color_a), (pos_b, color_b) in zip(stops, stops[1:]):
        if t <= pos_b:
            return mix(color_a, color_b, (t - pos_a) / (pos_b - pos_a))
    return stops[-1][1]


def rounded_mask(size: int, box: tuple[int, int, int, int], radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def bezier(p0: tuple[float, float], p1: tuple[float, float], p2: tuple[float, float], steps: int = 120) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for index in range(steps + 1):
        t = index / steps
        inv = 1 - t
        points.append(
            (
                inv * inv * p0[0] + 2 * inv * t * p1[0] + t * t * p2[0],
                inv * inv * p0[1] + 2 * inv * t * p1[1] + t * t * p2[1],
            )
        )
    return points


def draw_stroke(mask: Image.Image, points: list[tuple[float, float]], width: int) -> None:
    draw = ImageDraw.Draw(mask)
    draw.line(points, fill=255, width=width, joint="curve")
    radius = width / 2
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=255)


def make_master() -> Image.Image:
    icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # macOS-style shadow and white rounded square.
    shadow_mask = rounded_mask(SIZE, (126, 108, 1922, 1904), 430)
    shadow = Image.new("RGBA", (SIZE, SIZE), (10, 24, 48, 0))
    shadow.putalpha(shadow_mask.point(lambda value: round(value * 0.22)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(54))
    icon.alpha_composite(shadow, (0, 36))

    tile = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
    tile.putalpha(rounded_mask(SIZE, (126, 108, 1922, 1904), 430))
    icon.alpha_composite(tile)

    # A colorful abstract A, inspired by Antigravity's visual language but
    # drawn from scratch so the repository does not redistribute Google art.
    a_mask = Image.new("L", (SIZE, SIZE), 0)
    left = bezier((666, 1510), (775, 1000), (991, 532))
    right = bezier((1382, 1510), (1273, 1000), (1057, 532))
    draw_stroke(a_mask, left, 246)
    draw_stroke(a_mask, right, 246)
    draw_stroke(a_mask, [(829, 1163), (1219, 1163)], 184)

    gradient = Image.new("RGBA", (SIZE, SIZE))
    gradient_draw = ImageDraw.Draw(gradient)
    for y in range(SIZE):
        color = gradient_color(y / (SIZE - 1))
        gradient_draw.line((0, y, SIZE, y), fill=(*color, 255))

    a_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    a_layer.paste(gradient, (0, 0), a_mask)
    icon.alpha_composite(a_layer)

    # Small active-proxy badge: a green circle with a white circular arrow.
    badge = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    badge_draw = ImageDraw.Draw(badge)
    cx, cy, radius = 1642, 1642, 174
    badge_draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=(18, 164, 91, 255))
    badge_draw.ellipse((cx - radius + 10, cy - radius + 10, cx + radius - 10, cy + radius - 10), outline=(255, 255, 255, 72), width=8)

    arc_box = (cx - 86, cy - 86, cx + 86, cy + 86)
    badge_draw.arc(arc_box, start=34, end=322, fill=(255, 255, 255, 255), width=34)
    end_angle = math.radians(322)
    end_x = cx + 86 * math.cos(end_angle)
    end_y = cy + 86 * math.sin(end_angle)
    arrow = [
        (end_x + 34, end_y - 6),
        (end_x - 16, end_y - 42),
        (end_x - 18, end_y + 26),
    ]
    badge_draw.polygon(arrow, fill=(255, 255, 255, 255))
    icon.alpha_composite(badge)

    return icon


def main() -> int:
    PACKAGING.mkdir(parents=True, exist_ok=True)
    icon = make_master()
    icon.save(MASTER)

    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    with tempfile.TemporaryDirectory(prefix="antigravity-proxy-icon-") as temp_dir:
        iconset = Path(temp_dir) / "AppIcon.iconset"
        iconset.mkdir()
        for name, size in sizes.items():
            icon.resize((size, size), Image.Resampling.LANCZOS).save(iconset / name)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(ICNS)], check=True)

    print(f"Created {ICNS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
