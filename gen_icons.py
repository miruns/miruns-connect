"""Generate Miruns app icons - the M signal-wave logo (mirrored from m_signal_logo.dart)."""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

BG_COLOR     = (0, 0, 0)
GLOW_COLOR   = (0, 112, 243)
AURORA_COLOR = (121, 40, 202)

PADDING = 0.12

_SEGMENTS = [
    ((0.00, 0.56), (0.07, 0.56), (0.10, 0.10), (0.22, 0.10)),
    ((0.22, 0.10), (0.34, 0.10), (0.42, 0.72), (0.50, 0.72)),
    ((0.50, 0.72), (0.58, 0.72), (0.66, 0.10), (0.78, 0.10)),
    ((0.78, 0.10), (0.90, 0.10), (0.93, 0.56), (1.00, 0.56)),
]


def _cubic(p0, cp1, cp2, p1, t):
    mt = 1.0 - t
    return (
        mt**3*p0[0] + 3*mt**2*t*cp1[0] + 3*mt*t**2*cp2[0] + t**3*p1[0],
        mt**3*p0[1] + 3*mt**2*t*cp1[1] + 3*mt*t**2*cp2[1] + t**3*p1[1],
    )


def _sample_path(steps_per_seg=300):
    raw = []
    for seg in _SEGMENTS:
        for i in range(steps_per_seg):
            raw.append(_cubic(*seg, i / steps_per_seg))
    raw.append(_cubic(*_SEGMENTS[-1], 1.0))
    pts = [raw[0]]
    for p in raw[1:]:
        if abs(p[0] - pts[-1][0]) > 1e-9 or abs(p[1] - pts[-1][1]) > 1e-9:
            pts.append(p)
    lens = [0.0]
    for i in range(1, len(pts)):
        lens.append(lens[-1] + math.hypot(pts[i][0] - pts[i-1][0],
                                           pts[i][1] - pts[i-1][1]))
    total = lens[-1]
    return pts, [d / total for d in lens]


def _lerp(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def _layout(px, padding=PADDING):
    """Compute layout transforms shared by icon renderers."""
    pts, global_ts = _sample_path()
    bx0 = min(p[0] for p in pts)
    bx1 = max(p[0] for p in pts)
    by0 = min(p[1] for p in pts)
    by1 = max(p[1] for p in pts)
    pad   = padding * px
    avail = px - 2 * pad
    scale = min(avail / (bx1 - bx0), avail / (by1 - by0))
    draw_w = (bx1 - bx0) * scale
    draw_h = (by1 - by0) * scale
    ox = pad + (avail - draw_w) / 2
    oy = pad + (avail - draw_h) / 2

    def to_px(fx, fy):
        return (ox + (fx - bx0) * scale, oy + (fy - by0) * scale)

    pixel_pts = [to_px(fx, fy) for fx, fy in pts]
    stroke_w = max(int(px * 0.052), 2)
    return pixel_pts, global_ts, stroke_w


def make_icon(px):
    pixel_pts, global_ts, stroke_w = _layout(px)

    base = Image.new("RGBA", (px, px), BG_COLOR + (255,))

    # 1. Wide blurred glow
    glow = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    gd   = ImageDraw.Draw(glow)
    gw   = max(int(stroke_w * 2.6), 4)
    for i in range(1, len(pixel_pts)):
        col = _lerp(GLOW_COLOR, AURORA_COLOR, global_ts[i]) + (110,)
        gd.line([pixel_pts[i-1], pixel_pts[i]], fill=col, width=gw)
    glow = glow.filter(ImageFilter.GaussianBlur(radius=max(stroke_w * 1.8, 4)))
    base = Image.alpha_composite(base, glow)

    # 2. Main gradient stroke with round joins
    sl = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sl)
    r  = max(stroke_w // 2, 1)
    for i in range(1, len(pixel_pts)):
        col = _lerp(GLOW_COLOR, AURORA_COLOR, global_ts[i]) + (255,)
        sd.line([pixel_pts[i-1], pixel_pts[i]], fill=col, width=stroke_w)
        x, y = pixel_pts[i-1]
        cap  = _lerp(GLOW_COLOR, AURORA_COLOR, global_ts[i-1]) + (255,)
        sd.ellipse([(x-r, y-r), (x+r, y+r)], fill=cap)
    x, y = pixel_pts[-1]
    sd.ellipse([(x-r, y-r), (x+r, y+r)], fill=AURORA_COLOR + (255,))

    base = Image.alpha_composite(base, sl)
    return base.convert("RGB")


def make_adaptive_foreground(px):
    """Adaptive icon foreground: M-wave logo on transparent, centered in 108dp grid.

    The 108dp canvas has a 72dp safe zone (inner 66.7%), so the logo is inset
    to stay within that safe zone.
    """
    # padding=0.25 keeps the logo inside the 72/108 safe zone
    pixel_pts, global_ts, stroke_w = _layout(px, padding=0.25)

    base = Image.new("RGBA", (px, px), (0, 0, 0, 0))

    # 1. Glow
    glow = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    gd   = ImageDraw.Draw(glow)
    gw   = max(int(stroke_w * 2.6), 4)
    for i in range(1, len(pixel_pts)):
        col = _lerp(GLOW_COLOR, AURORA_COLOR, global_ts[i]) + (110,)
        gd.line([pixel_pts[i-1], pixel_pts[i]], fill=col, width=gw)
    glow = glow.filter(ImageFilter.GaussianBlur(radius=max(stroke_w * 1.8, 4)))
    base = Image.alpha_composite(base, glow)

    # 2. Main gradient stroke
    sl = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sl)
    r  = max(stroke_w // 2, 1)
    for i in range(1, len(pixel_pts)):
        col = _lerp(GLOW_COLOR, AURORA_COLOR, global_ts[i]) + (255,)
        sd.line([pixel_pts[i-1], pixel_pts[i]], fill=col, width=stroke_w)
        x, y = pixel_pts[i-1]
        cap  = _lerp(GLOW_COLOR, AURORA_COLOR, global_ts[i-1]) + (255,)
        sd.ellipse([(x-r, y-r), (x+r, y+r)], fill=cap)
    x, y = pixel_pts[-1]
    sd.ellipse([(x-r, y-r), (x+r, y+r)], fill=AURORA_COLOR + (255,))

    base = Image.alpha_composite(base, sl)
    return base


def make_notification_icon(px):
    """Android notification small icon: white M-wave on transparent background.

    Must be monochrome (alpha-only). Android uses only the alpha channel;
    all opaque pixels are tinted by the system accent colour.
    """
    pixel_pts, _, stroke_w = _layout(px, padding=0.18)

    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    white = (255, 255, 255, 255)
    r = max(stroke_w // 2, 1)

    for i in range(1, len(pixel_pts)):
        draw.line([pixel_pts[i-1], pixel_pts[i]], fill=white, width=stroke_w)
        x, y = pixel_pts[i-1]
        draw.ellipse([(x-r, y-r), (x+r, y+r)], fill=white)
    x, y = pixel_pts[-1]
    draw.ellipse([(x-r, y-r), (x+r, y+r)], fill=white)

    return img


ANDROID_ICONS = {
    r"android\app\src\main\res\mipmap-mdpi\ic_launcher.png":    48,
    r"android\app\src\main\res\mipmap-hdpi\ic_launcher.png":    72,
    r"android\app\src\main\res\mipmap-xhdpi\ic_launcher.png":   96,
    r"android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png":  144,
    r"android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png": 192,
}

# Adaptive icon foreground (108dp with 72dp safe-zone centered)
ANDROID_ADAPTIVE_FG = {
    r"android\app\src\main\res\mipmap-mdpi\ic_launcher_foreground.png":    108,
    r"android\app\src\main\res\mipmap-hdpi\ic_launcher_foreground.png":    162,
    r"android\app\src\main\res\mipmap-xhdpi\ic_launcher_foreground.png":   216,
    r"android\app\src\main\res\mipmap-xxhdpi\ic_launcher_foreground.png":  324,
    r"android\app\src\main\res\mipmap-xxxhdpi\ic_launcher_foreground.png": 432,
}

ANDROID_NOTIFICATION_ICONS = {
    r"android\app\src\main\res\drawable-mdpi\ic_notification.png":    24,
    r"android\app\src\main\res\drawable-hdpi\ic_notification.png":    36,
    r"android\app\src\main\res\drawable-xhdpi\ic_notification.png":   48,
    r"android\app\src\main\res\drawable-xxhdpi\ic_notification.png":  72,
    r"android\app\src\main\res\drawable-xxxhdpi\ic_notification.png": 96,
}

IOS_ICONS = {
    r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-20x20@1x.png":     20,
    r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-20x20@2x.png":     40,
    r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-20x20@3x.png":     60,
    r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-29x29@1x.png":     29,
    r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-29x29@2x.png":     58,
    r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-29x29@3x.png":     87,
    r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-40x40@1x.png":     40,
    r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-40x40@2x.png":     80,
    r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-40x40@3x.png":     120,
    r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-60x60@2x.png":     120,
    r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-60x60@3x.png":     180,
    r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-76x76@1x.png":     76,
    r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-76x76@2x.png":     152,
    r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-83.5x83.5@2x.png": 167,
    r"ios\Runner\Assets.xcassets\AppIcon.appiconset\Icon-App-1024x1024@1x.png": 1024,
}

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def generate_all():
    all_icons = {**ANDROID_ICONS, **IOS_ICONS}
    for rel_path, size in all_icons.items():
        full_path = os.path.join(BASE_DIR, rel_path)
        img = make_icon(size)
        img.save(full_path, "PNG")
        print(f"  OK  {size:>4}px  {rel_path}")

    for rel_path, size in ANDROID_ADAPTIVE_FG.items():
        full_path = os.path.join(BASE_DIR, rel_path)
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        img = make_adaptive_foreground(size)
        img.save(full_path, "PNG")
        print(f"  OK  {size:>4}px  {rel_path}")

    for rel_path, size in ANDROID_NOTIFICATION_ICONS.items():
        full_path = os.path.join(BASE_DIR, rel_path)
        os.makedirs(os.path.dirname(full_path), exist_ok=True)
        img = make_notification_icon(size)
        img.save(full_path, "PNG")
        print(f"  OK  {size:>4}px  {rel_path}")

    print("\nAll icons generated.")


if __name__ == "__main__":
    generate_all()
