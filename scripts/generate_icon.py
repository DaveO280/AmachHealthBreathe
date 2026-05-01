#!/usr/bin/env python3
"""Render the Amach Breathe app icon at 1024x1024.

Renders at 4x supersample (4096x4096) for anti-aliasing, scales down to 1024
with LANCZOS, then writes to icon-source-1024.png in the project root.
"""

from pathlib import Path

from PIL import Image, ImageDraw

# Canvas
SIZE = 1024
SUPER = 4
S = SIZE * SUPER  # 4096

# Colors
BG = (10, 26, 21, 255)            # #0A1A15
GREEN = (16, 185, 129, 255)       # #10B981

# Geometry helpers
def alpha(rgba, a):
    return (rgba[0], rgba[1], rgba[2], int(round(a * 255)))


def stroke_circle(draw, cx, cy, r, stroke_w, color):
    bbox = (cx - r, cy - r, cx + r, cy + r)
    draw.ellipse(bbox, outline=color, width=stroke_w)


def render(out_path: Path) -> None:
    img = Image.new("RGBA", (S, S), BG)
    draw = ImageDraw.Draw(img, "RGBA")

    cx = cy = S / 2
    canvas_radius = S / 2  # outer extent

    # Outer glow ring: 72% of canvas radius, opacity ~18%, stroke 1.5%
    stroke_circle(
        draw,
        cx, cy,
        r=int(round(canvas_radius * 0.72)),
        stroke_w=max(1, int(round(S * 0.015))),
        color=alpha(GREEN, 0.18),
    )

    # Main breathing ring: 58%, full opacity, stroke 3%
    stroke_circle(
        draw,
        cx, cy,
        r=int(round(canvas_radius * 0.58)),
        stroke_w=max(1, int(round(S * 0.03))),
        color=GREEN,
    )

    # Inner accent ring: 42%, opacity ~25%, stroke 0.8%
    stroke_circle(
        draw,
        cx, cy,
        r=int(round(canvas_radius * 0.42)),
        stroke_w=max(1, int(round(S * 0.008))),
        color=alpha(GREEN, 0.25),
    )

    # ── Amach leaf mark, centered slightly below center ───────────
    # Stem: from a point above center down to ~10% below center
    # Leaves spread out from upper part of stem.
    leaf_w_scale = 0.18  # leaf horizontal radius as fraction of canvas
    leaf_h_scale = 0.26  # leaf vertical extent

    stem_top_y = cy - S * 0.12
    stem_bot_y = cy + S * 0.10
    stem_x = cx
    stem_w = max(2, int(round(S * 0.02)))

    # Build a polygon leaf using a teardrop bezier-ish shape via points.
    # We'll produce a smooth leaf as a many-point polygon by sampling two
    # quadratic bezier curves and joining them.
    def quad_bezier(p0, p1, p2, n=64):
        pts = []
        for i in range(n + 1):
            t = i / n
            x = (1 - t) * (1 - t) * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
            y = (1 - t) * (1 - t) * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
            pts.append((x, y))
        return pts

    def make_leaf(side: int):
        # side: -1 left, +1 right
        # Anchor at top of stem; tip extends outward and slightly upward.
        base = (stem_x, stem_top_y)
        tip = (stem_x + side * S * leaf_w_scale, stem_top_y - S * 0.04)
        # Outer curve (away from stem) bulges out and up
        outer_ctrl = (stem_x + side * S * (leaf_w_scale * 0.55),
                      stem_top_y - S * (leaf_h_scale * 0.85))
        # Inner curve (along stem) sweeps back near the stem
        inner_ctrl = (stem_x + side * S * (leaf_w_scale * 0.18),
                      stem_top_y + S * 0.06)
        outer = quad_bezier(base, outer_ctrl, tip)
        inner = list(reversed(quad_bezier(base, inner_ctrl, tip)))
        # polygon: base -> along outer to tip -> along inner back to base
        return outer + inner

    left_leaf = make_leaf(-1)
    right_leaf = make_leaf(+1)

    # Right leaf opacity 72%, drawn first (behind)
    draw.polygon(right_leaf, fill=alpha(GREEN, 0.72))
    # Left leaf opacity 90%
    draw.polygon(left_leaf, fill=alpha(GREEN, 0.90))

    # Stem: thick line with rounded caps (approximated by line + circles at ends)
    draw.line([(stem_x, stem_top_y), (stem_x, stem_bot_y)],
              fill=GREEN, width=stem_w)
    # rounded caps
    cap_r = stem_w / 2
    draw.ellipse((stem_x - cap_r, stem_top_y - cap_r,
                  stem_x + cap_r, stem_top_y + cap_r), fill=GREEN)
    draw.ellipse((stem_x - cap_r, stem_bot_y - cap_r,
                  stem_x + cap_r, stem_bot_y + cap_r), fill=GREEN)

    # Center vein: thin BG-colored line down center of leaves to suggest vein.
    vein_w = max(1, int(round(S * 0.006)))
    vein_top = (stem_x, stem_top_y - S * 0.02)
    vein_bot = (stem_x, stem_top_y + S * 0.04)
    draw.line([vein_top, vein_bot], fill=BG, width=vein_w)

    # Downsample to 1024 with LANCZOS
    final = img.resize((SIZE, SIZE), Image.LANCZOS)
    # Flatten alpha onto opaque BG (no transparency in app icon)
    flat = Image.new("RGB", (SIZE, SIZE), BG[:3])
    flat.paste(final, mask=final.split()[3])
    flat.save(out_path, "PNG", optimize=True)


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    out = root / "icon-source-1024.png"
    render(out)
    print(f"wrote {out}")
