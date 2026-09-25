-- The 3DS HOME menu's own sound effects for the menus (never in game):
-- fold3ds/sounds/<name>.wav, trimmed from the originals.  Settings > 3DS
-- Shell turns them off.
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

local sources = {}
X.enabled = true

local function source(name)
  if sources[name] == nil then
    local ok, s = pcall(love.audio.newSource, DIR .. name .. ".wav", "static")
    sources[name] = ok and s or false
    if ok then s:setVolume(VOLUME) end
  end
  return sources[name] or nil
end

X.inGame = false   -- the menus' sounds stay out of the game

-- play a menu event's sound (restarting it if it is still going); `force`
-- plays it in game too (HOME, the C-stick: shell buttons the player pressed)
function X.play(event, force)
  if not X.enabled or not love.audio then return end
  if X.inGame and not force then return end
  local s = source(EVENTS[event] or event)
  if not s then return end
  pcall(function()
    s:stop()
    s:play()
  end)
end

return X
