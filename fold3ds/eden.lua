-- Eden -- the Nintendo Switch emulator -- as the HOME menu sees it, the
-- same way as Azahar (fold3ds/azahar.lua):
--
--   * the Switch games: Eden's side (org.yuzu.yuzu_emu.fold3ds.Fold3dsEdenBridge)
--     writes its game list into this save folder whenever the menu comes
--     back to the front -- fold3ds_eden/games.tsv, one line per game, and
--     fold3ds_eden/icons/<key>.png, each game's icon;
--   * the Eden folder: an icon per Eden settings page and tool
--     (icons: fold3ds/icons3ds/<id>.png);
--   * opening any of them: love.system.openURL("fold3ds-eden://...") to Eden's
--     link activity, which starts the game full screen in Eden's
--     EmulationActivity, or opens the page, over the menu (Back comes back).
--
-- games.tsv lines (tab separated):
--   state   ready | setup
--   userdir <Eden's folder>
--   game    <key [%w_]> <name> <publisher> <has icon 0/1> <file> <program id>
local E = {}

local DIR = "fold3ds_eden/"
local LIST = DIR .. "games.tsv"
local SCHEME = "fold3ds-eden://"
local POLL = 1.0

E.FOLDER = "eden"

-- the Eden folder: its settings pages (Eden's Settings.MenuTag sections),
-- then its tools.  url: what Eden's link activity is asked to open.
E.ITEMS = {
  { id = "eden_settings", name = "Emulation Settings", sub = "Every Eden setting", url = "settings?menu=SECTION_ROOT" },
  { id = "eden_system", name = "System", sub = "Language, region, docked mode, the clock", url = "settings?menu=SECTION_SYSTEM" },
  { id = "eden_graphics", name = "Graphics", sub = "Renderer, resolution, filtering, shaders", url = "settings?menu=SECTION_RENDERER" },
  { id = "eden_postfx", name = "Post-Processing", sub = "Frame generation and screen effects", url = "settings?menu=SECTION_POST_PROCESSING" },
  { id = "eden_audio", name = "Sound", sub = "Output engine and volume", url = "settings?menu=SECTION_AUDIO" },
  { id = "eden_controls", name = "Controls", sub = "Controllers, players and mapping", url = "settings?menu=SECTION_INPUT" },
  { id = "eden_overlay", name = "On-Screen Controls", sub = "The touch buttons over a game", url = "settings?menu=SECTION_INPUT_OVERLAY" },
  { id = "eden_stats", name = "Performance Overlay", sub = "FPS, frame time, memory", url = "settings?menu=SECTION_PERFORMANCE_STATS" },
  { id = "eden_applets", name = "Applets", sub = "The Switch's built-in applets", url = "settings?menu=SECTION_APPLETS" },
  { id = "eden_paths", name = "Folders", sub = "Where Eden keeps saves, NAND and SD", url = "settings?menu=SECTION_CUSTOM_PATHS" },
  { id = "eden_debug", name = "Debug", sub = "Logging and debugging", url = "settings?menu=SECTION_DEBUG" },
  { id = "eden_gamedir", name = "Games Folder", sub = "Choose the folder your Switch games are in", url = "games_folder" },
  { id = "eden_keys", name = "Keys & Firmware", sub = "Install prod.keys and the firmware", url = "eden?open=keys" },
  { id = "eden_install", name = "Install to NAND", sub = "Updates and DLC (NSP / XCI)", url = "install" },
  { id = "eden_drivers", name = "GPU Drivers", sub = "Custom GPU drivers", url = "eden?open=drivers" },
  { id = "eden_about", name = "About Eden", sub = "Version and licenses", url = "eden?open=about" },
}

local st = { status = nil, games = {}, stamp = nil, checkAt = -1, images = {} }
local P, FOLDER

local function split(line)
  local out = {}
  for field in (line .. "\t"):gmatch("([^\t]*)\t") do out[#out + 1] = field end
  return out
end

local function parse(text)
  local status, games = nil, {}
  st.userDir = nil
  for line in text:gmatch("[^\n]+") do
    local f = split(line)
    if f[1] == "state" then
      status = f[2]
    elseif f[1] == "userdir" then
      st.userDir = f[2] ~= "" and f[2] or nil
    elseif f[1] == "game" and f[2] and f[2]:match("^[%w_]+$") then
      games[#games + 1] = {
        id = "nx_" .. f[2], key = f[2], system = "switch",
        name = (f[3] ~= "" and f[3]) or "Switch game",
        sub = (f[4] ~= "" and f[4]) or "Nintendo Switch",
        hasIcon = f[5] == "1",
        file = f[6] ~= "" and f[6] or nil,
        programId = f[7] ~= "" and f[7] or nil,
      }
    end
  end
  return status, games
end

local function load()
  local info = love.filesystem.getInfo(LIST, "file")
  local stamp = info and ((info.modtime or 0) .. ":" .. (info.size or 0)) or nil
  if stamp == st.stamp then return end
  st.stamp = stamp
  st.images = {}
  if not stamp then st.status, st.games, P.folder = nil, {}, nil return end
  local ok, text = pcall(love.filesystem.read, LIST)
  if not ok or type(text) ~= "string" then return end
  st.status, st.games = parse(text)
  P.folder = st.status and FOLDER or nil
end

local function image(key, file)
  if st.images[key] == nil then
    st.images[key] = false
    local ok, img = pcall(love.graphics.newImage, file)
    if ok and img then
      img:setFilter("linear", "linear")
      st.images[key] = img
    end
  end
  return st.images[key] or nil
end

-- open something in Eden (false where there is no Eden: the desktop)
local function open(url)
  if not (love.system and love.system.openURL) then return false end
  if love.system.getOS and love.system.getOS() ~= "Android" then return false end
  return love.system.openURL(SCHEME .. url) and true or false
end

---------------------------------------------------------------- the provider

-- the folder and tiles show only once Eden's side has written games.tsv, so
-- a build without Eden in it shows nothing of it
FOLDER = { name = "Eden", sub = "Switch settings and tools", items = E.ITEMS }
P = {
  id = E.FOLDER,
  system = "Nintendo Switch",
  setupTile = { id = "eden_setup", name = "Set Up Eden", sub = "Keys, firmware and the games folder",
    url = "eden?open=setup" },
  addTile = { id = "eden_add", name = "Add Switch Games", sub = "Choose your Switch games folder (NSP / XCI)",
    url = "games_folder" },
}

function P.init() load() end
function P.poll(time)
  if time and time < st.checkAt then return end
  st.checkAt = (time or 0) + POLL
  load()
end
function P.status() return st.status end
function P.games() return st.games end
-- the eShop's art for a game (fold3ds/emudb/nx.tsv, made at build time
-- from blawar/titledb by tools/make_nx_art.py): icon and banner file names
-- under ESHOP, by the base game's title id
local ESHOP = "https://img-eshop.cdn.nintendo.net/i/"
local artText
local function eshopArt(t)
  local id = t and t.programId and t.programId:upper()
  if not id or #id ~= 16 then return nil end
  id = id:sub(1, 13) .. "000"
  if artText == nil then
    local ok, text = pcall(love.filesystem.read, "fold3ds/emudb/nx.tsv")
    artText = ok and type(text) == "string" and text or false
  end
  if not artText then return nil end
  local icon, banner = artText:match("\n" .. id .. "\t(%x*)\t(%x*)")
  if not icon then icon, banner = artText:match("^" .. id .. "\t(%x*)\t(%x*)") end
  if not icon then return nil end
  return { icon = icon ~= "" and icon or nil, banner = banner ~= "" and banner or nil, id = id }
end

-- a picture downloaded on the phone once (fold3ds_eden/art/): nil until it
-- is there; asks for it the first time
local fetching = {}
local function fetched(hash)
  if not hash then return nil end
  local file = DIR .. "art/" .. hash .. ".jpg"
  if love.filesystem.getInfo(file, "file") then return image(hash, file) end
  if not fetching[hash] then
    fetching[hash] = true
    local ok, Core = pcall(require, "fold3ds.emucore")
    if ok and Core and Core.fetch then pcall(Core.fetch, ESHOP .. hash .. ".jpg", file) end
  end
  return nil
end

-- the game's own square icon (Eden reads it from the game), else the eShop's
function P.icon(t)
  if not (t and t.key) then return nil end
  if t.hasIcon then
    local img = image(t.key, DIR .. "icons/" .. t.key .. ".png")
    if img then return img end
  end
  local a = eshopArt(t)
  return a and fetched(a.icon) or nil
end
function P.iconPath(t)
  if t and t.key and t.hasIcon then return DIR .. "icons/" .. t.key .. ".png" end
  local a = eshopArt(t)
  local file = a and a.icon and (DIR .. "art/" .. a.icon .. ".jpg")
  return file and love.filesystem.getInfo(file, "file") and file or nil
end
-- the game's banner (the eShop's), shown as its card
function P.cart(t)
  local a = eshopArt(t)
  return a and fetched(a.banner) or nil
end
-- the 3D Switch game card: dark grey, the banner or icon as its label
function P.cartSkin(t)
  return { shape = "switch", color = { 38, 38, 42 }, labelImage = P.cart(t) or P.icon(t), cart = true }
end
P.open = open
-- full screen in Eden's own EmulationActivity (in-shell play comes later)
function P.play(t) return t and t.key and open("play?key=" .. t.key) or false end
-- Manual: the game's properties in Eden (add-ons, saves, per-game settings)
function P.manual(t) return t and t.key and open("game?key=" .. t.key) or false end

E.provider = P
E.parse = parse   -- for the tests

return E
