-- A 3D Game Boy Color cartridge for the 3DS theme's top screen: a real
-- solid (front, back and side walls, lit from the upper left), the GBC
-- cart's shape -- the cut top-right corner, the grip groove across its top,
-- the recessed label, the arrow at its foot -- in the game's own colour,
-- with the game's label on the front.  It floats the way the 3DS shows a
-- title's banner: a slow bob, a gentle sway, a soft shadow that breathes
-- under it, and a spin into place when another game is chosen.  GBA games
-- (FireRed, LeafGreen) get the GBA cart's wider, shorter body.
--
-- Shell colours and labels are the launcher's own (the colour each game's
-- cart has everywhere else, the label art from assets/labels);
-- fold3ds/labels/<version>.png, if present, replaces a label with your own.
local C = {}

local lg = love.graphics
local DIR = "fold3ds/labels/"

-- cartridge shell colours, per game (0-255)
local SHELL = {
  red = { 214, 46, 52 }, blue = { 44, 96, 206 }, green = { 54, 150, 76 },
  yellow = { 236, 196, 26 }, gold = { 204, 150, 48 }, silver = { 176, 184, 196 },
  crystal = { 150, 206, 232 }, firered = { 222, 74, 44 }, leafgreen = { 62, 168, 88 },
}

local labels = {}
local shown = { version = nil, since = -10 }

local function label(version, path)
  local key = version .. "|" .. tostring(path)
  if labels[key] == nil then
    local img
    for _, path in ipairs({ DIR .. version .. ".png", path or "assets/labels/" .. version .. ".png" }) do
      local ok, i = pcall(lg.newImage, path)
      if ok then img = i break end
    end
    if img then img:setFilter("linear", "linear") end
    labels[key] = img or false
  end
  return labels[key] or nil
end

local function isGba(version)
  return version == "firered" or version == "leafgreen"
end

---------------------------------------------------------------- the model
-- Units: the cart is 1 wide; y runs down; z runs away from the viewer.

local function model(gba)
  if gba then
    local w, h, d = 1, 0.62, 0.1
    return { w = w, h = h, d = d, cut = 0,
      outline = { { -0.5, -h / 2 + 0.08 }, { -0.42, -h / 2 }, { 0.42, -h / 2 }, { 0.5, -h / 2 + 0.08 },
                  { 0.5, h / 2 }, { -0.5, h / 2 } },
      labelRect = { -0.38, -h / 2 + 0.07, 0.76, 0.42 },
      groove = nil,
      arrow = nil }
  end
  local w, h, d = 1, 1.14, 0.13
  local cut = 0.11
  return { w = w, h = h, d = d, cut = cut,
    outline = { { -0.5, -h / 2 }, { 0.5 - cut, -h / 2 }, { 0.5, -h / 2 + cut }, { 0.5, h / 2 }, { -0.5, h / 2 } },
    labelRect = { -0.38, -h / 2 + 0.3, 0.76, 0.62 },
    groove = { -0.3, -h / 2 + 0.08, 0.6, 0.1 },
    arrow = { 0, h / 2 - 0.1, 0.09 } }
end

-- turn a model point and put it on screen (a gentle perspective)
local function projector(cx, cy, scale, yaw, pitch)
  local cyw, syw = math.cos(yaw), math.sin(yaw)
  local cp, sp = math.cos(pitch), math.sin(pitch)
  local f = 3.2
  return function(x, y, z)
    local x1 = x * cyw + z * syw
    local z1 = -x * syw + z * cyw
    local y1 = y * cp - z1 * sp
    local z2 = y * sp + z1 * cp
    local k = f / (f + z2)
    return cx + x1 * k * scale, cy + y1 * k * scale, z2
  end, function(nx, ny, nz)
    local x1 = nx * cyw + nz * syw
    local z1 = -nx * syw + nz * cyw
    local y1 = ny * cp - z1 * sp
    local z2 = ny * sp + z1 * cp
    return x1, y1, z2
  end
end

-- light from the upper left, in front
local LX, LY, LZ = -0.45, -0.6, -0.66
local function lit(c, nx, ny, nz, amb)
  local d = -(nx * LX + ny * LY + nz * LZ)
  local k = (amb or 0.5) + (1 - (amb or 0.5)) * math.max(0, d)
  return c[1] / 255 * k, c[2] / 255 * k, c[3] / 255 * k
end

local function facing(pts)
  -- screen-space winding: front-facing when clockwise on screen (y down)
  local a = 0
  for i = 1, #pts do
    local p, q = pts[i], pts[i % #pts + 1]
    a = a + (p[1] * q[2] - q[1] * p[2])
  end
  return a > 0
end

local function poly(pts)
  local flat = {}
  for _, p in ipairs(pts) do flat[#flat + 1] = p[1]; flat[#flat + 1] = p[2] end
  if #flat >= 6 then
    local ok = pcall(lg.polygon, "fill", flat)
    if not ok then
      -- a concave outline: fan it from the first point
      for i = 2, #pts - 1 do
        lg.polygon("fill", pts[1][1], pts[1][2], pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2])
      end
    end
  end
end

-- a flat rectangle on the front face (z = zf), projected
local function frontRect(P, x, y, w, h, zf)
  local a = { P(x, y, zf) }
  local b = { P(x + w, y, zf) }
  local c = { P(x + w, y + h, zf) }
  local d = { P(x, y + h, zf) }
  return { a, b, c, d }
end

-- the label: a subdivided mesh so it keeps its perspective
local meshCache = {}
local function labelMesh(img, P, x, y, w, h, zf)
  local n = 6
  local verts = {}
  for j = 0, n do
    for i = 0, n do
      local u, v = i / n, j / n
      local sx, sy = P(x + u * w, y + v * h, zf)
      verts[#verts + 1] = { sx, sy, u, v, 1, 1, 1, 1 }
    end
  end
  local key = img
  local m = meshCache[key]
  if not m then
    local map = {}
    for j = 0, n - 1 do
      for i = 0, n - 1 do
        local a = j * (n + 1) + i + 1
        local b, c, d = a + 1, a + n + 1, a + n + 2
        for _, v in ipairs({ a, b, d, a, d, c }) do map[#map + 1] = v end
      end
    end
    m = lg.newMesh(#verts, "triangles", "stream")
    m:setVertexMap(map)
    m:setTexture(img)
    meshCache[key] = m
  end
  m:setVertices(verts)
  lg.draw(m)
end

---------------------------------------------------------------- drawing

-- Draw the cartridge for `version` floating in rect r at time t; `skin`
-- (the launcher's own cart skin, when it has one) gives the shell colour,
-- the shape and the label.
function C.draw(r, version, t, skin)
  local key = version .. "|" .. tostring(skin and skin.cacheKey)
  if shown.version ~= key then
    shown.version, shown.since = key, t
  end
  local gba = (skin and skin.shape == "gba") or (not skin and isGba(version))
  local M = model(gba)
  local color = (skin and skin.color) or SHELL[version] or { 180, 180, 190 }
  -- the float: a slow bob and sway; a spin-in when the game changes
  local spin = math.max(0, 1 - (t - shown.since) / 0.55)
  spin = spin * spin * (3 - 2 * spin)
  local yaw = 0.32 * math.sin(t * 0.55) + spin * math.pi * 1.0
  local pitch = -0.1 + 0.07 * math.sin(t * 0.43 + 1.3)
  local bob = math.sin(t * 1.25)
  local scale = math.min(r.w * 0.55, r.h * 0.8 / M.h)
  local cx, cy = r.x + r.w / 2, r.y + r.h * 0.46 + bob * r.h * 0.025
  local P, N = projector(cx, cy, scale, yaw, pitch)
  local zf, zb = -M.d / 2, M.d / 2
  lg.push("all")
  -- the shadow under it, smaller and fainter as it rises
  local sh = 0.26 - bob * 0.05
  lg.setColor(0, 0, 0, sh)
  lg.ellipse("fill", cx, r.y + r.h * 0.9, scale * (0.42 - bob * 0.03) * (gba and 1.1 or 1), r.h * 0.035)
  -- the solid: back, walls, front, painter's order
  local front, back = {}, {}
  for i, p in ipairs(M.outline) do
    front[i] = { P(p[1], p[2], zf) }
    back[i] = { P(p[1], p[2], zb) }
  end
  local backRev = {}
  for i = #back, 1, -1 do backRev[#backRev + 1] = back[i] end
  -- walls, farthest first
  local walls = {}
  for i = 1, #M.outline do
    local a, b = M.outline[i], M.outline[i % #M.outline + 1]
    local ex, ey = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(ex * ex + ey * ey)
    local nx, ny = ey / len, -ex / len
    local tnx, tny, tnz = N(nx, ny, 0)
    local pts = { front[i], front[i % #front + 1], back[i % #back + 1], back[i] }
    local z = (pts[1][3] + pts[2][3] + pts[3][3] + pts[4][3]) / 4
    walls[#walls + 1] = { pts = pts, z = z, n = { tnx, tny, tnz } }
  end
  table.sort(walls, function(a, b) return a.z > b.z end)
  local bnx, bny, bnz = N(0, 0, 1)
  if bnz < 0 then
    lg.setColor(lit(color, bnx, bny, bnz, 0.35))
    poly(backRev)
  end
  for _, wl in ipairs(walls) do
    if wl.n[3] < 0.05 then
      local rr, gg, bb = lit(color, wl.n[1], wl.n[2], wl.n[3], 0.4)
      lg.setColor(rr * 0.85, gg * 0.85, bb * 0.85, 1)
      poly(wl.pts)
    end
  end
  local fnx, fny, fnz = N(0, 0, -1)
  if fnz < 0 then
    lg.setColor(lit(color, fnx, fny, fnz, 0.55))
    poly(front)
    -- a soft sheen across the upper face
    lg.setColor(1, 1, 1, 0.08)
    poly(frontRect(P, -0.5 + M.cut * 0.2, -M.h / 2 + 0.02, 0.9, M.h * 0.28, zf - 0.001))
    -- the grip groove and the arrow
    if M.groove then
      local g = M.groove
      local rr, gg, bb = lit(color, fnx, fny, fnz, 0.55)
      lg.setColor(rr * 0.72, gg * 0.72, bb * 0.72, 1)
      poly(frontRect(P, g[1], g[2], g[3], g[4], zf - 0.002))
      lg.setColor(rr * 1.08, gg * 1.08, bb * 1.08, 1)
      poly(frontRect(P, g[1] + 0.01, g[2] + g[4] * 0.6, g[3] - 0.02, g[4] * 0.35, zf - 0.003))
      -- vents either side of the groove
      for k = 0, 3 do
        local vy = -M.h / 2 + 0.08 + k * 0.03
        lg.setColor(rr * 0.7, gg * 0.7, bb * 0.7, 1)
        poly(frontRect(P, -0.46, vy, 0.12, 0.012, zf - 0.002))
        poly(frontRect(P, 0.34 - M.cut * 0.3, vy + 0.02, 0.1, 0.012, zf - 0.002))
      end
    end
    if M.arrow then
      local a = M.arrow
      local rr, gg, bb = lit(color, fnx, fny, fnz, 0.55)
      lg.setColor(rr * 0.7, gg * 0.7, bb * 0.7, 1)
      local p1 = { P(a[1] - a[3], a[2] - a[3] * 0.55, zf - 0.002) }
      local p2 = { P(a[1] + a[3], a[2] - a[3] * 0.55, zf - 0.002) }
      local p3 = { P(a[1], a[2] + a[3] * 0.45, zf - 0.002) }
      poly({ p1, p2, p3 })
    end
    -- the label recess, then the label
    local L = M.labelRect
    local rr, gg, bb = lit(color, fnx, fny, fnz, 0.55)
    lg.setColor(rr * 0.6, gg * 0.6, bb * 0.6, 1)
    poly(frontRect(P, L[1] - 0.025, L[2] - 0.025, L[3] + 0.05, L[4] + 0.05, zf - 0.002))
    local img = label(version, skin and skin.labelPath)
    local shade = 0.72 + 0.28 * math.max(0, -(fnx * LX + fny * LY + fnz * LZ))
    if img then
      -- the art fitted into the recess, its own proportions kept
      local iw, ih = img:getDimensions()
      local lw, lh = L[3], L[4]
      if iw / ih > lw / lh then lh = lw * ih / iw else lw = lh * iw / ih end
      lg.setColor(shade, shade, shade, 1)
      labelMesh(img, P, L[1] + (L[3] - lw) / 2, L[2] + (L[4] - lh) / 2, lw, lh, zf - 0.004)
    else
      lg.setColor(0.9 * shade, 0.9 * shade, 0.92 * shade, 1)
      poly(frontRect(P, L[1], L[2], L[3], L[4], zf - 0.004))
    end
  end
  lg.pop()
end

return C
