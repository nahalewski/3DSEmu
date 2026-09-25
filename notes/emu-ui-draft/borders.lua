-- The top screen's borders: in game the picture no longer sits inside the
-- shell's printed Game Boy Color frame -- the whole top panel is the game's,
-- and a border for the game's own system is drawn around it:
--
--   gb   the original Game Boy's face, made for the 3DS top screen
--        (borders/gb.png: libretro common-overlays, ctr/borders/gb-integer)
--   gba  a Game Boy Advance (borders/gba.png: common-overlays, borders/gba-4k)
--   gbc  a Game Boy Color's face, drawn here
--   ds   a DS Lite's top half -- the screen between its two speakers --
--        drawn here
--
-- A game's own border: when a game starts, its border from The Bezel
-- Project (github.com/thebezelproject, by the game's No-Intro name) is
-- downloaded once into the save folder (emu_cache/bezels/) and used from
-- then on; none are shipped.  A DS game's is made for its two screens one
-- over the other, so only its upper half (the top screen) is used.
--
-- The screen hole of any border is found from its see-through pixels, so
-- any PNG with a transparent screen can replace one of these.
local B = {}

local lg = love.graphics
local DIR = "fold3ds/borders/"
local CACHE = "emu_cache/bezels/"
local BEZEL_REPO = {
  gb = { "bezelprojectSA-GB", "GB" }, gbc = { "bezelprojectSA-GBC", "GBC" },
  gba = { "bezelprojectSA-GBA", "GBA" }, ds = { "bezelprojectSA-NDS", "NDS" },
}
-- the systems' screens (for fitting the picture into a hole)
B.SCREEN = { gb = { 160, 144 }, gbc = { 160, 144 }, gba = { 240, 160 }, ds = { 256, 192 } }

-- "game": the game's own border when there is one; "system": always the
-- system's; set by the Settings (fold3ds/emu.lua)
B.style = "game"
-- how a download is asked for (fold3ds/emu.lua gives it: url, save path)
B.fetch = nil

local art = {}      -- key -> { img, hole = {x, y, w, h}, crop = {x, y, w, h}, fill } | false

local function sanitize(name)
  -- The Bezel Project's file names are No-Intro's with & and friends kept;
  -- only the characters a path cannot hold are changed
  return (name:gsub("[/\\:%*%?\"<>|]", "_"))
end

-- the see-through screen in an image: from its middle (or, for a DS
-- border, the middle of its upper half) out to the first solid pixels
local function findHole(data, w, h, upper)
  local cx, cy = math.floor(w / 2), math.floor(upper and h / 4 or h / 2)
  local function clear(x, y)
    local _, _, _, a = data:getPixel(x, y)
    return a < 0.5
  end
  if not clear(cx, cy) then return nil end
  local x0, x1, y0, y1 = cx, cx, cy, cy
  while x0 > 0 and clear(x0 - 1, cy) do x0 = x0 - 1 end
  while x1 < w - 1 and clear(x1 + 1, cy) do x1 = x1 + 1 end
  while y0 > 0 and clear(cx, y0 - 1) do y0 = y0 - 1 end
  while y1 < h - 1 and clear(cx, y1 + 1) do y1 = y1 + 1 end
  return { x = x0, y = y0, w = x1 - x0 + 1, h = y1 - y0 + 1 }
end

-- a border image, its hole, and the part of it to show
local function load(key, path, sys)
  if art[key] ~= nil then return art[key] or nil end
  art[key] = false
  local ok, data = pcall(love.image.newImageData, path)
  if not ok or not data then return nil end
  local w, h = data:getDimensions()
  local hole = findHole(data, w, h, false)
  local crop = { x = 0, y = 0, w = w, h = h }
  if sys == "ds" and hole and hole.h > hole.w then
    -- two screens one over the other: the top one, and the art beside it
    local top = { x = hole.x, y = hole.y, w = hole.w, h = math.floor(hole.h / 2) }
    local ch = top.y + top.h + math.floor(top.h * 0.08)
    local cw = math.min(w, math.floor(ch * 1.84))
    crop = { x = math.floor((w - cw) / 2), y = 0, w = cw, h = math.min(h, ch) }
    hole = top
  end
  if not hole or hole.w < 16 or hole.h < 16 then return nil end
  local ok2, img = pcall(lg.newImage, data)
  if not ok2 then return nil end
  img:setFilter("linear", "linear")
  -- the colour beside the art where the panel is wider than it: its edge
  local r, g, b = data:getPixel(math.max(0, crop.x + 2), math.min(h - 1, crop.y + math.floor(crop.h / 2)))
  art[key] = { img = img, hole = hole, crop = crop, fill = { r, g, b },
    quad = lg.newQuad(crop.x, crop.y, crop.w, crop.h, w, h) }
  return art[key]
end

local current = { sys = nil, name = nil }

-- a game starts: its own border, when there is one (downloaded now, once)
function B.setGame(sys, name)
  current.sys, current.name = sys, name
  if B.style ~= "game" or not name or not BEZEL_REPO[sys] then return end
  local repo = BEZEL_REPO[sys]
  local file = CACHE .. repo[2] .. "/" .. sanitize(name) .. ".png"
  if love.filesystem.getInfo(file) or love.filesystem.getInfo(file .. ".fail") then return end
  if B.fetch then
    local url = ("https://raw.githubusercontent.com/thebezelproject/%s/master/retroarch/overlay/GameBezels/%s/%s.png")
      :format(repo[1], repo[2], name:gsub("[^%w%-%._~]", function(c) return ("%%%02X"):format(c:byte()) end))
    love.filesystem.createDirectory(CACHE .. repo[2])
    B.fetch(url, file)
  end
end

local function gameArt(sys)
  if B.style ~= "game" or current.sys ~= sys or not current.name or not BEZEL_REPO[sys] then return nil end
  local file = CACHE .. BEZEL_REPO[sys][2] .. "/" .. sanitize(current.name) .. ".png"
  if not love.filesystem.getInfo(file) then return nil end
  return load("game:" .. file, file, sys)
end

local function systemArt(sys)
  if sys == "gb" or sys == "gba" then return load("sys:" .. sys, DIR .. sys .. ".png", sys) end
  return nil
end

-- where things go in panel rect r: the art (x, y, scale), and the hole
local function place(r, a)
  local s = math.min(r.w / a.crop.w, r.h / a.crop.h)
  local x = r.x + (r.w - a.crop.w * s) / 2
  local y = r.y + (r.h - a.crop.h * s) / 2
  local hole = { x = x + (a.hole.x - a.crop.x) * s, y = y + (a.hole.y - a.crop.y) * s,
                 w = a.hole.w * s, h = a.hole.h * s }
  return x, y, s, hole
end

---------------------------------------------------------------- drawn borders

-- the Game Boy Color: a grape-purple face, the dark lens around the screen
-- with the power lamp at its left, COLOR in its five colours under it
local function gbcHole(r)
  local hh = math.floor(r.h * 0.78)
  local hw = math.floor(hh * 160 / 144)
  return { x = r.x + math.floor((r.w - hw) / 2), y = r.y + math.floor(r.h * 0.07), w = hw, h = hh }
end

local fonts = {}
local function font(px)
  px = math.max(8, math.floor(px))
  if not fonts[px] then fonts[px] = lg.newFont(px) end
  return fonts[px]
end

local function drawGbc(r, hole)
  lg.setColor(0.36, 0.2, 0.55, 1)
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  -- a soft sheen from the top
  for i = 0, 7 do
    lg.setColor(1, 1, 1, 0.025)
    lg.rectangle("fill", r.x, r.y, r.w, r.h * (0.1 + i * 0.05))
  end
  local m = r.h * 0.035
  local lens = { x = hole.x - m * 3.2, y = hole.y - m, w = hole.w + m * 6.4, h = hole.h + m * 2.6 }
  lg.setColor(0.13, 0.13, 0.16, 1)
  lg.rectangle("fill", lens.x, lens.y, lens.w, lens.h, m * 1.2, m * 1.2)
  lg.setColor(1, 1, 1, 0.06)
  lg.rectangle("line", lens.x + 1, lens.y + 1, lens.w - 2, lens.h - 2, m * 1.2, m * 1.2)
  -- the power lamp
  lg.setColor(0.95, 0.15, 0.15, 1)
  lg.circle("fill", lens.x + m * 1.6, hole.y + hole.h * 0.3, m * 0.42)
  lg.setColor(1, 1, 1, 0.4)
  lg.circle("fill", lens.x + m * 1.5, hole.y + hole.h * 0.3 - m * 0.12, m * 0.14)
  local f = font(m * 0.9)
  lg.setFont(f)
  lg.setColor(0.7, 0.7, 0.75, 1)
  lg.print("POWER", lens.x + m * 1.6 - f:getWidth("POWER") / 2, hole.y + hole.h * 0.3 + m * 0.7)
  -- COLOR, a colour to a letter
  local word = { { "C", 0.85, 0.2, 0.55 }, { "O", 0.2, 0.45, 0.9 }, { "L", 0.3, 0.75, 0.3 },
                 { "O", 0.95, 0.75, 0.15 }, { "R", 0.9, 0.3, 0.2 } }
  local big = font(m * 1.5)
  lg.setFont(big)
  local total = 0
  for _, c in ipairs(word) do total = total + big:getWidth(c[1]) end
  local x = r.x + (r.w - total) / 2
  local y = lens.y + lens.h + (r.y + r.h - lens.y - lens.h - big:getHeight()) / 2
  for _, c in ipairs(word) do
    lg.setColor(c[2], c[3], c[4], 1)
    lg.print(c[1], x, y)
    x = x + big:getWidth(c[1])
  end
end

-- the DS Lite's top half: a glossy black lid, the screen in its frame, the
-- speakers' dots either side, the camera-less top edge
local function dsHole(r)
  local hh = math.floor(r.h * 0.84)
  local hw = math.floor(hh * 256 / 192)
  return { x = r.x + math.floor((r.w - hw) / 2), y = r.y + math.floor((r.h - hh) / 2), w = hw, h = hh }
end

local function drawDs(r, hole)
  lg.setColor(0.07, 0.07, 0.08, 1)
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  -- gloss: a lighter band across the top and a soft edge
  lg.setColor(1, 1, 1, 0.05)
  lg.rectangle("fill", r.x, r.y, r.w, r.h * 0.18)
  lg.setColor(1, 1, 1, 0.03)
  lg.rectangle("fill", r.x, r.y + r.h * 0.18, r.w, r.h * 0.12)
  local m = r.h * 0.02
  lg.setColor(0.16, 0.16, 0.18, 1)
  lg.rectangle("fill", hole.x - m, hole.y - m, hole.w + m * 2, hole.h + m * 2, m, m)
  -- the speakers: a little cross of dots each side, as on the DS Lite
  local d = r.h * 0.022
  for _, side in ipairs({ -1, 1 }) do
    local cx = side < 0 and (r.x + (hole.x - m - r.x) / 2) or (hole.x + hole.w + m + (r.x + r.w - hole.x - hole.w - m) / 2)
    local cy = r.y + r.h * 0.34
    lg.setColor(0.02, 0.02, 0.02, 1)
    for _, p in ipairs({ { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
      if p[1] == 0 or p[2] == 0 then lg.circle("fill", cx + p[1] * d * 2.2, cy + p[2] * d * 2.2, d * 0.55) end
    end
  end
end

---------------------------------------------------------------- the interface

-- the hole (the game's screen area) for system sys in panel rect r
function B.hole(r, sys)
  local a = gameArt(sys) or systemArt(sys)
  if a then
    local _, _, _, hole = place(r, a)
    return hole
  end
  if sys == "gbc" then return gbcHole(r) end
  if sys == "ds" then return dsHole(r) end
  return { x = r.x, y = r.y, w = r.w, h = r.h }
end

-- the picture's rect inside the hole: the system's shape, as large as fits
-- (whole pixels when there is room for two or more)
function B.gameRect(r, sys, dpi)
  local hole = B.hole(r, sys)
  local sw, sh = unpack(B.SCREEN[sys] or { hole.w, hole.h })
  local s = math.min(hole.w / sw, hole.h / sh)
  dpi = dpi or 1
  if s * dpi >= 2 then s = math.floor(s * dpi) / dpi end
  local w, h = math.floor(sw * s), math.floor(sh * s)
  return { x = math.floor(hole.x + (hole.w - w) / 2), y = math.floor(hole.y + (hole.h - h) / 2), w = w, h = h }
end

-- behind the game: a drawn border (its hole black), or black under an
-- image border (drawn over the game by drawFront)
function B.drawBack(r, sys)
  lg.push("all")
  lg.setColor(0, 0, 0, 1)
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  if not (gameArt(sys) or systemArt(sys)) then
    local hole = B.hole(r, sys)
    if sys == "gbc" then drawGbc(r, hole) elseif sys == "ds" then drawDs(r, hole) end
    lg.setColor(0, 0, 0, 1)
    lg.rectangle("fill", hole.x, hole.y, hole.w, hole.h)
  end
  lg.pop()
end

-- over the game: an image border (its screen see-through)
function B.drawFront(r, sys)
  local a = gameArt(sys) or systemArt(sys)
  if a then
    local x, y, s = place(r, a)
    lg.setColor(a.fill[1], a.fill[2], a.fill[3], 1)
    -- the panel wider than the art: its edge colour on either side
    if x > r.x then
      lg.rectangle("fill", r.x, r.y, x - r.x + 1, r.h)
      lg.rectangle("fill", x + a.crop.w * s - 1, r.y, r.x + r.w - x - a.crop.w * s + 1, r.h)
    end
    if y > r.y then
      lg.rectangle("fill", r.x, r.y, r.w, y - r.y + 1)
      lg.rectangle("fill", r.x, y + a.crop.h * s - 1, r.w, r.y + r.h - y - a.crop.h * s + 1)
    end
    lg.setColor(1, 1, 1, 1)
    lg.draw(a.img, a.quad, x, y, 0, s, s)
    return
  end
end

-- the recomp games' systems
local VERSION_SYS = {
  red = "gb", blue = "gb", green = "gb", yellow = "gb",
  gold = "gbc", silver = "gbc", crystal = "gbc",
  firered = "gba", leafgreen = "gba",
}
-- and their No-Intro names (their own borders)
local VERSION_NAME = {
  red = "Pokemon - Red Version (USA, Europe) (SGB Enhanced)",
  blue = "Pokemon - Blue Version (USA, Europe) (SGB Enhanced)",
  yellow = "Pokemon - Yellow Version - Special Pikachu Edition (USA, Europe) (CGB+SGB Enhanced)",
  green = "Pocket Monsters - Midori (Japan) (SGB Enhanced)",
  gold = "Pokemon - Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible)",
  silver = "Pokemon - Silver Version (USA, Europe) (SGB Enhanced) (GB Compatible)",
  crystal = "Pokemon - Crystal Version (USA, Europe) (Rev 1)",
  firered = "Pokemon - FireRed Version (USA, Europe) (Rev 1)",
  leafgreen = "Pokemon - LeafGreen Version (USA, Europe) (Rev 1)",
}
function B.versionSystem(v) return VERSION_SYS[v] or "gbc" end
function B.versionName(v) return VERSION_NAME[v] end

return B
