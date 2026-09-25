-- A 3D Game Boy Color cartridge for the 3DS theme's top screen: a real
-- solid (front, back and side walls, lit from the upper left), the GBC
-- cart's shape -- the cut top-right corner, the grip groove across its top,
-- the recessed label, the arrow at its foot -- in the game's own colour,
-- with the game's label on the front.  It floats the way the 3DS shows a
-- title's banner: a slow bob, a gentle sway, a soft shadow that breathes
-- under it, a spin into place when another game is chosen, and a quick
-- spin when the phone is moved (C.kick, from the gyroscope) while it leans
-- a little with the phone's tilt (C.setTilt).  GBA games (FireRed,
-- LeafGreen) get the GBA cart: 57 x 35 x 7.5 mm, the top edge arched, the
-- grip ridges above a wide label, the locking notches in its sides.
--
-- Shells are the real carts' colours: Red, Blue, Yellow, Gold and Silver
-- solid, Crystal and the GBA pair see-through (the board shows inside).
-- Labels: fold3ds/labels/<version>.png, else the launcher's; either is
-- cropped to fill the label, not squeezed.
local C = {}

local lg = love.graphics
local DIR = "fold3ds/labels/"

-- the real cartridges' shells, per game (0-255, and how solid)
local SHELL = {
  red = { 200, 36, 44 }, blue = { 40, 88, 192 }, yellow = { 242, 200, 30 },
  green = { 150, 152, 160 },                       -- Japan's Green: a grey cart
  gold = { 210, 168, 64 }, silver = { 184, 190, 198 },
  crystal = { 150, 168, 232, 0.7 },                -- see-through blue-violet
  firered = { 238, 58, 42, 0.74 }, leafgreen = { 64, 196, 78, 0.74 },
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

-- motion: a quick spin when the phone is moved, a lean with its tilt
local motion = { kickAt = -10, tx = 0, ty = 0 }
function C.kick(t)
  if t - motion.kickAt > 1.2 then motion.kickAt = t end
end
function C.setTilt(x, y)
  motion.tx = motion.tx + (math.max(-1, math.min(1, x)) - motion.tx) * 0.1
  motion.ty = motion.ty + (math.max(-1, math.min(1, y)) - motion.ty) * 0.1
end

local function isGba(version)
  return version == "firered" or version == "leafgreen"
end

---------------------------------------------------------------- the model
-- Units: the cart is 1 wide; y runs down; z runs away from the viewer.

local function model(gba)
  if gba then
    -- 57 x 35 x 7.5 mm: the top edge gently arched, the corners rounded
    local w, h, d = 1, 0.614, 0.13
    local top, out = -h / 2, {}
    local function add(x, y) out[#out + 1] = { x, y } end
    add(-0.5, top + 0.09); add(-0.487, top + 0.052); add(-0.462, top + 0.034)
    for i = 0, 8 do
      local x = -0.44 + 0.88 * i / 8
      add(x, top + 0.03 * (x / 0.44) ^ 2)
    end
    add(0.462, top + 0.034); add(0.487, top + 0.052); add(0.5, top + 0.09)
    add(0.5, h / 2 - 0.03); add(0.49, h / 2 - 0.009); add(0.47, h / 2)
    add(-0.47, h / 2); add(-0.49, h / 2 - 0.009); add(-0.5, h / 2 - 0.03)
    return { w = w, h = h, d = d, cut = 0, gba = true,
      outline = out,
      labelRect = { -0.43, top + 0.15, 0.86, h - 0.15 - 0.055 },
      ridges = { top + 0.055, top + 0.08, top + 0.105 },
      notches = { top + 0.1, 0.07 },
      board = { -0.4, top + 0.07, 0.8, h - 0.1 } }
  end
  local w, h, d = 1, 1.14, 0.13
  local cut = 0.11
  return { w = w, h = h, d = d, cut = cut,
    outline = { { -0.5, -h / 2 }, { 0.5 - cut, -h / 2 }, { 0.5, -h / 2 + cut }, { 0.5, h / 2 }, { -0.5, h / 2 } },
    labelRect = { -0.38, -h / 2 + 0.25, 0.76, 0.7 },
    groove = { -0.3, -h / 2 + 0.08, 0.6, 0.1 },
    board = { -0.38, -h / 2 + 0.12, 0.76, h - 0.2 },
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
local function labelMesh(img, P, x, y, w, h, zf, uv)
  local n = 6
  local verts = {}
  local u0, v0, u1, v1 = uv[1], uv[2], uv[3], uv[4]
  for j = 0, n do
    for i = 0, n do
      local u, v = i / n, j / n
      local sx, sy = P(x + u * w, y + v * h, zf)
      verts[#verts + 1] = { sx, sy, u0 + (u1 - u0) * u, v0 + (v1 - v0) * v, 1, 1, 1, 1 }
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
  -- a custom cart keeps its own colour; the stock carts wear the real one
  local color = (skin and skin.cart and skin.color) or SHELL[version] or (skin and skin.color) or { 180, 180, 190 }
  local alpha = color[4] or 1
  -- the float: a slow bob and sway; a spin-in when the game changes
  local spin = math.max(0, 1 - (t - shown.since) / 0.55)
  spin = spin * spin * (3 - 2 * spin)
  -- the phone moved: one quick turn
  local k = (t - motion.kickAt) / 0.7
  local kick = 0
  if k >= 0 and k < 1 then kick = k * k * (3 - 2 * k) * math.pi * 2 end
  local yaw = 0.32 * math.sin(t * 0.55) + spin * math.pi * 1.0 + kick + motion.tx * 0.45
  local pitch = -0.1 + 0.07 * math.sin(t * 0.43 + 1.3) + motion.ty * 0.3
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
    local rr, gg, bb = lit(color, bnx, bny, bnz, 0.35)
    lg.setColor(rr, gg, bb, alpha)
    poly(backRev)
  end
  if alpha < 1 and M.board then
    -- a see-through shell: the circuit board and its chip inside
    local b = M.board
    lg.setColor(0.08, 0.3, 0.16, 0.9)
    poly(frontRect(P, b[1], b[2], b[3], b[4], 0))
    lg.setColor(0.06, 0.06, 0.07, 0.9)
    poly(frontRect(P, b[1] + b[3] * 0.3, b[2] + b[4] * 0.25, b[3] * 0.4, b[4] * 0.3, -0.001))
    lg.setColor(0.8, 0.66, 0.2, 0.9)
    for i = 0, 9 do
      poly(frontRect(P, b[1] + b[3] * (0.06 + i * 0.09), b[2] + b[4] * 0.9, b[3] * 0.05, b[4] * 0.08, -0.001))
    end
  end
  for _, wl in ipairs(walls) do
    if wl.n[3] < 0.05 then
      local rr, gg, bb = lit(color, wl.n[1], wl.n[2], wl.n[3], 0.4)
      lg.setColor(rr * 0.85, gg * 0.85, bb * 0.85, math.min(1, alpha + 0.12))
      poly(wl.pts)
    end
  end
  local fnx, fny, fnz = N(0, 0, -1)
  if fnz < 0 then
    local fr, fg, fb = lit(color, fnx, fny, fnz, 0.55)
    lg.setColor(fr, fg, fb, alpha)
    poly(front)
    if M.ridges then
      -- the GBA cart's grip ridges, and the notches in its sides
      for _, ry in ipairs(M.ridges) do
        lg.setColor(fr * 0.7, fg * 0.7, fb * 0.7, math.max(alpha, 0.85))
        poly(frontRect(P, -0.36, ry, 0.72, 0.01, zf - 0.002))
        lg.setColor(math.min(1, fr * 1.15), math.min(1, fg * 1.15), math.min(1, fb * 1.15), math.max(alpha, 0.85))
        poly(frontRect(P, -0.36, ry + 0.01, 0.72, 0.006, zf - 0.002))
      end
      local ny, nh = M.notches[1], M.notches[2]
      lg.setColor(fr * 0.5, fg * 0.5, fb * 0.5, 1)
      poly(frontRect(P, -0.5, ny, 0.025, nh, zf - 0.002))
      poly(frontRect(P, 0.475, ny, 0.025, nh, zf - 0.002))
    end
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
    lg.setColor(rr * 0.6, gg * 0.6, bb * 0.6, math.max(alpha, 0.9))
    poly(frontRect(P, L[1] - 0.025, L[2] - 0.025, L[3] + 0.05, L[4] + 0.05, zf - 0.002))
    local img = label(version, skin and skin.labelPath)
    local shade = 0.72 + 0.28 * math.max(0, -(fnx * LX + fny * LY + fnz * LZ))
    if img then
      -- the art filling the recess: cropped to its shape, never squeezed
      local iw, ih = img:getDimensions()
      local ra, ia = L[3] / L[4], iw / ih
      local uv = { 0, 0, 1, 1 }
      if ia > ra then
        local f = ra / ia
        uv = { (1 - f) / 2, 0, (1 + f) / 2, 1 }
      else
        local f = ia / ra
        uv = { 0, (1 - f) / 2, 1, (1 + f) / 2 }
      end
      lg.setColor(shade, shade, shade, 1)
      labelMesh(img, P, L[1], L[2], L[3], L[4], zf - 0.004, uv)
    else
      lg.setColor(0.9 * shade, 0.9 * shade, 0.92 * shade, 1)
      poly(frontRect(P, L[1], L[2], L[3], L[4], zf - 0.004))
    end
  end
  lg.pop()
end

return C
