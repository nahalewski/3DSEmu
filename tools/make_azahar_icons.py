#!/usr/bin/env python3
"""Draws the 3DS HOME menu's Azahar icons: the Azahar folder, Close Folder,
and one icon per settings page / tool in the folder (see fold3ds/azahar.lua's
A.ITEMS).  Glossy rounded squares with a white glyph, like the 3DS's own
applets.  Output: fold3ds/icons3ds/<id>.png (128 x 128).

    pip install pillow && python3 tools/make_azahar_icons.py

Drop in your own PNG under the same name to replace any of them.
"""
import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter

OUT = pathlib.Path(__file__).resolve().parent.parent / "fold3ds" / "icons3ds"
N = 512          # drawn at 4x, then scaled down (smooth edges)
SIZE = 128
W = (255, 255, 255, 255)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def base(color):
    """A rounded square in `color`: lighter at the top, a gloss band, a rim."""
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    top = lerp(color, (255, 255, 255), 0.28)
    bot = lerp(color, (0, 0, 0), 0.18)
    grad = Image.new("RGBA", (N, N))
    gd = ImageDraw.Draw(grad)
    for y in range(N):
        gd.line([(0, y), (N, y)], fill=lerp(top, bot, y / N) + (255,))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle([8, 8, N - 8, N - 8], radius=96, fill=255)
    img.paste(grad, (0, 0), mask)
    gloss = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).rounded_rectangle([28, 22, N - 28, N * 0.46], radius=80,
                                            fill=(255, 255, 255, 60))
    img = Image.alpha_composite(img, gloss)
    ImageDraw.Draw(img).rounded_rectangle([8, 8, N - 8, N - 8], radius=96,
                                          outline=lerp(color, (0, 0, 0), 0.3) + (255,), width=8)
    return img


def glyph_layer():
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    return layer, ImageDraw.Draw(layer)


def finish(img, layer, name):
    # a soft shadow under the glyph, then the glyph
    alpha = layer.split()[3]
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    shadow.putalpha(alpha.point(lambda a: a * 0.35))
    shadow = shadow.filter(ImageFilter.GaussianBlur(6))
    img = Image.alpha_composite(img, shadow.transform((N, N), Image.AFFINE, (1, 0, -4, 0, 1, -8)))
    img = Image.alpha_composite(img, layer)
    img.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / f"{name}.png")


# ---------------------------------------------------------------- glyphs

def gear(d, cx, cy, r, col=W, hole=None):
    teeth = 8
    pts = []
    for i in range(teeth * 4):
        a = i / (teeth * 4) * 2 * math.pi
        rr = r if (i % 4) in (0, 1) else r * 0.78
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.polygon(pts, fill=col)
    d.ellipse([cx - r * 0.32, cy - r * 0.32, cx + r * 0.32, cy + r * 0.32], fill=hole or (0, 0, 0, 0))


def g_settings(d):
    gear(d, 256, 256, 170)


def g_library(d):
    for i in range(2):
        for j in range(2):
            x, y = 130 + i * 136, 130 + j * 136
            d.rounded_rectangle([x, y, x + 116, y + 116], radius=22, fill=W)


def g_graphics(d):
    d.rounded_rectangle([104, 130, 408, 340], radius=20, outline=W, width=26)
    d.rectangle([230, 340, 282, 384], fill=W)
    d.rounded_rectangle([170, 380, 342, 406], radius=12, fill=W)
    # a sparkle
    cx, cy, s = 300, 208, 50
    d.polygon([(cx, cy - s), (cx + s * 0.25, cy - s * 0.25), (cx + s, cy), (cx + s * 0.25, cy + s * 0.25),
               (cx, cy + s), (cx - s * 0.25, cy + s * 0.25), (cx - s, cy), (cx - s * 0.25, cy - s * 0.25)], fill=W)


def g_layout(d):
    d.rounded_rectangle([110, 110, 402, 262], radius=18, outline=W, width=24)
    d.rounded_rectangle([150, 290, 362, 412], radius=18, fill=W)


def g_controls(d):
    d.rounded_rectangle([86, 178, 426, 356], radius=86, fill=W)
    d.ellipse([60, 250, 190, 400], fill=W)
    d.ellipse([322, 250, 452, 400], fill=W)
    c = (0, 0, 0, 0)
    d.rectangle([140, 250, 216, 276], fill=c)
    d.rectangle([165, 225, 191, 301], fill=c)
    d.ellipse([318, 222, 352, 256], fill=c)
    d.ellipse([352, 262, 386, 296], fill=c)


def g_audio(d):
    d.polygon([(110, 208), (180, 208), (270, 130), (270, 382), (180, 304), (110, 304)], fill=W)
    for k, r in enumerate((70, 130)):
        d.arc([270 - r, 256 - r, 270 + r, 256 + r], start=-50, end=50, fill=W, width=26)


def g_system(d):
    # a 3DS, open
    d.rounded_rectangle([140, 80, 372, 236], radius=22, fill=W)
    d.rounded_rectangle([140, 262, 372, 432], radius=22, fill=W)
    c = (0, 0, 0, 0)
    d.rectangle([170, 104, 342, 212], fill=c)
    d.rectangle([200, 286, 312, 370], fill=c)
    d.ellipse([160, 380, 188, 408], fill=c)
    d.ellipse([326, 380, 354, 408], fill=c)


def g_core(d):
    d.rounded_rectangle([150, 150, 362, 362], radius=24, fill=W)
    d.rounded_rectangle([196, 196, 316, 316], radius=12, fill=(0, 0, 0, 0))
    for i in range(4):
        o = 176 + i * 54
        for (x0, y0, x1, y1) in ((o, 100, o + 22, 150), (o, 362, o + 22, 412),
                                 (100, o, 150, o + 22), (362, o, 412, o + 22)):
            d.rectangle([x0, y0, x1, y1], fill=W)


def g_camera(d):
    d.rounded_rectangle([88, 164, 424, 392], radius=40, fill=W)
    d.rounded_rectangle([186, 118, 326, 180], radius=20, fill=W)
    d.ellipse([176, 196, 336, 356], fill=(0, 0, 0, 0))
    d.ellipse([210, 230, 302, 322], fill=W)


def g_storage(d):
    d.polygon([(160, 96), (320, 96), (372, 148), (372, 416), (160, 416)], fill=W)
    for i in range(4):
        x = 196 + i * 40
        d.rectangle([x, 120, x + 22, 186], fill=(0, 0, 0, 0))
    d.rectangle([196, 300, 336, 320], fill=(0, 0, 0, 0))


def g_network(d):
    d.ellipse([106, 106, 406, 406], outline=W, width=24)
    d.ellipse([196, 106, 316, 406], outline=W, width=20)
    d.line([(106, 256), (406, 256)], fill=W, width=20)
    d.arc([130, 60, 382, 230], start=30, end=150, fill=W, width=18)
    d.arc([130, 282, 382, 452], start=210, end=330, fill=W, width=18)


def g_debug(d):
    d.ellipse([176, 176, 336, 420], fill=W)
    d.ellipse([200, 110, 312, 210], fill=W)
    for y in (230, 300, 370):
        d.line([(110, y - 20), (180, y)], fill=W, width=22)
        d.line([(402, y - 20), (332, y)], fill=W, width=22)
    d.line([(256, 216), (256, 410)], fill=(0, 0, 0, 0), width=14)


def g_install(d):
    d.rectangle([232, 90, 280, 280], fill=W)
    d.polygon([(160, 240), (352, 240), (256, 346)], fill=W)
    d.rounded_rectangle([110, 340, 402, 420], radius=20, fill=W)
    d.rounded_rectangle([150, 340, 362, 380], radius=8, fill=(0, 0, 0, 0))


def folder_shape(d, col, x0=86, y0=130, x1=426, y1=402):
    d.rounded_rectangle([x0, y0, x0 + 150, y0 + 60], radius=20, fill=col)
    d.rounded_rectangle([x0, y0 + 34, x1, y1], radius=28, fill=col)


def g_gamedir(d):
    folder_shape(d, W)
    d.rounded_rectangle([196, 206, 316, 346], radius=12, fill=(0, 0, 0, 0))
    d.rounded_rectangle([212, 236, 300, 330], radius=8, fill=W)


def g_sysfiles(d):
    d.polygon([(140, 80), (310, 80), (372, 142), (372, 432), (140, 432)], fill=W)
    for y in (200, 256, 312, 368):
        d.rectangle([180, y, 332, y + 18], fill=(0, 0, 0, 0))


def g_drivers(d):
    g_core(d)
    d.polygon([(268, 196), (220, 268), (256, 268), (240, 320), (296, 240), (260, 240)], fill=W)


def g_multiplayer(d):
    for cx, s in ((196, 1.0), (330, 0.86)):
        r = 56 * s
        d.ellipse([cx - r, 150 - r * 0.2, cx + r, 150 + r * 1.8], fill=W)
        d.pieslice([cx - 110 * s, 280, cx + 110 * s, 500], start=180, end=360, fill=W)


def g_artic(d):
    d.rounded_rectangle([196, 250, 316, 420], radius=16, fill=W)
    d.rectangle([214, 270, 298, 330], fill=(0, 0, 0, 0))
    for r in (80, 140, 200):
        d.arc([256 - r, 220 - r, 256 + r, 220 + r], start=225, end=315, fill=W, width=22)


def g_userdir(d):
    folder_shape(d, W)
    d.polygon([(256, 196), (196, 252), (212, 252), (212, 340), (300, 340), (300, 252), (316, 252)],
              fill=(0, 0, 0, 0))


def g_log(d):
    pts = [(170, 256), (340, 156), (340, 356)]
    d.line([pts[0], pts[1]], fill=W, width=24)
    d.line([pts[0], pts[2]], fill=W, width=24)
    for x, y in pts:
        d.ellipse([x - 52, y - 52, x + 52, y + 52], fill=W)


def g_about(d):
    d.ellipse([96, 96, 416, 416], outline=W, width=28)
    d.ellipse([232, 150, 280, 198], fill=W)
    d.rounded_rectangle([230, 226, 282, 364], radius=14, fill=W)


ICONS = {
    "az_library": ((214, 44, 52), g_library),
    "az_settings": ((120, 130, 146), g_settings),
    "az_graphics": ((132, 84, 214), g_graphics),
    "az_layout": ((22, 160, 170), g_layout),
    "az_controls": ((56, 168, 72), g_controls),
    "az_audio": ((238, 130, 30), g_audio),
    "az_system": ((40, 120, 226), g_system),
    "az_core": ((70, 82, 104), g_core),
    "az_camera": ((226, 70, 140), g_camera),
    "az_storage": ((70, 80, 200), g_storage),
    "az_network": ((20, 170, 210), g_network),
    "az_debug": ((170, 80, 50), g_debug),
    "az_install": ((40, 170, 110), g_install),
    "az_gamedir": ((230, 160, 20), g_gamedir),
    "az_sysfiles": ((80, 110, 170), g_sysfiles),
    "az_drivers": ((120, 180, 30), g_drivers),
    "az_multiplayer": ((236, 96, 50), g_multiplayer),
    "az_artic": ((60, 150, 240), g_artic),
    "az_userdir": ((214, 170, 40), g_userdir),
    "az_log": ((24, 150, 140), g_log),
    "az_about": ((50, 130, 220), g_about),
    # the tile that stands in for the 3DS games until Azahar is set up
    "ctr_setup": ((206, 32, 40), g_system),
}


def folder_icon(name, mark):
    """The HOME menu folder itself: a yellow folder, with a mark on it."""
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    back = (226, 160, 24, 255)
    front_top, front_bot = (255, 214, 90), (240, 178, 36)
    d.rounded_rectangle([40, 70, 230, 170], radius=30, fill=back)
    d.rounded_rectangle([40, 110, 472, 450], radius=40, fill=back)
    d.rounded_rectangle([90, 96, 432, 200], radius=16, fill=(250, 250, 252, 255))
    grad = Image.new("RGBA", (N, N))
    gd = ImageDraw.Draw(grad)
    for y in range(N):
        gd.line([(0, y), (N, y)], fill=lerp(front_top, front_bot, y / N) + (255,))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle([40, 160, 472, 450], radius=40, fill=255)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([40, 160, 472, 450], radius=40, outline=(200, 138, 10, 255), width=8)
    layer, gd2 = glyph_layer()
    mark(gd2)
    finish(img, layer, name)


def mark_azahar(d):
    # a small 3DS on the folder
    c = (0, 0, 0, 0)
    d.rounded_rectangle([196, 206, 316, 290], radius=12, fill=W)
    d.rounded_rectangle([196, 304, 316, 400], radius=12, fill=W)
    d.rectangle([212, 220, 300, 276], fill=c)
    d.rectangle([228, 318, 284, 364], fill=c)


def mark_close(d):
    d.polygon([(170, 300), (250, 230), (250, 276), (340, 276), (340, 324), (250, 324), (250, 370)], fill=W)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (color, draw) in ICONS.items():
        img = base(color)
        layer, d = glyph_layer()
        draw(d)
        finish(img, layer, name)
    folder_icon("azahar", mark_azahar)
    folder_icon("folder_close", mark_close)
    print("wrote %d icons to %s" % (len(ICONS) + 2, OUT))


if __name__ == "__main__":
    main()
