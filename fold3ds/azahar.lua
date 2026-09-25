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
  { id = "az_screens", name = "Full / Native Screens", sub = "Switch 3DS games between full screens and native size", url = "screens?mode=toggle" },
  { id = "az_inshell", name = "Play in the Shell", sub = "3DS games on the shell's screens, or in Azahar's own", url = "inshell?toggle" },
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
  st.userDir, st.gamesDir = nil, nil
  for line in text:gmatch("[^\n]+") do
    local f = split(line)
    if f[1] == "state" then
      status = f[2]
    elseif f[1] == "userdir" then
      st.userDir = f[2] ~= "" and f[2] or nil
    elseif f[1] == "gamesdir" then
      st.gamesDir = f[2] ~= "" and f[2] or nil
    elseif f[1] == "game" and f[2] and f[2]:match("^[%w_]+$") then
      games[#games + 1] = {
        id = "ctr_" .. f[2], key = f[2], ctr = true,
        name = (f[3] ~= "" and f[3]) or "3DS game",
        sub = (f[4] ~= "" and f[4]) or "Nintendo 3DS",
        regions = f[5], hasIcon = f[6] == "1", installed = f[7] == "1",
        tdb = f[9] ~= "" and f[9] or nil, hasCart = f[10] == "1", system = "3ds",
        file = f[11] ~= "" and f[11] or nil, titleId = f[12],
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
-- Azahar's folder and the 3DS games folder, as paths (Download Play)
function A.userDir() return st.userDir end
function A.gamesDir() return st.gamesDir end

-- a 3DS game's files for Download Play, as FoldBridge.zip entries
-- ("/path=>entry"): the cartridge dump (games3ds/<file>) and, in Azahar's
-- folder, its title folders -- the game if installed, its update, its DLC
-- and its save data -- at the same place (azahar/sdmc/...)
local SDMC = "sdmc/Nintendo 3DS/00000000000000000000000000000000/00000000000000000000000000000000/title/"
function A.transferEntries(t)
  local out = {}
  if t.file then out[#out + 1] = t.file .. "=>games3ds/" .. (t.file:match("[^/]+$") or "game.3ds") end
  local low = t.titleId and t.titleId:sub(9, 16)
  if st.userDir and low and #low == 8 then
    for _, high in ipairs({ "00040000", "0004000e", "0004008c" }) do
      local rel = SDMC .. high .. "/" .. low
      out[#out + 1] = st.userDir .. "/" .. rel .. "=>azahar/" .. rel
    end
  end
  return out
end
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
  if url == "inshell?toggle" then return A.toggleShell() end
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

---------------------------------------------------------------- in the shell
-- A 3DS game plays INSIDE the 3DS shell (fold3ds.emuplay): Azahar's core
-- runs in this process (Fold3dsShell.kt) and its frames come here through
-- FoldBridge ("3ds.*").  The frame is one buffer, the top screen above the
-- touch screen (400s x 480s); its address is read through LuaJIT's FFI and
-- copied into two ImageData.  If the core can't start in the shell, the game
-- opens in Azahar's own full screen instead, as before.
local ffi = require("ffi")
local SHELL_CFG = "fold3ds_azahar.cfg"
local play = { tile = nil, serial = -1, data = {}, img = {}, menu = false, sel = 1,
  toast = nil, dirs = {}, checkAt = 0 }

local function bridge(cmd, arg)
  local f = love.system and love.system.foldCamera
  if not f then return nil end
  local ok, out = pcall(f, "call", cmd, arg or "")
  return ok and out or nil
end

local function say(text) play.toast = { text = text, at = love.timer.getTime() } end

-- play in the shell (1, the default) or in Azahar's own screen (0)
function A.inShell()
  local ok, text = pcall(love.filesystem.read, SHELL_CFG)
  return not (ok and type(text) == "string" and text:match("shell=0"))
end

function A.setInShell(on)
  pcall(love.filesystem.write, SHELL_CFG, "shell=" .. (on and "1" or "0") .. "\n")
end

function A.toggleShell()
  A.setInShell(not A.inShell())
  say(A.inShell() and "3DS games play in the shell" or "3DS games open in Azahar's own screen")
  return true
end

function A.play(t)
  if not (t and t.key) then return end
  if A.inShell() then
    local r = bridge("3ds.start", t.key)
    if r == "ok" then
      play.tile, play.serial, play.menu, play.sel, play.dirs = t, -1, false, 1, {}
      return true
    end
    if r == "error:setup" then return A.open("setup") end
  end
  return A.open("play?key=" .. t.key)
end

function A.running()
  if not play.tile then return nil end
  -- the core ended by itself (an error, the game quit): back to the menu
  local now = love.timer.getTime()
  if now >= play.checkAt then
    play.checkAt = now + 0.5
    if bridge("3ds.state") == "stopped" then play.tile = nil end
  end
  return play.tile
end

-- the newest frame into the two screens' images
local function copyFrame()
  local info = bridge("3ds.frame")
  local hi, lo, w, h, serial, s = (info or ""):match("^(%d+):(%d+):(%d+):(%d+):(%d+):(%d+)$")
  if not hi then return end
  serial = tonumber(serial)
  if serial == play.serial or serial == 0 then return end
  play.serial = serial
  w, h, s = tonumber(w), tonumber(h), tonumber(s)
  local addr = ffi.cast("uint64_t", tonumber(hi)) * 4294967296ULL + ffi.cast("uint64_t", tonumber(lo))
  local src = ffi.cast("const uint8_t*", addr)
  local tw, th, bw = 400 * s, 240 * s, 320 * s
  for i, size in ipairs({ { tw, th }, { bw, th } }) do
    if not play.data[i] then
      play.data[i] = love.image.newImageData(size[1], size[2])
    end
  end
  -- the top screen: whole rows of the frame; the touch screen: the left
  -- 320s of each row below it
  local top = ffi.cast("uint8_t*", play.data[1]:getFFIPointer())
  ffi.copy(top, src, tw * th * 4)
  local bot = ffi.cast("uint8_t*", play.data[2]:getFFIPointer())
  for y = 0, th - 1 do
    ffi.copy(bot + y * bw * 4, src + (th + y) * w * 4, bw * 4)
  end
  for i = 1, 2 do
    if play.img[i] then
      play.img[i]:replacePixels(play.data[i])
    else
      play.img[i] = love.graphics.newImage(play.data[i])
      play.img[i]:setFilter("linear", "linear")
    end
  end
end

function A.update() if play.tile then copyFrame() end end

function A.screen(i) return play.img[(i or 0) + 1] end

function A.screenSize() return 400, 240 end

-- the circle pad from the shell's directions
local function stick()
  local d = play.dirs
  local x = (d.right and 1 or 0) - (d.left and 1 or 0)
  local y = (d.down and 1 or 0) - (d.up and 1 or 0)
  bridge("3ds.stick", x .. "|" .. y)
end

local MENU = { { "Resume", "resume" }, { "Save State", "save" }, { "Load State", "load" }, { "Close Game", "close" } }

local function setMenu(open)
  play.menu = open
  play.sel = 1
  bridge(open and "3ds.pause" or "3ds.resume")
end

function A.press(btn)
  if not play.tile then return end
  if btn == "home" then setMenu(not play.menu) return end
  if play.menu then
    if btn == "up" then play.sel = math.max(1, play.sel - 1)
    elseif btn == "down" then play.sel = math.min(#MENU, play.sel + 1)
    elseif btn == "a" then A.menuDo(MENU[play.sel][2])
    elseif btn == "b" then setMenu(false) end
    return
  end
  if btn == "up" or btn == "down" or btn == "left" or btn == "right" then
    play.dirs[btn] = true
    stick()
    return
  end
  bridge("3ds.key", btn .. "|1")
end

function A.release(btn)
  if not play.tile or play.menu or btn == "home" then return end
  if btn == "up" or btn == "down" or btn == "left" or btn == "right" then
    play.dirs[btn] = nil
    stick()
    return
  end
  bridge("3ds.key", btn .. "|0")
end

function A.touch(phase, u, v)
  if play.tile and not play.menu then bridge("3ds.touch", ("%s|%.4f|%.4f"):format(phase, u, v)) end
end

function A.menu()
  local rows = {}
  for i, m in ipairs(MENU) do rows[i] = { m[1], m[2] } end
  return { open = play.menu, rows = rows, sel = play.sel }
end

function A.menuDo(id)
  if id == "resume" then setMenu(false)
  elseif id == "save" then bridge("3ds.save", "1"); say("Saved"); setMenu(false)
  elseif id == "load" then bridge("3ds.load", "1"); say("Loaded"); setMenu(false)
  elseif id == "close" then A.stop() end
end

function A.stop()
  bridge("3ds.stop")
  play.tile, play.menu, play.dirs = nil, false, {}
end

function A.toast()
  local t = play.toast
  if t and love.timer.getTime() - t.at < 2.5 then return t.text end
  return nil
end

function A.manual(t) return t and t.key and A.open("manual?key=" .. t.key) end

-- on the HOME menu (fold3ds.emus): Azahar's folder, its set-up and
-- add-games tiles, and its games.  Functions are looked up on A when called,
-- so a wrapper put on A.play (the Activity Log's) still sees every launch.
A.provider = {
  id = A.FOLDER,
  system = "Nintendo 3DS",
  folder = { name = "Azahar", sub = "3DS emulator settings and tools", items = A.ITEMS },
  setupTile = { id = "ctr_setup", url = "setup", name = "Set Up 3DS",
    sub = "Choose Azahar's folder to play 3DS games" },
  addTile = { id = "ctr_add", url = "add_games", name = "Add 3DS Games",
    sub = "Install CIA files or choose your games folder" },
  status = function() return A.status() end,
  games = function() return A.games() end,
  icon = function(t) return A.icon(t) end,
  iconPath = function(t) return t.hasIcon and t.key and (DIR .. "icons/" .. t.key .. ".png") or nil end,
  cart = function(t) return A.cart(t) end,
  open = function(url) return A.open(url) end,
  play = function(t) return A.play(t) end,
  -- in the shell (fold3ds.emuplay)
  running = function() return A.running() end,
  update = function(dt) return A.update(dt) end,
  screen = function(i) return A.screen(i) end,
  screenSize = function(sys) return A.screenSize(sys) end,
  press = function(btn) return A.press(btn) end,
  release = function(btn) return A.release(btn) end,
  touch = function(phase, u, v) return A.touch(phase, u, v) end,
  menu = function() return A.menu() end,
  menuDo = function(id) return A.menuDo(id) end,
  stop = function() return A.stop() end,
  toast = function() return A.toast() end,
  manual = function(t) return A.manual(t) end,
  init = function() return A.init() end,
  poll = function(time) return A.poll(time) end,
  transferEntries = function(t) return A.transferEntries(t) end,
}

return A
