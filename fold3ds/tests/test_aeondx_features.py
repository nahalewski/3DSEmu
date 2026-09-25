import os
import unittest

class TestAeonDXFeatures(unittest.TestCase):
    def setUp(self):
        self.base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    def test_audio_hinge_assets(self):
        sounds_dir = os.path.join(self.base_dir, "sounds")
        hinge_open = os.path.join(sounds_dir, "hinge_open.ogg")
        hinge_close = os.path.join(sounds_dir, "hinge_close.ogg")
        self.assertTrue(os.path.isfile(hinge_open), "hinge_open.ogg must exist")
        self.assertTrue(os.path.isfile(hinge_close), "hinge_close.ogg must exist")
        self.assertGreater(os.path.getsize(hinge_open), 1000)
        self.assertGreater(os.path.getsize(hinge_close), 1000)

    def test_boot_assets(self):
        boot_dir = os.path.join(self.base_dir, "boot")
        top_boot = os.path.join(boot_dir, "top.jpg")
        bot_boot = os.path.join(boot_dir, "bottom.jpg")
        self.assertTrue(os.path.isfile(top_boot), "boot/top.jpg must exist")
        self.assertTrue(os.path.isfile(bot_boot), "boot/bottom.jpg must exist")
        self.assertGreater(os.path.getsize(top_boot), 5000)
        self.assertGreater(os.path.getsize(bot_boot), 5000)

    def test_shell_assets(self):
        skin_dir = os.path.join(self.base_dir, "skin")
        matte = os.path.join(skin_dir, "bottom_empty.png")
        clean = os.path.join(skin_dir, "bottom_aeondx_clean.png")
        distressed = os.path.join(skin_dir, "bottom_aeondx_distressed.png")
        top_gbc = os.path.join(skin_dir, "top_gbc.png")
        self.assertTrue(os.path.isfile(matte), "bottom_empty.png must exist")
        self.assertTrue(os.path.isfile(clean), "bottom_aeondx_clean.png must exist")
        self.assertTrue(os.path.isfile(distressed), "bottom_aeondx_distressed.png must exist")
        self.assertTrue(os.path.isfile(top_gbc), "top_gbc.png must exist")

    def test_sticker_assets(self):
        stickers_dir = os.path.join(self.base_dir, "stickers")
        clean_logo = os.path.join(stickers_dir, "aeondx_logo.png")
        distressed_logo = os.path.join(stickers_dir, "aeondx_distressed.png")
        ui_sheet = os.path.join(self.base_dir, "skin", "sticker_ui.png")
        self.assertTrue(os.path.isfile(clean_logo), "aeondx_logo sticker must exist")
        self.assertTrue(os.path.isfile(distressed_logo), "aeondx_distressed sticker must exist")
        self.assertTrue(os.path.isfile(ui_sheet), "sticker_ui.png must exist")

    def test_init_lua_contains_features(self):
        init_path = os.path.join(self.base_dir, "init.lua")
        with open(init_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("BOTTOM_SHELLS", content)
        self.assertIn("bottom_aeondx_clean.png", content)
        self.assertIn("bottom_aeondx_distressed.png", content)
        self.assertIn("openAnim", content)
        self.assertIn("Sfx.play(\"hinge\"", content)
        self.assertIn("LV.foldBottomShell", content)
        self.assertIn("drawBoot(L, \"top\")", content)
        self.assertIn("drawBoot(L, \"bot\")", content)

    def test_sticker_lua_contains_favorites(self):
        sticker_path = os.path.join(self.base_dir, "sticker.lua")
        with open(sticker_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("FAVORITES_FILE", content)
        self.assertIn("toggleFavorite", content)
        self.assertIn("saveFavorite", content)
        self.assertIn("getFavorites", content)
        self.assertIn("addDefault", content)
        self.assertIn("applyFavorite", content)

if __name__ == '__main__':
    unittest.main()
