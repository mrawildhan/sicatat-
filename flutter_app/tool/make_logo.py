"""Draw the SICATAT logo: a gear (operations) with a check (work done).

Rendered at 4x and downscaled for clean edges. Colours follow AppColors.
Needs Pillow and the Windows Arial fonts. From flutter_app/:

    python tool/make_logo.py assets/images/logo-full.png full 1100
    python tool/make_logo.py assets/images/logo-icon.png mark 1024
    dart run flutter_launcher_icons
"""
import math
import sys

from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1]
DEEP = (11, 61, 46, 255)       # AppColors.greenDark
GREEN = (23, 107, 77, 255)     # AppColors.green
MINT = (231, 243, 237, 255)    # AppColors.mint
ORANGE = (242, 163, 58, 255)
MUTED = (84, 110, 99, 255)
SS = 4


def gear_points(cx, cy, outer, root, teeth, tip_half, root_half, start=-90):
    pts = []
    step = 360 / teeth
    for i in range(teeth):
        a = math.radians(start + i * step)
        for ang, rad in (
            (a - math.radians(root_half), root),
            (a - math.radians(tip_half), outer),
            (a + math.radians(tip_half), outer),
            (a + math.radians(root_half), root),
        ):
            pts.append((cx + rad * math.cos(ang), cy + rad * math.sin(ang)))
        # arc along the root to the next tooth
        a2 = math.radians(start + (i + 1) * step)
        for t in range(1, 6):
            ang = (a + math.radians(root_half)) + (a2 - math.radians(root_half) - (a + math.radians(root_half))) * t / 6
            pts.append((cx + root * math.cos(ang), cy + root * math.sin(ang)))
    return pts


def thick_polyline(draw, pts, width, fill):
    for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
        draw.line((x1, y1, x2, y2), fill=fill, width=int(width))
    r = width / 2
    for x, y in pts:
        draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def draw_mark(size, supersampled=False):
    """Badge with gear and check, on a transparent square canvas."""
    s = size * SS
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, s - 1, s - 1), radius=int(s * 0.23), fill=DEEP)

    cx, cy = s * 0.47, s * 0.53
    outer, root, hole = s * 0.33, s * 0.262, s * 0.150
    d.polygon(gear_points(cx, cy, outer, root, 8, 8.5, 12.5), fill=MINT)
    d.ellipse((cx - hole, cy - hole, cx + hole, cy + hole), fill=DEEP)

    # The check leaves the gear towards the upper right: the work is done.
    check = [(s * 0.36, s * 0.535), (s * 0.46, s * 0.635), (s * 0.79, s * 0.255)]
    thick_polyline(d, check, s * 0.125, DEEP)     # cut-out outline
    thick_polyline(d, check, s * 0.082, ORANGE)
    return img if supersampled else img.resize((size, size), Image.LANCZOS)


def spaced_text(draw, xy, text, font, fill, tracking):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill)
        x += draw.textlength(ch, font=font) + tracking


def spaced_width(draw, text, font, tracking):
    return sum(draw.textlength(ch, font=font) for ch in text) + tracking * (len(text) - 1)


def draw_full(width):
    s = SS
    w = width * s
    mark_size = int(width * 0.40)
    mark = draw_mark(mark_size, supersampled=True)

    word_font = ImageFont.truetype(r'C:\Windows\Fonts\ariblk.ttf', int(w * 0.15))
    probe = ImageDraw.Draw(Image.new('RGBA', (10, 10)))
    word = 'SICATAT'
    word_track = w * 0.006
    word_w = spaced_width(probe, word, word_font, word_track)
    tag = 'OPERASIONAL  •  REFERENSI  •  INFORMASI KERJA'
    tag_track = w * 0.002
    # Shrink the tagline until it is no wider than the wordmark.
    size = int(w * 0.05)
    while True:
        tag_font = ImageFont.truetype(r'C:\Windows\Fonts\arialbd.ttf', size)
        tag_w = spaced_width(probe, tag, tag_font, tag_track)
        if tag_w <= word_w or size < 8:
            break
        size -= 1
    wb = probe.textbbox((0, 0), word, font=word_font)
    tb = probe.textbbox((0, 0), tag, font=tag_font)

    gap1, gap2 = int(w * 0.035), int(w * 0.03)
    h = mark.height + gap1 + (wb[3] - wb[1]) + gap2 + (tb[3] - tb[1]) + int(w * 0.01)
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    img.alpha_composite(mark, ((w - mark.width) // 2, 0))
    d = ImageDraw.Draw(img)
    y = mark.height + gap1 - wb[1]
    spaced_text(d, ((w - word_w) / 2, y), word, word_font, DEEP, word_track)
    y = mark.height + gap1 + (wb[3] - wb[1]) + gap2 - tb[1]
    spaced_text(d, ((w - tag_w) / 2, y), tag, tag_font, GREEN, tag_track)
    return img.resize((width, h // s), Image.LANCZOS)


if __name__ == '__main__':
    kind = sys.argv[2]
    if kind == 'mark':
        draw_mark(int(sys.argv[3])).save(OUT)
    elif kind == 'full':
        draw_full(int(sys.argv[3])).save(OUT)
    print('saved', OUT)

