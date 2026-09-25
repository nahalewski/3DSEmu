#!/usr/bin/env python3
"""
compress_sounds.py: High-quality audio compression & packaging pipeline for AeonDX / fold3ds.
Converts uncompressed 16-bit PCM WAV audio to transparent-quality Ogg Vorbis (q6 ~160-192kbps).
Generates banner_sounds.lua lookup index and packages audio for APK builds.
"""

import os
import glob
import re
import json
import shutil
import subprocess
import sys

# Ensure UTF-8 output
if sys.stdout.encoding != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)             # 3DSEmu
WORKSPACE = os.path.dirname(ROOT)        # RECOMP
SOUNDS_DIR = os.path.join(WORKSPACE, "SOUNDS")
FOLD3DS_SOUNDS = os.path.join(ROOT, "fold3ds", "sounds")
FOLD3DS_2EDC = os.path.join(WORKSPACE, "3DSEmu-2edc3d6", "fold3ds", "sounds")

def normalize_title(t):
    t = re.sub(r'\[[A-Za-z0-9_-]+\]', '', t)
    t = re.sub(r'\([^)]*\)', '', t)
    t = t.replace('_', ' ').replace('-', ' ').replace(':', ' ').replace("'", "")
    t = re.sub(r'\s+', ' ', t).strip().lower()
    return t

def convert_wav_to_ogg(wav_path, q=6):
    ogg_path = os.path.splitext(wav_path)[0] + ".ogg"
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", wav_path,
        "-c:a", "libvorbis",
        "-q:a", str(q),
        ogg_path
    ]
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if res.returncode != 0:
        print(f"Error converting {wav_path}: {res.stderr.decode('utf-8', errors='ignore')}")
        return None
    if os.path.exists(ogg_path) and os.path.getsize(ogg_path) > 0:
        return ogg_path
    return None

def main():
    print("=" * 60)
    print("AeonDX Audio Compression & Packaging Pipeline")
    print("=" * 60)

    # 1. Compress WAVs in SOUNDS
    banner_dir = os.path.join(SOUNDS_DIR, "3DS", "Game_Cartridge_Banner_Sounds")
    banner_wavs = glob.glob(os.path.join(banner_dir, "**", "*.wav"), recursive=True)
    print(f"Found {len(banner_wavs)} WAV files in Game_Cartridge_Banner_Sounds.")

    orig_total = sum(os.path.getsize(f) for f in banner_wavs)
    compressed_total = 0
    converted_count = 0

    games_manifest = []

    for w in banner_wavs:
        fname = os.path.basename(w)
        ogg = convert_wav_to_ogg(w, q=6)
        if ogg:
            c_size = os.path.getsize(ogg)
            compressed_total += c_size
            converted_count += 1
            os.remove(w) # Safely replace WAV with compressed OGG

            # Build metadata
            if fname != "cartridge_insert.wav":
                m = re.match(r'^(.*?)(?:\s+\[([A-Za-z0-9_-]+)\])?\.wav$', fname)
                raw_title = m.group(1).replace('_', ':') if m else os.path.splitext(fname)[0]
                code = m.group(2) if (m and m.group(2)) else ""
                category = os.path.basename(os.path.dirname(w))
                rel_ogg = os.path.relpath(ogg, SOUNDS_DIR).replace('\\', '/')
                games_manifest.append({
                    "title": raw_title,
                    "norm": normalize_title(raw_title),
                    "code": code.upper(),
                    "category": category,
                    "rel_path": rel_ogg
                })

    print(f"Compressed {converted_count} banner sounds:")
    print(f"  Original WAV size:     {orig_total / (1024*1024):.2f} MB")
    print(f"  Compressed OGG size:   {compressed_total / (1024*1024):.2f} MB")
    reduction = (1.0 - (compressed_total / orig_total)) * 100 if orig_total > 0 else 0
    print(f"  Space saved:           {reduction:.1f}% reduction")

    # 2. Convert standard WAV sounds in fold3ds/sounds to OGG
    fold_wavs = glob.glob(os.path.join(FOLD3DS_SOUNDS, "*.wav"))
    print(f"\nCompressing {len(fold_wavs)} UI sound WAVs in fold3ds/sounds...")
    fold_orig = sum(os.path.getsize(f) for f in fold_wavs)
    fold_comp = 0
    for w in fold_wavs:
        ogg = convert_wav_to_ogg(w, q=6)
        if ogg:
            fold_comp += os.path.getsize(ogg)
            # We keep WAV or replace? Let's keep OGG and remove large WAVs
            os.remove(w)
    print(f"  UI sounds WAV: {fold_orig / (1024*1024):.2f} MB -> OGG: {fold_comp / (1024*1024):.2f} MB")

    # 3. Generate Lua banner lookup table: fold3ds/banner_sounds.lua
    lua_path = os.path.join(ROOT, "fold3ds", "banner_sounds.lua")
    print(f"\nGenerating banner sounds lookup index: {lua_path}")
    with open(lua_path, "w", encoding="utf-8") as f:
        f.write("-- banner_sounds.lua: Fast index mapping game titles, IDs, and product codes\n")
        f.write("-- to authentic 3DS cartridge banner sounds.\n")
        f.write("local M = {}\n\n")
        f.write("M.codes = {\n")
        for g in games_manifest:
            if g["code"]:
                f.write(f'  ["{g["code"]}"] = "fold3ds/sounds/{g["rel_path"]}",\n')
        f.write("}\n\n")

        f.write("M.titles = {\n")
        for g in games_manifest:
            clean_norm = g["norm"].replace('\\', '\\\\').replace('"', '\\"')
            f.write(f'  ["{clean_norm}"] = "fold3ds/sounds/{g["rel_path"]}",\n')
        f.write("}\n\n")

        f.write("""local function norm(s)
  if not s then return "" end
  s = s:gsub("%b[]", ""):gsub("%b()", ""):gsub("[_%-':]", " ")
  return s:gsub("%s+", " "):lower():match("^%s*(.-)%s*$")
end

function M.find(game)
  if not game then return nil end
  if type(game) == "string" then
    local n = norm(game)
    if M.titles[n] then return M.titles[n] end
    local code = game:upper():match("%[?([A-Z0-9]+)%]?")
    if code and M.codes[code] then return M.codes[code] end
    -- Check direct key
    local c3 = game:upper():sub(1, 3)
    local c4 = game:upper():sub(1, 4)
    if M.codes[c4] then return M.codes[c4] end
    if M.codes[c3] then return M.codes[c3] end
    return nil
  end

  -- Table representation
  local serial = game.serial or game.code or game.product_code or game.id
  if serial then
    local s = tostring(serial):upper()
    if M.codes[s] then return M.codes[s] end
    local c3 = s:sub(1, 3)
    local c4 = s:sub(1, 4)
    if M.codes[c4] then return M.codes[c4] end
    if M.codes[c3] then return M.codes[c3] end
  end

  local name = game.name or game.title
  if name then
    local n = norm(tostring(name))
    if M.titles[n] then return M.titles[n] end
    -- Fuzzy prefix matching
    for k, v in pairs(M.titles) do
      if #n > 4 and (k:find(n, 1, true) or n:find(k, 1, true)) then
        return v
      end
    end
  end

  return nil
end

return M
""")

    # 4. Generate JSON Manifest in SOUNDS/
    manifest_path = os.path.join(SOUNDS_DIR, "sounds_manifest.json")
    all_sounds = []
    for root_dir, _, files in os.walk(SOUNDS_DIR):
        for file in files:
            if file.endswith((".ogg", ".mp3", ".wav")):
                full = os.path.join(root_dir, file)
                rel = os.path.relpath(full, SOUNDS_DIR).replace('\\', '/')
                all_sounds.append({
                    "name": file,
                    "rel_path": rel,
                    "size": os.path.getsize(full)
                })

    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump({
            "total_sounds": len(all_sounds),
            "total_bytes": sum(s["size"] for s in all_sounds),
            "sounds": all_sounds,
            "banner_games": games_manifest
        }, f, indent=2)

    print(f"Generated sounds manifest: {manifest_path} ({len(all_sounds)} audio files total)")

    # 5. Mirror SOUNDS into fold3ds/sounds and 3DSEmu-2edc3d6
    for target in [FOLD3DS_SOUNDS, FOLD3DS_2EDC]:
        if os.path.exists(os.path.dirname(target)):
            print(f"Mirroring SOUNDS to {target}...")
            os.makedirs(target, exist_ok=True)
            for item in os.listdir(SOUNDS_DIR):
                s = os.path.join(SOUNDS_DIR, item)
                d = os.path.join(target, item)
                if os.path.isdir(s):
                    shutil.copytree(s, d, dirs_exist_ok=True)
                elif item.endswith((".ogg", ".mp3", ".wav", ".json")):
                    shutil.copy2(s, d)

    # Also copy banner_sounds.lua to 3DSEmu-2edc3d6
    lua_2edc = os.path.join(WORKSPACE, "3DSEmu-2edc3d6", "fold3ds", "banner_sounds.lua")
    if os.path.exists(os.path.dirname(lua_2edc)):
        shutil.copy2(lua_path, lua_2edc)

    print("\nCompression, indexing, and mirroring complete!")

if __name__ == "__main__":
    main()
