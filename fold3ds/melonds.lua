-- DS games on the HOME menu (the melonDS core, in libemucore): the provider
-- fold3ds/emus.lua picks up.  Its folder holds the DS settings pages and
-- tools; the data side is fold3ds/emucore.lua.
local Core = require("fold3ds.emucore")
local M = {}

local N = Core.NAME
M.provider = require("fold3ds.emuprovider")({
  id = "melonds",
  system = "Nintendo DS",
  systems = { ds = true },
  folderName = "melonDS",
  folderSub = "Nintendo DS (AeonDX)",
  items = {
    { id = "nds_screen", name = "Screens", sub = "Which screen is on top, pixels, borders", url = "page?id=ds_screen" },
    { id = "nds_profile", name = "DS Profile", sub = "Nickname, language, birthday", url = "page?id=ds_profile" },
    { id = "nds_system", name = "DS System", sub = "BIOS and firmware, the fast CPU", url = "page?id=ds_system" },
    { id = "nds_audio", name = "Sound", sub = "Volume and the sound filter", url = "page?id=audio" },
    { id = "nds_controls", name = "Controls", sub = "Fast forward", url = "page?id=controls" },
    { id = "nds_folder", name = "Games & Folders", sub = "Add games, the " .. N .. " folder", url = "page?id=folder" },
    { id = "nds_about", name = "About melonDS", sub = "The cores and where the art comes from", url = "page?id=about" },
  },
  setupTile = { id = "nds_setup", name = "Set Up " .. N, sub = "Let " .. N .. " keep its folder on storage",
    url = "act?id=storage" },
  addTile = { id = "nds_add", name = "Add DS Games", sub = "Pick a game, or copy into AeonDX/melonds/roms/ds/",
    url = "act?id=add" },
})

return M
