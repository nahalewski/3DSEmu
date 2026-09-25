#!/usr/bin/env python3
"""
Unit tests for AeonDX / fold3ds audio assets, compression integrity, and build packaging.
"""

import os
import json
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FOLD3DS = os.path.dirname(HERE)
ROOT = os.path.dirname(FOLD3DS)
WORKSPACE = os.path.dirname(ROOT)
SOUNDS_DIR = os.path.join(WORKSPACE, "SOUNDS")

class TestAudioAssets(unittest.TestCase):
    def test_sounds_manifest_exists_and_complete(self):
        manifest_path = os.path.join(SOUNDS_DIR, "sounds_manifest.json")
        self.assertTrue(os.path.exists(manifest_path), "sounds_manifest.json must exist in SOUNDS/")
        with open(manifest_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        self.assertIn("total_sounds", data)
        self.assertGreaterEqual(data["total_sounds"], 900, "Manifest must track at least 900 sounds")
        self.assertIn("banner_games", data)
        self.assertGreaterEqual(len(data["banner_games"]), 250, "Must track at least 250 banner games")

    def test_no_uncompressed_banner_wavs(self):
        banner_dir = os.path.join(SOUNDS_DIR, "3DS", "Game_Cartridge_Banner_Sounds")
        wav_files = []
        for r, _, files in os.walk(banner_dir):
            for f in files:
                if f.endswith(".wav"):
                    wav_files.append(os.path.join(r, f))
        self.assertEqual(len(wav_files), 0, f"No uncompressed WAVs should remain in banner sounds, found: {wav_files}")

    def test_banner_sounds_lua_index(self):
        lua_path = os.path.join(FOLD3DS, "banner_sounds.lua")
        self.assertTrue(os.path.exists(lua_path), "banner_sounds.lua must exist")
        with open(lua_path, "r", encoding="utf-8") as f:
            content = f.read()
        # Verify key product codes and titles are present
        self.assertIn('["BKU"]', content, "Mario Kart DS code BKU should be indexed")
        self.assertIn('["CPU"]', content, "New Super Mario Bros code CPU should be indexed")
        self.assertIn('["A2D"]', content, "Super Mario 64 DS code A2D should be indexed")
        self.assertIn('["mario kart ds"]', content, "Normalized title mario kart ds should be indexed")
        self.assertIn('["pokemon heartgold"]', content, "pokemon heartgold should be indexed")
        self.assertIn('function M.find', content, "Lookup function M.find must be defined")

    def test_fold3ds_sounds_mirrored(self):
        fold_sounds = os.path.join(FOLD3DS, "sounds")
        self.assertTrue(os.path.exists(fold_sounds), "fold3ds/sounds must exist")
        # Ensure system sound folders exist inside fold3ds/sounds
        self.assertTrue(os.path.exists(os.path.join(fold_sounds, "3DS")), "3DS sounds must be mirrored")
        self.assertTrue(os.path.exists(os.path.join(fold_sounds, "Switch")), "Switch sounds must be mirrored")
        banner_ogg = os.path.join(fold_sounds, "3DS", "Game_Cartridge_Banner_Sounds")
        self.assertTrue(os.path.exists(banner_ogg), "Banner sounds must be mirrored")

    def test_sfx_lua_supports_ogg_and_banners(self):
        sfx_path = os.path.join(FOLD3DS, "sfx.lua")
        with open(sfx_path, "r", encoding="utf-8") as f:
            sfx = f.read()
        self.assertIn(".ogg", sfx, "sfx.lua must support .ogg files")
        self.assertIn("playBanner", sfx, "sfx.lua must define playBanner")
        self.assertIn("playInsert", sfx, "sfx.lua must define playInsert")

    def test_build_sh_mirrors_sounds(self):
        build_path = os.path.join(ROOT, "build.sh")
        with open(build_path, "r", encoding="utf-8") as f:
            b = f.read()
        self.assertIn("0b. sounds", b, "build.sh must contain step 0b. sounds")
        self.assertIn('cp -r "$SOUNDS_SRC"/* "$HERE/fold3ds/sounds/"', b, "build.sh must copy SOUNDS into fold3ds/sounds")

if __name__ == "__main__":
    unittest.main()
