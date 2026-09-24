-- The 3DS theme's HOME menu: the bottom screen as the 3DS draws it -- a
-- grid of icon tiles on the blue-grey wall, the selected one's name on the
-- cream bar under it, a status row (a coin with the ready games, the mods,
-- the clock, the battery) and the page buttons.  One tile per game and one
-- per launcher function (MODS, FIND, ONLINE, SKINS, IMPORT, Settings, save
-- sync, exit).  Tap a tile to select it, tap it again (or A) to open it;
-- the D-pad moves the selection.  An opened tile shows the launcher's own
-- page under a bar with a back button; back (or HOME) returns here.
--
-- Icons: fold3ds/icons3ds/<id>.png (square, any size) when present; else a
-- stand-in -- the game's cartridge colour and letter, or the function's
-- glyph on a white tile.
local H = {}

local lg = love.graphics
local DIR = "fold3ds/icons3ds/"

local GAME_NAMES = {
  red = "Pokémon Red", blue = "Pokémon Blue", green = "Pokémon Green",
  yellow = "Pokémon Yellow", gold = "Pokémon Gold", silver = "Pokémon Silver",
  crystal = "Pokémon Crystal", firered = "Pokémon FireRed", leafgreen = "Pokémon LeafGreen",
}
local GAME_COLORS = {
  red = { 232, 52, 60 }, blue = { 52, 110, 232 }, green = { 60, 170, 80 },
  yellow = { 250, 200, 20 }, gold = { 214, 150, 40 }, silver = { 180, 188, 200 },
  crystal = { 120, 196, 230 }, firered = { 220, 60, 40 }, leafgreen = { 60, 170, 90 },
}
local GAME_LETTERS = {
  red = "R", blue = "B", green = "G", yellow = "Y", gold = "G", silver = "S",
  crystal = "C", firered = "FR", leafgreen = "LG",
}
local FUNCS = {
  { id = "mods", name = "Mods", icon = "puzzle", color = { 246, 130, 20 }, tab = "mods" },
  { id = "find", name = "Find Mods", icon = "search", color = { 30, 136, 240 }, tab = "find" },
  { id = "online", name = "Online", icon = "globe", color = { 24, 120, 220 }, tab = "online" },
  { id = "skins", name = "Skins", icon = "paintbrush", color = { 236, 80, 150 }, tab = "skins" },
  { id = "importers", name = "Import", icon = "download", color = { 40, 170, 90 }, tab = "importers" },
  { id = "settings", name = "Settings", icon = "settings", color = { 110, 112, 120 }, modal = "settings" },
  { id = "sync", name = "Save Sync", icon = "arrow-left-right", color = { 20, 170, 170 }, modal = "sync" },
  { id = "exit", name = "Exit", icon = "x", color = { 226, 56, 60 }, exit = true },
}

local st = {
  open = nil,          -- the opened tile, or nil while the grid shows
  sel = 1,             -- selected tile index
  page = 1,
  big = false,         -- the grid button: 4 x 2 big tiles instead of 5 x 3
  images = {},
  hit = {},            -- this frame's tap targets
  drag = nil,          -- a finger on the grid { id, x0, y0, x, dragged }
  slide = 0,           -- the wall's sideways offset (follows a swipe, eases back)
  wallW = 1,
}
local ctx

local function col(c, a) lg.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1) end

local function icon(id)
  if st.images[id] == nil then
    local ok, img = pcall(lg.newImage, DIR .. id .. ".png")
    st.images[id] = ok and img or false
    if ok then img:setFilter("linear", "linear") end
  end
  return st.images[id] or nil
end

function H.tiles(imp)
  local out = {}
  local okGV, GV = pcall(require, "src.core.GameVersion")
  for _, v in ipairs(okGV and GV.ORDER or { "red", "blue", "yellow" }) do
    out[#out + 1] = { id = v, game = true, name = GAME_NAMES[v] or v,
      ready = imp and imp.ready and imp.ready[v] }
  end
  for _, f in ipairs(FUNCS) do
    if not (f.exit and imp and imp.ios) then out[#out + 1] = f end
  end
  return out
end

local function grid() if st.big then return 4, 2 end return 5, 3 end

function H.showing() return st.open == nil end
function H.opened() return st.open end

function H.init(context) ctx = context end

---------------------------------------------------------------- actions

local function openTile(imp, t)
  if not imp or not t then return end
  if t.exit then
    if imp._quitApp then imp:_quitApp() end
    return
  end
  st.open = t
  if t.game then
    if imp._switchTab then imp:_switchTab(t.id) end
  elseif t.tab then
    if imp._switchTab then imp:_switchTab(t.tab) end
  elseif t.modal == "settings" then
    if imp._openSettings then imp:_openSettings() end
  elseif t.modal == "sync" then
    if imp._openSync then imp:_openSync() end
  end
end

-- back to the grid, closing the Settings screen if it is what is open
function H.goHome(imp)
  if imp and imp._settings and imp._closeSettings then imp:_closeSettings() end
  st.open = nil
end

-- per frame: a tile that was a popup (Settings, Save Sync) is done when its
-- popup closes
function H.update(imp)
  local t = st.open
  if t and t.modal and imp then
    if t.modal == "settings" and not imp._settings then st.open = nil end
    if t.modal == "sync" and not imp._modalKey and (st.syncSeen or 0) > 2 then st.open = nil end
    st.syncSeen = t.modal == "sync" and (st.syncSeen or 0) + 1 or 0
  else
    st.syncSeen = 0
  end
end

---------------------------------------------------------------- drawing

local function roundRect(mode, x, y, w, h, r)
  lg.rectangle(mode, x, y, w, h, r, r, 12)
end

local function bevelBox(x, y, w, h, r, fill, edge)
  col({ 0, 0, 0 }, 0.18)
  roundRect("fill", x, y + h * 0.05, w, h, r)
  col(fill)
  roundRect("fill", x, y, w, h, r)
  col({ 255, 255, 255 }, 0.55)
  roundRect("fill", x + w * 0.06, y + h * 0.05, w * 0.88, h * 0.35, r * 0.7)
  col(fill)
  roundRect("fill", x + w * 0.04, y + h * 0.16, w * 0.92, h * 0.78, r * 0.8)
  lg.setLineWidth(math.max(1, h * 0.03))
  col(edge or { 150, 150, 150 })
  roundRect("line", x, y, w, h, r)
end

local function drawIcon(t, x, y, s)
  local img = icon(t.id)
  if img then
    local iw, ih = img:getDimensions()
    local k = math.min(s / iw, s / ih)
    lg.setColor(1, 1, 1, 1)
    lg.draw(img, x + (s - iw * k) / 2, y + (s - ih * k) / 2, 0, k, k)
    return
  end
  -- stand-ins
  if t.game then
    local c = GAME_COLORS[t.id] or { 150, 150, 160 }
    local r = s * 0.2
    col(c)
    roundRect("fill", x, y, s, s, r)
    col({ 255, 255, 255 }, 0.25)
    roundRect("fill", x + s * 0.08, y + s * 0.06, s * 0.84, s * 0.3, r * 0.6)
    -- a label window like a cartridge's
    col({ 255, 255, 255 }, 0.9)
    roundRect("fill", x + s * 0.18, y + s * 0.34, s * 0.64, s * 0.46, s * 0.06)
    col(c)
    local f = ctx.font(s * (#(GAME_LETTERS[t.id] or "?") > 1 and 0.26 or 0.34))
    lg.setFont(f)
    lg.printf(GAME_LETTERS[t.id] or "?", x + s * 0.18, y + s * 0.57 - f:getHeight() / 2, s * 0.64, "center")
    return
  end
  local okI, Icons = pcall(require, "src.ui.kit.Icons")
  col({ 255, 255, 255 })
  roundRect("fill", x, y, s, s, s * 0.2)
  lg.setLineWidth(math.max(1, s * 0.05))
  col(t.color)
  roundRect("line", x + s * 0.03, y + s * 0.03, s * 0.94, s * 0.94, s * 0.18)
  if okI then
    local c = t.color
    Icons.draw(t.icon, x + s * 0.18, y + s * 0.18, s * 0.64, { c[1], c[2], c[3] }, 1)
  end
end

-- the selection cursor: the HOME menu's corner brackets
local function brackets(x, y, w, h, t)
  local len = w * 0.26
  local th = math.max(2, w * 0.07)
  local pulse = 0.75 + 0.25 * math.sin(t * 5)
  lg.setColor(0.2, 0.86, 0.7, pulse)
  local pts = {
    { x, y, 1, 1 }, { x + w, y, -1, 1 }, { x, y + h, 1, -1 }, { x + w, y + h, -1, -1 },
  }
  for _, p in ipairs(pts) do
    lg.rectangle("fill", p[3] > 0 and p[1] or p[1] - len, p[4] > 0 and p[2] or p[2] - th, len, th, th / 2, th / 2)
    lg.rectangle("fill", p[3] > 0 and p[1] or p[1] - th, p[4] > 0 and p[2] or p[2] - len, th, len, th / 2, th / 2)
  end
end

local function button(id, x, y, w, h, fill, edge)
  bevelBox(x, y, w, h, h * 0.2, fill, edge)
  st.hit[#st.hit + 1] = { id = id, x = x, y = y, w = w, h = h }
end

local function triangle(cx, cy, s, dir, c)
  col(c)
  if dir < 0 then lg.polygon("fill", cx + s * 0.4, cy - s * 0.55, cx + s * 0.4, cy + s * 0.55, cx - s * 0.5, cy)
  else lg.polygon("fill", cx - s * 0.4, cy - s * 0.55, cx - s * 0.4, cy + s * 0.55, cx + s * 0.5, cy) end
end

function H.draw(r, imp, time)
  st.hit = {}
  local tiles = H.tiles(imp)
  local cols, rows = grid()
  local per = cols * rows
  local pages = math.max(1, math.ceil(#tiles / per))
  st.page = math.max(1, math.min(st.page, pages))
  st.sel = math.max(1, math.min(st.sel, #tiles))
  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)
  col({ 250, 250, 250 })
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  local pad = math.floor(r.w * 0.018)
  -- the wall: blue-grey, lighter at the top, with the faint empty slots
  local wallH = math.floor(r.h * 0.63)
  local wx, wy, ww = r.x + pad, r.y + pad, r.w - 2 * pad
  lg.stencil(function() roundRect("fill", wx, wy, ww, wallH, r.w * 0.025) end, "replace", 1)
  lg.setStencilTest("greater", 0)
  for i = 0, wallH do
    local k = i / wallH
    lg.setColor(0.64 - 0.14 * k, 0.68 - 0.13 * k, 0.75 - 0.12 * k, 1)
    lg.rectangle("fill", wx, wy + i, ww, 1)
  end
  local gap = ww * 0.022
  local cw = (ww - gap * (cols + 1)) / cols
  local ch = (wallH - gap * (rows + 1)) / rows
  local ts = math.min(cw, ch)
  st.wallW, st.wall = ww, { x = wx, y = wy, w = ww, h = wallH }
  -- ease a released swipe back into place
  if not (st.drag and st.drag.dragged) then st.slide = st.slide * 0.7 if math.abs(st.slide) < 0.5 then st.slide = 0 end end
  local function drawPage(page, off)
  for i = 0, per - 1 do
    local cx = wx + off + gap + (i % cols) * (cw + gap) + (cw - ts) / 2
    local cy = wy + gap + math.floor(i / cols) * (ch + gap) + (ch - ts) / 2
    lg.setColor(1, 1, 1, 0.13)
    roundRect("fill", cx, cy, ts, ts, ts * 0.2)
    local idx = (page - 1) * per + i + 1
    local t = tiles[idx]
    if t then
      -- the tile: white-grey frame around the icon
      local inset = ts * 0.1
      col({ 245, 245, 247 })
      roundRect("fill", cx, cy, ts, ts, ts * 0.2)
      col({ 170, 172, 178 })
      lg.setLineWidth(math.max(1, ts * 0.025))
      roundRect("line", cx, cy, ts, ts, ts * 0.2)
      drawIcon(t, cx + inset, cy + inset, ts - 2 * inset)
      if t.game and not t.ready then
        lg.setColor(0.2, 0.22, 0.28, 0.45)
        roundRect("fill", cx, cy, ts, ts, ts * 0.2)
      end
      if idx == st.sel then brackets(cx - ts * 0.08, cy - ts * 0.08, ts * 1.16, ts * 1.16, time) end
      if off == 0 then st.hit[#st.hit + 1] = { id = "tile", idx = idx, x = cx, y = cy, w = ts, h = ts } end
    end
  end
  end
  local off = math.floor(st.slide)
  st.selShown = math.floor((st.sel - 1) / per) + 1 == st.page
  drawPage(st.page, off)
  -- the neighbours slide in beside it (wrapping, like the page buttons)
  if off > 0 then drawPage((st.page - 2) % pages + 1, off - ww) end
  if off < 0 then drawPage(st.page % pages + 1, off + ww) end
  -- page dots over the wall's foot
  if pages > 1 then
    local dr = math.max(2, wallH * 0.018)
    for p = 1, pages do
      lg.setColor(1, 1, 1, p == st.page and 0.95 or 0.4)
      lg.circle("fill", wx + ww / 2 + (p - (pages + 1) / 2) * dr * 4, wy + wallH - dr * 2.2, dr)
    end
  end
  lg.setStencilTest()
  -- the name bar
  local by = wy + wallH + math.floor(r.h * 0.015)
  local bh = math.floor(r.h * 0.115)
  col({ 243, 241, 232 })
  roundRect("fill", wx, by, ww, bh, bh * 0.2)
  lg.setLineWidth(math.max(1, bh * 0.03))
  col({ 170, 168, 160 })
  roundRect("line", wx, by, ww, bh, bh * 0.2)
  local t = tiles[st.sel]
  local f = ctx.font(bh * 0.52)
  lg.setFont(f)
  col({ 70, 70, 72 })
  local name = t and t.name or ""
  if t and t.game and not t.ready then name = name .. "  (import the ROM)" end
  lg.printf(name, wx, by + (bh - f:getHeight()) / 2, ww, "center")
  -- the status row: cyan bar, a coin with the ready games, mods, clock, battery
  local sy = by + bh + math.floor(r.h * 0.022)
  local sh = math.floor(r.h * 0.075)
  col({ 20, 200, 225 })
  roundRect("fill", wx, sy, ww * 0.3, sh, sh / 2)
  col({ 90, 235, 250 })
  roundRect("fill", wx + sh * 0.2, sy + sh * 0.15, ww * 0.3 - sh * 0.4, sh * 0.35, sh * 0.2)
  local ready = 0
  for _, tt in ipairs(tiles) do if tt.game and tt.ready then ready = ready + 1 end end
  local coinX = wx + ww * 0.34
  col({ 240, 196, 30 })
  lg.circle("fill", coinX + sh / 2, sy + sh / 2, sh / 2)
  col({ 255, 226, 90 })
  lg.circle("fill", coinX + sh / 2, sy + sh / 2, sh * 0.36)
  local sf = ctx.font(sh * 0.8)
  lg.setFont(sf)
  col({ 70, 70, 72 })
  lg.print(tostring(ready), coinX + sh * 1.2, sy + (sh - sf:getHeight()) / 2)
  local mods = imp and imp.mods and #imp.mods or 0
  local clock = os.date("%H:%M")
  local pw = ww * 0.42
  local px = wx + ww - pw
  col({ 120, 122, 128 })
  roundRect("fill", px, sy, pw, sh, sh * 0.3)
  col({ 255, 255, 255 })
  local status = ("%d Mods   %s"):format(mods, clock)
  lg.printf(status, px, sy + (sh - sf:getHeight()) / 2, pw - sh * 1.6, "center")
  -- battery
  local bx, bw2 = px + pw - sh * 1.5, sh * 1.2
  local pct = 1
  if love.system.getPowerInfo then
    local _, p = love.system.getPowerInfo()
    if p then pct = p / 100 end
  end
  col({ 255, 255, 255 })
  roundRect("fill", bx, sy + sh * 0.2, bw2, sh * 0.6, sh * 0.1)
  col({ 20, 200, 225 })
  lg.rectangle("fill", bx + sh * 0.08, sy + sh * 0.28, (bw2 - sh * 0.16) * pct, sh * 0.44)
  -- page buttons: < 1 2 ... > and the grid-size button
  local ry = sy + sh + math.floor(r.h * 0.022)
  local rh = r.y + r.h - pad - ry
  local bw = rh * 1.2
  button("prev", wx, ry, bw, rh, { 238, 236, 226 }, { 150, 150, 146 })
  triangle(wx + bw / 2, ry + rh / 2, rh * 0.4, -1, { 50, 50, 52 })
  local gridW = rh * 1.3
  button("grid", wx + ww - gridW, ry, gridW, rh, { 70, 72, 78 }, { 40, 40, 44 })
  col({ 255, 255, 255 })
  local q = rh * 0.2
  for i = 0, 1 do for j = 0, 1 do
    lg.rectangle("fill", wx + ww - gridW / 2 - q * 1.1 + i * q * 1.2, ry + rh / 2 - q * 1.1 + j * q * 1.2, q, q, q * 0.2)
  end end
  local nextX = wx + ww - gridW - gap - bw
  button("next", nextX, ry, bw, rh, { 238, 236, 226 }, { 150, 150, 146 })
  triangle(nextX + bw / 2, ry + rh / 2, rh * 0.4, 1, { 50, 50, 52 })
  local nx0, nx1 = wx + bw + gap, nextX - gap
  local nw = math.min(rh * 1.1, (nx1 - nx0 - gap * (pages - 1)) / pages)
  local nf = ctx.font(rh * 0.55)
  lg.setFont(nf)
  for p = 1, pages do
    local x = nx0 + (p - 1) * (nw + gap)
    local on = p == st.page
    button("page" .. p, x, ry, nw, rh, on and { 150, 240, 180 } or { 238, 236, 226 },
      on and { 40, 190, 90 } or { 150, 150, 146 })
    col(on and { 20, 110, 50 } or { 50, 50, 52 })
    lg.printf(tostring(p), x, ry + (rh - nf:getHeight()) / 2, nw, "center")
  end
  lg.pop()
end

-- the bar over an opened tile: a back button and the tile's name
function H.barHeight(r) return math.floor(r.h * 0.14) end

function H.drawBar(r)
  local t = st.open
  if not t then return end
  st.barHit = nil
  lg.push("all")
  local h = H.barHeight(r)
  col({ 250, 250, 250 })
  lg.rectangle("fill", r.x, r.y, r.w, h)
  local pad = math.floor(h * 0.12)
  local bw = h * 1.25
  bevelBox(r.x + pad, r.y + pad, bw, h - 2 * pad, (h - 2 * pad) * 0.22, { 238, 236, 226 }, { 150, 150, 146 })
  triangle(r.x + pad + bw / 2, r.y + h / 2, (h - 2 * pad) * 0.42, -1, { 50, 50, 52 })
  st.barHit = { x = r.x + pad, y = r.y + pad, w = bw, h = h - 2 * pad }
  local tx = r.x + pad * 2 + bw
  col({ 243, 241, 232 })
  roundRect("fill", tx, r.y + pad, r.x + r.w - pad - tx, h - 2 * pad, (h - 2 * pad) * 0.22)
  lg.setLineWidth(1)
  col({ 170, 168, 160 })
  roundRect("line", tx, r.y + pad, r.x + r.w - pad - tx, h - 2 * pad, (h - 2 * pad) * 0.22)
  local f = ctx.font((h - 2 * pad) * 0.5)
  lg.setFont(f)
  col({ 70, 70, 72 })
  lg.printf(t.name, tx, r.y + (h - f:getHeight()) / 2, r.x + r.w - pad - tx, "center")
  lg.pop()
end

---------------------------------------------------------------- input

local function inside(h, x, y) return x >= h.x and y >= h.y and x <= h.x + h.w and y <= h.y + h.h end

local SWIPE_SLOP = 12

local function turnPage(imp, dir)
  local tiles = H.tiles(imp)
  local cols, rows = grid()
  local per = cols * rows
  local pages = math.max(1, math.ceil(#tiles / per))
  if pages < 2 then return end
  -- the selection stays where it was, as on a 3DS: a tap after a swipe
  -- selects, it never opens something unseen
  st.page = (st.page - 1 + dir) % pages + 1
end

-- A finger on the grid screen.  On the wall it can swipe left / right to
-- turn the page (the wall follows it); a short touch is a tap.
function H.pressed(imp, id, x, y)
  st.drag = { id = id, x0 = x, y0 = y, x = x, onWall = st.wall and x >= st.wall.x and x <= st.wall.x + st.wall.w
    and y >= st.wall.y and y <= st.wall.y + st.wall.h }
  return true
end

function H.moved(imp, id, x, y)
  local d = st.drag
  if not d or d.id ~= id then return false end
  d.x = x
  if d.onWall and math.abs(x - d.x0) > SWIPE_SLOP then d.dragged = true end
  if d.dragged then st.slide = x - d.x0 end
  return true
end

function H.released(imp, id, x, y)
  local d = st.drag
  if not d or d.id ~= id then return false end
  st.drag = nil
  if d.dragged then
    local dx = x - d.x0
    if math.abs(dx) > st.wallW * 0.18 then
      local dir = dx < 0 and 1 or -1
      turnPage(imp, dir)
      -- the new page starts where the finger left the old one's neighbour
      st.slide = dx + (dir > 0 and st.wallW or -st.wallW)
    end
    return true
  end
  return H.tap(imp, d.x0, d.y0)
end

-- a tap on the grid screen; true when it landed on something
function H.tap(imp, x, y)
  for _, h in ipairs(st.hit) do
    if inside(h, x, y) then
      local tiles = H.tiles(imp)
      local cols, rows = grid()
      local pages = math.max(1, math.ceil(#tiles / (cols * rows)))
      if h.id == "tile" then
        if st.sel == h.idx and st.selShown then openTile(imp, tiles[h.idx]) else st.sel = h.idx end
      elseif h.id == "prev" then
        turnPage(imp, -1)
        st.slide = -st.wallW * 0.5
      elseif h.id == "next" then
        turnPage(imp, 1)
        st.slide = st.wallW * 0.5
      elseif h.id == "grid" then
        st.big = not st.big
        local per = st.big and 8 or 15
        st.page = math.floor((st.sel - 1) / per) + 1
      elseif h.id:match("^page") then
        st.page = tonumber(h.id:sub(5))
      end
      return true
    end
  end
  return false
end

function H.tapBar(imp, x, y)
  if st.open and st.barHit and inside(st.barHit, x, y) then
    H.goHome(imp)
    return true
  end
  return false
end

-- shell buttons on the grid: the d-pad / circle pad move, A opens
function H.button(imp, name)
  local tiles = H.tiles(imp)
  local cols, rows = grid()
  local per = cols * rows
  local s = st.sel
  if name == "a" then openTile(imp, tiles[s]) return true end
  if name == "left" then s = s - 1
  elseif name == "right" then s = s + 1
  elseif name == "up" then s = s - cols
  elseif name == "down" then s = s + cols
  else return false end
  st.sel = math.max(1, math.min(#tiles, s))
  local page = math.floor((st.sel - 1) / per) + 1
  if page ~= st.page then st.slide = (page > st.page and 0.5 or -0.5) * st.wallW end
  st.page = page
  return true
end

return H
