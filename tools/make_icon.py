"""Make the Warcraft Survivors icon (.ico, 16 to 256 px): a gold "WS" monogram
in the lobby title's style (gold metal, bevel, fire glow) on a dark ember
square with a gold rim.

    python tools/make_icon.py <FRIZQT__.TTF> <out.ico> [preview.png] [web icons dir]

The web icons dir gets survivor-180.png and survivor-192.png, the browser
build's favicon (engine/port/web/site/icons, build-engine.py --survivor).

The font is Warcraft III's own Friz Quadrata (Fonts\\FRIZQT__.TTF in the MPQs,
see make_title.py). The icon goes into the launcher (make_portable.ps1,
make_release.ps1: csc /win32icon) and the engine exe (engine/port/windows/
openwarcraft3.rc), whose window and taskbar button SDL then show.
"""
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

S = 1024                      # drawn large, then scaled down per icon size
SIZES = [256, 128, 64, 48, 32, 24, 16]


def vertical(top_rgb, mid_rgb, bottom_rgb, y0, y1):
    img = Image.new('RGB', (1, S))
    for y in range(S):
        t = min(1.0, max(0.0, (y - y0) / float(y1 - y0)))
        a, b, u = (top_rgb, mid_rgb, t * 2) if t < 0.5 else (mid_rgb, bottom_rgb, (t - 0.5) * 2)
        img.putpixel((0, y), tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3)))
    return img.resize((S, S))


def layer(rgb, alpha):
    return Image.merge('RGBA', (*Image.new('RGB', (S, S), rgb).split(), alpha))


def bevel(fill, mask, depth):
    soft = mask.filter(ImageFilter.GaussianBlur(depth * 0.8))
    light = ImageChops.subtract(soft, ImageChops.offset(soft, depth, depth))
    shade = ImageChops.subtract(soft, ImageChops.offset(soft, -depth, -depth))
    fill = ImageChops.add(fill, Image.merge('RGB', (light, light, light.point(lambda v: v // 2))))
    return ImageChops.subtract(fill, Image.merge('RGB', (shade.point(lambda v: v // 2), shade, shade)))


def draw(font_path):
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    margin, radius, rim = 24, 170, 46

    # Plate: a rounded square, dark ember red in the middle, near black at the edge.
    plate = Image.new('L', (S, S), 0)
    ImageDraw.Draw(plate).rounded_rectangle((margin, margin, S - margin, S - margin), radius, fill=255)
    ember = Image.new('L', (S, S), 0)
    ImageDraw.Draw(ember).ellipse((S * 0.12, S * 0.18, S * 0.88, S * 0.94), fill=255)
    ember = ember.filter(ImageFilter.GaussianBlur(120))
    base = Image.composite(Image.new('RGB', (S, S), (112, 26, 8)), Image.new('RGB', (S, S), (16, 8, 6)), ember)
    out.alpha_composite(Image.merge('RGBA', (*base.split(), plate)))

    # Gold rim with its own bevel and a dark inner line.
    inner = Image.new('L', (S, S), 0)
    ImageDraw.Draw(inner).rounded_rectangle((margin + rim, margin + rim, S - margin - rim, S - margin - rim),
                                            radius - rim, fill=255)
    ring = ImageChops.subtract(plate, inner)
    gold = bevel(vertical((255, 240, 170), (214, 140, 30), (110, 46, 8), margin, S - margin), ring, 10)
    out.alpha_composite(Image.merge('RGBA', (*gold.split(), ring)))
    line = ImageChops.subtract(inner.filter(ImageFilter.MaxFilter(13)), inner)
    out.alpha_composite(layer((30, 12, 4), line))

    # Monogram: tall W and S side by side, first letters of the title.
    font = ImageFont.truetype(font_path, 560)
    mask = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(mask)
    stroke = 10
    widths = [font.getlength(c) + stroke * 2 for c in 'WS']
    gap = -36
    x = (S - (sum(widths) + gap)) / 2
    baseline = S * 0.735
    for c, w in zip('WS', widths):
        d.text((x + stroke, baseline), c, font=font, fill=255, anchor='ls', stroke_width=stroke, stroke_fill=255)
        x += w + gap
    box = mask.getbbox()
    glow_wide = mask.filter(ImageFilter.MaxFilter(31)).filter(ImageFilter.GaussianBlur(36))
    glow_near = mask.filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.GaussianBlur(12))
    out.alpha_composite(layer((210, 50, 10), ImageChops.multiply(glow_wide.point(lambda v: int(v * 0.9)), inner)))
    out.alpha_composite(layer((255, 130, 24), ImageChops.multiply(glow_near.point(lambda v: int(v * 0.7)), inner)))
    out.alpha_composite(layer((36, 14, 4), mask.filter(ImageFilter.MaxFilter(17))))
    letters = bevel(vertical((255, 248, 180), (255, 180, 34), (150, 50, 6), box[1], box[3]), mask, 8)
    out.alpha_composite(Image.merge('RGBA', (*letters.split(), mask)))
    return out


def main():
    font_path, out_path = sys.argv[1], sys.argv[2]
    big = draw(font_path)
    images = [big.resize((n, n), Image.LANCZOS) for n in SIZES]
    images[0].save(out_path, format='ICO', sizes=[(n, n) for n in SIZES], append_images=images[1:])
    if len(sys.argv) > 3:
        sheet = Image.new('RGBA', (sum(SIZES) + 8 * len(SIZES), 256), (40, 40, 44, 255))
        x = 0
        for img in images:
            sheet.alpha_composite(img, (x, 0))
            x += img.width + 8
        sheet.save(sys.argv[3])
    if len(sys.argv) > 4:
        for n in (180, 192):
            big.resize((n, n), Image.LANCZOS).save('{}/survivor-{}.png'.format(sys.argv[4], n))


if __name__ == '__main__':
    main()
