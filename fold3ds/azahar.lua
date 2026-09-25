-- Azahar -- the 3DS emulator this app is built on -- as the 3DS HOME menu
-- sees it:
--
--   * the 3DS games: Azahar's side (org.citra.citra_emu.fold3ds.Fold3dsBridge)
--     writes its library into this save folder whenever the menu comes back
--     to the front -- fold3ds_azahar/games.tsv, one line per game, and
--     fold3ds_azahar/icons/<key>.png, each game's own icon.  They become
--     tiles on the HOME menu next to the recomp games;
--   * the Azahar folder: one tile on the HOME menu that opens to an icon per
--     settings page and tool (icons: fold3ds/icons3ds/<id>.png);
--   * opening any of them: love.system.openURL("fold3ds-azahar://...") to
--     Fold3dsLinkActivity, which starts the game or opens the page on top of
--     the menu (Back comes back here).
--
-- POKEPORT_FOLD_FAKEAZAHAR=1 lists three made-up games on the desktop.
local A = {}

local DIR = "fold3ds_azahar/"
local LIST = DIR .. "games.tsv"
local SCHEME = "fold3ds-azahar://"
local POLL = 1.0             -- seconds between looks at games.tsv

A.FOLDER = "azahar"

-- the Azahar folder, in the order it shows: settings pages first, then the
-- tools.  url: what Fold3dsLinkActivity is asked to open.
A.ITEMS = {
  { id = "az_library", name = "3DS Library", sub = "Azahar's own list of every 3DS game", url = "azahar?open=library" },
  { id = "az_settings", name = "Emulation Settings", sub = "Every Azahar setting", url = "settings?menu=config" },
  { id = "az_graphics", name = "Graphics", sub = "Renderer, resolution, shaders, filtering", url = "settings?menu=Renderer" },
  { id = "az_layout", name = "Screen Layout", sub = "Where the two 3DS screens go", url = "settings?menu=Layout" },
  { id = "az_controls", name = "Controls", sub = "Buttons, controllers and hotkeys", url = "settings?menu=Controls" },
  { id = "az_audio", name = "Sound", sub = "Output, volume and the microphone", url = "settings?menu=Audio" },
  { id = "az_system", name = "System Settings", sub = "Region, language, user name, clock", url = "settings?menu=System" },
  { id = "az_core", name = "General", sub = "CPU, speed limit and turbo", url = "settings?menu=Core" },
  { id = "az_camera", name = "3DS Camera", sub = "Which phone camera the 3DS sees", url = "settings?menu=Camera" },
  { id = "az_storage", name = "Storage", sub = "The virtual SD card and NAND", url = "settings?menu=Storage" },
  { id = "az_network", name = "Web Service", sub = "Your Azahar account", url = "settings?menu=WebService" },
  { id = "az_debug", name = "Debug", sub = "Logging and debugging", url = "settings?menu=Debugging" },
  { id = "az_install", name = "Install CIA", sub = "Install games, updates and DLC", url = "install" },
  { id = "az_gamedir", name = "Games Folder", sub = "Choose the folder your 3DS games are in", url = "games_folder" },
  { id = "az_sysfiles", name = "System Files", sub = "Set up the 3DS system files", url = "azahar?open=system_files" },
  { id = "az_drivers", name = "GPU Drivers", sub = "Custom GPU drivers", url = "azahar?open=drivers" },
  { id = "az_multiplayer", name = "Multiplayer", sub = "Local wireless play, online", url = "azahar?open=multiplayer" },
  { id = "az_artic", name = "Artic Base", sub = "Play from a real 3DS", url = "artic" },
  { id = "az_userdir", name = "Azahar Folder", sub = "Where Azahar keeps its data", url = "azahar?open=user_folder" },
  { id = "az_log", name = "Share Log", sub = "Send Azahar's log file", url = "share_log" },
  { id = "az_about", name = "About Azahar", sub = "Version and licenses", url = "azahar?open=about" },
}

local st = {
  status = nil,    -- nil (no word from Azahar yet) | "ready" | "setup"
  games = {},      -- tiles, in the list's order
  stamp = nil,     -- games.tsv's modtime and size when last read
  checkAt = -1,
  images = {},     -- key -> Image | false
}

local function fake()
  return os.getenv and os.getenv("POKEPORT_FOLD_FAKEAZAHAR") == "1"
end

local function split(line)
  local out = {}
  for field in (line .. "\t"):gmatch("([^\t]*)\t") do out[#out + 1] = field end
  return out
end

local function parse(text)
  local status, games = nil, {}
  for line in text:gmatch("[^\n]+") do
    local f = split(line)
    if f[1] == "state" then
      status = f[2]
    elseif f[1] == "game" and f[2] and f[2]:match("^[%w_]+$") then
      games[#games + 1] = {
        id = "ctr_" .. f[2], key = f[2], ctr = true,
        name = (f[3] ~= "" and f[3]) or "3DS game",
        sub = (f[4] ~= "" and f[4]) or "Nintendo 3DS",
        regions = f[5], hasIcon = f[6] == "1", installed = f[7] == "1",
        tdb = f[9] ~= "" and f[9] or nil, hasCart = f[10] == "1",
      }
    end
  end
  return status, games
end

local function load()
  if fake() then
    st.status = "ready"
    st.games = {
      { id = "ctr_fake1", key = "fake1", ctr = true, name = "Pokémon X", sub = "Nintendo" },
      { id = "ctr_fake2", key = "fake2", ctr = true, name = "Pokémon Alpha Sapphire", sub = "Nintendo" },
      { id = "ctr_fake3", key = "fake3", ctr = true, name = "Super Mario 3D Land", sub = "Nintendo" },
    }
    st.stamp = "fake"
    return
  end
  local info = love.filesystem.getInfo(LIST, "file")
  local stamp = info and ((info.modtime or 0) .. ":" .. (info.size or 0)) or nil
  if stamp == st.stamp then return end
  st.stamp = stamp
  st.images = {}
  if not stamp then st.status, st.games = nil, {} return end
  local ok, text = pcall(love.filesystem.read, LIST)
  if not ok or type(text) ~= "string" then return end
  st.status, st.games = parse(text)
end

function A.init() load() end

-- a look at games.tsv now and then (Azahar rewrites it when the menu comes
-- back from a game or a settings page)
function A.poll(time)
  if time and time < st.checkAt then return end
  st.checkAt = (time or 0) + POLL
  load()
end

function A.status() return st.status end
function A.games() return st.games end

-- the game's own icon (48x48 from its SMDH)
function A.icon(t)
  if not t or not t.key then return nil end
  if st.images[t.key] == nil then
    st.images[t.key] = false
    if t.hasIcon then
      local ok, img = pcall(love.graphics.newImage, DIR .. "icons/" .. t.key .. ".png")
      if ok and img then
        img:setFilter("linear", "linear")
        st.images[t.key] = img
      end
    end
  end
  return st.images[t.key] or nil
end

-- a photo of the game's card (GameTDB, fetched by Azahar's side)
function A.cart(t)
  if not t or not t.key or not t.hasCart then return nil end
  local k = t.key .. "_cart"
  if st.images[k] == nil then
    st.images[k] = false
    local ok, img = pcall(love.graphics.newImage, DIR .. "icons/" .. t.key .. "_cart.png")
    if ok and img then
      img:setFilter("linear", "linear")
      st.images[k] = img
    end
  end
  return st.images[k] or nil
end

-- open something in Azahar (false on a desktop, which has no Azahar)
function A.open(url)
  if not (love.system and love.system.openURL) then return false end
  if love.system.getOS and love.system.getOS() ~= "Android" then return false end
  return love.system.openURL(SCHEME .. url) and true or false
end

-- a name's first character (whole, however many bytes it is in UTF-8)
function A.initial(name)
  name = name or ""
  local ok, utf8 = pcall(require, "utf8")
  local stop = ok and utf8.offset(name, 2) or 2
  local c = name:sub(1, (stop or #name + 1) - 1)
  return c ~= "" and c or "?"
end

function A.play(t) return t and t.key and A.open("play?key=" .. t.key) end
function A.manual(t) return t and t.key and A.open("manual?key=" .. t.key) end

return A
