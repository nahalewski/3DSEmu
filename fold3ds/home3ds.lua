-- The 3DS theme's HOME menu, as the 3DS draws its bottom screen:
--
--   * the applet bar across the top -- Camera, Download Play, Settings, Mods, Find, Online,
--     Skins, Import, Save Sync, Exit -- with the two icon-size buttons on its
--     right;
--   * the icon grid: one tile per game, laid out in columns (down, then
--     across) on one strip that scrolls sideways under a finger (with a
--     flick's momentum) or the d-pad;
--   * at one row, the selected tile's name in a speech bubble above it;
--   * the play meter: the blue bar fills with time spent in the app, and
--     every 12 hours it fills it pays a coin and starts over (up to 99999
--     coins, kept in fold3ds_coins.cfg);
--   * the Manual / Open bar across the bottom.
--
-- Sizes: 1 row of 4 across up to 5 rows of 9 across (the size buttons, a
-- pinch, or X / Y).  Changing size animates: every tile glides and scales
-- from its old slot to its new one, and the empty slots cross-fade.
-- Rearranging: hold a tile until it lifts, drag it to a new slot (the strip
-- scrolls at the edges), let go.  Order and size are remembered
-- (fold3ds_home.cfg).
--
-- Tap a tile to select it, tap it again (or A / Open) to open it.  An
-- opened tile shows the launcher's page under a back bar; back, B or HOME
-- return here.  Icons: fold3ds/icons3ds/<id>.png, else a drawn stand-in.
--
-- Emulators (fold3ds.emus -- Azahar, and any other built in): every game in
-- an emulator's library is a tile too (its own icon; Open plays it, Manual
-- shows its options), and each emulator's folder holds an icon per settings
-- page and tool.  An
-- open folder shows its icons on the grid, a Close Folder tile first; B,
-- HOME or that tile close it.
local H = {}

local lg = love.graphics
local DIR = "fold3ds/icons3ds/"
local CFG = "fold3ds_home.cfg"

-- rows -> icons across, the five sizes
local LEVELS = { { rows = 1, cols = 4 }, { rows = 2, cols = 5 }, { rows = 3, cols = 6 },
                 { rows = 4, cols = 8 }, { rows = 5, cols = 9 } }
local ANIM = 0.32            -- resize, seconds
local HOLD = 0.45            -- press this long to lift a tile
local SLOP = 10              -- finger travel that makes a drag

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
-- the applet bar (always there, not rearranged)
local APPLETS = {
  { id = "camera", name = "Camera", camera = true },
  { id = "downloadplay", name = "Download Play", dlplay = true },
  { id = "eshop", name = "Nintendo eShop", eshop = true },
  { id = "activity", name = "Activity Log", activity = true },
  { id = "friends", name = "Friend List", app = true },
  { id = "gamenotes", name = "Game Notes", app = true },
  { id = "settings", name = "Settings", icon = "settings", color = { 70, 140, 220 }, modal = "settings" },
  { id = "mods", name = "Mods", icon = "puzzle", color = { 236, 176, 30 }, tab = "mods" },
  { id = "find", name = "Find Mods", icon = "search", color = { 246, 130, 40 }, tab = "find" },
  { id = "online", name = "Online", icon = "globe", color = { 30, 170, 170 }, tab = "online" },
  { id = "skins", name = "Skins", icon = "paintbrush", color = { 40, 130, 230 }, tab = "skins" },
  { id = "importers", name = "Import", icon = "download", color = { 90, 180, 60 }, tab = "importers" },
  { id = "sync", name = "Save Sync", icon = "arrow-left-right", color = { 20, 170, 170 }, modal = "sync" },
  { id = "exit", name = "Exit", icon = "x", color = { 226, 56, 60 }, exit = true },
}

-- the play meter: seconds toward the next coin, and the coins
local COIN_FILE = "fold3ds_coins.cfg"
local COIN_SECONDS = 12 * 60 * 60
local COIN_MAX = 99999
local coins = { seconds = 0, count = 0, dirty = 0, loaded = false }

local st = {
  open = nil,          -- the opened tile, or nil while the grid shows
  sel = 1,             -- selected index in the ordered tiles
  level = 3, prevLevel = 3, animAt = -10,
  scroll = 0, prevScroll = 0,   -- grid strip offset (px) at level / prevLevel
  vel = 0,             -- flick momentum, px / s
  order = nil,         -- tile ids in grid order
  images = {},
  hit = {},
  touches = {},        -- id -> { x0, y0, x, y, t0, kind, ... }
  lift = nil,          -- the tile being rearranged { id, x, y }
  disp = {},           -- tile id -> displayed { x, y, s } (eased)
  lastT = nil,
  pinch = nil,
}
local ctx
local Sfx = require("fold3ds.sfx")
local Emus = require("fold3ds.emus")

local function col(c, a) lg.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function now() return love.timer.getTime() end
local function ease(t) t = clamp(t, 0, 1) return 1 - (1 - t) ^ 3 end

local function icon(id)
  if st.images[id] == nil then
    local ok, img = pcall(lg.newImage, DIR .. id .. ".png")
    st.images[id] = ok and img or false
    if ok then img:setFilter("linear", "linear") end
  end
  return st.images[id] or nil
end

---------------------------------------------------------------- persistence

local function load()
  local ok, text = pcall(love.filesystem.read, CFG)
  text = ok and type(text) == "string" and text or ""
  local lv = tonumber(text:match("level=(%d)"))
  if lv and LEVELS[lv] then st.level, st.prevLevel = lv, lv end
  -- new games arrive wrapped as presents (the 3DS's new software): the
  -- ones still wrapped, and every game ever seen
  st.gifts, st.known = {}, {}
  st.knownLoaded = text:match("known=") ~= nil
  for id in (text:match("gifts=([%w_,]*)") or ""):gmatch("[%w_]+") do st.gifts[id] = true end
  for id in (text:match("known=([%w_,]*)") or ""):gmatch("[%w_]+") do st.known[id] = true end
  local order = text:match("order=([%w_,]+)")
  if order then
    st.order = {}
    for id in order:gmatch("[%w_]+") do st.order[#st.order + 1] = id end
  end
end

local function idList(set)
  local out = {}
  for id in pairs(set or {}) do out[#out + 1] = id end
  table.sort(out)
  return table.concat(out, ",")
end

local function save()
  pcall(love.filesystem.write, CFG, ("level=%d\norder=%s\ngifts=%s\nknown=%s\n"):format(st.level,
    table.concat(st.order or {}, ","), idList(st.gifts), idList(st.known)))
end

---------------------------------------------------------------- tiles

local function allTiles(imp)
  local byId, ids = {}, {}
  local okGV, GV = pcall(require, "src.core.GameVersion")
  for _, v in ipairs(okGV and GV.ORDER or { "red", "blue", "yellow" }) do
    byId[v] = { id = v, game = true, name = GAME_NAMES[v] or v,
      ready = imp and imp.ready and imp.ready[v] }
    ids[#ids + 1] = v
  end
  -- every emulator (fold3ds.emus): its folder of settings and tools, its
  -- set-up tile until it is set up, its games, its add-games tile
  Emus.addTiles(function(id, t)
    if not byId[id] then byId[id] = t; ids[#ids + 1] = id end
  end)
  return byId, ids
end

-- the open folder's tiles: Close Folder, then its icons
local CLOSE = { id = "folder_close", close = true, name = "Close Folder", sub = "Back to the HOME Menu" }
local function folderTiles(folder)
  local out = { CLOSE }
  for _, it in ipairs(folder.items or {}) do out[#out + 1] = it end
  return out
end

-- the tiles in the player's order (new tiles join at the end)
function H.tiles(imp)
  if st.folder then return folderTiles(st.folder) end
  local byId, ids = allTiles(imp)
  local out, seen = {}, {}
  for _, id in ipairs(st.order or {}) do
    if byId[id] and not seen[id] then out[#out + 1] = byId[id]; seen[id] = true end
  end
  for _, id in ipairs(ids) do
    if not seen[id] then out[#out + 1] = byId[id] end
  end
  local order = {}
  for i, t in ipairs(out) do order[i] = t.id end
  st.order = order
  -- a game never seen before arrives wrapped (not on the very first run:
  -- the library already there is simply there)
  st.gifts, st.known, st.arrive = st.gifts or {}, st.known or {}, st.arrive or {}
  local changed, arrived = false, false
  for _, t in ipairs(out) do
    if (t.emuGame or t.game) and not st.known[t.id] then
      st.known[t.id] = true
      changed = true
      if st.knownLoaded then
        st.gifts[t.id] = true
        st.arrive[t.id] = now() + (arrived and 0.15 or 0)
        arrived = true
      end
    end
  end
  if changed then
    st.knownLoaded = true
    save()
    if arrived then Sfx.play("newapp") end
  end
  return out
end

function H.showing() return st.open == nil end
-- the applet the d-pad has picked on the bar, if any (its banner shows on top)
function H.barFocus() return st.bar and APPLETS[st.bar] and APPLETS[st.bar].id or nil end
function H.opened() return st.open end
function H.folderOpen() return st.folder ~= nil end
---------------------------------------------------------------- play meter

local function loadCoins()
  coins.loaded = true
  local ok, text = pcall(love.filesystem.read, COIN_FILE)
  text = ok and type(text) == "string" and text or ""
  coins.seconds = tonumber(text:match("seconds=([%d%.]+)")) or 0
  coins.count = math.min(COIN_MAX, math.floor(tonumber(text:match("coins=(%d+)")) or 0))
end

local function saveCoins()
  pcall(love.filesystem.write, COIN_FILE,
    ("seconds=%.1f\ncoins=%d\n"):format(coins.seconds, coins.count))
  coins.dirty = 0
end

-- every frame the app runs (launcher or game): the meter fills; a full
-- meter pays a coin and starts over.  Saved every half minute and on quit.
function H.tick(dt)
  if not coins.loaded then loadCoins() end
  dt = math.max(0, math.min(dt or 0, 1))
  coins.seconds = coins.seconds + dt
  while coins.seconds >= COIN_SECONDS do
    coins.seconds = coins.seconds - COIN_SECONDS
    if coins.count < COIN_MAX then Sfx.play("coin") end
    coins.count = math.min(COIN_MAX, coins.count + 1)
  end
  coins.dirty = coins.dirty + dt
  if coins.dirty >= 30 then saveCoins() end
end

function H.saveCoins() if coins.loaded then saveCoins() end end
function H.coins() return coins.count, coins.seconds / COIN_SECONDS end

function H.init(context) ctx = context; load(); loadCoins(); Emus.init() end

---------------------------------------------------------------- actions

local function selectTile(imp, t)
  -- the top screen follows the selected game, as the 3DS shows its banner
  if t and t.game and imp and imp.tab ~= t.id then imp.tab = t.id end
end

local function closeFolder()
  if not st.folder then return end
  st.folder = nil
  st.folderAt = now()
  st.sel, st.scroll, st.vel = st.mainSel or 1, st.mainScroll or 0, 0
  st.disp = {}
end

local UNWRAP = 1.0
local function openTile(imp, t)
  if not imp or not t then return end
  -- a present: the first open unwraps it, the next one starts the game
  if st.gifts and st.gifts[t.id] then
    if not (st.unwrap and st.unwrap.id == t.id) then
      st.unwrap = { id = t.id, t0 = now() }
      Sfx.play("gift")
    end
    return
  end
  -- the Azahar folder, its icons and the 3DS games
  if t.folder then
    Sfx.play("open")
    st.folder = t
    st.folderAt = now()
    st.mainSel, st.mainScroll = st.sel, st.scroll
    st.sel, st.scroll, st.vel = 2, 0, 0
    st.disp = {}
    return
  end
  if t.close then Sfx.play("back"); closeFolder() return end
  if t.url and t.emu then Sfx.play("open"); Emus.open(t) return end
  if t.emuGame then Sfx.play("open"); Emus.play(t) return end
  Sfx.play("open")
  if t.exit then
    if imp._quitApp then imp:_quitApp() end
    return
  end
  if t.camera then
    if ctx.openCamera then ctx.openCamera() end
    return
  end
  if t.dlplay then
    if ctx.openDlplay then ctx.openDlplay() end
    return
  end
  if t.eshop then
    if ctx.openEshop then ctx.openEshop() end
    return
  end
  if t.activity then
    if ctx.openActivity then ctx.openActivity() end
    return
  end
  if t.app then
    if ctx.openApp then ctx.openApp(t.id) end
    return
  end
  st.open = t
  if t.game or t.tab then
    if imp._switchTab then imp:_switchTab(t.tab or t.id) end
  elseif t.modal == "settings" then
    if imp._openSettings then imp:_openSettings() end
  elseif t.modal == "sync" then
    if imp._openSync then imp:_openSync() end
  end
end

-- Manual: the game's manage page (ROM, saves, carts)
local function manual(imp, t)
  if t and t.emuGame then
    if Emus.hasManual(t) then Sfx.play("open"); Emus.manual(t) end
    return
  end
  if not imp or not t or not t.game then return end
  openTile(imp, t)
  imp._gameManage = t.id
end

-- open an applet on the bar by its id (the eShop's Open goes to Mods)
function H.openApplet(imp, id)
  for _, a in ipairs(APPLETS) do
    if a.id == id then openTile(imp, a) return true end
  end
  return false
end

function H.goHome(imp, quiet)
  if imp and imp._settings and imp._closeSettings then imp:_closeSettings() end
  if st.open and not quiet then Sfx.play("back") end
  st.open = nil
  closeFolder()
end

-- the selected tile when it is not one of the recomp games (the top screen
-- shows it instead of a cartridge), and opening it from there
function H.topTile(imp)
  if st.open then return nil end
  local t = H.tiles(imp)[st.sel]
  if t and not t.game then return t end
  return nil
end

function H.openSelected(imp)
  local t = H.tiles(imp)[st.sel]
  if t then openTile(imp, t) end
end

function H.update(imp)
  Emus.poll(now())
  local t = st.open
  if t and t.modal and imp then
    if t.modal == "settings" and not imp._settings then st.open = nil end
    if t.modal == "sync" and not imp._modalKey and (st.syncSeen or 0) > 2 then st.open = nil end
    st.syncSeen = t.modal == "sync" and (st.syncSeen or 0) + 1 or 0
  else
    st.syncSeen = 0
  end
  -- a finger held still on a tile lifts it for rearranging
  for id, tc in pairs(st.touches) do
    if tc.kind == "tile" and not tc.moved and not st.lift and not st.folder and now() - tc.t0 >= HOLD then
      tc.kind = "lift"
      st.lift = { id = tc.tileId, x = tc.x, y = tc.y, touch = id }
      Sfx.play("grab")
      st.sel = tc.idx
    end
  end
end

---------------------------------------------------------------- layout

-- The grid's geometry at a level inside grid rect g.  One row leaves room
-- above for the name bubble.
local function geometry(level, g)
  local L = LEVELS[level]
  local top = g.y
  local h = g.h
  if L.rows == 1 then top = g.y + g.h * 0.36; h = g.h * 0.64 end
  local pitchX = g.w / (L.cols + 0.35)
  local pitchY = h / L.rows
  local ts = math.min(pitchX, pitchY) * 0.84
  local y0 = top + (h - pitchY * L.rows) / 2 + (pitchY - ts) / 2
  local x0 = g.x + pitchX * 0.35
  return { rows = L.rows, pitchX = pitchX, pitchY = pitchY, ts = ts, x0 = x0, y0 = y0, top = top, h = h }
end

local function slotPos(G, i, scroll)
  local c = math.floor((i - 1) / G.rows)
  local r = (i - 1) % G.rows
  return G.x0 + c * G.pitchX - scroll, G.y0 + r * G.pitchY
end

local function maxScroll(G, n, g)
  local ncols = math.ceil(n / G.rows)
  return math.max(0, G.x0 - g.x + ncols * G.pitchX + G.pitchX * 0.35 - g.w)
end

-- keep the selected tile on screen
local function reveal(G, n, g)
  local x = slotPos(G, st.sel, 0)
  local lo = x + G.ts + G.pitchX * 0.35 - (g.x + g.w)
  local hi = x - G.pitchX * 0.35 - g.x
  st.scroll = clamp(clamp(st.scroll, lo, hi), 0, maxScroll(G, n, g))
end

local function setLevel(lv, g, n)
  lv = clamp(lv, 1, #LEVELS)
  if lv == st.level then Sfx.play("edge") return end
  Sfx.play(lv < st.level and "zoomIn" or "zoomOut")
  -- the selected tile stays where it is on screen while everything reflows
  local Gold = geometry(st.level, g)
  local sx = slotPos(Gold, st.sel, st.scroll)
  st.prevLevel, st.prevScroll = st.level, st.scroll
  st.level, st.animAt = lv, now()
  local Gnew = geometry(lv, g)
  local nx = slotPos(Gnew, st.sel, 0)
  st.scroll = clamp(nx - sx, 0, maxScroll(Gnew, n, g))
  st.vel = 0
  save()
end

---------------------------------------------------------------- drawing

local function roundRect(mode, x, y, w, h, r)
  lg.rectangle(mode, x, y, w, h, r, r, 12)
end

local function drawIcon(t, x, y, s)
  local img = t.emuGame and Emus.icon(t) or icon(t.id)
  if img then
    local iw, ih = img:getDimensions()
    local k = math.min(s / iw, s / ih)
    lg.setColor(1, 1, 1, 1)
    lg.draw(img, x + (s - iw * k) / 2, y + (s - ih * k) / 2, 0, k, k)
    return
  end
  if t.game then
    local c = GAME_COLORS[t.id] or { 150, 150, 160 }
    local r = s * 0.12
    col(c)
    roundRect("fill", x, y, s, s, r)
    col({ 255, 255, 255 }, 0.25)
    roundRect("fill", x + s * 0.06, y + s * 0.05, s * 0.88, s * 0.3, r * 0.6)
    col({ 255, 255, 255 }, 0.92)
    roundRect("fill", x + s * 0.16, y + s * 0.34, s * 0.68, s * 0.48, s * 0.06)
    col(c)
    local letters = GAME_LETTERS[t.id] or "?"
    local f = ctx.font(s * (#letters > 1 and 0.28 or 0.36))
    lg.setFont(f)
    lg.printf(letters, x + s * 0.16, y + s * 0.58 - f:getHeight() / 2, s * 0.68, "center")
    return
  end
  if t.emuGame or t.url or t.folder or t.close then
    -- a 3DS game without an icon, or an Azahar icon not drawn yet: a
    -- rounded square with the first letter
    local c = t.emuGame and { 206, 32, 40 } or { 70, 140, 220 }
    col(c)
    roundRect("fill", x, y, s, s, s * 0.18)
    col({ 255, 255, 255 }, 0.25)
    roundRect("fill", x + s * 0.06, y + s * 0.05, s * 0.88, s * 0.3, s * 0.1)
    col({ 255, 255, 255 })
    local f = ctx.font(s * 0.42)
    lg.setFont(f)
    lg.printf(Emus.initial(t.name), x, y + (s - f:getHeight()) / 2, s, "center")
    return
  end
  local okI, Icons = pcall(require, "src.ui.kit.Icons")
  if okI then Icons.draw(t.icon, x + s * 0.12, y + s * 0.12, s * 0.76, t.color, 1) end
end

-- draw a tile's icon by its id (the Activity Log's rows); false if unknown
function H.drawIconFor(imp, id, x, y, s)
  for _, t in ipairs(H.tiles(imp)) do
    if t.id == id then drawIcon(t, x, y, s) return true end
  end
  return false
end

-- the white tile the icon sits in, with its soft shadow
-- the present's wrapping: a paper colour of its own per game
local PAPERS = { { 232, 58, 76 }, { 52, 132, 228 }, { 248, 184, 36 }, { 64, 184, 104 }, { 168, 86, 216 },
                 { 240, 120, 40 } }
local function paperFor(id)
  local h = 0
  for i = 1, #id do h = (h * 31 + id:byte(i)) % 997 end
  return PAPERS[h % #PAPERS + 1], h
end

-- a wrapped present in the tile's square: paper with its stripes, the
-- ribbon both ways, the bow on top.  open 0..1: the bow and ribbon fly
-- off and the paper bursts away in four pieces
local function drawPresent(id, x, y, ts, alpha, open)
  local paper, h = paperFor(id)
  local r = ts * 0.2
  local cx, cy = x + ts / 2, y + ts / 2
  local k = open or 0
  local fade = alpha * (1 - clamp((k - 0.2) / 0.6, 0, 1))
  if fade <= 0 then return end
  -- the paper: four quarters, each flying out from the centre when opened
  local fly = ease(clamp(k / 0.8, 0, 1)) * ts * 0.9
  for qi, q in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
    lg.push()
    lg.translate(cx + q[1] * fly, cy + q[2] * fly * 0.8 + (k > 0 and (k * k) * ts * 0.6 or 0))
    lg.rotate(q[1] * k * 1.6 + (qi % 2 == 0 and 0.3 or -0.3) * k)
    lg.stencil(function() lg.rectangle("fill", q[1] < 0 and -ts / 2 or 0, q[2] < 0 and -ts / 2 or 0, ts / 2, ts / 2) end,
      "replace", 1)
    lg.setStencilTest("greater", 0)
    col(paper, fade)
    roundRect("fill", -ts / 2, -ts / 2, ts, ts, r)
    -- stripes
    col({ 255, 255, 255 }, 0.22 * fade)
    for i = -3, 3 do
      local sx = i * ts * 0.22 + (h % 7) * 0.01 * ts
      lg.polygon("fill", sx - ts * 0.04, -ts / 2, sx + ts * 0.05, -ts / 2, sx - ts * 0.35, ts / 2, sx - ts * 0.44, ts / 2)
    end
    -- the ribbon on the paper
    col({ 255, 236, 150 }, fade)
    lg.rectangle("fill", -ts * 0.07, -ts / 2, ts * 0.14, ts)
    lg.rectangle("fill", -ts / 2, -ts * 0.07, ts, ts * 0.14)
    col({ 220, 170, 40 }, fade)
    lg.rectangle("fill", ts * 0.045, -ts / 2, ts * 0.025, ts)
    lg.rectangle("fill", -ts / 2, ts * 0.045, ts, ts * 0.025)
    lg.setStencilTest()
    lg.pop()
  end
  -- the bow, lifting off first
  local bowUp = ease(clamp(k / 0.5, 0, 1)) * ts * 1.1
  local bx, by = cx, y + ts * 0.14 - bowUp
  local ba = alpha * (1 - clamp((k - 0.1) / 0.4, 0, 1))
  if ba > 0 then
    lg.push()
    lg.translate(bx, by)
    lg.rotate(k * 2.5)
    col({ 255, 226, 110 }, ba)
    lg.ellipse("fill", -ts * 0.14, 0, ts * 0.15, ts * 0.09)
    lg.ellipse("fill", ts * 0.14, 0, ts * 0.15, ts * 0.09)
    col({ 230, 180, 50 }, ba)
    lg.ellipse("fill", -ts * 0.14, 0, ts * 0.07, ts * 0.04)
    lg.ellipse("fill", ts * 0.14, 0, ts * 0.07, ts * 0.04)
    col({ 250, 210, 80 }, ba)
    lg.circle("fill", 0, 0, ts * 0.065)
    lg.pop()
  end
  -- a soft sheen over the wrapped box
  if k == 0 then
    lg.setColor(1, 1, 1, 0.16 * alpha)
    roundRect("fill", x + ts * 0.06, y + ts * 0.05, ts * 0.88, ts * 0.32, r * 0.8)
  end
end

-- confetti bursting out of an opened present
local function drawConfetti(id, x, y, ts, k)
  if k <= 0.25 or k >= 1 then return end
  local _, h = paperFor(id)
  local p = (k - 0.25) / 0.75
  for i = 1, 16 do
    local a = (i / 16) * math.pi * 2 + (h % 10) * 0.1
    local sp = ts * (0.7 + ((i * 37 + h) % 10) * 0.05)
    local px = x + ts / 2 + math.cos(a) * sp * p
    local py = y + ts / 2 + math.sin(a) * sp * p * 0.8 + p * p * ts * 0.8
    col(PAPERS[(i + h) % #PAPERS + 1], 1 - p)
    lg.push()
    lg.translate(px, py)
    lg.rotate(p * 8 + i)
    lg.rectangle("fill", -ts * 0.03, -ts * 0.015, ts * 0.06, ts * 0.03)
    lg.pop()
  end
end

local function drawTile(t, x, y, ts, alpha, lifted)
  local gift = st.gifts and st.gifts[t.id]
  local un = st.unwrap and st.unwrap.id == t.id and st.unwrap or nil
  local ka = st.arrive and st.arrive[t.id]
  -- arriving: dropping in from above with a bounce
  if ka and not lifted then
    local a = (now() - ka) / 0.7
    if a < 0 then return end
    if a >= 1 then st.arrive[t.id] = nil
    else
      local b = 1 - a
      y = y - ts * 1.6 * b * b + math.sin(a * math.pi) * ts * 0.08 * (1 - a)
      alpha = alpha * math.min(1, a * 3)
    end
  end
  if gift and not lifted then
    local k = 0
    if un then
      k = (now() - un.t0) / UNWRAP
      if k >= 1 then
        -- unwrapped: from now on it is the game's own tile
        st.gifts[t.id] = nil
        st.unwrap = nil
        st.popAt = st.popAt or {}
        st.popAt[t.id] = now()
        save()
        gift = nil
      end
    end
    if gift then
      -- a shake before it opens
      local shake = (k > 0 and k < 0.25) and math.sin(k * 90) * ts * 0.04 * (1 - k * 4) or 0
      if k > 0.35 then
        -- the game's icon inside, growing out of the paper
        local g = ease(clamp((k - 0.35) / 0.5, 0, 1))
        local s = ts * (0.6 + 0.4 * g)
        lg.push()
        col({ 255, 255, 255 }, alpha * g)
        roundRect("fill", x + (ts - s) / 2, y + (ts - s) / 2, s, s, s * 0.2)
        local inset = s * 0.12
        drawIcon(t, x + (ts - s) / 2 + inset, y + (ts - s) / 2 + inset, s - 2 * inset)
        lg.pop()
      end
      drawPresent(t.id, x + shake, y, ts, alpha, k)
      drawConfetti(t.id, x, y, ts, k)
      return
    end
  end
  -- just unwrapped: a little pop
  local pop = st.popAt and st.popAt[t.id]
  if pop then
    local a = (now() - pop) / 0.35
    if a >= 1 then st.popAt[t.id] = nil
    else
      local s = 1 + math.sin(a * math.pi) * 0.12
      x, y, ts = x - ts * (s - 1) / 2, y - ts * (s - 1) / 2, ts * s
    end
  end
  local r = ts * 0.2
  col({ 60, 70, 90 }, (lifted and 0.3 or 0.14) * alpha)
  roundRect("fill", x + ts * 0.02, y + ts * (lifted and 0.1 or 0.05), ts, ts, r)
  col({ 255, 255, 255 }, alpha)
  roundRect("fill", x, y, ts, ts, r)
  local inset = ts * 0.12
  drawIcon(t, x + inset, y + inset, ts - 2 * inset)
  if t.game and not t.ready then
    lg.setColor(0.93, 0.94, 0.96, 0.55 * alpha)
    roundRect("fill", x, y, ts, ts, r)
  end
end

local function brackets(x, y, w, h, t)
  local len = w * 0.3
  local th = math.max(2, w * 0.075)
  local pulse = 0.78 + 0.22 * math.sin(t * 5)
  lg.setColor(0.36, 0.9, 0.76, pulse)
  local pts = { { x, y, 1, 1 }, { x + w, y, -1, 1 }, { x, y + h, 1, -1 }, { x + w, y + h, -1, -1 } }
  for _, p in ipairs(pts) do
    lg.rectangle("fill", p[3] > 0 and p[1] or p[1] - len, p[4] > 0 and p[2] or p[2] - th, len, th, th / 2, th / 2)
    lg.rectangle("fill", p[3] > 0 and p[1] or p[1] - th, p[4] > 0 and p[2] or p[2] - len, th, len, th / 2, th / 2)
  end
end

local function hit(id, x, y, w, h, extra)
  local e = extra or {}
  e.id, e.x, e.y, e.w, e.h = id, x, y, w, h
  st.hit[#st.hit + 1] = e
end

-- the two size buttons: one big tile (bigger icons), four small (smaller)
local function sizeButtons(x, y, w, h)
  local bw = w / 2
  col({ 246, 248, 251 })
  roundRect("fill", x, y, w, h, h * 0.25)
  col({ 200, 206, 216 })
  lg.rectangle("fill", x + bw, y + h * 0.18, 1, h * 0.64)
  local s = h * 0.42
  lg.setColor(0.42, 0.62, 0.86, st.level > 1 and 1 or 0.35)
  roundRect("fill", x + bw / 2 - s / 2, y + h / 2 - s / 2, s, s, s * 0.3)
  lg.setColor(0.42, 0.62, 0.86, st.level < #LEVELS and 1 or 0.35)
  local q = s * 0.42
  for i = 0, 1 do for j = 0, 1 do
    roundRect("fill", x + bw + bw / 2 - q - q * 0.08 + i * q * 1.16, y + h / 2 - q - q * 0.08 + j * q * 1.16, q, q, q * 0.25)
  end end
  hit("bigger", x, y, bw, h)
  hit("smaller", x + bw, y, bw, h)
end

function H.draw(r, imp, time)
  st.hit = {}
  st.barRects = {}
  local dt = st.lastT and clamp(time - st.lastT, 0, 0.1) or 0
  st.lastT = time
  local tiles = H.tiles(imp)
  local n = #tiles
  st.sel = clamp(st.sel, 1, math.max(1, n))
  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)
  -- the wallpaper: pale, faintly striped
  for i = 0, r.h, 2 do
    local k = i / r.h
    lg.setColor(0.93 - 0.03 * k, 0.945 - 0.03 * k, 0.965 - 0.025 * k, 1)
    lg.rectangle("fill", r.x, r.y + i, r.w, 2)
  end
  lg.setColor(1, 1, 1, 0.22)
  local stripe = math.max(4, math.floor(r.w / 70))
  for x = r.x, r.x + r.w, stripe * 2 do lg.rectangle("fill", x, r.y, stripe, r.h) end

  -- applet bar
  local barH = math.floor(r.h * 0.17)
  local pad = math.floor(r.w * 0.015)
  local sizeW = barH * 1.9
  local ax = r.x + pad
  local aw = (r.w - 2 * pad - sizeW - pad) / #APPLETS
  for i, a in ipairs(APPLETS) do
    local x = ax + (i - 1) * aw
    local s = math.min(aw, barH) * 0.72
    local hot = st.appletDown == a.id
    if i == 1 then
      col({ 246, 248, 251 })
      roundRect("fill", x, r.y + pad * 0.6, aw, barH - pad * 0.6, barH * 0.25)
    end
    local img = icon(a.id)
    local ix, iy = x + (aw - s) / 2, r.y + (barH - s) / 2 + (hot and s * 0.05 or 0)
    if img then
      local iw, ih = img:getDimensions()
      lg.setColor(1, 1, 1, 1)
      lg.draw(img, ix, iy, 0, s / iw, s / ih)
    elseif a.camera and ctx.drawCameraIcon then
      ctx.drawCameraIcon(ix, iy, s)
    else
      local okI, Icons = pcall(require, "src.ui.kit.Icons")
      if okI then Icons.draw(a.icon, ix, iy, s, a.color, 1) end
    end
    hit("applet", x, r.y, aw, barH, { applet = a })
    st.barRects[i] = { x + (aw - s) / 2, r.y + (barH - s) / 2, s, s }
  end
  local sx, sy, sh = r.x + r.w - pad - sizeW, r.y + pad * 0.6, barH - pad * 1.2
  sizeButtons(sx, sy, sizeW, sh)
  st.barRects[#APPLETS + 1] = { sx + sizeW * 0.25 - sh * 0.4, sy + sh * 0.1, sh * 0.8, sh * 0.8 }
  st.barRects[#APPLETS + 2] = { sx + sizeW * 0.75 - sh * 0.4, sy + sh * 0.1, sh * 0.8, sh * 0.8 }
  -- the d-pad's place on the bar
  local br = st.bar and st.barRects[st.bar]
  if br then
    local k = br[3] * 0.12
    brackets(br[1] - k, br[2] - k, br[3] + 2 * k, br[4] + 2 * k, time)
  end

  local obH = math.floor(r.h * 0.14)
  local oy = r.y + r.h - obH
  local mh = math.floor(r.h * 0.075)         -- the play meter row
  local my = oy - mh - pad
  local g = { x = r.x, y = r.y + barH + pad, w = r.w, h = my - (r.y + barH + pad) - pad }
  st.grid = g
  local G = geometry(st.level, g)
  local Gp = geometry(st.prevLevel, g)
  local a = ease((now() - st.animAt) / ANIM)
  local animating = a < 1

  -- momentum after a flick, and the springy edges
  if not next(st.touches) and st.vel ~= 0 then
    st.scroll = st.scroll + st.vel * dt
    st.vel = st.vel * math.exp(-dt * 5)
    if math.abs(st.vel) < 5 then st.vel = 0 end
  end
  local maxS = maxScroll(G, n, g)
  if not next(st.touches) then
    if st.scroll < 0 then st.scroll = st.scroll * math.exp(-dt * 14); st.vel = 0 end
    if st.scroll > maxS then st.scroll = maxS + (st.scroll - maxS) * math.exp(-dt * 14); st.vel = 0 end
  end
  -- while a lifted tile is held near an edge, the strip scrolls
  if st.lift then
    local edge = g.w * 0.1
    if st.lift.x < g.x + edge then st.scroll = math.max(0, st.scroll - dt * g.w * 0.8) end
    if st.lift.x > g.x + g.w - edge then st.scroll = math.min(maxS, st.scroll + dt * g.w * 0.8) end
  end

  lg.setScissor(g.x, g.y - pad, g.w, g.h + 2 * pad)
  -- empty slots, cross-faded between the old size and the new
  local function slots(Gx, scroll, alpha)
    if alpha <= 0.01 then return end
    local ncols = math.max(math.ceil(n / Gx.rows), math.ceil((g.w + scroll) / Gx.pitchX) + 1)
    local first = math.max(0, math.floor((scroll - Gx.x0 + g.x) / Gx.pitchX) - 1)
    for c = first, ncols do
      for rr = 0, Gx.rows - 1 do
        local x = Gx.x0 + c * Gx.pitchX - scroll
        if x > g.x - Gx.pitchX and x < g.x + g.w then
          lg.setColor(0.8, 0.83, 0.88, 0.5 * alpha)
          roundRect("line", x, Gx.y0 + rr * Gx.pitchY, Gx.ts, Gx.ts, Gx.ts * 0.2)
        end
      end
    end
  end
  lg.setLineWidth(1)
  if animating then slots(Gp, st.prevScroll, 1 - a) end
  slots(G, st.scroll, a)

  -- tiles: each eases toward its slot (so a rearrange glides; a resize
  -- follows the animated blend of the old and new layouts)
  local k = 1 - math.exp(-dt * 16)
  local selRect
  for i, t in ipairs(tiles) do
    local tx, ty = slotPos(G, i, st.scroll)
    local ts = G.ts
    if animating then
      local px, py = slotPos(Gp, i, st.prevScroll)
      tx, ty, ts = px + (tx - px) * a, py + (ty - py) * a, Gp.ts + (G.ts - Gp.ts) * a
    end
    local d = st.disp[t.id]
    if not d or animating or dt == 0 or st.dragging then
      d = d or {}
      d.x, d.y, d.s = tx, ty, ts
      st.disp[t.id] = d
    else
      d.x, d.y, d.s = d.x + (tx - d.x) * k, d.y + (ty - d.y) * k, d.s + (ts - d.s) * k
    end
    local lifted = st.lift and st.lift.id == t.id
    if not lifted and d.x > g.x - d.s * 1.5 and d.x < g.x + g.w + d.s then
      drawTile(t, d.x, d.y, d.s, 1, false)
      hit("tile", d.x, d.y, d.s, d.s, { idx = i, tile = t })
    end
    if i == st.sel then selRect = { d.x, d.y, d.s } end
  end
  -- one row: the name bubble over the selected tile
  if LEVELS[st.level].rows == 1 and selRect and not animating then
    local t = tiles[st.sel]
    local bx, bw = g.x + g.w * 0.08, g.w * 0.84
    local by, bh = g.y + g.h * 0.03, g.h * 0.28
    lg.setColor(1, 1, 1, 0.96)
    roundRect("fill", bx, by, bw, bh, bh * 0.2)
    lg.setColor(0.78, 0.8, 0.84, 1)
    lg.setLineWidth(math.max(1, bh * 0.025))
    lg.line(selRect[1] + selRect[3] / 2, by + bh, selRect[1] + selRect[3] / 2, selRect[2] - selRect[3] * 0.1)
    local f = ctx.font(bh * 0.3)
    lg.setFont(f)
    col({ 80, 82, 88 })
    local sub = t.sub or (t.game and (t.ready and "Game Freak / BOIS CLUB GAMES" or "Import the ROM to play")) or ""
    lg.printf(t.name, bx, by + bh * 0.16, bw, "center")
    col({ 110, 112, 118 })
    lg.printf(sub, bx, by + bh * 0.16 + f:getHeight() * 1.1, bw, "center")
  end
  if selRect and not st.lift then
    local s = selRect[3]
    if not st.bar then brackets(selRect[1] - s * 0.1, selRect[2] - s * 0.1, s * 1.2, s * 1.2, time) end
  end
  -- more to the right / left: the half-round arrow tabs at the edges
  local function edgeTab(side)
    local th = g.h * 0.36
    local cy = g.y + g.h / 2
    local cx = side > 0 and g.x + g.w or g.x
    lg.setColor(1, 1, 1, 0.9)
    lg.circle("fill", cx, cy, th / 2)
    lg.setColor(0.45, 0.78, 0.86, 1)
    local s = th * 0.16
    local ax = cx - side * th * 0.22
    lg.polygon("fill", ax - side * s, cy - s, ax - side * s, cy + s, ax + side * s * 0.6, cy)
    hit(side > 0 and "scrollRight" or "scrollLeft", side > 0 and cx - th / 2 or cx, cy - th / 2, th / 2, th)
  end
  if st.scroll < maxS - 1 then edgeTab(1) end
  if st.scroll > 1 then edgeTab(-1) end
  -- the lifted tile rides the finger, a little larger, on top
  if st.lift then
    local t
    for _, tt in ipairs(tiles) do if tt.id == st.lift.id then t = tt end end
    if t then
      local s = G.ts * 1.15
      drawTile(t, st.lift.x - s / 2, st.lift.y - s / 2, s, 0.95, true)
    end
  end
  lg.setScissor(r.x, r.y, r.w, r.h)

  -- the play meter and the coins
  do
    local count, frac = H.coins()
    local bw = r.w * 0.42
    local bx = r.x + pad * 2
    col({ 20, 190, 220 })
    roundRect("fill", bx, my, bw, mh, mh / 2)
    col({ 190, 240, 250 })
    roundRect("fill", bx + mh * 0.14, my + mh * 0.14, bw - mh * 0.28, mh * 0.72, mh * 0.36)
    local fw = (bw - mh * 0.28) * math.max(0, math.min(1, frac))
    if fw > 0.5 then
      col({ 40, 215, 240 })
      roundRect("fill", bx + mh * 0.14, my + mh * 0.14, math.max(fw, mh * 0.72), mh * 0.72, mh * 0.36)
      col({ 255, 255, 255 }, 0.4)
      roundRect("fill", bx + mh * 0.25, my + mh * 0.2, math.max(fw - mh * 0.22, 0), mh * 0.2, mh * 0.1)
    end
    local cx, cy, cr = bx + bw + mh * 1.1, my + mh / 2, mh * 0.62
    col({ 214, 160, 10 })
    lg.circle("fill", cx, cy, cr)
    col({ 250, 206, 40 })
    lg.circle("fill", cx, cy, cr * 0.84)
    col({ 214, 160, 10 })
    lg.rectangle("fill", cx - cr * 0.3, cy - cr * 0.45, cr * 0.18, cr * 0.9)
    lg.rectangle("fill", cx + cr * 0.12, cy - cr * 0.45, cr * 0.18, cr * 0.9)
    local cf = ctx.font(mh * 1.05)
    lg.setFont(cf)
    col({ 80, 82, 88 })
    lg.print(tostring(count), cx + cr * 1.6, cy - cf:getHeight() / 2)
    -- an open folder: its name at the row's right, on a folder tab
    if st.folder then
      local name = st.folder.name
      local tw = cf:getWidth(name) + mh * 1.9
      local tx = r.x + r.w - pad * 2 - tw
      col({ 255, 255, 255 }, 0.95)
      roundRect("fill", tx, my, tw, mh, mh / 2)
      col({ 236, 176, 30 })
      roundRect("fill", tx + mh * 0.3, my + mh * 0.3, mh * 0.9, mh * 0.55, mh * 0.08)
      roundRect("fill", tx + mh * 0.3, my + mh * 0.2, mh * 0.4, mh * 0.2, mh * 0.06)
      col({ 80, 82, 88 })
      lg.print(name, tx + mh * 1.45, cy - cf:getHeight() / 2)
    end
  end

  -- Manual / Open
  col({ 250, 250, 252 })
  lg.rectangle("fill", r.x, oy, r.w, obH)
  col({ 205, 208, 214 })
  lg.rectangle("fill", r.x, oy, r.w, 1)
  local split = r.x + r.w * 0.44
  lg.rectangle("fill", split, oy + obH * 0.12, 1, obH * 0.76)
  local f = ctx.font(obH * 0.5)
  lg.setFont(f)
  local sel = tiles[st.sel]
  col({ 100, 102, 108 }, sel and (sel.game or (sel.emuGame and Emus.hasManual(sel))) and 1 or 0.35)
  lg.printf("Manual", r.x, oy + (obH - f:getHeight()) / 2, split - r.x, "center")
  col({ 100, 102, 108 })
  lg.printf("Open", split, oy + (obH - f:getHeight()) / 2, r.x + r.w - split, "center")
  hit("manual", r.x, oy, split - r.x, obH)
  hit("open", split, oy, r.x + r.w - split, obH)
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
  col({ 248, 249, 251 })
  lg.rectangle("fill", r.x, r.y, r.w, h)
  col({ 205, 208, 214 })
  lg.rectangle("fill", r.x, r.y + h - 1, r.w, 1)
  local bw = h * 1.2
  col({ 100, 102, 108 })
  local cx, cy, s = r.x + bw / 2, r.y + h / 2, h * 0.2
  lg.polygon("fill", cx + s * 0.6, cy - s, cx + s * 0.6, cy + s, cx - s * 0.8, cy)
  lg.rectangle("fill", r.x + bw, r.y + h * 0.15, 1, h * 0.7)
  st.barHit = { x = r.x, y = r.y, w = bw, h = h }
  local f = ctx.font(h * 0.46)
  lg.setFont(f)
  lg.printf(t.name, r.x + bw, r.y + (h - f:getHeight()) / 2, r.w - bw, "center")
  lg.pop()
end

---------------------------------------------------------------- input

local function inside(h, x, y) return x >= h.x and y >= h.y and x <= h.x + h.w and y <= h.y + h.h end

local function hitAt(x, y)
  for i = #st.hit, 1, -1 do
    local h = st.hit[i]
    if inside(h, x, y) then return h end
  end
end

-- the slot a point on the grid falls in (for dropping a lifted tile)
local function slotAt(x, y, n)
  local g = st.grid
  if not g then return nil end
  local G = geometry(st.level, g)
  local c = math.floor((x + st.scroll - G.x0 + (G.pitchX - G.ts) / 2) / G.pitchX)
  local rr = math.floor((y - G.y0 + (G.pitchY - G.ts) / 2) / G.pitchY)
  c = math.max(0, c)
  rr = clamp(rr, 0, G.rows - 1)
  return clamp(c * G.rows + rr + 1, 1, n)
end

local function moveTile(from, to)
  if from == to then return end
  local id = table.remove(st.order, from)
  table.insert(st.order, to, id)
end

function H.pressed(imp, id, x, y)
  st.bar = nil
  local tc = { x0 = x, y0 = y, x = x, y = y, t0 = now(), lastX = x, lastT = now() }
  st.touches[id] = tc
  -- a second finger on the grid: pinch to resize
  local count, other = 0, nil
  for oid, o in pairs(st.touches) do count = count + 1; if oid ~= id then other = o end end
  if count == 2 and other and st.grid and inside(st.grid, x, y) and not st.lift then
    local d = math.sqrt((x - other.x) ^ 2 + (y - other.y) ^ 2)
    st.pinch = { d0 = math.max(1, d) }
    other.kind = "pinch"
    tc.kind = "pinch"
    return true
  end
  local h = hitAt(x, y)
  if h and h.id == "tile" then
    tc.kind, tc.idx, tc.tileId = "tile", h.idx, h.tile.id
  elseif h then
    tc.kind, tc.hit = "button", h
    if h.id == "applet" then st.appletDown = h.applet.id end
  elseif st.grid and inside(st.grid, x, y) then
    tc.kind = "strip"
  else
    tc.kind = "none"
  end
  st.vel = 0
  return true
end

function H.moved(imp, id, x, y)
  local tc = st.touches[id]
  if not tc then return false end
  local dx = x - tc.x
  tc.x, tc.y = x, y
  if math.abs(x - tc.x0) > SLOP or math.abs(y - tc.y0) > SLOP then tc.moved = true end
  if tc.kind == "pinch" and st.pinch then
    local a, b
    for _, o in pairs(st.touches) do if o.kind == "pinch" then if a then b = o else a = o end end end
    if a and b and st.grid then
      local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
      local ratio = d / st.pinch.d0
      local n = #H.tiles(imp)
      if ratio > 1.3 then setLevel(st.level - 1, st.grid, n); st.pinch.d0 = d end
      if ratio < 0.77 then setLevel(st.level + 1, st.grid, n); st.pinch.d0 = d end
    end
    return true
  end
  if tc.kind == "lift" and st.lift then
    st.lift.x, st.lift.y = x, y
    local to = slotAt(x, y, #st.order)
    local from
    for i, oid in ipairs(st.order) do if oid == st.lift.id then from = i end end
    if to and from and to ~= from then moveTile(from, to); st.sel = to; Sfx.play("swap") end
    return true
  end
  if (tc.kind == "tile" or tc.kind == "strip") and tc.moved then
    tc.kind = "strip"
    st.dragging = true
    st.scroll = st.scroll - dx
    local t = now()
    local sdt = math.max(1e-3, t - tc.lastT)
    st.vel = -(x - tc.lastX) / sdt
    tc.lastX, tc.lastT = x, t
  end
  return true
end

function H.released(imp, id, x, y)
  local tc = st.touches[id]
  if not tc then return false end
  st.touches[id] = nil
  st.appletDown = nil
  st.dragging = nil
  if tc.kind == "pinch" then
    if not next(st.touches) then st.pinch = nil end
    for _, o in pairs(st.touches) do o.kind = "none" end
    return true
  end
  if tc.kind == "lift" then
    st.lift = nil
    Sfx.play("drop")
    save()
    return true
  end
  if tc.kind == "strip" then
    if now() - tc.lastT > 0.08 then st.vel = 0 end
    return true
  end
  st.vel = 0
  if tc.moved then return true end
  local tiles = H.tiles(imp)
  -- right after a folder opens or closes, a tile under the finger is not
  -- opened by the same tap arriving twice
  if tc.kind == "tile" and now() - (st.folderAt or -10) < 0.35 then return true end
  if tc.kind == "tile" then
    if st.sel == tc.idx then openTile(imp, tiles[tc.idx])
    else st.sel = tc.idx; Sfx.play("select"); selectTile(imp, tiles[tc.idx]) end
  elseif tc.kind == "button" then
    local h = tc.hit
    local g = st.grid
    local n = #tiles
    if h.id == "applet" then Sfx.play("touch"); openTile(imp, h.applet)
    elseif h.id == "bigger" and g then setLevel(st.level - 1, g, n)
    elseif h.id == "smaller" and g then setLevel(st.level + 1, g, n)
    elseif h.id == "open" then openTile(imp, tiles[st.sel])
    elseif h.id == "manual" then manual(imp, tiles[st.sel])
    elseif h.id == "scrollRight" and g then st.vel = g.w * 3.2; Sfx.play("strip")
    elseif h.id == "scrollLeft" and g then st.vel = -g.w * 3.2; Sfx.play("strip") end
  end
  return true
end

function H.tapBar(imp, x, y)
  if st.open and st.barHit and inside(st.barHit, x, y) then
    H.goHome(imp)
    return true
  end
  return false
end

-- shell buttons on the grid: the d-pad / circle pad move (down a column,
-- then across), A opens, X / Y resize
function H.button(imp, name)
  local tiles = H.tiles(imp)
  local n = #tiles
  local rows = LEVELS[st.level].rows
  local s = st.sel
  local g = st.grid
  -- on the applet bar: left / right along it, A opens, down (or B) back
  -- to the icons
  if st.bar then
    local count = #APPLETS + 2
    if name == "left" or name == "right" then
      local b = clamp(st.bar + (name == "right" and 1 or -1), 1, count)
      Sfx.play(b ~= st.bar and "over" or "edge")
      st.bar = b
    elseif name == "down" or name == "b" then
      st.lastBar, st.bar = st.bar, nil
      Sfx.play("over")
    elseif name == "a" then
      if st.bar <= #APPLETS then
        Sfx.play("touch")
        openTile(imp, APPLETS[st.bar])
      elseif g then
        setLevel(st.level + (st.bar == #APPLETS + 1 and -1 or 1), g, n)
      end
    elseif name == "up" then
      Sfx.play("edge")
    else
      return false
    end
    return true
  end
  if name == "a" then openTile(imp, tiles[s]) return true end
  if name == "b" and st.folder then Sfx.play("back"); closeFolder() return true end
  if name == "x" and g then setLevel(st.level - 1, g, n) return true end
  if name == "y" and g then setLevel(st.level + 1, g, n) return true end
  -- ZL / ZR resize; L / R scroll the strip a screen at a time
  if name == "zr" and g then setLevel(st.level - 1, g, n) return true end
  if name == "zl" and g then setLevel(st.level + 1, g, n) return true end
  if (name == "l" or name == "r") and g then
    st.vel = (name == "r" and 1 or -1) * g.w * 3.2
    Sfx.play("strip")
    return true
  end
  if name == "up" and ((s - 1) % rows == 0 or n == 0) then
    -- off the top row: up onto the applet bar
    st.bar = st.lastBar or 1
    Sfx.play("over")
    return true
  end
  if name == "up" then if (s - 1) % rows > 0 then s = s - 1 end
  elseif name == "down" then if (s - 1) % rows < rows - 1 and s < n then s = s + 1 end
  elseif name == "left" then s = s - rows
  elseif name == "right" then s = math.min(n, s + rows)
  else return false end
  local was = st.sel
  st.sel = clamp(s, 1, n)
  Sfx.play(st.sel ~= was and "over" or "edge")
  selectTile(imp, tiles[st.sel])
  if g then reveal(geometry(st.level, g), n, g) end
  return true
end

return H
