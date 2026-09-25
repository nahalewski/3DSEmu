-- The cover sticker: a picture of the player's own, cropped, with rounded
-- corners and a white die-cut edge, stuck on the closed lid (the cover
-- screen).  SKINS opens the editor: the bottom screen crops the picture and
-- sets the corners, size and outline; the top screen previews the cover,
-- and dragging the sticker there moves it.  The sticker keeps its own
-- proportions and always stays on the shell -- a picture never stretches
-- the lid or runs off it.
--
-- Files in the save directory:
--   fold3ds_sticker_src.png   the picture as picked (kept to re-crop)
--   fold3ds_sticker.png       the finished sticker (cut, cornered, edged)
--   fold3ds_sticker.cfg       crop / corners / outline / size / position
local S = {}

local lg = love.graphics
local SRC_FILE = "fold3ds_sticker_src.png"
local OUT_FILE = "fold3ds_sticker.png"
local CFG_FILE = "fold3ds_sticker.cfg"
local PICKED = "picked_image.img"       -- where Android's picker lands
local MAX_SIDE = 1024                   -- the finished sticker's long side, px
local MAX_SRC = 2048                    -- a huge photo is scaled down to this

local ctx                               -- from init: real setCanvas, font()
local saved = nil                       -- { img, cfg } the sticker on the lid
local ed = nil                          -- the open editor
local pickWait = nil                    -- { since, modtime } a pick in flight

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function defaults(iw, ih)
  -- a centred square-ish crop of the middle of the picture
  local side = math.min(iw, ih) * 0.9
  return {
    cx = (iw - side) / 2, cy = (ih - side) / 2, cw = side, ch = side,
    round = 0.18,                        -- corner radius, share of the short side
    outline = true,
    size = 0.34,                         -- width on the lid, share of the lid width
    px = 0.36, py = 0.42,                -- centre on the lid, 0..1 of the lid box
  }
end

local function encodeCfg(c)
  local out = {}
  for _, k in ipairs({ "cx", "cy", "cw", "ch", "round", "size", "px", "py" }) do
    out[#out + 1] = ("%s=%.5f"):format(k, c[k])
  end
  out[#out + 1] = "outline=" .. (c.outline and "1" or "0")
  return table.concat(out, "\n") .. "\n"
end

local function decodeCfg(text)
  local c = {}
  for k, v in tostring(text or ""):gmatch("(%w+)=([%w%.%-]+)") do
    if k == "outline" then c.outline = v == "1" else c[k] = tonumber(v) end
  end
  return c
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

-- Draw the sticker (cut from `img` by cfg) with its top-left at x, y and
-- width w, into whatever canvas is current.  Used for the finished PNG and
-- for the editor's live previews alike.
-- `masked`: stencil value 1 already marks where the sticker may show (the
-- shell), so the picture's own rounded cut stacks on it instead of
-- replacing it
local function drawSticker(img, c, x, y, w, masked)
  local ih = w * c.ch / c.cw
  local short = math.min(w, ih)
  local edge = c.outline and short * 0.055 or 0
  local r = c.round * short
  -- the picture sits inside the white edge
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

-- Where the sticker goes on a lid box of bw x bh (the shell's own pixels):
-- its proportions kept, its size and centre clamped so it stays on the shell.
-- The flat of the lid inside its box: clear of the rounded corners' worst
-- and of the hinge along the bottom (landscape, before any turn).
local FACE = { left = 0.035, right = 0.035, top = 0.06, bottom = 0.2 }

local function placement(c, aspect, bw, bh)
  local x0, x1 = bw * FACE.left, bw * (1 - FACE.right)
  local y0, y1 = bh * FACE.top, bh * (1 - FACE.bottom)
  local w = c.size * bw
  local h = w / aspect
  local maxW = math.min(x1 - x0, (y1 - y0) * aspect)
  if w > maxW then w = maxW; h = w / aspect end
  local x = clamp(c.px * bw - w / 2, x0, x1 - w)
  local y = clamp(c.py * bh - h / 2, y0, y1 - h)
  return x, y, w, h
end
S.placement = placement

---------------------------------------------------------------- saved sticker

function S.load()
  saved = nil
  if not love.filesystem.getInfo(OUT_FILE) then return end
  local okI, img = pcall(lg.newImage, OUT_FILE)
  if not okI then return end
  img:setFilter("linear", "linear")
  local c = decodeCfg(love.filesystem.read(CFG_FILE))
  local d = defaults(1, 1)
  for k, v in pairs(d) do if c[k] == nil then c[k] = v end end
  saved = { img = img, cfg = c }
end

function S.has() return saved ~= nil end

-- Draw the saved sticker (or the editor's live one) on the lid.  The caller
-- has set up the lid's transform: box origin ox, oy at scale s (units per
-- lid-box pixel), box bw x bh.
-- `mask` draws the shell's own shape: whatever part of the sticker (or its
-- shadow) would hang off the cover is cut away.
function S.drawOnLid(ox, oy, s, bw, bh, mask)
  local live = ed and ed.img
  local c = live and ed.cfg or (saved and saved.cfg)
  if not c then return end
  local aspect = c.cw / c.ch
  local x, y, w, h = placement(c, aspect, bw, bh)
  lg.push("all")
  if mask then
    lg.stencil(mask, "replace", 1)
    lg.setStencilTest("greater", 0)
  end
  -- a soft shadow, then the sticker
  lg.setColor(0, 0, 0, 0.28)
  roundRect("fill", ox + (x + bh * 0.008) * s, oy + (y + bh * 0.012) * s, w * s, h * s,
    c.round * math.min(w, h) * s)
  if live then
    drawSticker(ed.img, c, ox + x * s, oy + y * s, w * s, mask ~= nil)
  else
    local iw = saved.img:getWidth()
    lg.setColor(1, 1, 1, 1)
    lg.draw(saved.img, ox + x * s, oy + y * s, 0, w * s / iw, w * s / iw)
  end
  lg.setStencilTest()
  lg.pop()
  if ed then
    -- in screen coordinates, for dragging on the preview (never rotated)
    local sx, sy = ox, oy
    if lg.transformPoint then sx, sy = lg.transformPoint(ox, oy) end
    ed.lidRect = { ox = sx, oy = sy, s = s, bw = bw, bh = bh }
  end
end

function S.remove()
  love.filesystem.remove(OUT_FILE)
  love.filesystem.remove(SRC_FILE)
  love.filesystem.remove(CFG_FILE)
  saved = nil
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
      pickWait = { since = love.timer.getTime(), modtime = info and info.modtime or -1 }
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
  ed = { img = img, data = data, cfg = c, drag = nil, note = nil }
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
  openEditorWith(shrink(data), ed and ed.cfg or nil)
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
    if data then
      openEditorWith(shrink(data), ed and ed.cfg or nil)
    elseif ed then
      ed.note = "That file is not a PNG or JPEG picture."
    end
  elseif love.timer.getTime() - pickWait.since > 600 then
    pickWait = nil
  end
end

function S.waiting() return pickWait ~= nil end

---------------------------------------------------------------- the editor

function S.editing() return ed ~= nil end

-- Open the editor: on the saved picture when there is one, else pick one.
function S.open()
  local data = love.filesystem.getInfo(SRC_FILE) and readImageData(SRC_FILE)
  if data then
    openEditorWith(data, saved and saved.cfg or decodeCfg(love.filesystem.read(CFG_FILE)))
    return true
  end
  ed = { cfg = defaults(1, 1), note = nil }   -- empty until a picture arrives
  local ok, err = S.pick()
  if not ok then ed.note = err or "No picture chosen." end
  return true
end

function S.close() ed = nil end

function S.save()
  if not ed or not ed.img then return false end
  local c = ed.cfg
  local canvas = bake(ed.img, c)
  local okW = pcall(function()
    canvas:newImageData():encode("png", OUT_FILE)
    ed.data:encode("png", SRC_FILE)
    love.filesystem.write(CFG_FILE, encodeCfg(c))
  end)
  if not okW then ed.note = "Could not save the sticker." return false end
  S.load()
  ed = nil
  return true
end

-- the editor's controls, laid out per frame in the bottom screen rect
local function controls(r)
  local colW = math.floor(r.w * 0.40)
  local colX = r.x + r.w - colW
  local pad = math.max(3, math.floor(r.h * 0.02))
  local rows = {
    { id = "round", label = "Round", kind = "step" },
    { id = "size", label = "Size", kind = "step" },
    { id = "outline", label = "White edge", kind = "toggle" },
    { id = "pick", label = "New picture", kind = "button" },
    { id = "save", label = "Save", kind = "button", accent = true },
    { id = "cancel", label = "Cancel", kind = "button" },
  }
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
  local f = ctx.font(math.max(9, r.h * 0.052))
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
  -- controls
  for _, row in ipairs(rows) do
    local enabled = ed.img ~= nil or row.id == "pick" or row.id == "cancel"
    lg.setColor(row.accent and 0.18 or 0.14, row.accent and 0.42 or 0.15, row.accent and 0.78 or 0.18, enabled and 1 or 0.4)
    lg.rectangle("fill", row.x, row.y, row.w, row.h, 5, 5)
    lg.setColor(1, 1, 1, enabled and 1 or 0.4)
    local ty = row.y + (row.h - f:getHeight()) / 2
    if row.kind == "step" then
      local bw = math.floor(row.h * 0.9)
      lg.printf("-", row.x, ty, bw, "center")
      lg.printf("+", row.x + row.w - bw, ty, bw, "center")
      local v = row.id == "round" and ("%d%%"):format(ed.cfg.round * 200) or ("%d%%"):format(ed.cfg.size * 100)
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
    lg.printf("Drag the sticker to place it", r.x, r.y + r.h - f:getHeight() * 1.25, r.w, "center")
  end
  lg.pop()
end

local function step(id, dir)
  local c = ed.cfg
  if id == "round" then c.round = clamp(c.round + dir * 0.05, 0, 0.5)
  elseif id == "size" then c.size = clamp(c.size + dir * 0.04, 0.12, 0.9) end
end

local function tapRow(row, x)
  if row.kind == "step" then
    if not ed.img then return end
    step(row.id, x < row.x + row.w / 2 and -1 or 1)
  elseif row.id == "outline" then
    if ed.img then ed.cfg.outline = not ed.cfg.outline end
  elseif row.id == "pick" then
    local ok, err = S.pick()
    if not ok and err then ed.note = err end
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
    local f = ed.fit
    if ed.img and f then
      local c = ed.cfg
      local cx, cy, cw, ch = f.ox + c.cx * f.k, f.oy + c.cy * f.k, c.cw * f.k, c.ch * f.k
      local grab = f.hs * 1.6
      local corners = { { cx, cy, "tl" }, { cx + cw, cy, "tr" }, { cx, cy + ch, "bl" }, { cx + cw, cy + ch, "br" } }
      for _, p in ipairs(corners) do
        if math.abs(x - p[1]) <= grab and math.abs(y - p[2]) <= grab then
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
  if inside(x, y, top.x, top.y, top.w, top.h) then
    if ed.img and ed.lidRect then ed.drag = { id = id, kind = "place" } S.moved(id, x, y) end
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
-- sticker on the cover
function S.button(name)
  if not ed then return false end
  if name == "a" then S.save()
  elseif name == "b" then S.close()
  elseif ed.img and (name == "up" or name == "down" or name == "left" or name == "right") then
    local c = ed.cfg
    if name == "left" then c.px = clamp(c.px - 0.02, 0, 1) end
    if name == "right" then c.px = clamp(c.px + 0.02, 0, 1) end
    if name == "up" then c.py = clamp(c.py - 0.03, 0, 1) end
    if name == "down" then c.py = clamp(c.py + 0.03, 0, 1) end
  end
  return true
end

function S.init(context)
  ctx = context
  S.load()
end

return S
