-- SkinManager: Manages UI skins (3DS clamshell and full-screen Switch)
-- Configurable via XML in fold3ds/SKINS/<skin_id>/skin.xml
local M = {}

local lg = love.graphics
local XML = require("fold3ds.xmlparser")

local CFG_FILE = "fold3ds_skin.cfg"
local DEFAULT_SKIN = "3ds" -- Keep 3DS skin default until user toggles or sets it

M.currentSkin = DEFAULT_SKIN
M.variant = "dark"
M.config = nil
M.textures = {}
M.prebuilt = {}

local BASE_DIRS = {
  "fold3ds/SKINS/switch/",
  "SKINS/switch/",
}

local function findSkinDir(id)
  for _, dir in ipairs(BASE_DIRS) do
    local path = dir .. "skin.xml"
    local info = love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(path)
    if info or (love.filesystem and love.filesystem.read and love.filesystem.read(path)) then
      return dir
    end
  end
  return "fold3ds/SKINS/switch/"
end

function M.init()
  -- Load user skin preference
  if love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(CFG_FILE) then
    local content = love.filesystem.read(CFG_FILE)
    if content then
      for line in content:gmatch("[^\r\n]+") do
        local k, v = line:match("^([%w_]+)=(.*)$")
        if k == "skin" then M.currentSkin = v end
        if k == "variant" then M.variant = v end
      end
    end
  end
  
  if M.currentSkin == "switch" then
    M.loadSkin("switch")
  end
end

function M.save()
  if love.filesystem and love.filesystem.write then
    pcall(love.filesystem.write, CFG_FILE, ("skin=%s\nvariant=%s\n"):format(M.currentSkin, M.variant))
  end
end

function M.setSkin(id)
  if id ~= "3ds" and id ~= "switch" then return end
  M.currentSkin = id
  if id == "switch" then
    M.loadSkin("switch")
  end
  M.save()
end

function M.toggleSkin()
  if M.currentSkin == "3ds" then
    M.setSkin("switch")
  else
    M.setSkin("3ds")
  end
  return M.currentSkin
end

function M.loadSkin(id)
  local skinDir = findSkinDir(id)
  local xmlPath = skinDir .. "skin.xml"
  local content = love.filesystem and love.filesystem.read and love.filesystem.read(xmlPath)
  if content then
    local parsed = XML.parse(content)
    if parsed then
      M.config = parsed
    end
  end
  M.skinDir = skinDir
end

function M.getTexture(filename)
  if not filename then return nil end
  if M.textures[filename] then return M.textures[filename] end

  local base = M.skinDir or "fold3ds/SKINS/switch/"
  local fullPath = base .. filename
  if not (filename:find("/") or filename:find("\\")) then
    fullPath = base .. "textures/" .. filename
  end

  local ok, img = pcall(lg.newImage, fullPath)
  if ok and img then
    M.textures[filename] = img
    return img
  end
  return nil
end

-- Map a game tile to its corresponding Switch card or frame
function M.getCardForGame(t)
  if not t then return M.getTexture("card_placeholder_light.png") end
  local id = string.lower(t.id or "")
  local sys = string.lower(t.system or "")

  -- Prebuilt Pokemon titles
  local prebuiltNames = {
    red = "card_pokemon_red.png",
    blue = "card_pokemon_blue.png",
    yellow = "card_pokemon_yellow.png",
    gold = "card_pokemon_gold.png",
    silver = "card_pokemon_silver.png",
    crystal = "card_pokemon_crystal.png",
    firered = "card_pokemon_firered.png",
    leafgreen = "card_pokemon_leafgreen.png",
    ruby = "card_pokemon_ruby.png",
    sapphire = "card_pokemon_sapphire.png",
    emerald = "card_pokemon_emerald.png",
    diamond = "card_nds.png",
    omegaruby = "card_3ds.png",
  }
  for key, imgName in pairs(prebuiltNames) do
    if id:find(key) then
      local tex = M.getTexture(imgName)
      if tex then return tex end
    end
  end

  -- System-specific frames
  local frameForSys = {
    gb = "frame_gb.png",
    gbc = "frame_gbc.png",
    gba = "frame_gba.png",
    nds = "frame_nds.png",
    ["3ds"] = "frame_3ds.png",
    nes = "frame_nes.png",
    snes = "frame_snes.png",
    n64 = "frame_n64.png",
    gamecube = "frame_gamecube.png",
    wii = "frame_wii.png",
    wiiu = "frame_wiiu.png",
    switch = "frame_switch.png",
  }
  if frameForSys[sys] then
    local frm = M.getTexture(frameForSys[sys])
    if frm then return frm, true end
  end

  -- Fallback default frame based on active theme variant
  if M.variant == "dark" then
    return M.getTexture("frame_dark.png") or M.getTexture("card_placeholder_dark.png")
  else
    return M.getTexture("frame_clean.png") or M.getTexture("card_placeholder_light.png")
  end
end

return M
