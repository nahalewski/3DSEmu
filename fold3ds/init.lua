-- fold3ds: the Android foldable layer for gen1recomp.
--
-- On a foldable held open the app becomes a 3DS: the game (or the
-- launcher) draws inside the top shell's screen, the bottom shell carries
-- drawn A / B / X / Y, D-pad, stick, START, SELECT and HOME buttons that
-- press real input, and the bottom screen shows the launcher (menus) or,
-- in game, the game's Pokemon animated.  On the cover screen (the phone
-- closed) the closed lid fills the screen.
--
-- It plugs into the engine's own seams and touches no engine file:
--   * HostDisplay backend: beginFrame / endFrame around the launcher's and
--     the game's draw, so each renders into a canvas placed in a screen
--     cutout while believing that canvas is the window (love.graphics
--     size, window mode, safe area, mouse and touch queries are answered
--     in that "virtual window" while it is active);
--   * Input:overlayPressed / overlayReleased for the game buttons;
--   * the launcher's gamepadpressed / gamepadreleased for menu buttons;
--   * Orientation.apply("landscape") so the hinge runs across the middle;
--   * LauncherView.fold (a flag the patched launcher reads) for the compact
--     bottom-screen launcher, and the mod index API to list the community
--     catalog in FIND.
--
-- In game the top screen has three shapes, cycled by a tap on the C-stick
-- above X: the Game Boy's own 10:9 screen at a whole pixel scale, wide
-- (the whole screen opening), and full (the whole top panel, over the
-- Game Boy Color frame).  START's menu and the SELECT mod manager draw on
-- the bottom screen while the world stays on top.
--
-- POKEPORT_FOLD=ds|lid|off forces a mode on the desktop for testing.
local M = {}

local lg, lw, lm, lt = love.graphics, love.window, love.mouse, love.touch
local real = {
  getDimensions = lg.getDimensions, getWidth = lg.getWidth, getHeight = lg.getHeight,
  getPixelDimensions = lg.getPixelDimensions, getPixelWidth = lg.getPixelWidth, getPixelHeight = lg.getPixelHeight,
  setCanvas = lg.setCanvas,
  getMode = lw.getMode, getSafeArea = lw.getSafeArea,
  mouseGetPosition = lm.getPosition, mouseGetX = lm.getX, mouseGetY = lm.getY,
  touchGetTouches = lt.getTouches, touchGetPosition = lt.getPosition,
}
local orig = {}   -- the engine's event handlers, wrapped by install()
local Sticker = require("fold3ds.sticker")
local Theme3DS = require("fold3ds.theme3ds")
local Home = require("fold3ds.home3ds")
local Sfx = require("fold3ds.sfx")
local Cart3D = require("fold3ds.cart3d")
local Camera = require("fold3ds.camera")
local Dlplay = require("fold3ds.dlplay")
local Eshop = require("fold3ds.eshop")
local Azahar = require("fold3ds.azahar")

local DIR = "fold3ds/"
-- shell art (full size); cut = the screen opening in the art's pixels
-- full = the dark panel around the opening (the "full screen" game shape)
local TOP = { file = "skin/top_gbc.png", cut = { 318, 196, 838, 464 }, full = { 224, 148, 1044, 568 } }
local BOTTOM = { file = "skin/bottom_empty.png", cut = { 318, 158, 756, 504 } }
local SHEET = "skin/buttons.png"
local LID = "skin/lid.png"
-- wallpapers: behind the open 3DS, and behind the closed lid on the cover
local WALL_OPEN = "skin/wall_open.jpg"
local WALL_LID = "skin/wall_lid.jpg"
-- the closed shell inside lid.png (x, y, w, h); the rest is transparent
local LID_BOX = { 30, 157, 1390, 757 }
-- sockets in half-size units of the bottom shell (x, y centre, r radius);
-- sprite = rect in the half-size button sheet.  Both scale by 2 for the art.
local BUTTONS = {
  { name = "stick", x = 68, y = 134, r = 50, sprite = { 270, 228, 181, 182 }, kind = "dpad" },
  { name = "pad", x = 68, y = 249, r = 48, sprite = { 37, 228, 184, 186 }, kind = "dpad" },
  { name = "x", x = 620, y = 126, r = 21, sprite = { 381, 57, 133, 134 } },
  -- the C-stick in its socket above X: cycles the top screen's shape
  { name = "cstick", x = 583.5, y = 93.5, r = 13, sprite = { 515, 256, 62, 62 } },
  { name = "y", x = 583, y = 164, r = 21, sprite = { 560, 58, 133, 133 } },
  { name = "a", x = 656, y = 164, r = 21, sprite = { 35, 58, 132, 133 } },
  { name = "b", x = 620, y = 201, r = 21, sprite = { 209, 58, 132, 133 } },
  { name = "start", x = 586, y = 271, r = 14, sprite = { 515, 256, 62, 62 } },
  { name = "select", x = 586, y = 316, r = 14, sprite = { 515, 340, 62, 63 } },
  { name = "home", x = 342, y = 365, r = 25, sprite = { 288, 427, 144, 86 }, wide = true },
}
-- game buttons (Input names) and launcher buttons (SDL gamepad names)
local GAME_BTN = { a = "a", b = "b", x = "r", y = "l", start = "start", select = "select",
                   up = "up", down = "down", left = "left", right = "right", l = "l", r = "r" }
local PAD_BTN = { a = "a", b = "b", x = "x", y = "y", start = "start", select = "back",
                  up = "dpup", down = "dpdown", left = "dpleft", right = "dpright",
                  l = "leftshoulder", r = "rightshoulder", zl = "triggerleft", zr = "triggerright" }
-- ZL / ZR in game: the controller triggers (game speed down / up)
local GAME_TRIGGER = { zl = "lefttrigger", zr = "righttrigger" }

-- The shoulder buttons: L over ZL at the middle of the left edge, R over ZR
-- at the middle of the right, straddling the hinge.  They fade away when
-- nothing touches that edge and come back at a touch; Settings can hide
-- them for good.
local SHOULDERS = {
  { name = "l", label = "L", side = -1, slot = 0 },
  { name = "zl", label = "ZL", side = -1, slot = 1 },
  { name = "r", label = "R", side = 1, slot = 0 },
  { name = "zr", label = "ZR", side = 1, slot = 1 },
}
local SHOULDER_SHOW, SHOULDER_FADE = 3.0, 0.6

local state = {
  mode = "off",          -- off | lid | ds
  kind = nil,            -- last HostDisplay kind: launcher | game | editor ...
  subject = nil,
  W = 0, H = 0,          -- real window
  L = nil,               -- layout
  vwin = nil,            -- the virtual window rect (x, y, w, h) in real pixels
  frameCanvas = nil,     -- while a subject draws: its canvas
  canvases = {},
  held = {},             -- touch id -> { name=, dirs= }
  vtouch = {},           -- touch id -> { x, y } inside the virtual window
  images = {},
  idle = { manifest = nil, sheets = {} },
  oriented = false,
  time = 0,
  screenMode = nil,      -- gbc | wide | full (the game's top screen shape)
  theme = "3ds",         -- the bottom-screen launcher's look: always the 3DS HOME menu
  shoulders = true,      -- L / ZL / R / ZR shown at the sides
  sounds = true,         -- the HOME menu's sound effects in the menus
  shoulderSeen = -10,    -- when an edge was last touched (they fade after)
  toast = nil,           -- { text, at } shown over the top screen
  arrowHeld = nil,       -- { dir, id, next } an on-screen scroll arrow held
  padScroll = nil,       -- { dir, next } the d-pad held up / down in the launcher
  split = nil,           -- this frame's in-game menu split { full, top, menus }
}

local MODES = { "gbc", "wide", "full" }
local MODE_NAMES = { gbc = "GAME BOY COLOR  -  10:9", wide = "WIDESCREEN", full = "FULL SCREEN" }
local SETTINGS_FILE = "fold3ds.cfg"
-- the community mod index (the catalog at gen1recomp.com/mod), and the copy
-- of its feed shipped in the APK so the list is there before any network
local MOD_INDEX = "bryanthaboi/gen1recomp-mod-index"
local MOD_INDEX_SNAPSHOT = "modindex/index.json"

---------------------------------------------------------------- helpers

local function image(file)
  if state.images[file] == nil then
    local ok, img = pcall(lg.newImage, DIR .. file)
    state.images[file] = ok and img or false
    if ok then img:setFilter("linear", "linear") end
  end
  return state.images[file] or nil
end

local function loadSettings()
  local ok, text = pcall(love.filesystem.read, SETTINGS_FILE)
  text = ok and type(text) == "string" and text or ""
  local mode = text:match("screen=(%a+)")
  state.screenMode = (mode == "gbc" or mode == "wide" or mode == "full") and mode or "gbc"
  -- the 3DS theme is the only one now (the Classic look is gone)
  state.theme = "3ds"
  state.shoulders = text:match("shoulders=(%d)") ~= "0"
  state.sounds = text:match("sounds=(%d)") ~= "0"
  state.volume = tonumber(text:match("volume=([%d%.]+)")) or 1
  state.volKeys = text:match("volkeys=(%d)") ~= "0"
  Cart3D.region = text:match("carts=(%a+)") == "jp" and "jp" or "intl"
  if love.audio then love.audio.setVolume(state.volume) end
  Sfx.enabled = state.sounds
end

local function saveSettings()
  pcall(love.filesystem.write, SETTINGS_FILE, "screen=" .. tostring(state.screenMode)
    .. "\ntheme=" .. tostring(state.theme) .. "\nshoulders=" .. (state.shoulders and "1" or "0")
    .. "\nsounds=" .. (state.sounds and "1" or "0")
    .. ("\nvolume=%.2f"):format(state.volume or 1) .. "\nvolkeys=" .. (state.volKeys and "1" or "0")
    .. "\ncarts=" .. Cart3D.region .. "\n")
end

-- physical pixels per LOVE unit (Android runs high-DPI: a unit is several pixels)
local function dpi()
  local w = real.getWidth()
  local pw = real.getPixelWidth and real.getPixelWidth() or w
  if not w or w <= 0 or not pw or pw <= 0 then return 1 end
  return pw / w
end

local function detectMode()
  local force = os.getenv and os.getenv("POKEPORT_FOLD")
  if force == "off" or force == "ds" or force == "lid" then return force end
  local os_ = love.system and love.system.getOS and love.system.getOS()
  if os_ ~= "Android" then return "off" end
  local W, H = real.getDimensions()
  if W <= 0 or H <= 0 then return "off" end
  -- the cover screen is phone-shaped, the inner screen nearly square
  local r = math.min(W, H) / math.max(W, H)
  if r < 0.62 then return "lid" end
  return "ds"
end

local function layout(W, H)
  local top, bottom = image(TOP.file), image(BOTTOM.file)
  if not top or not bottom then return nil end
  local topH = math.floor(H / 2)
  local botH = H - topH
  local L = {}
  local tw, th = top:getDimensions()
  local sc = math.min(W / tw, topH / th)
  L.top = { x = math.floor((W - tw * sc) / 2), y = topH - th * sc, sc = sc, img = top }
  L.topCut = { x = math.floor(L.top.x + TOP.cut[1] * sc), y = math.floor(L.top.y + TOP.cut[2] * sc),
               w = math.floor(TOP.cut[3] * sc), h = math.floor(TOP.cut[4] * sc) }
  local bw, bh = bottom:getDimensions()
  local sb = math.min(W / bw, botH / bh)
  L.bottom = { x = math.floor((W - bw * sb) / 2), y = topH, sc = sb, img = bottom }
  L.botCut = { x = math.floor(L.bottom.x + BOTTOM.cut[1] * sb), y = math.floor(L.bottom.y + BOTTOM.cut[2] * sb),
               w = math.floor(BOTTOM.cut[3] * sb), h = math.floor(BOTTOM.cut[4] * sb) }
  L.topFull = { x = math.floor(L.top.x + TOP.full[1] * sc), y = math.floor(L.top.y + TOP.full[2] * sc),
                w = math.floor(TOP.full[3] * sc), h = math.floor(TOP.full[4] * sc) }
  -- the Game Boy's own screen: 10:9 at the largest whole number of physical
  -- pixels per Game Boy pixel that fits the opening, centred in it
  do
    local d = dpi()
    local k = math.floor(math.min(L.topCut.w * d / 160, L.topCut.h * d / 144))
    local gw, gh
    if k >= 1 then
      gw, gh = math.floor(160 * k / d), math.floor(144 * k / d)
    else
      gh = L.topCut.h
      gw = math.floor(gh * 160 / 144)
    end
    L.topGbc = { x = L.topCut.x + math.floor((L.topCut.w - gw) / 2),
                 y = L.topCut.y + math.floor((L.topCut.h - gh) / 2), w = gw, h = gh }
  end
  -- the launcher's window is the bottom opening less a column on its right
  -- for the up / down scroll arrows
  do
    local c = L.botCut
    local aw = math.max(18, math.floor(c.w * 0.085))
    L.botView = { x = c.x, y = c.y, w = c.w - aw, h = c.h }
    L.arrows = { x = c.x + c.w - aw, y = c.y, w = aw, h = c.h }
    L.arrowUp = { x = L.arrows.x, y = c.y, w = aw, h = math.floor(c.h / 2) }
    L.arrowDown = { x = L.arrows.x, y = c.y + math.floor(c.h / 2), w = aw, h = c.h - math.floor(c.h / 2) }
  end
  L.s2 = sb * 2          -- half-size units -> pixels
  L.topH = topH
  L.W, L.H = W, H
  return L
end

-- where the game draws on the top screen, by the chosen shape
local function gameRect(L)
  if state.screenMode == "full" then return L.topFull end
  if state.screenMode == "wide" then return L.topCut end
  return L.topGbc
end

-- the 3DS theme's HOME menu is up (the grid, or a tile opened from it)
local function homeActive()
  return state.mode == "ds" and state.theme == "3ds" and state.kind ~= "game"
end

local skipBoot   -- the boot screen (defined with the drawing)

-- the Camera applet owns both screens while it is open (launcher only)
local function cameraOn()
  return state.mode == "ds" and state.kind ~= "game" and state.L ~= nil and Camera.isOpen()
end

-- the eShop owns both screens while it is open (launcher only)
local function esOn()
  return state.mode == "ds" and state.kind ~= "game" and state.L ~= nil and Eshop.isOpen()
end

-- the eShop's answers: "exit" closes it, "mods" goes on to the Mods applet
local function eshopDone(r)
  if r == "exit" then Eshop.close()
  elseif r == "mods" then Eshop.close(); Home.openApplet(state.subject, "mods") end
end

-- Download Play owns both screens while it is open (launcher only)
local function dlOn()
  return state.mode == "ds" and state.kind ~= "game" and state.L ~= nil and Dlplay.isOpen()
end

---------------------------------------------------------------- volume slider
-- The shell's VOL slider (left edge of the top half): drag it, or press the
-- phone's volume keys (they move it instead of Android's volume, with no
-- popup, while Settings > 3DS Shell > Volume keys is on).  It sets the
-- app's own volume; full up is the top, OFF the bottom.
local VOL = { x = 4, top = 479, bottom = 564, knob = { 24, 49 } }   -- top_gbc.png pixels (the VOL slot)

local function bridge(cmd, arg)
  local f = love.system and love.system.foldCamera
  if not f then return nil end
  local ok, out = pcall(f, "call", cmd, arg or "")
  return ok and out or nil
end

local function setVolume(v, quiet)
  v = math.max(0, math.min(1, v))
  if math.abs(v - (state.volume or 1)) < 0.001 then return end
  state.volume = v
  if love.audio then love.audio.setVolume(v) end
  state.volSaveAt = state.time + 1
end

local function volumeKnob(L)
  local sc = L.top.sc
  local y = VOL.bottom - (VOL.bottom - VOL.top) * (state.volume or 1)
  return { x = L.top.x + VOL.x * sc, y = L.top.y + y * sc, w = VOL.knob[1] * sc, h = VOL.knob[2] * sc }
end

local function volumeZone(L, x, y)
  local sc = L.top.sc
  local zx, zy = L.top.x + (VOL.x - 14) * sc, L.top.y + (VOL.top - 20) * sc
  return x >= zx and x <= zx + (VOL.knob[1] + 34) * sc
     and y >= zy and y <= zy + (VOL.bottom - VOL.top + VOL.knob[2] + 40) * sc
end

local function volumeFromY(L, y)
  local sc = L.top.sc
  local top = L.top.y + (VOL.top + VOL.knob[2] / 2) * sc
  local bottom = L.top.y + (VOL.bottom + VOL.knob[2] / 2) * sc
  setVolume(1 - (y - top) / (bottom - top))
end

local function drawVolume(L)
  local key = "skin:vol_knob"
  if state.images[key] == nil then
    local ok, img = pcall(lg.newImage, DIR .. "skin/vol_knob.png")
    state.images[key] = ok and img or false
  end
  local img = state.images[key]
  if not img then return end
  local k = volumeKnob(L)
  lg.setColor(1, 1, 1, 1)
  lg.draw(img, k.x, k.y, 0, L.top.sc, L.top.sc)
end

local function virtualRect()
  local L = state.L
  if not L then return nil end
  if state.kind == "game" then return gameRect(L) end
  if homeActive() and Home.opened() then
    -- an opened tile: the launcher's page under the HOME menu's back bar
    local bh = Home.barHeight(L.botCut)
    return { x = L.botView.x, y = L.botView.y + bh, w = L.botView.w, h = L.botView.h - bh }
  end
  return L.botView
end

local function vactive()
  return state.mode == "ds" and state.vwin ~= nil
end

local function inside(r, x, y)
  return x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h
end

---------------------------------------------------------------- buttons

-- the shell button under a point (bottom half, outside the screen)
-- where each shoulder button sits: the margin beside the shells (or over
-- their edge on a narrow screen), centred on the hinge
local function shoulderRect(L, sb)
  local margin = math.max(L.bottom.x, L.top.x)
  local w = math.max(math.min(margin * 0.8, L.W * 0.1), L.W * 0.06)
  local h = math.min(L.H * 0.11, w * 1.1)
  local gap = h * 0.25
  local x = sb.side < 0 and math.max(4, (margin - w) / 2) or L.W - math.max(4, (margin - w) / 2) - w
  local y = L.topH - h - gap / 2 + sb.slot * (h + gap)
  return { x = x, y = y, w = w, h = h }
end

-- the edge strips that wake the shoulder buttons
local function shoulderZone(L, x, y)
  local margin = math.max(L.bottom.x, L.top.x, L.W * 0.06)
  return (x < margin or x > L.W - margin) and math.abs(y - L.topH) < L.H * 0.25
end

local function buttonAt(x, y)
  local L = state.L
  if M.debug then print("fold3ds buttonAt L=" .. tostring(L) .. " topH=" .. tostring(L and L.topH)) end
  if L and state.shoulders then
    for _, sb in ipairs(SHOULDERS) do
      local r = shoulderRect(L, sb)
      if x >= r.x - 6 and x <= r.x + r.w + 6 and y >= r.y - 4 and y <= r.y + r.h + 4 then
        state.shoulderSeen = state.time
        return sb
      end
    end
  end
  if not L or y < L.topH then return nil end
  for _, b in ipairs(BUTTONS) do
    if M.debug then print("fold3ds  check " .. b.name) end
    local cx, cy, r = L.bottom.x + b.x * L.s2, L.bottom.y + b.y * L.s2, b.r * L.s2
    local dx, dy = x - cx, y - cy
    if b.kind == "dpad" then
      if math.abs(dx) <= r * 1.3 and math.abs(dy) <= r * 1.3 then return b end
    elseif b.wide then
      if math.abs(dx) <= r * 2 and math.abs(dy) <= r * 1.2 then return b end
    elseif dx * dx + dy * dy <= (r * 1.25) * (r * 1.25) then
      return b
    end
  end
  return nil
end

-- directions a d-pad / stick touch holds
local function dirsAt(b, x, y)
  local L = state.L
  local cx, cy, r = L.bottom.x + b.x * L.s2, L.bottom.y + b.y * L.s2, b.r * L.s2
  local dx, dy = x - cx, y - cy
  local ax, ay = math.abs(dx), math.abs(dy)
  local d = {}
  if ax > r * 0.2 or ay > r * 0.2 then
    if ax >= ay * 0.45 then d[dx < 0 and "left" or "right"] = true end
    if ay >= ax * 0.45 then d[dy < 0 and "up" or "down"] = true end
  end
  return d
end

local function gameInput()
  local ok, Input = pcall(require, "src.core.Input")
  return ok and Input or nil
end

---------------------------------------------------------------- launcher scroll
-- What an up / down arrow (or the d-pad) scrolls: the open Settings page, else
-- the open popup's list, else the tab's panel, else the whole page.
local function scrollTarget()
  local imp = state.subject
  if not imp or state.kind == "game" then return nil end
  local s = imp._settings
  if s and imp._modalKey == "_settings" and not s.confirm then
    return { get = function() return s.scroll or 0 end, max = s.maxScroll or 0,
             set = function(v) s.scroll = v end }
  end
  if imp._modalKey then
    local ms = imp._modalScroll and imp._modalScroll[imp._modalKey]
    if ms and (ms.maxScroll or 0) > 0 then
      return { get = function() return ms.scroll or 0 end, max = ms.maxScroll,
               set = function(v) ms.scroll = v end }
    end
    return nil
  end
  local tab = imp.tab or "red"
  local tmax = imp._tabScrollMax and imp._tabScrollMax[tab] or 0
  local pmax = imp._pageScrollMax or 0
  if tmax <= 0 and pmax <= 0 then return nil end
  -- the page (header) scroll first on the way down, last on the way up
  return {
    get = function() return (imp._pageScroll or 0) + ((imp._tabScroll and imp._tabScroll[tab]) or 0) end,
    max = tmax + pmax,
    set = function(v)
      local page = math.min(pmax, v)
      imp._pageScroll = page
      imp._tabScroll = imp._tabScroll or {}
      imp._tabScroll[tab] = math.max(0, math.min(tmax, v - page))
    end,
  }
end

local function canScroll(dir)
  local t = scrollTarget()
  if not t or t.max <= 0 then return false end
  local at = t.get()
  if dir < 0 then return at > 0.5 end
  return at < t.max - 0.5
end

local function scrollBy(dir, mult)
  local t = scrollTarget()
  if not t or t.max <= 0 then return false end
  local step = math.max(24, math.floor((state.vwin and state.vwin.h or 300) * 0.3)) * (mult or 1)
  t.set(math.max(0, math.min(t.max, t.get() + dir * step)))
  return true
end

-- the launcher's own text fields / file browser keep the d-pad
local function launcherOwnsPad()
  local ok, Kit = pcall(require, "src.ui.kit.Kit")
  if not ok then return false end
  return (Kit.FileBrowser and Kit.FileBrowser.active)
    or (Kit.VirtualKeyboard and Kit.VirtualKeyboard.active) or false
end

local REPEAT_FIRST, REPEAT_NEXT = 0.35, 0.09

local function toast(text)
  state.toast = { text = text, at = state.time }
end

local function cycleScreen()
  local idx = 1
  for i, m in ipairs(MODES) do if m == state.screenMode then idx = i end end
  state.screenMode = MODES[idx % #MODES + 1]
  Sfx.play("screen", true)
  saveSettings()
  toast(MODE_NAMES[state.screenMode])
end

---------------------------------------------------------------- in-game menus
-- The states that draw on the bottom screen: START's menu and the mod
-- manager, and everything opened on top of them.
local MENU_BASE = { StartMenu = true, Gen2StartMenu = true, ManagerState = true }

local function menuBase(game)
  local st = game and game.stack and game.stack.states
  if type(st) ~= "table" then return nil end
  for i = 1, #st do
    local s = st[i]
    if type(s) == "table" and MENU_BASE[s.screenId] then return i end
  end
  return nil
end

-- SELECT in the overworld opens the mod manager (and closes it again)
local function selectOpensMods(game)
  if not game or not game.stack then return false end
  local top = game.stack.top and game.stack:top()
  local ok, Screens = pcall(require, "src.ui.Screens")
  if not ok then return false end
  if top and top.screenId == "ManagerState" then
    game.stack:pop()
    return true
  end
  local overworld = (top ~= nil and top == game.overworld)
    or (top == nil and game.world ~= nil and game.phase == "play")
  if not overworld then return false end
  pcall(Screens.push, game, "ManagerState")
  return true
end

local function press(btn, src)
  if skipBoot() then return end
  if Sticker.editing() and state.kind ~= "game" then Sticker.button(btn) return end
  if cameraOn() then
    if Camera.button(btn) == "exit" then Camera.close() end
    return
  end
  if dlOn() then
    if Dlplay.button(btn) == "exit" then Dlplay.close() end
    return
  end
  if esOn() then eshopDone(Eshop.button(btn)) return end
  if btn == "cstick" then cycleScreen() return end
  if state.kind == "game" then
    if btn == "select" and selectOpensMods(state.subject) then return end
    if GAME_TRIGGER[btn] then
      local g = state.subject
      if g and g.gamepadpressed then pcall(g.gamepadpressed, g, nil, GAME_TRIGGER[btn]) end
      return
    end
    if btn == "home" then
      -- HOME: back to the launcher (the engine turns quit into a return)
      Sfx.play("home", true)
      love.event.quit()
      return
    end
    local Input = gameInput()
    if Input and Input.overlayPressed and GAME_BTN[btn] then Input:overlayPressed(GAME_BTN[btn]) end
  else
    local s = state.subject
    if homeActive() then
      -- the HOME menu: HOME returns to it; on the grid the pads move and A opens
      if btn == "home" then Sfx.play("homeMenu"); Home.goHome(s, true) return end
      if Home.showing() then
        -- L or R: the Camera, as on the 3DS HOME menu
        if (btn == "l" or btn == "r") and Theme3DS.active then Camera.open() return end
        Home.button(s, btn)
        return
      end
      if btn == "b" and s and not s._modalKey and not launcherOwnsPad() then
        Sfx.play("cancel")
        Home.goHome(s, true)
        return
      end
    end
    if btn == "home" then Sfx.play("homeMenu") return end
    -- the d-pad's up / down scroll the bottom screen; the circle pad and the
    -- d-pad's left / right move the launcher's focus
    if src == "pad" and (btn == "up" or btn == "down") and not launcherOwnsPad() then
      local dir = btn == "up" and -1 or 1
      if scrollBy(dir) then
        Sfx.play("scroll")
        state.padScroll = { dir = dir, next = state.time + REPEAT_FIRST }
        return
      end
    end
    if s and s.gamepadpressed and PAD_BTN[btn] then pcall(s.gamepadpressed, s, nil, PAD_BTN[btn]) end
  end
end

local function release(btn, src)
  if btn == "cstick" then return end
  if Sticker.editing() and state.kind ~= "game" then return end
  if cameraOn() or dlOn() or esOn() then return end
  if src == "pad" and (btn == "up" or btn == "down") then state.padScroll = nil end
  if state.kind == "game" and GAME_TRIGGER[btn] then
    local g = state.subject
    if g and g.gamepadreleased then pcall(g.gamepadreleased, g, nil, GAME_TRIGGER[btn]) end
    return
  end
  if state.kind == "game" then
    local Input = gameInput()
    if Input and Input.overlayReleased and GAME_BTN[btn] then Input:overlayReleased(GAME_BTN[btn]) end
  else
    local s = state.subject
    if s and s.gamepadreleased and PAD_BTN[btn] then pcall(s.gamepadreleased, s, nil, PAD_BTN[btn]) end
  end
end

local function holdStart(id, b, x, y)
  local h = { name = b.name, kind = b.kind, dirs = {} }
  state.held[id] = h
  if b.kind == "dpad" then
    h.dirs = dirsAt(b, x, y)
    for d in pairs(h.dirs) do press(d, b.name) end
  else
    press(b.name)
  end
end

local function holdMove(id, x, y)
  local h = state.held[id]
  if not h or h.kind ~= "dpad" then return end
  local b
  for _, bb in ipairs(BUTTONS) do if bb.name == h.name then b = bb end end
  local nd = dirsAt(b, x, y)
  for d in pairs(h.dirs) do if not nd[d] then release(d, h.name) end end
  for d in pairs(nd) do if not h.dirs[d] then press(d, h.name) end end
  h.dirs = nd
end

local function holdEnd(id)
  local h = state.held[id]
  if not h then return end
  state.held[id] = nil
  if h.kind == "dpad" then
    for d in pairs(h.dirs) do release(d, h.name) end
  else
    release(h.name)
  end
end

local function releaseAll()
  for id in pairs(state.held) do holdEnd(id) end
  state.vtouch = {}
  state.arrowHeld, state.padScroll = nil, nil
end

-- The bottom screen's right-hand column: in the Classic theme, sync /
-- settings / quit at its top (the launcher's tab row gives them up so all
-- its tabs fit), then the up / down scroll arrows in what is left.
local COLUMN_BUTTONS = {
  { id = "sync", icon = "arrow-left-right" },
  { id = "gear", icon = "settings" },
  { id = "quit", icon = "x" },
}
local function clusterInColumn()
  return state.mode == "ds" and state.theme ~= "3ds" and state.kind ~= "game"
end

local function columnRects(L)
  local a = L.arrows
  local top = a.y
  local buttons = {}
  if clusterInColumn() then
    local s = a.w
    for i, b in ipairs(COLUMN_BUTTONS) do
      buttons[i] = { id = b.id, icon = b.icon, x = a.x, y = a.y + (i - 1) * s, w = a.w, h = s }
    end
    top = a.y + #COLUMN_BUTTONS * s + math.floor(s * 0.2)
  end
  local h = a.y + a.h - top
  local up = { x = a.x, y = top, w = a.w, h = math.floor(h / 2) }
  local down = { x = a.x, y = top + math.floor(h / 2), w = a.w, h = h - math.floor(h / 2) }
  return up, down, buttons
end

local function columnButtonAt(x, y)
  local L = state.L
  if not L or state.kind == "game" or not clusterInColumn() then return nil end
  local _, _, buttons = columnRects(L)
  for _, b in ipairs(buttons) do
    if inside(b, x, y) then return b end
  end
end

local function pressColumnButton(b)
  local imp = state.subject
  if not imp then return end
  Sfx.play("button")
  if b.id == "sync" and imp._openSync then imp:_openSync()
  elseif b.id == "gear" and imp._openSettings then imp:_openSettings()
  elseif b.id == "quit" and imp._quitApp then imp:_quitApp() end
end

-- the on-screen scroll arrows at the bottom screen's right edge
local function arrowAt(x, y)
  local L = state.L
  if not L or state.kind == "game" then return nil end
  local up, down = columnRects(L)
  if inside(up, x, y) then return -1 end
  if inside(down, x, y) then return 1 end
  return nil
end

local function arrowStart(id, dir)
  Sfx.play(canScroll(dir) and "scroll" or "noMove")
  scrollBy(dir)
  state.arrowHeld = { dir = dir, id = id, next = state.time + REPEAT_FIRST }
end

local function arrowEnd(id)
  if state.arrowHeld and state.arrowHeld.id == id then state.arrowHeld = nil end
end

local function buttonLit(b)
  for _, h in pairs(state.held) do
    if h.name == b.name then return true, h.dirs end
  end
  return false, nil
end

---------------------------------------------------------------- events

local topScreenTap   -- defined with the drawing (the launcher's top screen)
-- the cover sticker editor owns both screens while it is open (launcher only)
local function editingSticker()
  return state.mode == "ds" and state.kind ~= "game" and state.L ~= nil and Sticker.editing()
end

-- a touch on the 3DS HOME menu (the grid, or an opened tile's back bar)
local function homeTouch(id, x, y)
  if not homeActive() or not state.L then return false end
  if Home.showing() then
    if inside(state.L.botCut, x, y) then return Home.pressed(state.subject, id, x, y) end
    return false
  end
  return Home.tapBar(state.subject, x, y)
end
local function toVirtual(x, y)
  local r = state.vwin
  if not r then return x, y, false end
  return x - r.x, y - r.y, inside(r, x, y)
end

local function onTouchPressed(id, x, y, dx, dy, pr)
  if M.debug then print("fold3ds touchpressed enter mode=" .. tostring(state.mode)) end
  if state.mode ~= "ds" then
    if state.mode == "lid" then Sticker.coverPressed(id, x, y) return end
    return orig.touchpressed and orig.touchpressed(id, x, y, dx, dy, pr)
  end
  if state.L and shoulderZone(state.L, x, y) then state.shoulderSeen = state.time end
  if skipBoot() then return end
  if state.L and volumeZone(state.L, x, y) then state.volDrag = id; volumeFromY(state.L, y) return end
  local b = buttonAt(x, y)
  if M.debug then print("fold3ds buttonAt -> " .. tostring(b and b.name)) end
  if b then holdStart(id, b, x, y) return end
  if editingSticker() then Sticker.pressed(id, x, y, state.L.botCut, state.L.topCut) return end
  if cameraOn() then Camera.pressed(id, x, y) return end
  if dlOn() then Dlplay.pressed(id, x, y) return end
  if esOn() then Eshop.pressed(id, x, y) return end
  if homeTouch(id, x, y) then return end
  local cb = columnButtonAt(x, y)
  if cb then state.columnDown = cb.id; pressColumnButton(cb) return end
  local dir = arrowAt(x, y)
  if dir then arrowStart(id, dir) return end
  if topScreenTap(x, y) then return end
  local lx, ly, ok = toVirtual(x, y)
  if M.debug then print(("fold3ds touch %d,%d -> %s %.0f,%.0f kind=%s"):format(x, y, tostring(ok), lx, ly, tostring(state.kind))) end
  if ok then
    state.vtouch[id] = { lx, ly }
    if orig.touchpressed then
      local okc, err = pcall(orig.touchpressed, id, lx, ly, dx, dy, pr)
      if M.debug then print("fold3ds forwarded ok=" .. tostring(okc)) end
      if not okc then print("fold3ds: touchpressed error: " .. tostring(err)) end
    end
  end
end

local function onTouchMoved(id, x, y, dx, dy, pr)
  if state.mode ~= "ds" then
    if state.mode == "lid" then Sticker.coverMoved(id, x, y) return end
    return orig.touchmoved and orig.touchmoved(id, x, y, dx, dy, pr)
  end
  if state.volDrag == id then volumeFromY(state.L, y) return end
  if state.held[id] then holdMove(id, x, y) return end
  if editingSticker() then Sticker.moved(id, x, y) return end
  if cameraOn() then Camera.moved(id, x, y) return end
  if dlOn() then Dlplay.moved(id, x, y) return end
  if esOn() then Eshop.moved(id, x, y) return end
  if Home.moved(state.subject, id, x, y) then return end
  if state.vtouch[id] then
    local lx, ly = toVirtual(x, y)
    state.vtouch[id] = { lx, ly }
    if orig.touchmoved then return orig.touchmoved(id, lx, ly, dx, dy, pr) end
  end
end

local function onTouchReleased(id, x, y, dx, dy, pr)
  if state.mode ~= "ds" then
    if state.mode == "lid" then Sticker.coverReleased(id, x, y) return end
    return orig.touchreleased and orig.touchreleased(id, x, y, dx, dy, pr)
  end
  if state.volDrag == id then state.volDrag = nil return end
  if state.held[id] then holdEnd(id) return end
  if editingSticker() then Sticker.released(id) return end
  if cameraOn() then if Camera.released(id, x, y) == "exit" then Camera.close() end return end
  if dlOn() then if Dlplay.released(id, x, y) == "exit" then Dlplay.close() end return end
  if esOn() then eshopDone(Eshop.released(id, x, y)) return end
  if Home.released(state.subject, id, x, y) then return end
  if state.arrowHeld and state.arrowHeld.id == id then arrowEnd(id) return end
  if state.vtouch[id] then
    state.vtouch[id] = nil
    local lx, ly = toVirtual(x, y)
    if orig.touchreleased then return orig.touchreleased(id, lx, ly, dx, dy, pr) end
  end
end

-- a real mouse (desktop testing) is a finger too; Android's synthesized
-- mouse twin of a touch just gets the same coordinate change
local function onMousePressed(x, y, button, istouch, presses)
  if state.mode ~= "ds" then
    if state.mode == "lid" then if not istouch then Sticker.coverPressed("mouse", x, y) end return end
    return orig.mousepressed and orig.mousepressed(x, y, button, istouch, presses)
  end
  if not istouch and button == 1 and skipBoot() then return end
  if not istouch and button == 1 and state.L and volumeZone(state.L, x, y) then
    state.volDrag = "mouse"; volumeFromY(state.L, y) return
  end
  if not istouch and button == 1 then
    local b = buttonAt(x, y)
    if b then holdStart("mouse", b, x, y) return end
    if editingSticker() then Sticker.pressed("mouse", x, y, state.L.botCut, state.L.topCut) return end
    if cameraOn() then Camera.pressed("mouse", x, y) return end
    if dlOn() then Dlplay.pressed("mouse", x, y) return end
    if esOn() then Eshop.pressed("mouse", x, y) return end
    if homeTouch("mouse", x, y) then return end
    local cb = columnButtonAt(x, y)
    if cb then state.columnDown = cb.id; pressColumnButton(cb) return end
    local dir = arrowAt(x, y)
    if dir then arrowStart("mouse", dir) return end
    if topScreenTap(x, y) then return end
  end
  local lx, ly, ok = toVirtual(x, y)
  if ok and orig.mousepressed then return orig.mousepressed(lx, ly, button, istouch, presses) end
end

local function onMouseMoved(x, y, dx, dy, istouch)
  if state.mode ~= "ds" then
    if state.mode == "lid" then if not istouch then Sticker.coverMoved("mouse", x, y) end return end
    return orig.mousemoved and orig.mousemoved(x, y, dx, dy, istouch)
  end
  if state.volDrag == "mouse" then volumeFromY(state.L, y) return end
  if state.held.mouse then holdMove("mouse", x, y) return end
  if editingSticker() then if not istouch then Sticker.moved("mouse", x, y) end return end
  if cameraOn() then if not istouch then Camera.moved("mouse", x, y) end return end
  if dlOn() then if not istouch then Dlplay.moved("mouse", x, y) end return end
  if esOn() then if not istouch then Eshop.moved("mouse", x, y) end return end
  if not istouch and Home.moved(state.subject, "mouse", x, y) then return end
  local lx, ly = toVirtual(x, y)
  if orig.mousemoved then return orig.mousemoved(lx, ly, dx, dy, istouch) end
end

local function onMouseReleased(x, y, button, istouch, presses)
  if state.mode ~= "ds" then
    if state.mode == "lid" then if not istouch then Sticker.coverReleased("mouse", x, y) end return end
    return orig.mousereleased and orig.mousereleased(x, y, button, istouch, presses)
  end
  if state.volDrag == "mouse" and not istouch then state.volDrag = nil return end
  if state.held.mouse and not istouch then holdEnd("mouse") return end
  if editingSticker() then if not istouch then Sticker.released("mouse") end return end
  if cameraOn() then
    if not istouch and Camera.released("mouse", x, y) == "exit" then Camera.close() end
    return
  end
  if dlOn() then
    if not istouch and Dlplay.released("mouse", x, y) == "exit" then Dlplay.close() end
    return
  end
  if esOn() then
    if not istouch then eshopDone(Eshop.released("mouse", x, y)) end
    return
  end
  if not istouch and Home.released(state.subject, "mouse", x, y) then return end
  if not istouch and state.arrowHeld and state.arrowHeld.id == "mouse" then arrowEnd("mouse") return end
  local lx, ly = toVirtual(x, y)
  if orig.mousereleased then return orig.mousereleased(lx, ly, button, istouch, presses) end
end

---------------------------------------------------------------- drawing

local function idleAnim(version)
  local idle = state.idle
  if idle.manifest == nil then
    local ok, m = pcall(function() return love.filesystem.load(DIR .. "idle/manifest.lua")() end)
    idle.manifest = ok and type(m) == "table" and m or false
  end
  local entry = idle.manifest and idle.manifest[version]
  if not entry then return nil end
  if idle.sheets[version] == nil then
    local ok, img = pcall(lg.newImage, DIR .. "idle/" .. entry.file)
    if ok then
      img:setFilter("nearest", "nearest")
      local w, h = img:getDimensions()
      local fw = math.floor(w / entry.frames)
      local quads = {}
      for i = 0, entry.frames - 1 do quads[i + 1] = lg.newQuad(i * fw, 0, fw, h, w, h) end
      idle.sheets[version] = { img = img, quads = quads, fw = fw, fh = h, fps = entry.fps or 5, frames = entry.frames }
    else
      idle.sheets[version] = false
    end
  end
  return idle.sheets[version] or nil
end

local function currentVersion()
  local ok, GV = pcall(require, "src.core.GameVersion")
  return ok and GV.get and GV.get() or "red"
end

-- the bottom screen while playing: the game's Pokemon; Yellow's Pikachu surfs
local function drawIdle(r)
  local t = state.time
  local version = currentVersion()
  lg.setColor(0.04, 0.06, 0.16, 1)
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  local anim = idleAnim(version)
  local surf = version == "yellow"
  if surf then
    for band = 0, 2 do
      local by = r.y + r.h * (0.62 + band * 0.12)
      lg.setColor(0.16 + band * 0.06, 0.40 + band * 0.08, 0.85 - band * 0.10, 1)
      lg.rectangle("fill", r.x, by, r.w, r.h - (by - r.y))
      lg.setColor(0.85, 0.93, 1, 0.9)
      local step = r.w / 18
      for wx = r.x - step, r.x + r.w, step do
        local px = wx + (t * (30 + band * 12) * (r.w / 480)) % step
        local py = by + math.sin((px + t * 40) / 9) * 2
        if px >= r.x and px + step / 2 <= r.x + r.w then lg.rectangle("fill", px, py - 1, step / 2, r.h / 90) end
      end
    end
  end
  if not anim then return end
  local scale = math.max(1, math.floor((r.h * 0.55) / anim.fh))
  local frame = math.floor(t * anim.fps) % anim.frames + 1
  local dx = r.x + (r.w - anim.fw * scale) / 2
  local dy = r.y + (r.h - anim.fh * scale) / 2
  if surf then dy = r.y + r.h * 0.62 - anim.fh * scale + r.h * 0.08 + math.sin(t * 2.5) * r.h * 0.015 end
  lg.setColor(1, 1, 1, 1)
  lg.draw(anim.img, anim.quads[frame], math.floor(dx), math.floor(dy), 0, scale, scale)
end

-- the launcher's selected game (the GAMES tab's version, else the last panel)
local function launcherVersion()
  local imp = state.subject
  local ok, GV = pcall(require, "src.core.GameVersion")
  local v = imp and (imp.panelVersion or imp.tab)
  if ok and GV.VERSIONS and v and GV.VERSIONS[v] then return v end
  return "red"
end

local function cartImage(version)
  local key = "cart:" .. version
  if state.images[key] == nil then
    local ok, img = pcall(lg.newImage, DIR .. "carts/" .. version .. ".png")
    state.images[key] = ok and img or false
    if ok then img:setFilter("linear", "linear") end
  end
  return state.images[key] or nil
end

local fonts = {}
local function font(px)
  px = math.max(8, math.floor(px))
  if not fonts[px] then fonts[px] = lg.newFont(px) end
  return fonts[px]
end

-- the top screen behind the launcher: the selected game's cartridge, the
-- arrows that change it, the project credit
local function drawTopIdle(r)
  lg.setColor(0.02, 0.02, 0.03, 1)
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  local version = launcherVersion()
  local img = cartImage(version)
  if img then
    local iw, ih = img:getDimensions()
    local s = math.max(r.w / iw, r.h / ih)
    lg.setColor(1, 1, 1, 1)
    lg.setScissor(r.x, r.y, r.w, r.h)
    lg.draw(img, r.x + (r.w - iw * s) / 2, r.y + (r.h - ih * s) / 2, 0, s, s)
    lg.setScissor()
  end
  local f = font(r.h * 0.12)
  lg.setFont(f)
  lg.setColor(1, 1, 1, 0.85)
  lg.print("<", r.x + r.w * 0.03, r.y + r.h / 2 - f:getHeight() / 2)
  lg.print(">", r.x + r.w * 0.97 - f:getWidth(">"), r.y + r.h / 2 - f:getHeight() / 2)
  local ok, GV = pcall(require, "src.core.GameVersion")
  local info = ok and GV.info and GV.info(version)
  local imp = state.subject
  local ready = imp and imp.ready and imp.ready[version]
  local cf = font(r.h * 0.05)
  lg.setFont(cf)
  lg.setColor(0, 0, 0, 0.55)
  lg.rectangle("fill", r.x, r.y + r.h - cf:getHeight() * 3.4, r.w, cf:getHeight() * 3.4)
  lg.setColor(0.85, 0.85, 0.9, 1)
  lg.printf((info and info.displayName or version) .. (ready and "  -  tap the cart to play" or "  -  import the ROM below"),
    r.x, r.y + r.h - cf:getHeight() * 3.2, r.w, "center")
  lg.printf("Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC\ngithub.com/bryanthaboi/gen1recomp",
    r.x, r.y + r.h - cf:getHeight() * 2.1, r.w, "center")
end

-- The 3DS theme's top screen, as the 3DS draws its own: the status bar
-- (signal, Internet, the play coins, date and time, battery), the tiled
-- wallpaper with the selected game's cartridge floating over it (a 3D
-- Game Boy Color / Advance cart, fold3ds.cart3d), and the game's name.
local function col3(c, a) lg.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1) end

local function topPanel(r)
  local sh = math.floor(r.h * 0.13)
  local pad = math.floor(r.w * 0.02)
  local nh = math.floor(r.h * 0.12)
  return { x = r.x + pad, y = r.y + sh + pad, w = r.w - 2 * pad, h = r.h - sh - nh - 2 * pad }, sh, nh, pad
end

-- the top screen's picture of a selected tile that is not a recomp game:
-- a 3DS game card with the game's icon as its label, or the icon itself on
-- a white tile, floating over its shadow
local function drawTopTile(P, t)
  local time = state.time
  local bob = math.sin(time * 1.7) * P.h * 0.025
  local cx, cy = P.x + P.w / 2, P.y + P.h * 0.47
  local img = t.ctr and Azahar.icon(t) or image("icons3ds/" .. t.id .. ".png")
  -- the shadow
  lg.setColor(0.2, 0.24, 0.3, 0.16 - bob / P.h)
  lg.ellipse("fill", cx, P.y + P.h * 0.9, P.h * 0.26, P.h * 0.05)
  local photo = t.ctr and Azahar.cart(t)
  if photo then
    -- the game card itself (GameTDB's photo), floating, with a slow sway
    local iw, ih = photo:getDimensions()
    local k = math.min(P.h * 0.9 / ih, P.w * 0.6 / iw)
    local sway = math.sin(time * 0.9) * 0.05
    lg.setColor(1, 1, 1, 1)
    lg.draw(photo, cx, cy + bob, sway, k, k, iw / 2, ih / 2)
    return
  end
  if t.ctr then
    -- a 3DS game card: grey, the ridge on top, the label below it
    local w, h = P.h * 0.6, P.h * 0.68
    local x, y = cx - w / 2, cy - h / 2 + bob
    col3({ 150, 152, 158 })
    lg.rectangle("fill", x + w * 0.012, y + h * 0.02, w, h, w * 0.06, w * 0.06)
    col3({ 214, 216, 220 })
    lg.rectangle("fill", x, y, w, h, w * 0.06, w * 0.06)
    col3({ 192, 194, 199 })
    lg.rectangle("fill", x, y, w, h * 0.13, w * 0.06, w * 0.06)
    lg.rectangle("fill", x + w * 0.1, y + h * 0.13, w * 0.8, h * 0.02)
    local lx, ly, ls = x + w * 0.1, y + h * 0.2, w * 0.8
    col3({ 255, 255, 255 })
    lg.rectangle("fill", lx, ly, ls, ls * 0.95, w * 0.03, w * 0.03)
    if img then
      local iw, ih = img:getDimensions()
      local k = math.min(ls * 0.86 / iw, ls * 0.8 / ih)
      lg.setColor(1, 1, 1, 1)
      lg.draw(img, lx + (ls - iw * k) / 2, ly + (ls * 0.95 - ih * k) / 2, 0, k, k)
    else
      -- no icon: the title's first letter
      local f = font(ls * 0.5)
      lg.setFont(f)
      col3({ 206, 32, 40 })
      lg.printf(Azahar.initial(t.name), lx, ly + (ls * 0.95 - f:getHeight()) / 2, ls, "center")
    end
    return
  end
  local s = P.h * 0.5
  local x, y = cx - s / 2, cy - s / 2 + bob
  lg.setColor(0.24, 0.28, 0.36, 0.18)
  lg.rectangle("fill", x + s * 0.02, y + s * 0.05, s, s, s * 0.2, s * 0.2)
  lg.setColor(1, 1, 1, 1)
  lg.rectangle("fill", x, y, s, s, s * 0.2, s * 0.2)
  if img then
    local iw, ih = img:getDimensions()
    local inset = s * 0.12
    lg.draw(img, x + inset, y + inset, 0, (s - 2 * inset) / iw, (s - 2 * inset) / ih)
  end
end

-- the L and R camera buttons in the top screen's lower corners (L or R
-- opens the Camera, as on the 3DS HOME menu)
local function drawLR(r, h, pad)
  state.lrRects = {}
  for k, name in ipairs({ "btn_l_camera", "btn_r_camera" }) do
    local key = "skin:" .. name
    if state.images[key] == nil then
      local ok, img = pcall(lg.newImage, DIR .. "skin/" .. name .. ".png")
      state.images[key] = ok and img or false
      if ok then img:setFilter("linear", "linear") end
    end
    local img = state.images[key]
    if img then
      local iw, ih = img:getDimensions()
      local s = h / ih
      local x = k == 1 and r.x + pad or r.x + r.w - pad - iw * s
      local y = r.y + r.h - h - pad * 0.4
      lg.setColor(1, 1, 1, 1)
      lg.draw(img, x, y, 0, s, s)
      state.lrRects[k] = { x = x, y = y, w = iw * s, h = h }
    end
  end
end

-- A HOME bar app's banner, as the 3DS shows it when the app is picked: its
-- icon turning in 3D (a slab, its edge a darker shade) above the app's
-- own title, English or Japanese with SKINS > CARTRIDGE ARTWORK
-- (fold3ds/icons3ds/<id>.png, fold3ds/banners/<id>_en|jp.png).
local function appletBanner(r, id, t)
  local function image(key, path)
    if state.images[key] == nil then
      local ok, im = pcall(lg.newImage, path)
      state.images[key] = ok and im or false
      if ok then im:setFilter("linear", "linear") end
    end
    return state.images[key] or nil
  end
  local icon = image("icon:" .. id, DIR .. "icons3ds/" .. id .. ".png")
  local jp = Cart3D.region == "jp"
  local title = image("banner:" .. id .. (jp and "_jp" or "_en"), DIR .. "banners/" .. id .. (jp and "_jp" or "_en") .. ".png")
  local th = r.h * 0.3
  if icon then
    local iw, ih = icon:getDimensions()
    local s = (r.h - th) * 0.82 / ih
    local cx, cy = r.x + r.w / 2, r.y + (r.h - th) * 0.5
    local cycle = (t % 5) / 5
    local turn = cycle < 0.35 and 0 or (cycle - 0.35) / 0.65
    turn = turn * turn * (3 - 2 * turn)
    local a = turn * math.pi * 2 + 0.2 * math.sin(t * 1.2)
    local ca, sa = math.cos(a), math.sin(a)
    local bob = math.sin(t * 1.5) * r.h * 0.02
    lg.setColor(0, 0, 0, 0.12)
    lg.ellipse("fill", cx, cy + ih * s * 0.55, iw * s * 0.42 * math.max(0.3, math.abs(ca)), r.h * 0.03)
    for k = 8, 1, -1 do
      local sh = 0.45 + 0.25 * k / 8
      lg.setColor(sh, sh, sh, 1)
      lg.draw(icon, cx + sa * iw * s * 0.1 * k / 8, cy + bob, 0, s * ca, s, iw / 2, ih / 2)
    end
    local lit = ca >= 0 and 1 or 0.8
    lg.setColor(lit, lit, lit, 1)
    lg.draw(icon, cx, cy + bob, 0, s * ca, s, iw / 2, ih / 2)
  end
  if title then
    local tw, tt = title:getDimensions()
    local s = math.min(r.w * 0.8 / tw, th * 0.8 / tt)
    lg.setColor(1, 1, 1, 1)
    lg.draw(title, r.x + (r.w - tw * s) / 2, r.y + r.h - th + (th - tt * s) / 2, 0, s, s)
  end
end

local function drawTop3DS(r, banner)
  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)
  col3({ 250, 251, 252 })
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  local P, sh, nh, pad = topPanel(r)
  local bannerH = math.floor(r.h * 0.42)
  if banner then P.h = r.h - sh - bannerH - 2 * pad end
  -- status bar
  local cy = r.y + pad * 0.6 + sh / 2
  local bh = sh * 0.7
  local x = r.x + pad
  for i = 1, 4 do
    col3({ 20, 150, 210 })
    local h = bh * (0.35 + 0.65 * i / 4)
    lg.rectangle("fill", x + (i - 1) * bh * 0.2, cy + bh / 2 - h, bh * 0.14, h)
  end
  x = x + bh * 0.95
  local iw = r.w * 0.22
  col3({ 40, 150, 230 })
  lg.rectangle("fill", x, cy - bh / 2, iw, bh, bh * 0.25, bh * 0.25)
  col3({ 120, 200, 250 }, 0.6)
  lg.rectangle("fill", x + bh * 0.1, cy - bh * 0.42, iw - bh * 0.2, bh * 0.35, bh * 0.15, bh * 0.15)
  local f = font(bh * 0.72)
  lg.setFont(f)
  lg.setColor(1, 1, 1, 1)
  lg.printf("Internet", x, cy - f:getHeight() / 2, iw, "center")
  x = x + iw + bh * 0.5
  local count = Home.coins()
  col3({ 214, 160, 10 })
  lg.circle("fill", x + bh / 2, cy, bh / 2)
  col3({ 250, 206, 40 })
  lg.circle("fill", x + bh / 2, cy, bh * 0.42)
  col3({ 70, 72, 78 })
  lg.print(tostring(count), x + bh * 1.2, cy - f:getHeight() / 2)
  -- battery, then the date and time left of it
  local batW = bh * 1.5
  local bx = r.x + r.w - pad - batW
  local pct = 1
  if love.system.getPowerInfo then
    local _, pc = love.system.getPowerInfo()
    if pc then pct = pc / 100 end
  end
  col3({ 60, 62, 68 })
  lg.rectangle("fill", bx, cy - bh * 0.38, batW, bh * 0.76, bh * 0.15, bh * 0.15)
  lg.rectangle("fill", bx - bh * 0.12, cy - bh * 0.18, bh * 0.14, bh * 0.36)
  lg.setColor(1, 1, 1, 1)
  lg.rectangle("fill", bx + bh * 0.08, cy - bh * 0.3, batW - bh * 0.16, bh * 0.6, bh * 0.1, bh * 0.1)
  col3({ 30, 150, 230 })
  local fw = (batW - bh * 0.26) * math.max(0.05, math.min(1, pct))
  lg.rectangle("fill", bx + batW - bh * 0.13 - fw, cy - bh * 0.25, fw, bh * 0.5, bh * 0.08, bh * 0.08)
  local t = os.date("*t")
  if state.steps and state.steps >= 0 then
    -- the pedometer, as the 3DS shows it: footprints, today's steps, the time
    local label = ("%d Steps"):format(state.steps)
    local clock = ("%d:%02d"):format(t.hour, t.min)
    local fw2 = bh * 1.25
    local dw = fw2 + f:getWidth(label) + bh * 0.7 + f:getWidth(clock) + bh * 0.6
    local dx = bx - bh * 0.4 - dw
    col3({ 96, 98, 104 })
    lg.rectangle("fill", dx, cy - bh / 2, dw, bh, bh * 0.4, bh * 0.4)
    col3({ 150, 152, 158 })
    lg.rectangle("line", dx, cy - bh / 2, dw, bh, bh * 0.4, bh * 0.4)
    -- two footprints
    lg.setColor(1, 1, 1, 1)
    for k = 0, 1 do
      local fx, fy = dx + bh * (0.42 + k * 0.34), cy + (k == 0 and bh * 0.05 or -bh * 0.05)
      lg.ellipse("fill", fx, fy - bh * 0.1, bh * 0.11, bh * 0.17)
      lg.ellipse("fill", fx, fy + bh * 0.2, bh * 0.08, bh * 0.07)
    end
    lg.setFont(f)
    lg.print(label, dx + fw2, cy - f:getHeight() / 2)
    lg.print(clock, dx + fw2 + f:getWidth(label) + bh * 0.7, cy - f:getHeight() / 2)
  else
    local days = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
    local stamp = ("%d/%d (%s) %d:%02d"):format(t.month, t.day, days[t.wday], t.hour, t.min)
    local dw = f:getWidth(stamp) + bh
    local dx = bx - bh * 0.4 - dw
    col3({ 244, 245, 247 })
    lg.rectangle("fill", dx, cy - bh / 2, dw, bh, bh * 0.4, bh * 0.4)
    col3({ 200, 203, 210 })
    lg.rectangle("line", dx, cy - bh / 2, dw, bh, bh * 0.4, bh * 0.4)
    col3({ 60, 62, 68 })
    lg.printf(stamp, dx, cy - f:getHeight() / 2, dw, "center")
  end
  -- the wallpaper panel: pale tiles on grey
  lg.stencil(function() lg.rectangle("fill", P.x, P.y, P.w, P.h, P.h * 0.05, P.h * 0.05) end, "replace", 1)
  lg.setStencilTest("greater", 0)
  col3({ 206, 210, 218 })
  lg.rectangle("fill", P.x, P.y, P.w, P.h)
  local ts = P.h / 3.2
  local step = ts * 1.08
  for i = -1, math.ceil(P.w / step) do
    for j = 0, 3 do
      local tx = P.x + i * step + step * 0.35
      local ty = P.y + j * step - step * 0.45
      col3({ 226, 229, 235 })
      lg.rectangle("fill", tx, ty, ts * 0.92, ts * 0.9, ts * 0.12, ts * 0.12)
      col3({ 236, 238, 243 }, 0.8)
      lg.rectangle("fill", tx + ts * 0.18, ty + ts * 0.18, ts * 0.56, ts * 0.54, ts * 0.08, ts * 0.08)
    end
  end
  lg.setStencilTest()
  if banner == "eshop" then
    -- the eShop: its own page below the status bar
    Eshop.drawTop({ x = r.x, y = P.y, w = r.w, h = r.y + r.h - P.y - nh * 0.2 })
    drawLR(r, nh * 0.72, pad)
    lg.pop()
    return
  end
  if banner and banner ~= "dlplay" then
    -- another HOME bar app picked: its banner under the panel
    local by = P.y + P.h + pad * 0.3
    appletBanner({ x = r.x + r.w * 0.16, y = by, w = r.w * 0.68, h = r.y + r.h - by - pad * 0.2 }, banner, state.time)
    drawLR(r, bannerH * 0.26, pad)
    lg.pop()
    return
  end
  if banner == "dlplay" then
    -- Download Play: its banner turning under the panel, its news in it
    local msg = Dlplay.topMessage()
    if msg then
      local mf = font(P.h * 0.14)
      lg.setFont(mf)
      col3({ 80, 82, 90 })
      lg.printf(msg, P.x, P.y + P.h / 2 - mf:getHeight() / 2, P.w, "center")
    end
    local by = P.y + P.h + pad * 0.3
    Dlplay.drawBanner({ x = r.x + r.w * 0.16, y = by, w = r.w * 0.68, h = r.y + r.h - by - pad * 0.2 }, state.time)
    drawLR(r, bannerH * 0.26, pad)
    lg.pop()
    return
  end
  -- a 3DS game, the Azahar folder or one of its icons: that, not a cartridge
  local other = Home.showing() and Home.topTile(state.subject)
  if other then
    drawTopTile(P, other)
    local nf = font(nh * 0.6)
    lg.setFont(nf)
    col3({ 70, 72, 78 })
    lg.printf(other.name or "", r.x, r.y + r.h - nh - pad * 0.3 + (nh - nf:getHeight()) / 2, r.w, "center")
    lg.pop()
    return
  end
  -- the selected game's cartridge
  local version = launcherVersion()
  local skin
  do
    local ok, LV = pcall(require, "src.import.LauncherView")
    if ok and type(LV) == "table" and LV.foldCartSkin and state.subject then
      local ok2, s = pcall(LV.foldCartSkin, state.subject, version)
      if ok2 then skin = s end
    end
  end
  Cart3D.draw(P, version, state.time, skin)
  -- the game's name under the panel
  local imp = state.subject
  local ok, GV = pcall(require, "src.core.GameVersion")
  local info = ok and GV.info and GV.info(version)
  local ready = imp and imp.ready and imp.ready[version]
  local nf = font(nh * 0.6)
  lg.setFont(nf)
  col3({ 70, 72, 78 })
  local name = (info and info.displayName or version) .. (ready and "" or "   -   import the ROM")
  lg.printf(name, r.x, r.y + r.h - nh - pad * 0.3 + (nh - nf:getHeight()) / 2, r.w, "center")
  drawLR(r, nh * 0.72, pad)
  lg.pop()
end
M.topPanel = topPanel

-- a tap on the top screen while the launcher shows: arrows change the
-- game, the cart plays it (the 3DS theme: the whole screen plays it)
topScreenTap = function(x, y)
  local L = state.L
  if not L or state.kind == "game" or not inside(L.topCut, x, y) then return false end
  if Theme3DS.active then
    for _, rr in pairs(state.lrRects or {}) do
      if inside(rr, x, y) then Camera.open() return true end
    end
  end
  local imp = state.subject
  if not imp then return true end
  if Theme3DS.active then
    -- a 3DS game or an Azahar icon selected: open it
    if Home.showing() and Home.topTile(imp) then Home.openSelected(imp) return true end
    local version = launcherVersion()
    if imp.ready and imp.ready[version] and imp.play then pcall(imp.play, imp, version, true) end
    return true
  end
  local rel = (x - L.topCut.x) / L.topCut.w
  local ok, GV = pcall(require, "src.core.GameVersion")
  local order = ok and GV.ORDER or { "red" }
  local version = launcherVersion()
  if rel < 0.2 or rel > 0.8 then
    local idx = 1
    for i, v in ipairs(order) do if v == version then idx = i end end
    idx = (idx - 1 + (rel < 0.2 and -1 or 1)) % #order + 1
    imp.tab = order[idx]
    imp.panelVersion = order[idx]
  elseif imp.ready and imp.ready[version] and imp.play then
    pcall(imp.play, imp, version, true)
  end
  return true
end

local function drawShoulders(L)
  if not state.shoulders then return end
  local age = state.time - state.shoulderSeen
  for _, sb in ipairs(SHOULDERS) do
    local lit = buttonLit(sb)
    if lit then state.shoulderSeen = state.time; age = 0 end
  end
  local alpha = 1 - math.max(0, math.min(1, (age - SHOULDER_SHOW) / SHOULDER_FADE))
  if alpha <= 0.01 then return end
  lg.push("all")
  for _, sb in ipairs(SHOULDERS) do
    local r = shoulderRect(L, sb)
    local lit = buttonLit(sb)
    local rad = r.h * 0.35
    lg.setColor(0, 0, 0, 0.35 * alpha)
    lg.rectangle("fill", r.x + 1, r.y + r.h * 0.08, r.w, r.h, rad, rad)
    if lit then lg.setColor(0.52, 0.53, 0.56, alpha) else lg.setColor(0.24, 0.25, 0.27, alpha) end
    lg.rectangle("fill", r.x, r.y + (lit and r.h * 0.05 or 0), r.w, r.h, rad, rad)
    lg.setColor(1, 1, 1, 0.12 * alpha)
    lg.rectangle("fill", r.x + r.w * 0.08, r.y + r.h * 0.08, r.w * 0.84, r.h * 0.3, rad * 0.6, rad * 0.6)
    lg.setColor(0.06, 0.06, 0.07, alpha)
    lg.setLineWidth(1.5)
    lg.rectangle("line", r.x, r.y + (lit and r.h * 0.05 or 0), r.w, r.h, rad, rad)
    local f = font(r.h * 0.46)
    lg.setFont(f)
    lg.setColor(0.93, 0.93, 0.95, alpha)
    lg.printf(sb.label, r.x, r.y + (lit and r.h * 0.05 or 0) + (r.h - f:getHeight()) / 2, r.w, "center")
  end
  lg.pop()
end

local function drawButtons(L)
  local sheet = image(SHEET)
  if not sheet then return end
  local sw, sh = sheet:getDimensions()
  for _, b in ipairs(BUTTONS) do
    b.quad = b.quad or lg.newQuad(b.sprite[1] * 2, b.sprite[2] * 2, b.sprite[3] * 2, b.sprite[4] * 2, sw, sh)
    local lit, dirs = buttonLit(b)
    local target = b.r * 2 * L.s2               -- socket width in pixels
    local qw, qh = b.sprite[3] * 2, b.sprite[4] * 2
    local scale = (b.wide and (target * 2 / qw)) or (target / math.max(qw, qh))
    local cx, cy = L.bottom.x + b.x * L.s2, L.bottom.y + b.y * L.s2
    local dx, dy = 0, 0
    if b.kind == "dpad" and lit and dirs then
      local lean = b.r * L.s2 * 0.12
      if dirs.left then dx = dx - lean end
      if dirs.right then dx = dx + lean end
      if dirs.up then dy = dy - lean end
      if dirs.down then dy = dy + lean end
    end
    local ps = scale * (lit and 0.93 or 1)
    if lit then lg.setColor(0.68, 0.68, 0.72, 1) else lg.setColor(1, 1, 1, 1) end
    lg.draw(sheet, b.quad, cx - qw * ps / 2 + dx, cy - qh * ps / 2 + dy + (lit and L.s2 * 1.5 or 0), 0, ps, ps)
  end
end

local function drawArrows(L)
  local a = L.arrows
  local light = Theme3DS.active
  local ink = light and Theme3DS.arrowInk or { 1, 1, 1 }
  if light then lg.setColor(Theme3DS.arrowFill) else lg.setColor(0.07, 0.08, 0.10, 1) end
  lg.rectangle("fill", a.x, a.y, a.w, a.h)
  lg.setColor(ink[1], ink[2], ink[3], 0.10)
  lg.rectangle("fill", a.x, a.y, 1, a.h)
  local function tri(r, dir)
    local on = canScroll(dir)
    local held = state.arrowHeld and state.arrowHeld.dir == dir
    local cx, cy = r.x + r.w / 2, r.y + r.h / 2
    local sz = math.min(r.w * 0.34, r.h * 0.2)
    if held then
      lg.setColor(ink[1], ink[2], ink[3], 0.12)
      lg.rectangle("fill", r.x + 2, r.y + 2, r.w - 4, r.h - 4, 4, 4)
    end
    lg.setColor(ink[1], ink[2], ink[3], on and (held and 1 or 0.85) or 0.18)
    if dir < 0 then
      lg.polygon("fill", cx - sz, cy + sz * 0.5, cx + sz, cy + sz * 0.5, cx, cy - sz * 0.7)
    else
      lg.polygon("fill", cx - sz, cy - sz * 0.5, cx + sz, cy - sz * 0.5, cx, cy + sz * 0.7)
    end
  end
  local up, down, buttons = columnRects(L)
  tri(up, -1)
  tri(down, 1)
  lg.setColor(ink[1], ink[2], ink[3], 0.10)
  lg.rectangle("fill", a.x + 4, down.y, a.w - 8, 1)
  -- sync / settings / quit, when the column carries them
  if #buttons > 0 then
    local okI, Icons = pcall(require, "src.ui.kit.Icons")
    for _, b in ipairs(buttons) do
      local s = math.floor(b.w * 0.5)
      if okI then
        Icons.draw(b.icon, b.x + (b.w - s) / 2, b.y + (b.h - s) / 2, s,
          { ink[1] * 255, ink[2] * 255, ink[3] * 255 }, 0.9)
      end
      lg.setColor(ink[1], ink[2], ink[3], 0.10)
      lg.rectangle("fill", b.x + 4, b.y + b.h - 1, b.w - 8, 1)
    end
  end
end

local function drawToast(r)
  local t = state.toast
  if not t then return end
  local age = state.time - t.at
  if age > 1.6 then state.toast = nil return end
  local alpha = age > 1.2 and (1.6 - age) / 0.4 or 1
  local f = font(r.h * 0.075)
  lg.setFont(f)
  local tw, th = f:getWidth(t.text) + f:getHeight() * 1.4, f:getHeight() * 1.6
  local x, y = r.x + (r.w - tw) / 2, r.y + r.h * 0.08
  lg.setColor(0, 0, 0, 0.72 * alpha)
  lg.rectangle("fill", x, y, tw, th, th / 3, th / 3)
  lg.setColor(1, 1, 1, alpha)
  lg.printf(t.text, x, y + (th - f:getHeight()) / 2, tw, "center")
end

-- The closed lid, as large as a rect holds (turned on its side when
-- `portrait`), with the player's sticker on it.
local function drawLidIn(x, y, W, H, portrait, cover)
  local lid = image(LID)
  if not lid then return end
  -- only the shell itself (the art's opaque box), as big as the rect holds
  -- with a thin margin
  local cw, ch = LID_BOX[3], LID_BOX[4]
  state.lidQuad = state.lidQuad or lg.newQuad(LID_BOX[1], LID_BOX[2], cw, ch, lid:getDimensions())
  local aw, ah = W, H
  if portrait then aw, ah = H, W end
  local s = math.min(aw / cw, ah / ch) * 0.98
  local ox, oy = math.floor((aw - cw * s) / 2), math.floor((ah - ch * s) / 2)
  lg.push()
  lg.translate(x, y)
  if portrait then
    lg.translate(W, 0)
    lg.rotate(math.pi / 2)
  end
  lg.setColor(1, 1, 1, 1)
  lg.draw(lid, state.lidQuad, ox, oy, 0, s, s)
  -- the sticker stays on the shell: its shape (the art's opaque pixels) is
  -- the stencil anything hanging off the edge is cut by
  state.alphaTest = state.alphaTest or lg.newShader([[
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      vec4 p = Texel(tex, tc);
      if (p.a < 0.5) discard;
      return p;
    }
  ]])
  Sticker.drawOnLid(ox, oy, s, cw, ch, function()
    lg.setShader(state.alphaTest)
    lg.draw(lid, state.lidQuad, ox, oy, 0, s, s)
    lg.setShader()
  end, cover)
  lg.pop()
end

-- a wallpaper filling a w x h box, cropped rather than stretched
-- The boot screen: the G1R Deluxe logo on both screens (fold3ds/boot/),
-- the lid's click, then the HOME menu's welcome jingle; it fades into the
-- menu after a few seconds, or at once on a tap or a button.
local BOOT_TIME, BOOT_FADE = 3.6, 0.5
local function booting()
  local b = state.boot
  if not b then return false end
  if state.time - b.t0 > BOOT_TIME then state.boot = nil return false end
  return true
end

skipBoot = function()
  local b = state.boot
  if not booting() then return false end
  -- already fading: the touch is the menu's
  if state.time - b.t0 >= BOOT_TIME - BOOT_FADE then return false end
  -- straight to the fade
  b.t0 = math.min(b.t0, state.time - (BOOT_TIME - BOOT_FADE))
  return true
end

local function bootImage(name)
  local key = "boot:" .. name
  if state.images[key] == nil then
    local ok, img = pcall(lg.newImage, DIR .. "boot/" .. name .. ".jpg")
    state.images[key] = ok and img or false
    if ok then img:setFilter("linear", "linear") end
  end
  return state.images[key] or nil
end

local function drawBootScreen(img, r, age, zoom, a)
  lg.setScissor(r.x, r.y, r.w, r.h)
  lg.setColor(0.94, 0.96, 1, a)
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  if img then
    local iw, ih = img:getDimensions()
    local k = math.max(r.w / iw, r.h / ih) * zoom
    lg.setColor(1, 1, 1, a)
    lg.draw(img, r.x + r.w / 2, r.y + r.h / 2, 0, k, k, iw / 2, ih / 2)
  end
  -- a light sweeping across once
  local sweep = (age - 0.5) / 1.1
  if sweep > 0 and sweep < 1 then
    local x = r.x - r.w * 0.3 + sweep * r.w * 1.6
    for i = 0, 7 do
      local o = i * r.w * 0.02
      lg.setColor(1, 1, 1, 0.06 * a * (1 - math.abs(i - 3.5) / 4))
      lg.polygon("fill", x + o, r.y, x + o + r.w * 0.04, r.y,
        x + o - r.w * 0.06, r.y + r.h, x + o - r.w * 0.1, r.y + r.h)
    end
  end
  -- from white, as the screens light up
  if age < 0.25 then
    lg.setColor(1, 1, 1, 1 - age / 0.25)
    lg.rectangle("fill", r.x, r.y, r.w, r.h)
  end
  lg.setScissor()
end

local function drawBoot(L)
  if not booting() then return end
  local b = state.boot
  local age = state.time - b.t0
  -- the jingle, a beat after the click
  if not b.jingle and age > 0.3 then b.jingle = true; Sfx.play("boot") end
  local a = 1
  if age > BOOT_TIME - BOOT_FADE then a = math.max(0, (BOOT_TIME - age) / BOOT_FADE) end
  local zoom = 1 + 0.035 * math.min(1, age / BOOT_TIME)
  lg.push("all")
  drawBootScreen(bootImage("top"), L.topCut, age, zoom, a)
  drawBootScreen(bootImage("bottom"), L.botCut, age, zoom, a)
  lg.pop()
end

local function drawWall(file, w, h)
  local img = image(file)
  if not img then return false end
  local iw, ih = img:getDimensions()
  local s = math.max(w / iw, h / ih)
  lg.setColor(1, 1, 1, 1)
  lg.draw(img, (w - iw * s) / 2, (h - ih * s) / 2, 0, s, s)
  return true
end

local function drawLid(W, H)
  lg.setColor(0.16, 0.16, 0.17, 1)
  lg.rectangle("fill", 0, 0, W, H)
  -- the black wallpaper behind the closed lid, turned with it
  local portrait = H > W * 1.1
  lg.push()
  if portrait then
    lg.translate(W, 0)
    lg.rotate(math.pi / 2)
    drawWall(WALL_LID, H, W)
  else
    drawWall(WALL_LID, W, H)
  end
  lg.pop()
  drawLidIn(0, 0, W, H, portrait, true)
end

local function drawFrame()
  local L = state.L
  local W, H = state.W, state.H
  real.setCanvas()
  lg.push("all")
  lg.origin()
  lg.setShader()
  lg.setScissor()
  lg.setBlendMode("alpha")
  lg.setColor(1, 1, 1, 1)
  if state.mode == "lid" then
    drawLid(W, H)
    lg.pop()
    return
  end
  lg.clear(0.05, 0.05, 0.06, 1)
  -- the white wallpaper behind the open 3DS
  drawWall(WALL_OPEN, W, H)
  -- screens first (the openings in the shell art are transparent)
  local canvas = state.canvases[state.kind == "game" and "game" or "launcher"]
  local gr = gameRect(L)
  if state.kind == "game" then
    lg.setColor(0, 0, 0, 1)
    lg.rectangle("fill", L.topCut.x, L.topCut.y, L.topCut.w, L.topCut.h)
    lg.setColor(1, 1, 1, 1)
    if canvas and state.screenMode ~= "full" then lg.draw(canvas, gr.x, gr.y) end
    local menus = state.canvases.menus
    if state.menusShown and menus then
      lg.setColor(0, 0, 0, 1)
      lg.rectangle("fill", L.botCut.x, L.botCut.y, L.botCut.w, L.botCut.h)
      lg.setColor(1, 1, 1, 1)
      lg.draw(menus, L.botCut.x, L.botCut.y)
    else
      drawIdle(L.botCut)
    end
  elseif cameraOn() then
    -- the Camera applet: the picture on top, the controls below
    Camera.drawTop(L.topCut)
    Camera.drawBottom(L.botCut)
  elseif Sticker.editing() then
    -- the cover sticker editor: the cover on top, the tools below
    Sticker.drawPreview(L.topCut, drawLidIn)
    Sticker.drawEditor(L.botCut)
  elseif dlOn() then
    drawTop3DS(L.topCut, "dlplay")
    Dlplay.drawBottom(L.botCut)
  elseif esOn() then
    drawTop3DS(L.topCut, "eshop")
    Eshop.drawBottom(L.botCut)
  elseif homeActive() and Home.showing() then
    local focus = Home.barFocus()
    local banners = { downloadplay = "dlplay", eshop = "eshop", camera = "camera", settings = "settings" }
    if Theme3DS.active then drawTop3DS(L.topCut, banners[focus or ""])
    else drawTopIdle(L.topCut) end
    Home.draw(L.botCut, state.subject, state.time)
  else
    if Theme3DS.active then drawTop3DS(L.topCut) else drawTopIdle(L.topCut) end
    lg.setColor(1, 1, 1, 1)
    local vr = state.vwin or L.botView
    if canvas then lg.draw(canvas, vr.x, vr.y) end
    if homeActive() then Home.drawBar(L.botView) end
    drawArrows(L)
  end
  drawBoot(L)
  lg.setColor(1, 1, 1, 1)
  lg.draw(L.top.img, L.top.x, L.top.y, 0, L.top.sc, L.top.sc)
  drawVolume(L)
  -- FULL: the game covers the whole top panel, Game Boy Color frame included
  if state.kind == "game" and state.screenMode == "full" and canvas then
    lg.setColor(0, 0, 0, 1)
    lg.rectangle("fill", gr.x, gr.y, gr.w, gr.h)
    lg.setColor(1, 1, 1, 1)
    lg.draw(canvas, gr.x, gr.y)
  end
  lg.draw(L.bottom.img, L.bottom.x, L.bottom.y, 0, L.bottom.sc, L.bottom.sc)
  drawButtons(L)
  drawShoulders(L)
  drawToast(state.kind == "game" and gr or L.topCut)
  lg.pop()
end

---------------------------------------------------------------- backend

local backend = {}

local dbgFrames = 0
function backend:update(dt)
  state.time = state.time + (dt or 0)
  Home.tick(dt)   -- the play meter runs whenever the app does
  Sticker.tick(dt) -- and wears the re-stuck stickers
  Camera.update(dt, cameraOn())
  Dlplay.update(dt)
  Eshop.update(dt)
  -- the volume keys move the slider (and are kept from Android's volume)
  if state.volKeysSent ~= state.volKeys then
    state.volKeysSent = state.volKeys
    bridge("vol.capture", state.volKeys and "1" or "0")
  end
  if state.volKeys then
    local n = tonumber(bridge("vol.take") or "0") or 0
    if n ~= 0 then setVolume((state.volume or 1) + n / 10) end
  end
  if state.volSaveAt and state.time >= state.volSaveAt then state.volSaveAt = nil; saveSettings() end
  -- the top screen's cartridge feels the phone: a quick spin when it is
  -- moved (the gyroscope), a lean with its tilt (the accelerometer)
  if Theme3DS.active and state.mode == "ds" and state.kind ~= "game" then
    if state.sensors == nil then
      local ok, S = pcall(require, "src.core.Sensors")
      state.sensors = ok and S or false
    end
    local S = state.sensors
    if S then
      local ok, gx, gy, gz = pcall(S.read, "gyroscope")
      if ok and gx and math.sqrt(gx * gx + gy * gy + (gz or 0) ^ 2) > 2.4 then Cart3D.kick(state.time) end
      local ok2, ax, ay = pcall(S.read, "accelerometer")
      if ok2 and ax then Cart3D.setTilt(-ax / 9.8, ay / 9.8 - 0.5) end
    end
  end
  -- today's steps for the top screen (every few seconds, 3DS theme only)
  if Theme3DS.active and state.time >= (state.stepsAt or 0) then
    state.stepsAt = state.time + 3
    local fake = os.getenv("POKEPORT_FOLD_FAKESTEPS")
    local n = fake and tonumber(fake) or tonumber(bridge("steps") or "")
    state.steps = n
  end
  if M.debug and dbgFrames < 3 then dbgFrames = dbgFrames + 1 io.stdout:setvbuf("no") print("fold3ds update mode=" .. tostring(state.mode) .. " kind=" .. tostring(state.kind)) end
  if M.driverTick then M.driverTick() end
  local mode = detectMode()
  local W, H = real.getDimensions()
  if mode ~= state.mode then
    releaseAll()
    -- opening the phone: the 3DS's click
    if mode == "ds" and state.mode == "lid" then Sfx.play("click", true) end
    state.mode = mode
  end
  if mode == "ds" and (W ~= state.W or H ~= state.H or not state.L) then
    state.W, state.H = W, H
    state.L = layout(W, H)
    if not state.L then state.mode = "off" end
  end
  state.W, state.H = W, H
  state.vwin = state.mode == "ds" and virtualRect() or nil
  -- the launcher's compact bottom-screen layout
  do
    local ok, LV = pcall(require, "src.import.LauncherView")
    if ok and type(LV) == "table" then
      LV.fold = state.mode == "ds" or nil
      LV.foldNoHeader = homeActive() or nil
      LV.foldClusterOut = (state.mode == "ds" and state.theme ~= "3ds") or nil
      LV.foldSticker = LV.foldSticker or {
        has = Sticker.has, open = Sticker.open, remove = Sticker.remove,
        count = Sticker.count, putBack = Sticker.putBack,
      }
      -- no THEME card in SKINS: the 3DS look is the only one
      LV.foldTheme = nil
      -- the top screen cartridges: EN or JP artwork
      LV.foldArtwork = LV.foldArtwork or {
        get = function() return Cart3D.region end,
        set = function(v)
          Cart3D.region = v == "jp" and "jp" or "intl"
          Sfx.play("button")
          saveSettings()
        end,
      }
    end
  end
  -- the 3DS look dresses the launcher on the fold's bottom screen
  Theme3DS.set(state.mode == "ds" and state.theme == "3ds")
  Sticker.update()
  if homeActive() then Home.update(state.subject) end
  -- held scroll arrow / d-pad: repeat
  local now = state.time
  for i = 1, 2 do
    local r = i == 1 and state.arrowHeld or state.padScroll
    if r and now >= r.next then
      -- held: speeds up to four steps a repeat over two seconds
      r.count = (r.count or 0) + 1
      if state.kind == "game" or not scrollBy(r.dir, 1 + math.min(3, r.count / 7)) then
        if r == state.padScroll then state.padScroll = nil end
      end
      r.next = now + REPEAT_NEXT
    end
  end
  if not state.oriented and love.system.getOS() == "Android" then
    state.oriented = true
    pcall(function() require("src.core.Orientation").apply("landscape") end)
  end
end

local function canvasFor(key, r)
  local c = state.canvases[key]
  if not c or c:getWidth() ~= r.w or c:getHeight() ~= r.h then
    if c and c.release then c:release() end
    c = lg.newCanvas(r.w, r.h)
    state.canvases[key] = c
  end
  return c
end

-- put a split frame's stack back (also run defensively before each frame,
-- should a draw have thrown between the two halves)
local function unsplit()
  local sp = state.split
  if sp and sp.stack and sp.stack.states ~= sp.full then sp.stack.states = sp.full end
  state.split = nil
end

function backend:beginFrame(kind, subject)
  unsplit()
  state.menusShown = false
  local changed = kind ~= state.kind
  state.kind, state.subject = kind, subject
  if changed then releaseAll() end
  -- back from a game: the HOME menu's grid, as on a 3DS
  if changed and kind == "launcher" then Home.goHome(nil, true) end
  -- the menu's chime the first time it comes up
  -- the first time the menu comes up on the open 3DS: the boot screen
  if kind == "launcher" and not state.chimed and state.mode == "ds" then
    state.chimed = true
    state.boot = { t0 = state.time, jingle = false }
    Sfx.play("click")
  end
  Sfx.inGame = kind == "game"
  if state.mode ~= "ds" or not state.L then return end
  state.vwin = virtualRect()
  local r = state.vwin
  local c = canvasFor(kind == "game" and "game" or "launcher", r)
  if kind == "game" then
    -- the shell's buttons replace the engine's touch overlay
    local ok, TC = pcall(require, "src.core.TouchControls")
    if ok and TC then TC.enabled = false end
    -- START's menu / the mod manager open: the top screen draws the stack
    -- below them, the bottom screen draws them (endFrame)
    local base = menuBase(subject)
    if base then
      local full = subject.stack.states
      local top = {}
      for i = 1, base - 1 do top[i] = full[i] end
      local menus = {}
      for i = base, #full do menus[#menus + 1] = full[i] end
      state.split = { stack = subject.stack, full = full, top = top, menus = menus }
      subject.stack.states = top
    end
  end
  -- the 3DS theme draws its own 3D cart on the top screen (fold3ds.cart3d)
  do
    local ok, LV = pcall(require, "src.import.LauncherView")
    if ok and type(LV) == "table" then LV.foldTopCart = nil end
  end
  state.frameCanvas = c
  real.setCanvas(c)
  lg.clear(0, 0, 0, 1)
end

-- the menus of a split frame, drawn by the game itself into the bottom screen
local function drawMenus(subject)
  local sp = state.split
  local L = state.L
  local r = L.botCut
  local c = canvasFor("menus", r)
  sp.stack.states = sp.menus
  state.vwin = r
  state.frameCanvas = c
  real.setCanvas(c)
  lg.clear(0, 0, 0, 1)
  lg.push("all")
  local ok, err = pcall(subject.draw, subject)
  lg.pop()
  if not ok then print("fold3ds: bottom menu draw: " .. tostring(err)) end
  sp.stack.states = sp.full
  state.frameCanvas = nil
  state.vwin = virtualRect()
  state.menusShown = true
end

function backend:endFrame(kind, subject)
  state.frameCanvas = nil
  if state.split then state.split.stack.states = state.split.full end
  if state.mode ~= "off" and kind == "game" and state.split and state.L then drawMenus(subject) end
  state.split = nil
  if state.mode == "off" then return end
  drawFrame()
end

---------------------------------------------------------------- install

-- The community mod catalog in FIND: the index is added once (a player who
-- removes it keeps it removed), and the feed shipped in the APK stands in
-- until the first live fetch replaces it.
local function seedModIndex()
  local ok, err = pcall(function()
    local ModIndex = require("src.mods.ModIndex")
    local SaveData = require("src.core.SaveData")
    local opts = SaveData.loadOptions()
    if type(opts) ~= "table" then return end
    local source = ModIndex.resolveSource(MOD_INDEX)
    if not source then return end
    if not opts.fold3dsModIndex then
      ModIndex.addSource(MOD_INDEX)
      opts = SaveData.loadOptions()
      opts.fold3dsModIndex = true
      SaveData.saveOptions(opts)
    end
    local listed = false
    for _, row in ipairs(opts.modIndexes or {}) do
      if row.feed == source.feed then listed = true end
    end
    if not listed or ModIndex.readCache(source.feed) then return end
    local text = love.filesystem.read(DIR .. MOD_INDEX_SNAPSHOT)
    if not text then return end
    local index = ModIndex.parse(text)
    if not index then return end
    ModIndex.writeCache(source.feed, index)
    -- stale on purpose: the next visit to FIND fetches the live feed
    opts = SaveData.loadOptions()
    local entry = opts.modIndexCache and opts.modIndexCache[source.feed]
    if entry then
      entry.checkedAt = 0
      SaveData.saveOptions(opts)
    end
  end)
  if not ok then print("fold3ds: mod index: " .. tostring(err)) end
end

-- Settings gets what the fold launcher's footer used to carry: the app
-- updater, the patch notes and the BOIS CLUB GAMES mark.
local invertShader
local function aboutSection(imp)
  local okLV, LV = pcall(require, "src.import.LauncherView")
  local okS, Strings = pcall(require, "src.core.Strings")
  local S = okS and Strings or function(x) return x end
  local rows = {}
  if okLV and LV._updateControl and imp.Check then
    rows[#rows + 1] = {
      label = S("App updates"),
      actionLabel = function()
        local _, label = LV._updateControl(imp)
        return label or S("Check for updates")
      end,
      action = function()
        local _, _, act = LV._updateControl(imp)
        if act then pcall(act) end
        return false
      end,
    }
  end
  rows[#rows + 1] = {
    label = S("Patch notes"),
    actionLabel = S("Open"),
    action = function()
      if imp._closeSettings then imp:_closeSettings() end
      imp._appPatchNotes = true
      return false
    end,
  }
  if imp._openBugPanel then
    rows[#rows + 1] = {
      label = S("Troubleshooting"),
      actionLabel = S("Open"),
      action = function() imp:_openBugPanel() return false end,
    }
  end
  if imp.bcg then
    rows[#rows + 1] = { label = "", custom = {
      height = function(m) return math.floor(76 * m.s) end,
      draw = function(_, m, x, y, w, h)
        local Kit = require("src.ui.kit.Kit")
        local Theme = require("src.ui.kit.Theme")
        invertShader = invertShader or lg.newShader([[
          vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec4 p = Texel(tex, tc);
            return vec4((vec3(1.0) - p.rgb) * color.rgb, p.a * color.a);
          }
        ]])
        local bw, bh = imp.bcg:getDimensions()
        local sc = math.min((160 * m.s) / bw, (28 * m.s) / bh)
        local dw, dh = bw * sc, bh * sc
        local bx, by = x + (w - dw) / 2, y + math.floor(10 * m.s)
        lg.setShader(invertShader)
        lg.setColor(1, 1, 1, Kit.hover(bx, by, dw, dh) and 1 or 0.85)
        lg.draw(imp.bcg, Theme.snap(bx), Theme.snap(by), 0, sc, sc)
        lg.setShader()
        lg.setColor(1, 1, 1, 1)
        local line = "BOIS CLUB GAMES  -  bois.icu"
        local lw = Kit.textWidth("micro", line)
        Kit.text("micro", line, x + (w - lw) / 2, by + dh + math.floor(8 * m.s), Theme.PAL.muted)
        if Kit.press(x, y, w, h) then pcall(love.system.openURL, "https://bois.icu") end
      end,
    } }
  end
  return { title = S("About"), rows = rows }
end

-- the 3DS shell's own options
local function controlsSection()
  local okS, Strings = pcall(require, "src.core.Strings")
  local S = okS and Strings or function(x) return x end
  return { title = S("3DS Shell"), rows = {
    { label = S("L / ZL / R / ZR buttons"),
      choices = { { value = "on", label = S("On") }, { value = "off", label = S("Off") } },
      selected = function() return state.shoulders and "on" or "off" end,
      select = function(v)
        state.shoulders = v == "on"
        state.shoulderSeen = state.time
        saveSettings()
      end },
    { label = S("Volume keys move the 3DS slider"),
      choices = { { value = "on", label = S("On") }, { value = "off", label = S("Off") } },
      selected = function() return state.volKeys and "on" or "off" end,
      select = function(v)
        state.volKeys = v == "on"
        saveSettings()
      end },
    { label = S("Menu sounds"),
      choices = { { value = "on", label = S("On") }, { value = "off", label = S("Off") } },
      selected = function() return state.sounds and "on" or "off" end,
      select = function(v)
        state.sounds = v == "on"
        Sfx.enabled = state.sounds
        Sfx.play(state.sounds and "on" or "off")
        saveSettings()
      end },
  } }
end

local function wrapSettings()
  local ok, RomImporter = pcall(require, "src.import.RomImporter")
  if not ok or type(RomImporter) ~= "table" or not RomImporter._openSettings then return end
  -- every launcher control a finger or A activates, and a game starting
  if RomImporter.runActions then
    local run = RomImporter.runActions
    RomImporter.runActions = function(self, queue, ...)
      if state.mode == "ds" and type(queue) == "table" and #queue > 0 then Sfx.play("button") end
      return run(self, queue, ...)
    end
  end
  if RomImporter.play then
    local play = RomImporter.play
    RomImporter.play = function(self, ...)
      if state.mode == "ds" then Sfx.play("launch") end
      return play(self, ...)
    end
  end
  local open = RomImporter._openSettings
  RomImporter._openSettings = function(self, ...)
    local r = open(self, ...)
    local model = self._settings
    if state.mode == "ds" and model and type(model.sections) == "table" then
      pcall(function()
        model.sections[#model.sections + 1] = controlsSection()
        model.sections[#model.sections + 1] = aboutSection(self)
      end)
    end
    return r
  end
end

function M.install()
  if M.installed then return end
  M.installed = true
  loadSettings()
  Sticker.init({ setCanvas = real.setCanvas, font = font })
  Camera.init({ font = font })
  Dlplay.init({ font = font, subject = function() return state.subject end })
  Eshop.init({ font = font, subject = function() return state.subject end,
    region = function() return Cart3D.region end })
  Home.init({ font = font, openCamera = Camera.open, drawCameraIcon = Camera.drawIcon, openDlplay = Dlplay.open, openEshop = Eshop.open })
  seedModIndex()
  wrapSettings()
  -- the virtual window: size, mode, safe area, pointer queries
  lg.getDimensions = function() if vactive() then return state.vwin.w, state.vwin.h end return real.getDimensions() end
  lg.getWidth = function() if vactive() then return state.vwin.w end return real.getWidth() end
  lg.getHeight = function() if vactive() then return state.vwin.h end return real.getHeight() end
  if real.getPixelDimensions then
    -- physical pixels, not units: the engine picks its whole-pixel Game Boy
    -- scale from these, and on a high-DPI phone units are several pixels
    local function px(v) return math.floor(v * dpi() + 0.5) end
    lg.getPixelDimensions = function() if vactive() then return px(state.vwin.w), px(state.vwin.h) end return real.getPixelDimensions() end
    lg.getPixelWidth = function() if vactive() then return px(state.vwin.w) end return real.getPixelWidth() end
    lg.getPixelHeight = function() if vactive() then return px(state.vwin.h) end return real.getPixelHeight() end
  end
  -- "the screen" (no target, or a nil target) is the subject's canvas while
  -- it draws; the engine's GameViewport passes nil when it has no viewport
  lg.setCanvas = function(...)
    if state.frameCanvas and (select("#", ...) == 0 or select(1, ...) == nil) then
      return real.setCanvas(state.frameCanvas)
    end
    return real.setCanvas(...)
  end
  lw.getMode = function()
    local w, h, flags = real.getMode()
    if vactive() then return state.vwin.w, state.vwin.h, flags end
    return w, h, flags
  end
  if real.getSafeArea then
    lw.getSafeArea = function()
      if vactive() then return 0, 0, state.vwin.w, state.vwin.h end
      return real.getSafeArea()
    end
  end
  lm.getPosition = function()
    local x, y = real.mouseGetPosition()
    if vactive() then return x - state.vwin.x, y - state.vwin.y end
    return x, y
  end
  lm.getX = function() local x = lm.getPosition() return x end
  lm.getY = function() local _, y = lm.getPosition() return y end
  lt.getTouches = function()
    if not vactive() then return real.touchGetTouches() end
    local ids = {}
    for id in pairs(state.vtouch) do ids[#ids + 1] = id end
    return ids
  end
  lt.getPosition = function(id)
    if vactive() and state.vtouch[id] then return state.vtouch[id][1], state.vtouch[id][2] end
    return real.touchGetPosition(id)
  end
  -- events
  orig.touchpressed, orig.touchmoved, orig.touchreleased = love.touchpressed, love.touchmoved, love.touchreleased
  orig.mousepressed, orig.mousemoved, orig.mousereleased = love.mousepressed, love.mousemoved, love.mousereleased
  love.touchpressed, love.touchmoved, love.touchreleased = onTouchPressed, onTouchMoved, onTouchReleased
  love.mousepressed, love.mousemoved, love.mousereleased = onMousePressed, onMouseMoved, onMouseReleased
  -- the frame
  local ok, HostDisplay = pcall(require, "src.core.HostDisplay")
  if ok and HostDisplay and HostDisplay.setBackend then HostDisplay.setBackend(backend) end
  -- desktop testing: a window the size of a foldable's screen, and a script
  local size = os.getenv and os.getenv("POKEPORT_FOLD_SIZE")
  if size then
    local w, h = size:match("^(%d+)x(%d+)$")
    if w then
      pcall(lw.setMode, tonumber(w), tonumber(h), { resizable = true })
      -- the launcher's desktop window manager would resize it back
      lw.setMode = function() return true end
    end
  end
  -- keep the play meter's last seconds when the app closes
  local quit = love.quit
  love.quit = function(...)
    pcall(Home.saveCoins)
    if quit then return quit(...) end
  end
  local script = os.getenv and os.getenv("POKEPORT_FOLD_TEST")
  if script then
    M.debug = true
    local okd, driver = pcall(function() return love.filesystem.load(DIR .. "dev/driver.lua")() end)
    if okd and driver then driver.start(script, M) end
  end
  backend:update(0)
end
M.backend = backend

M.state = state
return M
