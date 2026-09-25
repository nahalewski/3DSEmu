#!/usr/bin/env python3
"""Draws the HOME menu icons for the DS emulator's folder (melonDS, "Omnindo")
and the Virtual Console folder (GB / GBC / GBA): the two folders, one icon
per settings page / tool in each (see fold3ds/emucore.lua's folders), and
their set-up / add-games tiles.  Same style as the Azahar icons
(tools/make_azahar_icons.py).  Output: fold3ds/icons3ds/<id>.png.

    pip install pillow && python3 tools/make_emu_icons.py
"""
import make_azahar_icons as az
from make_azahar_icons import (W, base, glyph_layer, finish, folder_icon, g_layout, g_multiplayer,
                               g_system, g_audio, g_controls, g_gamedir, g_about, g_add, g_core)

DS = (72, 84, 104)        # the DS's steel grey
VC = (96, 70, 176)        # Virtual Console purple

ICONS = {
    "nds_screen": (DS, g_layout), "nds_profile": (DS, g_multiplayer), "nds_system": (DS, g_system),
    "nds_audio": (DS, g_audio), "nds_controls": (DS, g_controls), "nds_folder": (DS, g_gamedir),
    "nds_about": (DS, g_about), "nds_setup": (DS, g_system), "nds_add": (DS, g_add),
    "vc_screen": (VC, g_layout), "vc_system": (VC, g_core), "vc_audio": (VC, g_audio),
    "vc_controls": (VC, g_controls), "vc_folder": (VC, g_gamedir), "vc_about": (VC, g_about),
    "vc_add": (VC, g_add),
}


def mark_ds(d):
    # a small DS on the folder: two screens, the lower one in its shell
    c = (0, 0, 0, 0)
    d.rounded_rectangle([186, 204, 326, 290], radius=12, fill=W)
    d.rectangle([204, 218, 308, 276], fill=c)
    d.rounded_rectangle([186, 300, 326, 400], radius=12, fill=W)
    d.rectangle([222, 318, 290, 368], fill=c)


def mark_vc(d):
    # a small Game Boy on the folder
    c = (0, 0, 0, 0)
    d.rounded_rectangle([206, 196, 306, 404], radius=14, fill=W)
    d.rectangle([222, 214, 290, 280], fill=c)
    d.rectangle([224, 318, 236, 350], fill=c)
    d.rectangle([214, 328, 246, 340], fill=c)
    d.ellipse([264, 318, 282, 336], fill=c)
    d.ellipse([280, 304, 298, 322], fill=c)


def main():
    for name, (color, draw) in ICONS.items():
        img = base(color)
        layer, d = glyph_layer()
        draw(d)
        finish(img, layer, name)
    folder_icon("melonds", mark_ds)
    folder_icon("vc", mark_vc)
    print("wrote %d icons to %s" % (len(ICONS) + 2, az.OUT))


if __name__ == "__main__":
    main()
