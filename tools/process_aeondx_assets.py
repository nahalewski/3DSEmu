#!/usr/bin/env python3
"""
process_aeondx_assets.py: Process new AeonDX stickers, bottom shells, launcher icons,
and boot screens for AeonDX / fold3ds.
"""

import os
import shutil
from PIL import Image, ImageDraw, ImageFilter, ImageOps
import numpy as np
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)              # 3DSEmu
WORKSPACE = os.path.dirname(ROOT)         # RECOMP
SKIN_DIR = os.path.join(ROOT, "fold3ds", "skin")
BOOT_DIR = os.path.join(ROOT, "fold3ds", "boot")
STICKER_DIR = os.path.join(ROOT, "fold3ds", "stickers")
RES_GEN1 = os.path.join(ROOT, "build", "gen1recomp", "mobile", "android", "app", "src", "main", "res")
RES_AZAHAR = os.path.join(ROOT, "azahar", "res")
MIRROR_2EDC = os.path.join(WORKSPACE, "3DSEmu-2edc3d6", "fold3ds")

UPLOADED = "C:/Users/Ben/.gemini/antigravity/brain/c8571000-b41d-4151-abee-3ab29cfcdf83/.user_uploaded"

os.makedirs(SKIN_DIR, exist_ok=True)
os.makedirs(BOOT_DIR, exist_ok=True)
os.makedirs(STICKER_DIR, exist_ok=True)

def isolate_outer_background_and_cutout(img_path, crop_box, screen_rect, radius=8):
    """Isolate outer background via BFS flood fill, cut out screen, and crop."""
    img = Image.open(img_path).convert('RGBA')
    arr = np.array(img)
    h, w = arr.shape[:2]

    # BFS flood fill from 4 corners for outer background (black)
    visited = np.zeros((h, w), dtype=bool)
    is_black = np.all(arr[:, :, :3] < 16, axis=2)

    queue = deque([(0, 0), (w-1, 0), (0, h-1), (w-1, h-1)])
    for x, y in list(queue):
        visited[y, x] = True

    while queue:
        cx, cy = queue.popleft()
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < w and 0 <= ny < h:
                if not visited[ny, nx] and is_black[ny, nx]:
                    visited[ny, nx] = True
                    queue.append((nx, ny))

    alpha = np.ones((h, w), dtype=np.uint8) * 255
    alpha[visited] = 0

    # Screen cutout mask
    sx, sy, sw, sh = screen_rect
    screen_mask = Image.new('L', (w, h), 255)
    draw = ImageDraw.Draw(screen_mask)
    draw.rounded_rectangle([sx, sy, sx + sw - 1, sy + sh - 1], radius=radius, fill=0)

    final_alpha = np.minimum(alpha, np.array(screen_mask))
    arr[:, :, 3] = final_alpha

    x0, y0, x1, y1 = crop_box
    cropped = arr[y0:y1, x0:x1]
    return Image.fromarray(cropped, mode='RGBA')

def main():
    print("=" * 60)
    print("Processing AeonDX Brand Assets & Shell Alternates")
    print("=" * 60)

    # 1. Stickers
    fresh_sticker_src = os.path.join(UPLOADED, "media_1790354733614.png")
    dist_sticker_src = os.path.join(UPLOADED, "media_1790354733635.png")
    sticker_ui_src = os.path.join(UPLOADED, "media_1790354737312.png")

    fresh_dest = os.path.join(SKIN_DIR, "sticker_aeondx.png")
    dist_dest = os.path.join(SKIN_DIR, "sticker_aeondx_distressed.png")
    ui_dest = os.path.join(SKIN_DIR, "sticker_ui.png")

    shutil.copy2(fresh_sticker_src, fresh_dest)
    shutil.copy2(dist_sticker_src, dist_dest)
    shutil.copy2(sticker_ui_src, ui_dest)

    # Also place into fold3ds/stickers/ as defaults
    shutil.copy2(fresh_sticker_src, os.path.join(STICKER_DIR, "aeondx_logo.png"))
    shutil.copy2(dist_sticker_src, os.path.join(STICKER_DIR, "aeondx_distressed.png"))
    print("Installed default AeonDX stickers and sticker UI.")

    # 2. Bottom Shells (Default, Clean, Distressed)
    # Shell bounding box: x=21..1002 (w=982), y=101..660 (h=560)
    # Screen rect: x=239, y=203, w=532, h=365
    crop_box = (21, 101, 1003, 661) # 982 x 560
    screen_rect = (239, 203, 532, 365) # Inside uncropped coords

    # Clean AeonDX Graphic bottom shell
    clean_src = os.path.join(UPLOADED, "media_1790354744759.jpg")
    clean_img = isolate_outer_background_and_cutout(clean_src, crop_box, screen_rect, radius=6)
    clean_img.save(os.path.join(SKIN_DIR, "bottom_aeondx_clean.png"))
    print(f"Generated bottom_aeondx_clean.png: {clean_img.size}")

    # Distressed AeonDX Graphic bottom shell
    dist_src = os.path.join(UPLOADED, "media_1790354744750.jpg")
    dist_img = isolate_outer_background_and_cutout(dist_src, crop_box, screen_rect, radius=6)
    dist_img.save(os.path.join(SKIN_DIR, "bottom_aeondx_distressed.png"))
    print(f"Generated bottom_aeondx_distressed.png: {dist_img.size}")

    # Default Matte Black bottom shell (from previous upload)
    black_src = os.path.join(UPLOADED, "media_1790354695248.png")
    black_img = isolate_outer_background_and_cutout(black_src, crop_box, screen_rect, radius=6)
    # Backup previous bottom_empty.png
    old_bottom = os.path.join(SKIN_DIR, "bottom_empty.png")
    old_bottom_bak = os.path.join(SKIN_DIR, "bottom_empty_old.png")
    if os.path.exists(old_bottom) and not os.path.exists(old_bottom_bak):
        shutil.copy2(old_bottom, old_bottom_bak)
    black_img.save(old_bottom)
    print(f"Updated bottom_empty.png (Matte Black): {black_img.size}")

    # 3. Generate Android Launcher Icons from AeonDX Logo
    # Logo source: media_1790354733614.png (transparent)
    logo_img = Image.open(fresh_sticker_src).convert('RGBA')
    # Trim empty alpha borders from logo
    bbox = logo_img.getbbox()
    trimmed_logo = logo_img.crop(bbox)

    densities = {
        "drawable-mdpi": (108, 48),
        "drawable-hdpi": (162, 72),
        "drawable-xhdpi": (216, 96),
        "drawable-xxhdpi": (324, 144),
        "drawable-xxxhdpi": (432, 192),
    }

    # Generate icons across densities
    for folder, (fg_size, icon_size) in densities.items():
        # Foreground icon (adaptive icon layer, 108dp centered)
        fg = Image.new('RGBA', (fg_size, fg_size), (0, 0, 0, 0))
        # Logo fitted in safe center 66% area
        safe_w = int(fg_size * 0.72)
        safe_h = int(fg_size * 0.72)
        k = min(safe_w / trimmed_logo.width, safe_h / trimmed_logo.height)
        scaled_w = int(trimmed_logo.width * k)
        scaled_h = int(trimmed_logo.height * k)
        scaled_logo = trimmed_logo.resize((scaled_w, scaled_h), Image.Resampling.LANCZOS)
        fg.paste(scaled_logo, ((fg_size - scaled_w) // 2, (fg_size - scaled_h) // 2), scaled_logo)

        # Standard legacy icon with dark squircle / disc backdrop
        icon = Image.new('RGBA', (icon_size, icon_size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(icon)
        draw.rounded_rectangle([2, 2, icon_size - 3, icon_size - 3], radius=int(icon_size * 0.22), fill=(18, 20, 24, 255), outline=(10, 185, 230, 255), width=max(1, icon_size // 48))
        ik = min((icon_size * 0.8) / trimmed_logo.width, (icon_size * 0.8) / trimmed_logo.height)
        iw = int(trimmed_logo.width * ik)
        ih = int(trimmed_logo.height * ik)
        sc_icon = trimmed_logo.resize((iw, ih), Image.Resampling.LANCZOS)
        icon.paste(sc_icon, ((icon_size - iw) // 2, (icon_size - ih) // 2), sc_icon)

        # Save to gen1recomp resources
        target_dir = os.path.join(RES_GEN1, folder)
        if os.path.exists(target_dir):
            fg.save(os.path.join(target_dir, "ic_launcher_foreground.png"))
            icon.save(os.path.join(target_dir, "love.png"))

        # Save to azahar resources
        az_dir = os.path.join(RES_AZAHAR, folder)
        os.makedirs(az_dir, exist_ok=True)
        fg.save(os.path.join(az_dir, "ic_launcher_foreground.png"))
        icon.save(os.path.join(az_dir, "ic_launcher.png"))

    print("Generated Android adaptive & legacy icons for all screen densities.")

    # 4. Generate New Top and Bottom Boot Screens
    # Top boot screen: 975 x 585
    boot_top = Image.new('RGB', (975, 585), (14, 16, 20))
    top_draw = ImageDraw.Draw(boot_top)
    # Subtle gradient glow in center
    for r in range(250, 0, -5):
        alpha = int((1.0 - r / 250.0) * 45)
        top_draw.ellipse([487 - r * 1.6, 260 - r, 487 + r * 1.6, 260 + r], fill=(10 + alpha // 3, 20 + alpha // 2, 40 + alpha))

    # Center AeonDX logo
    top_logo_k = min(540 / trimmed_logo.width, 210 / trimmed_logo.height)
    tl_w, tl_h = int(trimmed_logo.width * top_logo_k), int(trimmed_logo.height * top_logo_k)
    tl_img = trimmed_logo.resize((tl_w, tl_h), Image.Resampling.LANCZOS)
    boot_top.paste(tl_img, ((975 - tl_w) // 2, 230 - tl_h // 2), tl_img)
    boot_top.save(os.path.join(BOOT_DIR, "top.jpg"), quality=95)

    # Bottom boot screen: 862 x 646
    boot_bot = Image.new('RGB', (862, 646), (14, 16, 20))
    bot_draw = ImageDraw.Draw(boot_bot)
    for r in range(200, 0, -5):
        alpha = int((1.0 - r / 200.0) * 35)
        bot_draw.ellipse([431 - r * 1.4, 290 - r, 431 + r * 1.4, 290 + r], fill=(15 + alpha // 2, 10 + alpha // 3, 35 + alpha))

    bot_logo_k = min(420 / trimmed_logo.width, 160 / trimmed_logo.height)
    bl_w, bl_h = int(trimmed_logo.width * bot_logo_k), int(trimmed_logo.height * bot_logo_k)
    bl_img = trimmed_logo.resize((bl_w, bl_h), Image.Resampling.LANCZOS)
    boot_bot.paste(bl_img, ((862 - bl_w) // 2, 270 - bl_h // 2), bl_img)
    boot_bot.save(os.path.join(BOOT_DIR, "bottom.jpg"), quality=95)
    print("Generated new AeonDX boot screens in fold3ds/boot/.")

    # 5. Mirror to 3DSEmu-2edc3d6
    if os.path.exists(MIRROR_2EDC):
        print(f"Mirroring assets to {MIRROR_2EDC}...")
        shutil.copytree(SKIN_DIR, os.path.join(MIRROR_2EDC, "skin"), dirs_exist_ok=True)
        shutil.copytree(BOOT_DIR, os.path.join(MIRROR_2EDC, "boot"), dirs_exist_ok=True)
        shutil.copytree(STICKER_DIR, os.path.join(MIRROR_2EDC, "stickers"), dirs_exist_ok=True)

    print("\nAll brand assets, stickers, shells, and boot screens generated successfully!")

if __name__ == "__main__":
    main()
