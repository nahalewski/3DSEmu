-- Playing an emulator's game INSIDE the 3DS shell (3DS theme): DS games on
-- both screens, Virtual Console (GB / GBC / GBA) games on the top screen
-- with their box art and Save / Load / Reset / Close below.  The 3DS games
-- (Azahar) leave for Azahar's own screen instead and never come here.
--
-- Emulators are the fold3ds.emus providers that play in the shell, i.e.
-- have running().  While one runs this module owns both screens:
--   p.running() -> the game tile, or nil
--   p.update(dt), p.screen(i) -> Image (0 top, 1 DS bottom)
--   p.screenSize(sys) -> w, h
--   p.press(btn) / p.release(btn)   shell button names; "home" = its pause menu
--   p.touch(phase, u, v)            DS bottom screen, 0..1
--   p.menu() -> { open, rows = {{label, id}}, sel }, p.menuDo(id)
--   p.boxArt(t) -> Image, p.stop()
--
-- The top screen: the game covers the whole top panel (not the printed
-- Game Boy Color frame) inside a border for its system.
local EP = {}

local lg = love.graphics
local Emus = require("fold3ds.emus")
local Sfx = require("fold3ds.sfx")

local ctx
local st = { hits = {}, touches = {}, screenRect = nil }

-- a system's native size and its border: frame colour, the lettering below
-- the screen, and the lettering's colour
local SYSTEMS = {
  gb = { w = 160, h = 144, frame = { 136, 138, 150 }, bezel = { 60, 62, 76 }, text = "GAME BOY",
    ink = { 38, 40, 110 }, dot = { 150, 30, 60 } },
  gbc = { w = 160, h = 144, frame = { 88, 72, 160 }, bezel = { 40, 36, 52 }, text = "GAME BOY COLOR",
    ink = { 240, 240, 250 }, dot = { 240, 70, 60 } },
  gba = { w = 240, h = 160, frame = { 64, 52, 132 }, bezel = { 28, 26, 38 }, text = "GAME BOY ADVANCE",
    ink = { 220, 220, 240 }, dot = { 110, 220, 90 } },
  nds = { w = 256, h = 192, frame = { 30, 31, 36 }, bezel = { 14, 14, 16 }, text = nil },
}
EP.SYSTEMS = SYSTEMS

local function col(c, a) lg.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1) end

-- the running emulator and its game
function EP.active()
  for _, p in ipairs(Emus.providers()) do
    if p.running then
      local ok, t = pcall(p.running)
      if ok and t then return p, t end
    end
  end
end

local function system(p, t)
  local s = t and (t.system or t.sys)
  if SYSTEMS[s] then return s end
  if p and p.id == "melonds" then return "nds" end
  return "gbc"
end
EP.system = system

function EP.update(dt)
  local p, t = EP.active()
  if not p then return nil end
  if p.update then pcall(p.update, dt) end
  return p, t
end

local function screenImage(p, i)
  if not p.screen then return nil end
  local ok, img = pcall(p.screen, i)
  if ok and img then
    if img.setFilter then img:setFilter("nearest", "nearest") end
    return img
  end
end

-- fit w x h into a rect: whole-pixel steps when that fills most of it
local function fit(r, w, h)
  local k = math.min(r.w / w, r.h / h)
  local ik = math.floor(k)
  if ik >= 1 and ik / k > 0.85 then k = ik end
  local dw, dh = w * k, h * k
  return r.x + (r.w - dw) / 2, r.y + (r.h - dh) / 2, dw, dh, k
end

---------------------------------------------------------------- the top screen

-- full: the whole top panel (the game covers it); the border drawn inside
function EP.drawTop(full)
  local p, t = EP.active()
  if not p then return end
  local sys = system(p, t)
  local S = SYSTEMS[sys]
  lg.push("all")
  lg.setScissor(full.x, full.y, full.w, full.h)
  col(S.frame)
  lg.rectangle("fill", full.x, full.y, full.w, full.h)
  -- the frame's inner bevel
  lg.setColor(1, 1, 1, 0.08)
  lg.rectangle("fill", full.x, full.y, full.w, full.h * 0.5)
  -- the screen's dark bezel, then the screen
  local textH = S.text and full.h * 0.12 or 0
  local area = { x = full.x + full.w * 0.04, y = full.y + full.h * 0.05, w = full.w * 0.92,
    h = full.h * 0.9 - textH }
  local sw, sh = S.w, S.h
  if p.screenSize then
    local ok, w, h = pcall(p.screenSize, sys)
    if ok and w and h then sw, sh = w, h end
  end
  local bx, by, bw, bh = fit({ x = area.x + area.w * 0.08, y = area.y + area.h * 0.06,
    w = area.w * 0.84, h = area.h * 0.88 }, sw, sh)
  local pad = math.max(4, bh * 0.07)
  col(S.bezel)
  lg.rectangle("fill", bx - pad * 1.6, by - pad, bw + pad * 3.2, bh + pad * 2, pad, pad)
  if S.dot then
    -- the power lamp on the bezel
    col(S.dot)
    lg.circle("fill", bx - pad * 0.8, by + bh * 0.35, pad * 0.28)
  end
  lg.setColor(0, 0, 0, 1)
  lg.rectangle("fill", bx, by, bw, bh)
  local img = screenImage(p, 0)
  if img then
    lg.setColor(1, 1, 1, 1)
    lg.draw(img, bx, by, 0, bw / img:getWidth(), bh / img:getHeight())
  end
  if S.text then
    local f = ctx.font(textH * 0.5)
    lg.setFont(f)
    col(S.ink)
    lg.printf(S.text, full.x, by + bh + pad + (full.y + full.h - by - bh - pad - f:getHeight()) / 2,
      full.w, "center")
  end
  lg.pop()
end

---------------------------------------------------------------- the bottom screen

local function hit(id, x, y, w, h) st.hits[#st.hits + 1] = { id = id, x = x, y = y, w = w, h = h } end

local function pill(id, x, y, w, h, label, on)
  if on then lg.setColor(0.2, 0.55, 0.95, 1) else lg.setColor(1, 1, 1, 1) end
  lg.rectangle("fill", x, y, w, h, h * 0.3, h * 0.3)
  lg.setColor(0.78, 0.8, 0.84, 1)
  lg.setLineWidth(1)
  lg.rectangle("line", x, y, w, h, h * 0.3, h * 0.3)
  local f = ctx.font(h * 0.42)
  lg.setFont(f)
  if on then lg.setColor(1, 1, 1, 1) else lg.setColor(0.25, 0.26, 0.3, 1) end
  lg.printf(label, x, y + (h - f:getHeight()) / 2, w, "center")
  hit(id, x, y, w, h)
end

-- the emulator's pause menu (HOME), 3DS style, over the bottom screen
local function drawMenu(r, m)
  lg.setColor(0, 0, 0, 0.55)
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  local rows = m.rows or {}
  local rh = math.min(r.h * 0.13, (r.h * 0.8) / math.max(1, #rows))
  local w = r.w * 0.6
  local x = r.x + (r.w - w) / 2
  local y = r.y + (r.h - rh * #rows * 1.15) / 2
  for i, row in ipairs(rows) do
    pill("menu:" .. tostring(row.id or row[2]), x, y, w, rh, tostring(row.label or row[1]), m.sel == i)
    y = y + rh * 1.15
  end
end

function EP.drawBottom(r)
  local p, t = EP.active()
  st.hits = {}
  st.screenRect = nil
  if not p then return end
  local sys = system(p, t)
  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)
  if sys == "nds" then
    -- the DS touch screen, as large as fits
    lg.setColor(0, 0, 0, 1)
    lg.rectangle("fill", r.x, r.y, r.w, r.h)
    local S = SYSTEMS.nds
    local x, y, w, h = fit(r, S.w, S.h)
    st.screenRect = { x = x, y = y, w = w, h = h }
    local img = screenImage(p, 1)
    if img then
      lg.setColor(1, 1, 1, 1)
      lg.draw(img, x, y, 0, w / img:getWidth(), h / img:getHeight())
    end
  else
    -- Virtual Console: the box art, the title, and the game's buttons
    for yy = 0, r.h, 2 do
      local k = yy / r.h
      lg.setColor(0.96 - 0.06 * k, 0.97 - 0.05 * k, 0.99, 1)
      lg.rectangle("fill", r.x, r.y + yy, r.w, 2)
    end
    local pad = r.w * 0.04
    local artR = { x = r.x + pad, y = r.y + pad, w = r.w * 0.5 - pad * 1.5, h = r.h - pad * 2 }
    local art = p.boxArt and select(2, pcall(p.boxArt, t))
    if type(art) == "userdata" then
      local x, y, w, h = fit(artR, art:getWidth(), art:getHeight())
      lg.setColor(0, 0, 0, 0.18)
      lg.rectangle("fill", x + 3, y + 4, w, h)
      lg.setColor(1, 1, 1, 1)
      lg.draw(art, x, y, 0, w / art:getWidth(), h / art:getHeight())
    else
      lg.setColor(1, 1, 1, 1)
      lg.rectangle("fill", artR.x, artR.y, artR.w, artR.h, 8, 8)
      col(SYSTEMS[sys].frame)
      local f = ctx.font(artR.h * 0.1)
      lg.setFont(f)
      lg.printf(t.name or "", artR.x + 6, artR.y + artR.h * 0.4, artR.w - 12, "center")
    end
    local bx = r.x + r.w * 0.5 + pad * 0.5
    local bw = r.w * 0.5 - pad * 1.5
    local tf = ctx.font(r.h * 0.06)
    lg.setFont(tf)
    lg.setColor(0.2, 0.2, 0.24, 1)
    lg.printf(t.name or "", bx, r.y + pad, bw, "left")
    local sf = ctx.font(r.h * 0.045)
    lg.setFont(sf)
    lg.setColor(0.45, 0.46, 0.5, 1)
    lg.printf(({ gb = "Game Boy", gbc = "Game Boy Color", gba = "Game Boy Advance" })[sys] .. "  -  Virtual Console",
      bx, r.y + pad + tf:getHeight() * 2.3, bw, "left")
    local bh = r.h * 0.12
    local y = r.y + r.h - pad - bh * 4 - pad * 1.5
    for _, b in ipairs({ { "save", "Save" }, { "load", "Load" }, { "reset", "Reset" }, { "close", "Close" } }) do
      pill("vc:" .. b[1], bx, y, bw, bh, b[2], false)
      y = y + bh + pad * 0.5
    end
  end
  local m = p.menu and select(2, pcall(p.menu))
  if type(m) == "table" and m.open then drawMenu(r, m) end
  lg.pop()
end

---------------------------------------------------------------- input

local function hitAt(x, y)
  for k = #st.hits, 1, -1 do
    local h = st.hits[k]
    if x >= h.x and y >= h.y and x <= h.x + h.w and y <= h.y + h.h then return h end
  end
end

function EP.press(btn)
  local p = EP.active()
  if not p then return false end
  if p.press then pcall(p.press, btn) end
  return true
end

function EP.release(btn)
  local p = EP.active()
  if not p then return false end
  if p.release then pcall(p.release, btn) end
  return true
end

local function toScreen(x, y)
  local r = st.screenRect
  if not r then return nil end
  local u, v = (x - r.x) / r.w, (y - r.y) / r.h
  return math.max(0, math.min(1, u)), math.max(0, math.min(1, v)),
    u >= 0 and u <= 1 and v >= 0 and v <= 1
end

local function activate(p, id)
  if id:match("^menu:") then
    if p.menuDo then pcall(p.menuDo, id:sub(6)) end
    Sfx.play("select")
  elseif id == "vc:close" then
    Sfx.play("back")
    if p.stop then pcall(p.stop) end
  elseif id:match("^vc:") then
    Sfx.play("select")
    if p.menuDo then pcall(p.menuDo, id:sub(4)) end
  end
end

function EP.touch(phase, id, x, y)
  local p = EP.active()
  if not p then return false end
  local m = p.menu and select(2, pcall(p.menu))
  local menuOpen = type(m) == "table" and m.open
  if phase == "pressed" then
    local h = hitAt(x, y)
    local u, v, inside = toScreen(x, y)
    if not menuOpen and inside and p.touch then
      st.touches[id] = { game = true }
      pcall(p.touch, "pressed", u, v)
    else
      st.touches[id] = { hit = h and h.id }
    end
  elseif phase == "moved" then
    local tt = st.touches[id]
    if tt and tt.game and p.touch then
      local u, v = toScreen(x, y)
      if u then pcall(p.touch, "moved", u, v) end
    end
  else
    local tt = st.touches[id]
    st.touches[id] = nil
    if not tt then return true end
    if tt.game then
      if p.touch then
        local u, v = toScreen(x, y)
        pcall(p.touch, "released", u or 0, v or 0)
      end
    else
      local h = hitAt(x, y)
      if h and h.id == tt.hit then activate(p, h.id) end
    end
  end
  return true
end

function EP.init(context) ctx = context end

return EP
