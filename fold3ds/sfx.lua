-- The 3DS HOME menu's sound effects for the menus (never in game):
-- fold3ds/sounds/ (OGG Vorbis, MP3, or WAV). Compressed to high-quality
-- OGG to keep the APK compact without losing audio quality. Settings > 3DS Shell turns them off.
-- In the Switch HOME menu the same events play the Switch's own sounds instead:
-- sounds/switch/<name>.wav in the save folder, fetched once onto the phone (FoldBridge sounds.fetch).
local X = {}

local DIR = "fold3ds/sounds/"
local VOLUME = 0.7
local BannerSounds = nil

-- what each menu event sounds like
local EVENTS = {
  select = "home_icon_select",        -- a HOME tile selected
  over = "home_icon_over",            -- the pads move the selection
  open = "common_ok",                 -- a tile / applet opened
  launch = "home_start",              -- a game started
  strip = "home_icon_scroll",         -- the icon strip turned a screen
  edge = "home_icon_scroll_invalid",  -- nowhere further to go
  zoomIn = "mymenu_zoom_in",          -- bigger icons
  zoomOut = "mymenu_zoom_out",        -- smaller icons
  grab = "home_icon_grab",            -- a tile lifted to move it
  drop = "home_icon_release",         -- and put down
  swap = "home_icon_exchange",        -- it passed another tile
  back = "common_return",             -- back to the HOME menu
  cancel = "common_cancel",
  home = "home_homebutton",           -- HOME out of a game
  homeMenu = "home_homebutton_return",-- HOME in the menus
  button = "common_button",           -- any launcher control
  touch = "home_touch",               -- the applet bar
  scroll = "common_scroll",           -- a scroll arrow step
  noMove = "common_nomove",           -- a scroll arrow at its end
  dialog = "common_dialog",           -- a popup opened
  peel = "badge_float",               -- a sticker lifted
  stick = "badge_replace",            -- a sticker stuck down
  fall = "badge_disappear",           -- a worn sticker fell off
  newSticker = "badge_appear",        -- a sticker made
  screen = "theme_list_over",         -- the C-stick changed the top screen
  coin = "home_popup_inf",            -- the play meter paid a coin
  start = "home_start_effect",        -- the menu first came up
  connect = "common_connect",         -- the eShop connecting
  waitEnd = "common_wait_end",        -- and done loading
  notice = "common_notice",
  error = "common_error",             -- a download that failed
  gift = "home_open_wrapped",         -- a download that arrived
  newapp = "home_newapp_in",          -- a new game arrived on the HOME menu, wrapped
  boot = "home_welcome",              -- the boot screen's jingle
  click = "hinge_open",               -- the lid opening (mechanical 3DS hinge)
  hinge = "hinge_open",               -- 3DS XL mechanical hinge detent snap
  hingeOpen = "hinge_open",           -- unfolding open
  hingeClose = "hinge_close",         -- clamshell closing snap
  on = "home_check_btn",
  off = "home_check_btn_off",
  insert = "cartridge_insert",        -- game cartridge inserted into slot
}

-- the Switch's sound for each event (sounds/switch/, the save folder)
local NX_DIR = "sounds/switch/"
local SWITCH = {
  select = "SeGameIconFocus", over = "SeBtnFocus", open = "SeGameIconDecide",
  launch = "SeEntLaunchEffect", strip = "SeGameIconScroll", scroll = "SeGameIconScroll",
  edge = "SeGameIconLimit", noMove = "SeGameIconLimit", zoomIn = "SePage", zoomOut = "SePage",
  grab = "SeIconFloat", drop = "SeIconSink", swap = "SeIconMove",
  back = "SeFooterDecideBack", cancel = "SeFooterDecideBack",
  home = "SeUnlockHome", homeMenu = "SeEntLaunchEffectHome",
  button = "SeBtnDecide", touch = "SeTouch", click = "SeTouchCheck",
  dialog = "SeDialogOpen", notice = "SeDialogOpen_Accent", error = "SeWarning",
  waitEnd = "SeSuccess", gift = "SeGiftReceive", newapp = "SeGameIconAdd",
  start = "StartupMenu_Game", boot = "StartupMenu_Ent", connect = "SeVgc_Connect",
  on = "SeToggleBtnOn", off = "SeToggleBtnOff", coin = "SeOptPointGet",
  screen = "SeSliderTickOver",
}

local sources = {}
local currentBanner = nil
X.enabled = true
X.inGame = false   -- the menus' sounds stay out of the game

local function resolvePath(name)
  if not name or name == "" then return nil end
  -- If path already specifies an extension
  if name:match("%.[a-zA-Z0-9]+$") then
    if love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(name) then
      return name
    end
    if love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(DIR .. name) then
      return DIR .. name
    end
    return name
  end

  -- Search extensions in preference order: .ogg (compact), .mp3, .wav
  local exts = { ".ogg", ".mp3", ".wav" }
  for _, ext in ipairs(exts) do
    local p = DIR .. name .. ext
    if not love.filesystem or not love.filesystem.getInfo or love.filesystem.getInfo(p) then
      return p
    end
  end
  return DIR .. name .. ".ogg"
end

local function source(pathOrName)
  if sources[pathOrName] == nil then
    local path = pathOrName
    if not (path:find("/") or path:find("%.[a-zA-Z0-9]+$")) then
      path = resolvePath(pathOrName)
    end
    local ok, s = pcall(love.audio.newSource, path, "static")
    if not ok then
      -- Fallback try other extensions directly if filesystem.getInfo was not available
      for _, ext in ipairs({ ".ogg", ".mp3", ".wav" }) do
        ok, s = pcall(love.audio.newSource, DIR .. pathOrName .. ext, "static")
        if ok then break end
      end
    end
    sources[pathOrName] = ok and s or false
    if ok and s then s:setVolume(VOLUME) end
  end
  return sources[pathOrName] or nil
end

-- the Switch HOME menu is up (fold3ds.homenx, once it has loaded)
local function switchHome()
  local nx = package.loaded["fold3ds.homenx"]
  if type(nx) ~= "table" or not nx.active then return false end
  local ok, on = pcall(nx.active)
  return ok and on
end

-- the Switch's sounds, asked for once a run while they are missing
local fetched = false
local function fetchSwitch()
  if fetched then return end
  fetched = true
  local f = love.system and love.system.foldCamera
  if f then pcall(f, "call", "sounds.fetch", love.filesystem.getSaveDirectory()) end
end

local function switchSource(event)
  local name = SWITCH[event]
  if not name then return nil end
  local path = NX_DIR .. name .. ".wav"
  if sources[path] then return sources[path] end
  if not love.filesystem.getInfo(path, "file") then fetchSwitch(); return nil end
  return source(path)
end

-- play a menu event's sound (restarting it if it is still going); `force`
-- plays it in game too (HOME, the C-stick: shell buttons the player pressed)
function X.play(event, force)
  if not X.enabled or not love.audio then return end
  if X.inGame and not force then return end
  local s = (switchHome() and switchSource(event))
    or source(EVENTS[event] or event)
  if not s then return end
  pcall(function()
    s:stop()
    s:play()
  end)
end

-- Play authentic cartridge insertion click
function X.playInsert(force)
  X.play("insert", force)
end

-- Play authentic game-specific cartridge banner sound
function X.playBanner(game, force)
  if not X.enabled or not love.audio then return end
  if X.inGame and not force then return end

  if BannerSounds == nil then
    local ok, m = pcall(require, "fold3ds.banner_sounds")
    BannerSounds = ok and m or false
  end

  local soundPath = nil
  if BannerSounds and BannerSounds.find then
    soundPath = BannerSounds.find(game)
  end

  if not soundPath then
    -- Generic cartridge click if no unique banner chime is registered
    X.playInsert(force)
    return
  end

  -- Stop previous banner sound so sounds do not clobber each other
  if currentBanner then
    pcall(function() currentBanner:stop() end)
    currentBanner = nil
  end

  local s = source(soundPath)
  if not s then
    local ok, src = pcall(love.audio.newSource, soundPath, "static")
    if ok then
      s = src
      sources[soundPath] = s
      s:setVolume(VOLUME)
    end
  end

  if s then
    currentBanner = s
    pcall(function()
      s:stop()
      s:play()
    end)
  end
end

-- Stop any active banner audio
function X.stopBanner()
  if currentBanner then
    pcall(function() currentBanner:stop() end)
    currentBanner = nil
  end
end

return X
