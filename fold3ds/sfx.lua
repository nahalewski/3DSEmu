-- The 3DS HOME menu's own sound effects for the menus (never in game):
-- fold3ds/sounds/<name>.wav, trimmed from the originals.  Settings > 3DS
-- Shell turns them off.  In the Switch HOME menu the same events play the
-- Switch's own sounds instead: sounds/switch/<name>.wav in the save folder,
-- fetched once onto the phone (FoldBridge sounds.fetch), with the 3DS ones
-- standing in until they are there.
local X = {}

local DIR = "fold3ds/sounds/"
local VOLUME = 0.7
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
  gift = "home_open_wrapped",         -- a download that arrived; a present unwrapped
  newapp = "home_newapp_in",          -- a new game arrived on the HOME menu, wrapped
  boot = "home_welcome",              -- the boot screen's jingle
  click = "home_capture_end",         -- the lid opening (and the app starting)
  on = "home_check_btn",
  off = "home_check_btn_off",
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
X.enabled = true

local function source(path)
  if sources[path] == nil then
    local ok, s = pcall(love.audio.newSource, path, "static")
    sources[path] = ok and s or false
    if ok then s:setVolume(VOLUME) end
  end
  return sources[path] or nil
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

X.inGame = false   -- the menus' sounds stay out of the game

-- play a menu event's sound (restarting it if it is still going); `force`
-- plays it in game too (HOME, the C-stick: shell buttons the player pressed)
function X.play(event, force)
  if not X.enabled or not love.audio then return end
  if X.inGame and not force then return end
  local s = switchHome() and switchSource(event)
    or source(DIR .. (EVENTS[event] or event) .. ".wav")
  if not s then return end
  pcall(function()
    s:stop()
    s:play()
  end)
end

return X
