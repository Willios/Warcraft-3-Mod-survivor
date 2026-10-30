"""Renders the lobby title, WARCRAFT SURVIVORS, in the Warcraft III logo style:
tall first letters, a gold metal gradient, a dark rim, a bevel and a fire glow.

    python tools/make_title.py <FRIZQT__.TTF> <out.tga> [preview.png]

The font is Warcraft III's own Friz Quadrata (Fonts\\FRIZQT__.TTF in the MPQs).
The engine shows the result in the lobby (src/art/title.tga, copied to
dist\\windows\\share\\warcraft-3\\Scripts\\Survivor\\).
"""
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

W, H = 1024, 128
WORDS = ['WARCRAFT', 'SURVIVORS']
BIG, SMALL = 86, 66           # first letter, other letters (pixels)
GAP = 28                      # between the two words
STROKE = 2                    # thickens the thin Friz strokes


def text_mask(font_path):
    big = ImageFont.truetype(font_path, BIG)
    small = ImageFont.truetype(font_path, SMALL)
    # Lay out once to measure, then draw centered.
    pieces = []
    x = 0
    for wi, word in enumerate(WORDS):
        for ci, ch in enumerate(word):
            font = big if ci == 0 else small
            pieces.append((x, ch, font))
            x += font.getlength(ch) + STROKE * 2 - 1
        if wi < len(WORDS) - 1:
            x += GAP
    total = x
    mask = Image.new('L', (W, H), 0)
    draw = ImageDraw.Draw(mask)
    base = 94                 # baseline, pixels from the top
    x0 = (W - total) / 2
    for x, ch, font in pieces:
        draw.text((x0 + x, base), ch, font=font, fill=255, anchor='ls', stroke_width=STROKE, stroke_fill=255)
    return mask


def gradient(top_rgb, mid_rgb, bottom_rgb, y0, y1):
    img = Image.new('RGB', (W, H))
    px = img.load()
    for y in range(H):
        t = min(1.0, max(0.0, (y - y0) / float(y1 - y0)))
        if t < 0.5:
            a, b, u = top_rgb, mid_rgb, t * 2
        else:
            a, b, u = mid_rgb, bottom_rgb, (t - 0.5) * 2
        c = tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3))
        for x in range(W):
            px[x, y] = c
    return img


def main():
    font_path, out = sys.argv[1], sys.argv[2]
    mask = text_mask(font_path)
    bbox = mask.getbbox()
    top, bottom = bbox[1], bbox[3]

    # Fire glow: a wide soft red halo and a tighter orange one.
    glow_wide = mask.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(10))
    glow_near = mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(4))
    # Dark rim around the letters.
    rim = mask.filter(ImageFilter.MaxFilter(5))

    out_img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    out_img.alpha_composite(Image.merge('RGBA', (*Image.new('RGB', (W, H), (190, 40, 10)).split(),
        glow_wide.point(lambda v: int(v * 0.85)))))
    out_img.alpha_composite(Image.merge('RGBA', (*Image.new('RGB', (W, H), (255, 120, 20)).split(),
        glow_near.point(lambda v: int(v * 0.75)))))
    out_img.alpha_composite(Image.merge('RGBA', (*Image.new('RGB', (W, H), (40, 16, 4)).split(), rim)))

    # Gold metal: pale yellow on top, deep orange below, a hot band in the middle.
    fill = gradient((255, 246, 170), (255, 176, 30), (150, 50, 6), top, bottom)
    # Bevel: light where the letter's top-left edge is, shadow on the bottom-right.
    soft = mask.filter(ImageFilter.GaussianBlur(1.6))
    light = ImageChops.subtract(soft, ImageChops.offset(soft, 2, 2))
    shade = ImageChops.subtract(soft, ImageChops.offset(soft, -2, -2))
    fill = ImageChops.add(fill, Image.merge('RGB', (light, light, light.point(lambda v: v // 2))))
    fill = ImageChops.subtract(fill, Image.merge('RGB', (shade.point(lambda v: v // 2), shade, shade)))
    out_img.alpha_composite(Image.merge('RGBA', (*fill.split(), mask)))

    out_img.save(out)
    if len(sys.argv) > 3:
        preview = Image.new('RGBA', (W, H), (14, 10, 8, 255))
        preview.alpha_composite(out_img)
        preview.save(sys.argv[3])


if __name__ == '__main__':
    main()
