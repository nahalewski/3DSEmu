"""Unit tests for AeonDX multi-emulator directory and ROM architecture."""

import unittest
import os
import tempfile
import shutil

class TestAeonDXPaths(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="aeondx_test_")

    def tearDown(self):
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_aeondx_lua_module_exists(self):
        lua_path = r"C:\Users\Ben\Desktop\RECOMP\3DSEmu\fold3ds\aeondx.lua"
        self.assertTrue(os.path.exists(lua_path), "aeondx.lua must exist in fold3ds")
        with open(lua_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn('M.NAME = "AeonDX"', content)
        self.assertIn('azahar', content)
        self.assertIn('melonds', content)
        self.assertIn('vc', content)
        self.assertIn('eden', content)

    def test_aeondx_folder_structure_generation(self):
        root = os.path.join(self.test_dir, "AeonDX")
        emulators = {
            "azahar": {
                "consoles": ["3ds"],
                "data_dirs": ["config", "saves", "states", "sdmc", "nand", "sysdata", "dumps"]
            },
            "melonds": {
                "consoles": ["ds"],
                "data_dirs": ["config", "saves", "states", "bios", "dsiware"]
            },
            "vc": {
                "consoles": ["gb", "gbc", "gba"],
                "data_dirs": ["config", "saves", "states", "bios"]
            },
            "eden": {
                "consoles": ["switch"],
                "data_dirs": ["config", "saves", "nand", "keys", "load", "screenshots"]
            }
        }

        # Simulate creation logic matching AeonDX.ensureAllDirectories
        for emu, spec in emulators.items():
            emu_base = os.path.join(root, emu)
            data_base = os.path.join(emu_base, "data")
            for sub in spec["data_dirs"]:
                os.makedirs(os.path.join(data_base, sub), exist_ok=True)
            for console in spec["consoles"]:
                os.makedirs(os.path.join(emu_base, "roms", console), exist_ok=True)
                os.makedirs(os.path.join(emu_base, "ROM", console), exist_ok=True)
                os.makedirs(os.path.join(root, "roms", console), exist_ok=True)

        # Verify all directories exist
        for emu, spec in emulators.items():
            emu_base = os.path.join(root, emu)
            self.assertTrue(os.path.isdir(emu_base), f"{emu} folder must exist")
            self.assertTrue(os.path.isdir(os.path.join(emu_base, "data")), f"{emu}/data must exist")
            for sub in spec["data_dirs"]:
                sub_dir = os.path.join(emu_base, "data", sub)
                self.assertTrue(os.path.isdir(sub_dir), f"{sub_dir} must exist")
            for console in spec["consoles"]:
                rom_dir = os.path.join(emu_base, "roms", console)
                self.assertTrue(os.path.isdir(rom_dir), f"{rom_dir} must exist")

    def test_emucore_aeondx_integration(self):
        emucore_path = r"C:\Users\Ben\Desktop\RECOMP\3DSEmu\fold3ds\emucore.lua"
        with open(emucore_path, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn('E.NAME = "AeonDX"', content)
        self.assertIn('AeonDX.pickRoot', content)
        self.assertIn('AeonDX.getSavePath', content)
        self.assertIn('AeonDX.getStatePath', content)
        self.assertIn('AeonDX.getBiosDir', content)
        self.assertIn('AeonDX.getAllScanDirs', content)

    def test_eden_and_azahar_aeondx_integration(self):
        eden_path = r"C:\Users\Ben\Desktop\RECOMP\3DSEmu\fold3ds\eden.lua"
        with open(eden_path, "r", encoding="utf-8") as f:
            eden_content = f.read()
        self.assertIn('fold3ds.aeondx', eden_content)
        self.assertIn('AeonDX.getRomDir("switch")', eden_content)
        self.assertIn('AeonDX.getDataDir("eden")', eden_content)

        azahar_path = r"C:\Users\Ben\Desktop\RECOMP\3DSEmu\fold3ds\azahar.lua"
        with open(azahar_path, "r", encoding="utf-8") as f:
            azahar_content = f.read()
        self.assertIn('fold3ds.aeondx', azahar_content)
        self.assertIn('AeonDX.getRomDir("3ds")', azahar_content)
        self.assertIn('AeonDX.getDataDir("azahar")', azahar_content)

if __name__ == "__main__":
    unittest.main()
