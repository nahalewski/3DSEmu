-- Cover stickers: pictures of the player's own, cropped, cornered, edged in
-- white and stuck on the closed lid (the cover screen) -- as many as they
-- like, stacked in the order they were stuck (the newest on top).
--
-- On the cover a sticker can be peeled: drag it and the corner nearest the
-- finger lifts, folding back to show the white backing; peel it far enough
-- and it comes off in the finger (a second finger twists it), and letting
-- go sticks it down again where it is.  Every re-stick costs it some grip:
-- its corner stays lifted a little more each time, and a sticker that has
-- been re-stuck starts to wear with play time (the play meter's hours) --
-- the more times re-stuck, the sooner -- until it falls off the cover.  A
-- sticker never peeled stays on for good.  Fallen stickers wait in SKINS to
-- be put back.
--
-- SKINS opens the editor (a new sticker, or the top one): the bottom
-- screen crops the picture and sets its corners, size, rotation and white
-- edge; the top screen previews the cover -- drag the sticker to place it,
-- drag the round knob above it to turn it freely.
--
-- Stickers keep their proportions, sit on the lid's flat face and are cut
-- to the shell's shape, so none ever stretches the lid or hangs off it.
--
-- Files in the save directory:
--   fold3ds_stickers.cfg            one line per sticker, bottom to top
--   fold3ds_sticker_<id>.png        the finished sticker (cut, cornered, edged)
--   fold3ds_sticker_<id>_src.png    the picture as picked (kept to re-crop)
local S = {}

local lg = love.graphics
local LIST_FILE = "fold3ds_stickers.cfg"
local PICKED = "picked_image.img"       -- where Android's picker lands
local MAX_SIDE = 1024                   -- the finished sticker's long side, px
local MAX_SRC = 2048                    -- a huge photo is scaled down to this
-- the single sticker of the first version, taken into the list once
local OLD = { out = "fold3ds_sticker.png", src = "fold3ds_sticker_src.png", cfg = "fold3ds_sticker.cfg" }

local HOUR = 3600
local PEEL_OFF = 0.8          -- peeled this far (share of the diagonal): it comes off
local RESTICK = 0.22          -- peeled at least this far and let go: it was re-stuck
local FALL_TIME = 1.3         -- the fall, seconds

local ctx                               -- from init: real setCanvas, font()
local Sfx = require("fold3ds.sfx")
local list = {}                         -- stickers, bottom to top
local nextId = 1
local ed = nil                          -- the open editor
local pickWait = nil                    -- { since, modtime } a pick in flight
local grab = nil                        -- a finger peeling / holding a sticker
local twist = nil                       -- a second finger turning a held sticker
local dirty = 0
local shaders = {}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function now() return love.timer.getTime() end

local function srcFile(id) return ("fold3ds_sticker_%d_src.png"):format(id) end
local function outFile(id) return ("fold3ds_sticker_%d.png"):format(id) end

local function defaults(iw, ih)
  -- a centred square-ish crop of the middle of the picture
  local side = math.min(iw, ih) * 0.9
  return {
    cx = (iw - side) / 2, cy = (ih - side) / 2, cw = side, ch = side,
    round = 0.18,                        -- corner radius, share of the short side
    outline = true,
    size = 0.34,                         -- width on the lid, share of the lid width
    px = 0.36, py = 0.42,                -- centre on the lid, 0..1 of the lid box
    rot = 0,                             -- radians
  }
end

---------------------------------------------------------------- wear

-- play time a re-stuck sticker holds before it falls: two days' play after
-- the first re-stick, less each time, never under four hours
local function life(st)
  if (st.peels or 0) <= 0 then return math.huge end
  return math.max(4 * HOUR, 48 * HOUR / st.peels)
end

-- how far its corner stands up at rest, 0..1
local function lift(st)
  if (st.peels or 0) <= 0 then return 0 end
  local base = math.min(0.45, 0.09 * st.peels)
  return base + (0.9 - base) * clamp((st.worn or 0) / life(st), 0, 1)
end

---------------------------------------------------------------- files

local FIELDS = { "cx", "cy", "cw", "ch", "round", "size", "px", "py", "rot", "worn", "surf" }

local function encode(st)
  local out = { ("id=%d"):format(st.id) }
  for _, k in ipairs(FIELDS) do out[#out + 1] = ("%s=%.5f"):format(k, st[k] or 0) end
  out[#out + 1] = ("peels=%d"):format(st.peels or 0)
  out[#out + 1] = ("corner=%d"):format(st.corner or 1)
  out[#out + 1] = "outline=" .. (st.outline and "1" or "0")
  out[#out + 1] = "on=" .. (st.on and "1" or "0")
  return table.concat(out, " ")
end

local function decode(line)
  local st = {}
  for k, v in line:gmatch("(%w+)=([%w%.%-]+)") do
    if k == "outline" or k == "on" then st[k] = v == "1" else st[k] = tonumber(v) end
  end
  return st
end

local function saveList()
  local lines = {}
  for _, st in ipairs(list) do lines[#lines + 1] = encode(st) end
  pcall(love.filesystem.write, LIST_FILE, table.concat(lines, "\n") .. "\n")
  dirty = 0
end

local function loadImage(st)
  local ok, img = pcall(lg.newImage, outFile(st.id))
  if ok then img:setFilter("linear", "linear"); st.img = img end
  return st.img ~= nil
end

-- the first version kept one sticker in three files: take it into the list
local function migrate()
  if love.filesystem.getInfo(LIST_FILE) or not love.filesystem.getInfo(OLD.out) then return end
  local st = defaults(1, 1)
  local text = love.filesystem.read(OLD.cfg) or ""
  for k, v in text:gmatch("(%w+)=([%w%.%-]+)") do
    if k == "outline" then st.outline = v == "1" else st[k] = tonumber(v) end
  end
  st.id, st.peels, st.worn, st.corner, st.on = 1, 0, 0, 1, true
  local okO, out = pcall(love.filesystem.read, OLD.out)
  local okS, src = pcall(love.filesystem.read, OLD.src)
  if okO and out then love.filesystem.write(outFile(1), out) end
  if okS and src then love.filesystem.write(srcFile(1), src) end
  list = { st }
  saveList()
  love.filesystem.remove(OLD.out)
  love.filesystem.remove(OLD.src)
  love.filesystem.remove(OLD.cfg)
end

function S.load()
  migrate()
  list = {}
  local text = love.filesystem.getInfo(LIST_FILE) and love.filesystem.read(LIST_FILE) or ""
  for line in text:gmatch("[^\n]+") do
    local st = decode(line)
    if st.id then
      local d = defaults(1, 1)
      for k, v in pairs(d) do if st[k] == nil then st[k] = v end end
      st.peels, st.worn, st.corner = st.peels or 0, st.worn or 0, st.corner or 1
      if loadImage(st) then list[#list + 1] = st end
      nextId = math.max(nextId, st.id + 1)
    end
  end
end

local function readImageData(name)
  local ok, data = pcall(love.image.newImageData, name)
  if ok then return data end
  return nil
end

-- A picked photo can be 12 megapixels; the editor and the sticker never need
-- more than MAX_SRC on a side.
local function shrink(data)
  local w, h = data:getDimensions()
  local k = MAX_SRC / math.max(w, h)
  if k >= 1 then return data end
  local nw, nh = math.max(1, math.floor(w * k)), math.max(1, math.floor(h * k))
  local img = lg.newImage(data)
  local c = lg.newCanvas(nw, nh, { dpiscale = 1 })
  lg.push("all")
  ctx.setCanvas(c)
  lg.origin()
  lg.clear(0, 0, 0, 0)
  lg.setColor(1, 1, 1, 1)
  lg.draw(img, 0, 0, 0, nw / w, nh / h)
  ctx.setCanvas()
  lg.pop()
  return c:newImageData()
end

---------------------------------------------------------------- rendering

local function roundRect(mode, x, y, w, h, r)
  r = math.max(0, math.min(r, w / 2, h / 2))
  lg.rectangle(mode, x, y, w, h, r, r, 24)
end

-- the sticker's silhouette in one colour (its backing, its shadow)
local function flatShader()
  shaders.flat = shaders.flat or lg.newShader([[
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      return vec4(color.rgb, Texel(tex, tc).a * color.a);
    }
  ]])
  return shaders.flat
end

-- Draw the sticker (cut from `img` by c) with its top-left at x, y and
-- width w.  `masked`: stencil value 1 already marks where it may show (the
-- shell), so its own rounded cut stacks on that instead of replacing it.
local function drawSticker(img, c, x, y, w, masked)
  local ih = w * c.ch / c.cw
  local short = math.min(w, ih)
  local edge = c.outline and short * 0.055 or 0
  local r = c.round * short
  local px, py, pw, ph = x + edge, y + edge, w - 2 * edge, ih - 2 * edge
  local pr = math.max(0, r - edge)
  if masked then lg.setStencilTest("greater", 0) end
  if c.outline then
    lg.setColor(1, 1, 1, 1)
    roundRect("fill", x, y, w, ih, r)
  end
  if masked then
    lg.stencil(function() roundRect("fill", px, py, pw, ph, pr) end, "increment", 1, true)
    lg.setStencilTest("greater", 1)
  else
    lg.stencil(function() roundRect("fill", px, py, pw, ph, pr) end, "replace", 1)
    lg.setStencilTest("greater", 0)
  end
  lg.setColor(1, 1, 1, 1)
  local iw, ihh = img:getDimensions()
  local q = lg.newQuad(c.cx, c.cy, c.cw, c.ch, iw, ihh)
  lg.draw(img, q, px, py, 0, pw / c.cw, ph / c.ch)
  lg.setStencilTest()
end

-- the finished sticker as an image (MAX_SIDE on its long side)
local function bake(img, c)
  local w, h
  if c.cw >= c.ch then w = MAX_SIDE; h = math.floor(MAX_SIDE * c.ch / c.cw)
  else h = MAX_SIDE; w = math.floor(MAX_SIDE * c.cw / c.ch) end
  local canvas = lg.newCanvas(w, h, { dpiscale = 1 })
  lg.push("all")
  ctx.setCanvas({ canvas, stencil = true })
  lg.origin()
  lg.clear(0, 0, 0, 0)
  drawSticker(img, c, 0, 0, w)
  ctx.setCanvas()
  lg.pop()
  return canvas
end

-- The flat of the lid inside its box: clear of the rounded corners' worst
-- and of the hinge along the bottom (landscape, before any turn).
-- Where a sticker sits: surf 0 the closed lid (the cover screen), 1 the
-- open 3DS's top shell, 2 its bottom shell (the shells' art is their mask,
-- so nothing lands on a screen).  Each surface's face, in shares of its box.
local FACES = {
  [0] = { left = 0.035, right = 0.035, top = 0.06, bottom = 0.2 },
  [1] = { left = 0.02, right = 0.02, top = 0.02, bottom = 0.02 },
  [2] = { left = 0.02, right = 0.02, top = 0.02, bottom = 0.02 },
}
local FACE = FACES[0]

-- a sticker's size and centre on a lid box of bw x bh: its proportions
-- kept, the centre held on the face, the size no larger than the face
local function geometry(st, bw, bh)
  local FACE = FACES[math.floor(st.surf or 0)] or FACES[0]
  local aspect = st.cw / st.ch
  local x0, x1 = bw * FACE.left, bw * (1 - FACE.right)
  local y0, y1 = bh * FACE.top, bh * (1 - FACE.bottom)
  local w = st.size * bw
  local h = w / aspect
  local maxW = math.min(x1 - x0, (y1 - y0) * aspect)
  if w > maxW then w = maxW; h = w / aspect end
  -- the whole turned outline stays on the face
  local c, sn = math.abs(math.cos(st.rot or 0)), math.abs(math.sin(st.rot or 0))
  local hx, hy = w / 2 * c + h / 2 * sn, w / 2 * sn + h / 2 * c
  local k = math.min(1, (x1 - x0) / (2 * hx), (y1 - y0) / (2 * hy))
  if k < 1 then w, h, hx, hy = w * k, h * k, hx * k, hy * k end
  local cx = clamp(st.px * bw, x0 + hx, x1 - hx)
  local cy = clamp(st.py * bh, y0 + hy, y1 - hy)
  return cx, cy, w, h
end
S.geometry = geometry

-- a point on the lid box, in a sticker's own frame (centred, unturned)
local function toLocal(st, bx, by, bw, bh)
  local cx, cy, w, h = geometry(st, bw, bh)
  local dx, dy = bx - cx, by - cy
  local c, s = math.cos(-st.rot), math.sin(-st.rot)
  return dx * c - dy * s, dx * s + dy * c, w, h
end

-- a half-plane as a big quad: the side of the line through m (normal n)
-- that n points to
local function halfPlane(mx, my, nx, ny, big)
  local tx, ty = -ny, nx
  return { mx + tx * big, my + ty * big, mx - tx * big, my - ty * big,
           mx - tx * big + nx * big, my - ty * big + ny * big,
           mx + tx * big + nx * big, my + ty * big + ny * big }
end

-- Draw one stuck sticker in its own frame, with a fold: corner (cxl, cyl)
-- lifted to (pxl, pyl).  The rest stays down (cut by the shell mask when
-- `mask`), the flap folds back over it showing its white backing.
local function drawFolded(st, w, h, fold, mask, drawFlat)
  local img = st.img
  local iw, ih = img:getDimensions()
  local sx, sy = w / iw, h / ih
  local short = math.min(w, h)
  if not fold then
    lg.setStencilTest("greater", 0)
    drawFlat()
    lg.setColor(1, 1, 1, 1)
    lg.draw(img, -w / 2, -h / 2, 0, sx, sy)
    lg.setStencilTest()
    return
  end
  local cx, cy, px, py = fold[1], fold[2], fold[3], fold[4]
  local dx, dy = px - cx, py - cy
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 0.5 then return drawFolded(st, w, h, nil, mask, drawFlat) end
  local nx, ny = dx / d, dy / d
  local mx, my = (cx + px) / 2, (cy + py) / 2
  local big = (w + h) * 3
  -- the part still stuck: the far side of the fold line from the corner
  lg.stencil(function() lg.polygon("fill", halfPlane(mx, my, nx, ny, big)) end, "increment", 1, true)
  lg.setStencilTest("greater", 1)
  drawFlat()
  lg.setColor(1, 1, 1, 1)
  lg.draw(img, -w / 2, -h / 2, 0, sx, sy)
  lg.setStencilTest()
  -- the flap: the corner's side, mirrored over the fold line
  local a, b = 1 - 2 * nx * nx, -2 * nx * ny
  local dd = 1 - 2 * ny * ny
  local k = 2 * (mx * nx + my * ny)
  local tf = love.math.newTransform()
  tf:setMatrix(a, b, 0, k * nx, b, dd, 0, k * ny, 0, 0, 1, 0, 0, 0, 0, 1)
  lg.push()
  lg.applyTransform(tf)
  lg.stencil(function() lg.polygon("fill", halfPlane(mx, my, -nx, -ny, big)) end, "replace", 1)
  lg.setStencilTest("greater", 0)
  lg.setShader(flatShader())
  -- its shadow on the cover, then its backing
  lg.push()
  lg.translate(-nx * short * 0.04, -ny * short * 0.04)
  lg.setColor(0, 0, 0, 0.22)
  lg.draw(img, -w / 2, -h / 2, 0, sx, sy)
  lg.pop()
  local shade = 0.97 - 0.12 * clamp(d / (w + h), 0, 1)
  lg.setColor(shade, shade, shade * 0.97, 1)
  lg.draw(img, -w / 2, -h / 2, 0, sx, sy)
  -- a soft crease along the fold: the backing darker in a band beside it
  lg.stencil(function() lg.polygon("fill", halfPlane(mx - nx * short * 0.06, my - ny * short * 0.06, nx, ny, big)) end,
    "increment", 1, true)
  lg.setStencilTest("greater", 1)
  lg.setColor(shade * 0.84, shade * 0.84, shade * 0.82, 1)
  lg.draw(img, -w / 2, -h / 2, 0, sx, sy)
  lg.setShader()
  lg.setStencilTest()
  lg.pop()
end

-- the corner a sticker's wear lifts, and how far, in its own frame
local CORNERS = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }
local function restFold(st, w, h)
  local l = lift(st)
  if l < 0.02 then return nil end
  local c = CORNERS[st.corner or 1] or CORNERS[1]
  local cx, cy = c[1] * w / 2, c[2] * h / 2
  local short = math.min(w, h)
  -- past the rounded corner's empty tip, then growing with the wear
  local len = short * ((st.round or 0.18) * 0.9 + 0.05 + l * 0.45)
  local ix, iy = -c[1], -c[2]
  local n = math.sqrt(2)
  return { cx, cy, cx + ix / n * len, cy + iy / n * len }
end

---------------------------------------------------------------- the cover

local lastBox = nil        -- the cover's lid box transform (for touches)

-- Draw the stickers on the lid.  The caller has set up the lid's space: box
-- origin ox, oy at scale s (units per lid-box pixel), box bw x bh.  `mask`
-- draws the shell's own shape (in that same space): whatever hangs off it
-- is cut away.  `cover`: this is the cover screen itself (touchable).
function S.drawOnLid(ox, oy, s, bw, bh, mask, cover, surf)
  local t = now()
  surf = surf or 0
  lg.push("all")
  for _, st in ipairs(list) do
    local editing = ed and ed.target == st
    local held = grab and grab.st == st and grab.held
    if st.on and not editing and not held and math.floor(st.surf or 0) == surf then
      if st.fall and st.fall.pending then st.fall = { t0 = t }; Sfx.play("fall") end
      local cx, cy, w, h = geometry(st, bw, bh)
      lg.stencil(mask or function() lg.rectangle("fill", -1e5, -1e5, 2e5, 2e5) end, "replace", 1)
      lg.push()
      lg.translate(ox, oy)
      lg.scale(s, s)
      local alpha = 1
      if st.fall then
        local k = clamp((t - st.fall.t0) / FALL_TIME, 0, 1)
        lg.translate(cx, cy + k * k * bh * 0.9)
        lg.rotate(st.rot + k * 0.9 * ((st.id % 2 == 0) and 1 or -1))
        alpha = 1 - k
        lg.setColor(1, 1, 1, alpha)
        lg.draw(st.img, -w / 2, -h / 2, 0, w / st.img:getWidth(), h / st.img:getHeight())
      else
        lg.translate(cx, cy)
        lg.rotate(st.rot)
        local fold
        if grab and grab.st == st and grab.fold then fold = grab.fold else fold = restFold(st, w, h) end
        local short = math.min(w, h)
        local ofx, ofy = short * 0.02, short * 0.035
        local c, sn = math.cos(-st.rot), math.sin(-st.rot)
        local sdx, sdy = ofx * c - ofy * sn, ofx * sn + ofy * c
        drawFolded(st, w, h, fold, mask, function()
          -- its shadow on whatever is under it
          lg.setShader(flatShader())
          lg.setColor(0, 0, 0, 0.3)
          lg.draw(st.img, -w / 2 + sdx, -h / 2 + sdy, 0, w / st.img:getWidth(), h / st.img:getHeight())
          lg.setShader()
        end)
      end
      lg.pop()
    end
  end
  lg.setStencilTest()
  -- the sticker being edited, live
  if ed and ed.img and cover ~= "shell" and (ed.surf or 0) == surf then
    local c = ed.cfg
    local cx, cy, w, h = geometry(c, bw, bh)
    if mask then lg.stencil(mask, "replace", 1) end
    lg.push()
    lg.translate(ox, oy)
    lg.scale(s, s)
    lg.translate(cx, cy)
    lg.rotate(c.rot)
    lg.setColor(0, 0, 0, 0.3)
    roundRect("fill", -w / 2 + math.min(w, h) * 0.02, -h / 2 + math.min(w, h) * 0.035, w, h, c.round * math.min(w, h))
    drawSticker(ed.img, c, -w / 2, -h / 2, w, mask ~= nil)
    lg.pop()
    lg.setStencilTest()
    -- the turn knob above it (screen coordinates for touches)
    local kx, ky = cx + math.sin(c.rot) * (h / 2 + bh * 0.07), cy - math.cos(c.rot) * (h / 2 + bh * 0.07)
    local sx0, sy0 = lg.transformPoint(ox + cx * s, oy + cy * s)
    local skx, sky = lg.transformPoint(ox + kx * s, oy + ky * s)
    lg.setColor(1, 1, 1, 0.9)
    lg.setLineWidth(2)
    lg.line(ox + cx * s + math.sin(c.rot) * h / 2 * s, oy + cy * s - math.cos(c.rot) * h / 2 * s, ox + kx * s, oy + ky * s)
    lg.circle("fill", ox + kx * s, oy + ky * s, bh * s * 0.035)
    lg.setColor(0.2, 0.55, 0.95, 1)
    lg.circle("fill", ox + kx * s, oy + ky * s, bh * s * 0.022)
    local lox, loy = lg.transformPoint(ox, oy)
    ed.lidRect = { ox = lox, oy = loy, s = s, bw = bw, bh = bh, knob = { skx, sky }, centre = { sx0, sy0 } }
  end
  -- a sticker peeled off, in the finger: lifted, bigger, its shadow further
  if grab and grab.held and cover then
    local st = grab.st
    local _, _, w, h = geometry(st, bw, bh)
    lg.push()
    lg.translate(ox, oy)
    lg.scale(s, s)
    lg.translate(grab.bx, grab.by)
    lg.rotate(st.rot)
    lg.setShader(flatShader())
    lg.setColor(0, 0, 0, 0.3)
    lg.draw(st.img, -w * 0.53 + w * 0.05, -h * 0.53 + h * 0.08, 0, w * 1.06 / st.img:getWidth(), h * 1.06 / st.img:getHeight())
    lg.setShader()
    lg.setColor(1, 1, 1, 1)
    lg.draw(st.img, -w * 0.53, -h * 0.53, 0, w * 1.06 / st.img:getWidth(), h * 1.06 / st.img:getHeight())
    lg.pop()
  end
  lg.pop()
  if cover == true then
    -- remember where the lid box lands on screen (it may be turned), to
    -- take touches into it: its origin and its two unit axes
    local x0, y0 = lg.transformPoint(ox, oy)
    local x1, y1 = lg.transformPoint(ox + s, oy)
    local x2, y2 = lg.transformPoint(ox, oy + s)
    lastBox = { x0 = x0, y0 = y0, ux = x1 - x0, uy = y1 - y0, vx = x2 - x0, vy = y2 - y0, bw = bw, bh = bh }
  end
  -- finished falls leave the cover
  for _, st in ipairs(list) do
    if st.fall and st.fall.t0 and t - st.fall.t0 >= FALL_TIME then
      st.fall, st.on = nil, false
      saveList()
    end
  end
end

---------------------------------------------------------------- peeling

local function topAt(bx, by, bw, bh)
  for i = #list, 1, -1 do
    local st = list[i]
    if st.on and not st.fall and (st.surf or 0) == 0 then
      local lx, ly, w, h = toLocal(st, bx, by, bw, bh)
      if math.abs(lx) <= w / 2 and math.abs(ly) <= h / 2 then return st, lx, ly, w, h end
    end
  end
end

local function toBox(x, y)
  local L = lastBox
  if not L then return nil end
  local det = L.ux * L.vy - L.vx * L.uy
  if math.abs(det) < 1e-9 then return nil end
  local dx, dy = x - L.x0, y - L.y0
  return (dx * L.vy - L.vx * dy) / det, (L.ux * dy - dx * L.uy) / det, L.bw, L.bh
end

-- the lid's right camera lens (fractions of the lid box): a tap there
-- opens the sticker maker right on the cover screen
local EYE = { 898 / 1390, 45 / 757, 0.04 }
function S.onEye(x, y)
  local bx, by, bw, bh = toBox(x, y)
  if not bx then return false end
  local dx, dy = bx / bw - EYE[1], (by / bh - EYE[2]) * bh / bw
  return dx * dx + dy * dy <= EYE[3] * EYE[3]
end

-- the lens's glint (drawn over the cover now and then, so it is found)
function S.eyeGlint(t)
  local L = lastBox
  if not L then return end
  local k = (t % 6) / 6
  if k > 0.2 then return end
  local a = math.sin(k / 0.2 * math.pi)
  local ex, ey = EYE[1] * L.bw, EYE[2] * L.bh
  local sx = L.x0 + L.ux * ex + L.vx * ey
  local sy = L.y0 + L.uy * ex + L.vy * ey
  local unit = math.sqrt(L.ux * L.ux + L.uy * L.uy)
  lg.setColor(1, 1, 1, 0.45 * a)
  lg.circle("line", sx, sy, unit * L.bw * 0.022 * (1 + k * 2))
  lg.setColor(1, 1, 1, 0.8 * a)
  lg.circle("fill", sx - unit * L.bw * 0.005, sy - unit * L.bw * 0.005, unit * L.bw * 0.004)
end

-- a finger on the cover screen (real window coordinates)
function S.coverPressed(id, x, y)
  local bx, by, bw, bh = toBox(x, y)
  if not bx then return end
  if not grab and S.onEye(x, y) then
    S.open()
    return "eye"
  end
  if grab and grab.held and not twist and id ~= grab.id then
    -- a second finger: twist the sticker in hand
    twist = { id = id, a0 = math.atan2(by - grab.by, bx - grab.bx), rot0 = grab.st.rot }
    return
  end
  if grab then return end
  local st, lx, ly, w, h = topAt(bx, by, bw, bh)
  if not st then return end
  -- the corner nearest the finger is the one that lifts
  local cxl = lx < 0 and -w / 2 or w / 2
  local cyl = ly < 0 and -h / 2 or h / 2
  grab = { id = id, st = st, cx = cxl, cy = cyl, lx0 = lx, ly0 = ly, fold = nil, amount = 0 }
end

function S.coverMoved(id, x, y)
  local bx, by, bw, bh = toBox(x, y)
  if not bx or not grab then return end
  if twist and id == twist.id then
    local a = math.atan2(by - grab.by, bx - grab.bx)
    grab.st.rot = twist.rot0 + (a - twist.a0)
    return
  end
  if id ~= grab.id then return end
  local st = grab.st
  if grab.held then
    grab.bx, grab.by = bx, by
    return
  end
  local lx, ly, w, h = toLocal(st, bx, by, bw, bh)
  local px, py = grab.cx + (lx - grab.lx0), grab.cy + (ly - grab.ly0)
  local diag = math.sqrt(w * w + h * h)
  grab.amount = math.sqrt((px - grab.cx) ^ 2 + (py - grab.cy) ^ 2) / diag
  grab.fold = { grab.cx, grab.cy, px, py }
  if not grab.peeled and grab.amount > 0.06 then grab.peeled = true; Sfx.play("peel") end
  if grab.amount >= PEEL_OFF then
    -- off the cover and into the finger
    grab.held, grab.fold = true, nil
    grab.bx, grab.by = bx, by
    Sfx.play("peel")
  end
end

local function restick(st)
  st.peels = (st.peels or 0) + 1
  st.worn = 0
  st.corner = love.math.random(1, 4)
end

function S.coverReleased(id, x, y)
  if twist and id == twist.id then twist = nil return end
  if not grab or id ~= grab.id then return end
  local st = grab.st
  local bw = lastBox and lastBox.bw or 1
  local bh = lastBox and lastBox.bh or 1
  if grab.held then
    -- stuck down again where it was let go, on top of the stack
    st.px, st.py = clamp(grab.bx / bw, 0, 1), clamp(grab.by / bh, 0, 1)
    restick(st)
    for i, o in ipairs(list) do if o == st then table.remove(list, i) break end end
    list[#list + 1] = st
    saveList()
    Sfx.play("stick")
  elseif grab.amount >= RESTICK then
    restick(st)
    saveList()
    Sfx.play("stick")
  elseif grab.peeled then
    Sfx.play("stick")
  end
  grab, twist = nil, nil
end

-- play time wears re-stuck stickers; a worn-out one falls (the fall plays
-- the next time the cover is drawn)
function S.tick(dt)
  dt = math.max(0, math.min(dt or 0, 1))
  local changed = false
  for _, st in ipairs(list) do
    if st.on and (st.peels or 0) > 0 and not st.fall then
      st.worn = (st.worn or 0) + dt
      if st.worn >= life(st) then st.fall = { pending = true }; changed = true end
    end
  end
  dirty = dirty + dt
  if changed or dirty >= 30 then saveList() end
end

---------------------------------------------------------------- SKINS

function S.has() return #list > 0 end
function S.count()
  local on, off = 0, 0
  for _, st in ipairs(list) do if st.on then on = on + 1 else off = off + 1 end end
  return on, off
end

-- the fallen ones, stuck back on (each re-stick wears them a little more)
function S.putBack()
  for _, st in ipairs(list) do
    if not st.on then st.on = true; st.fall = nil; restick(st) end
  end
  saveList()
end

local function deleteSticker(st)
  love.filesystem.remove(outFile(st.id))
  love.filesystem.remove(srcFile(st.id))
  for i, o in ipairs(list) do if o == st then table.remove(list, i) break end end
  saveList()
end

function S.remove()
  for i = #list, 1, -1 do deleteSticker(list[i]) end
end

---------------------------------------------------------------- picking

local function pickedInfo()
  return love.filesystem.getInfo(PICKED)
end

-- Ask the platform for a picture.  Android: the system picker (the photo
-- lands in the save directory); elsewhere a desktop dialog, if there is one.
function S.pick()
  if love.system.getOS() == "Android" then
    local fn = love.system.pickFile
    local kinds = love.system.pickFileKinds and love.system.pickFileKinds() or ""
    if fn and kinds:find("image", 1, true) and fn("image") then
      local info = pickedInfo()
      pickWait = { since = now(), modtime = info and info.modtime or -1 }
      return true
    end
    return false, "This build's file picker cannot open pictures."
  end
  local ok, FilePicker = pcall(require, "src.core.FilePicker")
  if ok and FilePicker.available and FilePicker.available() then
    local path = FilePicker.open("Choose a picture for the cover sticker", FilePicker.IMAGE)
    if path then return S.useFile(path) end
    return false
  end
  return false, "No file picker on this platform."
end

local function openEditorWith(data, cfg)
  local img = lg.newImage(data)
  img:setFilter("linear", "linear")
  local iw, ih = img:getDimensions()
  local c = defaults(iw, ih)
  if cfg then for k, v in pairs(cfg) do c[k] = v end end
  -- a crop from another picture may not fit this one
  c.cw = clamp(c.cw, 8, iw); c.ch = clamp(c.ch, 8, ih)
  c.cx = clamp(c.cx, 0, iw - c.cw); c.cy = clamp(c.cy, 0, ih - c.ch)
  ed = ed or {}
  c.surf = ed.surf or c.surf or 0
  ed.img, ed.data, ed.cfg, ed.drag, ed.note = img, data, c, nil, nil
end

-- the placement a new picture keeps from the sticker being edited
local function keepPlacement()
  if not ed or not ed.cfg then return nil end
  local c = ed.cfg
  return { size = c.size, px = c.px, py = c.py, rot = c.rot, round = c.round, outline = c.outline, surf = c.surf }
end

-- A picture from an absolute path (desktop dialogs, the test driver).
function S.useFile(path)
  local f = io.open(path, "rb")
  if not f then return false, "Could not read that file." end
  local bytes = f:read("*a")
  f:close()
  local ok, data = pcall(function()
    return love.image.newImageData(love.filesystem.newFileData(bytes, "pick"))
  end)
  if not ok then return false, "That file is not a PNG or JPEG picture." end
  if not ed then ed = {} end
  openEditorWith(shrink(data), keepPlacement())
  return true
end

-- Poll for Android's picked file (the app pauses while the picker is up).
function S.update()
  if not pickWait then return end
  local info = pickedInfo()
  if info and (info.modtime or 0) ~= pickWait.modtime then
    pickWait = nil
    local data = readImageData(PICKED)
    love.filesystem.remove(PICKED)
    if data and ed then
      openEditorWith(shrink(data), keepPlacement())
    elseif ed then
      ed.note = "That file is not a PNG or JPEG picture."
    end
  elseif now() - pickWait.since > 600 then
    pickWait = nil
  end
end

function S.waiting() return pickWait ~= nil end

---------------------------------------------------------------- the editor

function S.editing() return ed ~= nil end
-- the surface being edited (0 lid, 1 top shell, 2 bottom shell)
function S.surface() return ed and ed.surf or 0 end

-- Open the editor: "top" edits the top sticker on the cover, anything else
-- starts a new one (and asks for a picture).
function S.open(which, surf)
  surf = surf or 0
  if which == "top" then
    for i = #list, 1, -1 do
      local st = list[i]
      if st.on and math.floor(st.surf or 0) == surf then
        local data = readImageData(srcFile(st.id))
        if data then
          ed = { target = st, surf = surf }
          local cfg = { surf = surf }
          for _, k in ipairs({ "cx", "cy", "cw", "ch", "round", "size", "px", "py", "rot" }) do cfg[k] = st[k] end
          cfg.outline = st.outline
          openEditorWith(data, cfg)
          return true
        end
      end
    end
  end
  ed = { cfg = defaults(1, 1), note = nil, surf = surf }   -- empty until a picture arrives
  ed.cfg.surf = surf
  if surf ~= 0 then
    -- the shells have little bare face: a small sticker, beside the screen
    ed.cfg.size, ed.cfg.px, ed.cfg.py = 0.14, 0.11, surf == 1 and 0.62 or 0.82
  end
  local ok, err = S.pick()
  if not ok then ed.note = err or "No picture chosen." end
  return true
end

function S.close() ed = nil end

function S.save()
  if not ed or not ed.img then return false end
  local c = ed.cfg
  local st = ed.target
  if not st then
    st = { id = nextId, peels = 0, worn = 0, corner = 1, on = true }
    nextId = nextId + 1
    list[#list + 1] = st
  end
  for _, k in ipairs({ "cx", "cy", "cw", "ch", "round", "size", "px", "py", "rot" }) do st[k] = c[k] end
  st.outline = c.outline
  st.surf = ed.surf or 0
  local canvas = bake(ed.img, c)
  local okW = pcall(function()
    canvas:newImageData():encode("png", outFile(st.id))
    ed.data:encode("png", srcFile(st.id))
  end)
  if not okW then ed.note = "Could not save the sticker." return false end
  st.img = nil
  loadImage(st)
  saveList()
  ed = nil
  Sfx.play("newSticker")
  return true
end

-- the editor's controls, laid out per frame in the bottom screen rect
local function controls(r)
  local colW = math.floor(r.w * 0.40)
  local colX = r.x + r.w - colW
  local pad = math.max(3, math.floor(r.h * 0.018))
  local rows = {
    { id = "round", label = "Round", kind = "step" },
    { id = "size", label = "Size", kind = "step" },
    { id = "rot", label = "Turn", kind = "step" },
    { id = "outline", label = "White edge", kind = "toggle" },
    { id = "pick", label = "New picture", kind = "button" },
  }
  if ed and (ed.surf or 0) ~= 0 then
    table.insert(rows, 1, { id = "surf", label = ed.surf == 1 and "On: top shell" or "On: bottom shell", kind = "button" })
  end
  if ed and ed.target then rows[#rows + 1] = { id = "delete", label = "Delete", kind = "button", danger = true } end
  rows[#rows + 1] = { id = "save", label = "Save", kind = "button", accent = true }
  rows[#rows + 1] = { id = "cancel", label = "Cancel", kind = "button" }
  local rh = math.floor((r.h - pad * (#rows + 1)) / #rows)
  for i, row in ipairs(rows) do
    row.x, row.y, row.w, row.h = colX + pad, r.y + pad + (i - 1) * (rh + pad), colW - 2 * pad, rh
  end
  local area = { x = r.x + pad, y = r.y + pad, w = r.w - colW - pad, h = r.h - 2 * pad }
  return rows, area
end

-- the picture fitted into the crop area: offset and scale
local function fit(area)
  local iw, ih = ed.img:getDimensions()
  local k = math.min(area.w / iw, area.h / ih)
  return area.x + (area.w - iw * k) / 2, area.y + (area.h - ih * k) / 2, k
end

local function inside(x, y, rx, ry, rw, rh)
  return x >= rx and y >= ry and x <= rx + rw and y <= ry + rh
end

function S.drawEditor(r)
  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)
  lg.setColor(0.07, 0.08, 0.10, 1)
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  local rows, area = controls(r)
  local f = ctx.font(math.max(9, r.h * 0.048))
  lg.setFont(f)
  if ed.img then
    local ox, oy, k = fit(area)
    local iw, ih = ed.img:getDimensions()
    lg.setColor(1, 1, 1, 0.35)
    lg.draw(ed.img, ox, oy, 0, k, k)
    local c = ed.cfg
    local x, y, w, h = ox + c.cx * k, oy + c.cy * k, c.cw * k, c.ch * k
    -- the crop, bright, with its rounded corners
    lg.stencil(function() roundRect("fill", x, y, w, h, c.round * math.min(w, h)) end, "replace", 1)
    lg.setStencilTest("greater", 0)
    lg.setColor(1, 1, 1, 1)
    lg.draw(ed.img, ox, oy, 0, k, k)
    lg.setStencilTest()
    lg.setColor(1, 1, 1, 1)
    lg.setLineWidth(2)
    lg.rectangle("line", x, y, w, h)
    local hs = math.max(8, math.floor(r.h * 0.05))
    for _, p in ipairs({ { x, y }, { x + w, y }, { x, y + h }, { x + w, y + h } }) do
      lg.rectangle("fill", p[1] - hs / 2, p[2] - hs / 2, hs, hs)
    end
    lg.setColor(1, 1, 1, 0.6)
    lg.printf("Drag to move, corners to crop", area.x, area.y + area.h - f:getHeight(), area.w, "center")
    ed.fit = { ox = ox, oy = oy, k = k, iw = iw, ih = ih, hs = hs }
  else
    lg.setColor(1, 1, 1, 0.7)
    local msg = ed.note or (pickWait and "Choose a picture..." or "Tap New picture")
    lg.printf(msg, area.x, area.y + area.h / 2 - f:getHeight(), area.w, "center")
  end
  for _, row in ipairs(rows) do
    local enabled = ed.img ~= nil or row.id == "pick" or row.id == "cancel" or row.id == "delete"
    if row.danger then
      lg.setColor(0.45, 0.12, 0.14, enabled and 1 or 0.4)
    else
      lg.setColor(row.accent and 0.18 or 0.14, row.accent and 0.42 or 0.15, row.accent and 0.78 or 0.18, enabled and 1 or 0.4)
    end
    lg.rectangle("fill", row.x, row.y, row.w, row.h, 5, 5)
    lg.setColor(1, 1, 1, enabled and 1 or 0.4)
    local ty = row.y + (row.h - f:getHeight()) / 2
    if row.kind == "step" then
      local bw = math.floor(row.h * 0.9)
      lg.printf("-", row.x, ty, bw, "center")
      lg.printf("+", row.x + row.w - bw, ty, bw, "center")
      local v
      if row.id == "round" then v = ("%d%%"):format(ed.cfg.round * 200)
      elseif row.id == "size" then v = ("%d%%"):format(ed.cfg.size * 100)
      else v = ("%d°"):format(math.floor(math.deg(ed.cfg.rot or 0) + 0.5) % 360) end
      lg.printf(row.label .. " " .. v, row.x + bw, ty, row.w - 2 * bw, "center")
      lg.setColor(1, 1, 1, 0.12)
      lg.rectangle("fill", row.x + bw, row.y + 4, 1, row.h - 8)
      lg.rectangle("fill", row.x + row.w - bw, row.y + 4, 1, row.h - 8)
    elseif row.kind == "toggle" then
      lg.printf(row.label .. ": " .. (ed.cfg.outline and "On" or "Off"), row.x, ty, row.w, "center")
    else
      lg.printf(row.label, row.x, ty, row.w, "center")
    end
  end
  if ed.note and ed.img then
    lg.setColor(1, 0.55, 0.5, 1)
    lg.printf(ed.note, area.x, area.y, area.w, "center")
  end
  lg.pop()
  ed.rows = rows
end

-- the top screen while editing: the whole cover, landscape, as a preview
function S.drawPreview(r, drawLidIn)
  lg.push("all")
  lg.setColor(0.13, 0.13, 0.14, 1)
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  drawLidIn(r.x, r.y, r.w, r.h, false)
  if ed and ed.img then
    local f = ctx.font(math.max(9, r.h * 0.05))
    lg.setFont(f)
    lg.setColor(0, 0, 0, 0.5)
    lg.rectangle("fill", r.x, r.y + r.h - f:getHeight() * 1.5, r.w, f:getHeight() * 1.5)
    lg.setColor(1, 1, 1, 0.9)
    lg.printf("Drag to place it, the knob to turn it", r.x, r.y + r.h - f:getHeight() * 1.25, r.w, "center")
  end
  lg.pop()
end

local function step(id, dir)
  local c = ed.cfg
  if id == "round" then c.round = clamp(c.round + dir * 0.05, 0, 0.5)
  elseif id == "size" then c.size = clamp(c.size + dir * 0.02, (ed.surf or 0) ~= 0 and 0.06 or 0.12, 0.9)
  elseif id == "rot" then c.rot = (c.rot or 0) + dir * math.rad(5) end
end

local function tapRow(row, x)
  if row.kind == "step" then
    if not ed.img then return end
    step(row.id, x < row.x + row.w / 2 and -1 or 1)
  elseif row.id == "surf" then
    ed.surf = ed.surf == 1 and 2 or 1
    ed.cfg.surf = ed.surf
  elseif row.id == "outline" then
    if ed.img then ed.cfg.outline = not ed.cfg.outline end
  elseif row.id == "pick" then
    local ok, err = S.pick()
    if not ok and err then ed.note = err end
  elseif row.id == "delete" then
    deleteSticker(ed.target)
    ed = nil
  elseif row.id == "save" then
    S.save()
  elseif row.id == "cancel" then
    S.close()
  end
end

-- Touch / mouse, in real window coordinates.  bot / top: the screen rects.
function S.pressed(id, x, y, bot, top)
  if not ed then return false end
  if inside(x, y, bot.x, bot.y, bot.w, bot.h) then
    for _, row in ipairs(ed.rows or {}) do
      if inside(x, y, row.x, row.y, row.w, row.h) then
        ed.drag = { id = id, kind = "row", row = row }
        tapRow(row, x)
        return true
      end
    end
    local f = ed and ed.fit
    if ed and ed.img and f then
      local c = ed.cfg
      local cx, cy, cw, ch = f.ox + c.cx * f.k, f.oy + c.cy * f.k, c.cw * f.k, c.ch * f.k
      local grabR = f.hs * 1.6
      local corners = { { cx, cy, "tl" }, { cx + cw, cy, "tr" }, { cx, cy + ch, "bl" }, { cx + cw, cy + ch, "br" } }
      for _, p in ipairs(corners) do
        if math.abs(x - p[1]) <= grabR and math.abs(y - p[2]) <= grabR then
          ed.drag = { id = id, kind = "corner", corner = p[3], lx = x, ly = y }
          return true
        end
      end
      if inside(x, y, cx, cy, cw, ch) then
        ed.drag = { id = id, kind = "move", lx = x, ly = y }
      end
    end
    return true
  end
  if ed and inside(x, y, top.x, top.y, top.w, top.h) then
    local L = ed.lidRect
    if ed.img and L then
      local kn = L.knob
      local reach = L.bh * L.s * 0.09
      if kn and (x - kn[1]) ^ 2 + (y - kn[2]) ^ 2 <= reach * reach then
        ed.drag = { id = id, kind = "turn" }
      else
        ed.drag = { id = id, kind = "place" }
        S.moved(id, x, y)
      end
    end
    return true
  end
  return true   -- the editor owns the screens while it is open
end

function S.moved(id, x, y)
  local d = ed and ed.drag
  if not d or d.id ~= id then return ed ~= nil end
  local c = ed.cfg
  if d.kind == "place" then
    local L = ed.lidRect
    c.px = clamp((x - L.ox) / L.s / L.bw, 0, 1)
    c.py = clamp((y - L.oy) / L.s / L.bh, 0, 1)
    return true
  end
  if d.kind == "turn" then
    local L = ed.lidRect
    local ce = L.centre
    c.rot = math.atan2(x - ce[1], -(y - ce[2]))
    return true
  end
  local f = ed.fit
  if not f then return true end
  local dx, dy = (x - d.lx) / f.k, (y - d.ly) / f.k
  d.lx, d.ly = x, y
  local minS = math.max(8, math.min(f.iw, f.ih) * 0.08)
  if d.kind == "move" then
    c.cx = clamp(c.cx + dx, 0, f.iw - c.cw)
    c.cy = clamp(c.cy + dy, 0, f.ih - c.ch)
  elseif d.kind == "corner" then
    local x1, y1, x2, y2 = c.cx, c.cy, c.cx + c.cw, c.cy + c.ch
    if d.corner:find("l") then x1 = clamp(x1 + dx, 0, x2 - minS) else x2 = clamp(x2 + dx, x1 + minS, f.iw) end
    if d.corner:find("t") then y1 = clamp(y1 + dy, 0, y2 - minS) else y2 = clamp(y2 + dy, y1 + minS, f.ih) end
    c.cx, c.cy, c.cw, c.ch = x1, y1, x2 - x1, y2 - y1
  end
  return true
end

function S.released(id)
  if not ed then return false end
  if ed.drag and ed.drag.id == id then ed.drag = nil end
  return true
end

-- shell buttons while editing: A saves, B cancels, the d-pad nudges the
-- sticker on the cover, L / R turn it
function S.button(name)
  if not ed then return false end
  if name == "a" then S.save()
  elseif name == "b" then S.close()
  elseif ed.img then
    local c = ed.cfg
    if name == "left" then c.px = clamp(c.px - 0.02, 0, 1) end
    if name == "right" then c.px = clamp(c.px + 0.02, 0, 1) end
    if name == "up" then c.py = clamp(c.py - 0.03, 0, 1) end
    if name == "down" then c.py = clamp(c.py + 0.03, 0, 1) end
    if name == "l" then c.rot = c.rot - math.rad(5) end
    if name == "r" then c.rot = c.rot + math.rad(5) end
  end
  return true
end

function S.init(context)
  ctx = context
  S.load()
end

return S
