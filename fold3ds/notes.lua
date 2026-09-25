-- Game Notes (3DS theme, on the HOME menu's applet bar), after the 3DS's
-- own: sixteen pages to scribble on with the stylus -- a map, a code, a
-- reminder -- kept between sessions.
--
-- Bottom screen: the page being drawn on, with the tools above it (pen
-- colours, pen size, eraser, clear, the page arrows) and Back.  Top screen:
-- all sixteen pages as little cards, the current one lifted.
-- Pages are kept as fold3ds_notes/page_NN.png (drawn only once touched).
local N = {}

local lg = love.graphics
local Sfx = require("fold3ds.sfx")

local DIR = "fold3ds_notes/"
local PAGES = 16
local PW, PH = 640, 480              -- a page's canvas (the bottom screen, x2)
local INKS = {
  { 40, 42, 48 }, { 214, 44, 52 }, { 36, 108, 214 }, { 30, 150, 80 },
}
local SIZES = { 2, 5, 10 }
local YELLOW = { 250, 236, 150 }

local ctx
local st = {
  open = false, page = 1, ink = 1, size = 2, eraser = false,
  canvases = {},      -- page -> Canvas (loaded on first sight)
  dirty = {},         -- page -> true when it needs saving
  hits = {}, touches = {}, pending = {},
  area = nil,         -- where the page is on the bottom screen
  confirmClear = false,
}

local function col(c, a) lg.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1) end
local function file(p) return ("%spage_%02d.png"):format(DIR, p) end

-- draw into a canvas outside the frame's own state: no scissor, the real
-- setCanvas (the layer's redirects "the screen"), everything restored
local function into(canvas, fn)
  local prev = lg.getCanvas()
  lg.push("all")
  lg.setScissor()
  lg.origin()
  ctx.setCanvas(canvas)
  fn()
  ctx.setCanvas(prev)
  lg.pop()
end

local function canvas(p)
  local c = st.canvases[p]
  if c then return c end
  c = lg.newCanvas(PW, PH)
  c:setFilter("linear", "linear")
  local ok, img = pcall(lg.newImage, file(p))
  into(c, function()
    lg.clear(0, 0, 0, 0)
    if ok and img then
      lg.setColor(1, 1, 1, 1)
      lg.setBlendMode("alpha", "premultiplied")
      lg.draw(img, 0, 0, 0, PW / img:getWidth(), PH / img:getHeight())
    end
  end)
  st.canvases[p] = c
  return c
end

local function save()
  love.filesystem.createDirectory(DIR)
  for p in pairs(st.dirty) do
    local c = st.canvases[p]
    if c then
      local ok, data = pcall(function() return c:newImageData() end)
      if ok and data then pcall(function() data:encode("png", file(p)) end) end
    end
  end
  st.dirty = {}
end

---------------------------------------------------------------- drawing

-- strokes arrive with the touches and are laid into the page's canvas when
-- it is next drawn (inside the frame)
local function stroke(x0, y0, x1, y1)
  st.pending[#st.pending + 1] = { st.page, x0, y0, x1, y1, st.eraser, st.ink, SIZES[st.size] }
end

local function flushStrokes()
  if #st.pending == 0 then return end
  local byPage = {}
  for _, s in ipairs(st.pending) do
    byPage[s[1]] = byPage[s[1]] or {}
    table.insert(byPage[s[1]], s)
  end
  st.pending = {}
  for p, list in pairs(byPage) do
    into(canvas(p), function()
      lg.setLineStyle("smooth")
      lg.setLineJoin("bevel")
      for _, s in ipairs(list) do
        local w = s[8] * (s[6] and 4 or 1)
        if s[6] then
          lg.setBlendMode("replace")
          lg.setColor(0, 0, 0, 0)
        else
          lg.setBlendMode("alpha")
          col(INKS[s[7]])
        end
        lg.setLineWidth(w)
        lg.line(s[2], s[3], s[4], s[5])
        lg.circle("fill", s[4], s[5], w / 2)
      end
    end)
    st.dirty[p] = true
  end
end

-- a screen point in page pixels (nil off the page)
local function toPage(x, y)
  local a = st.area
  if not a then return nil end
  if x < a.x or y < a.y or x > a.x + a.w or y > a.y + a.h then return nil end
  return (x - a.x) / a.w * PW, (y - a.y) / a.h * PH
end

-- the paper: pale yellow, ruled
local function paper(x, y, w, h)
  col(YELLOW)
  lg.rectangle("fill", x, y, w, h)
  col({ 226, 206, 110 })
  local rows = 12
  for i = 1, rows - 1 do
    lg.rectangle("fill", x, y + h * i / rows, w, 1)
  end
end

local function hit(id, x, y, w, h) st.hits[#st.hits + 1] = { id = id, x = x, y = y, w = w, h = h } end

function N.drawBottom(r)
  flushStrokes()
  st.hits = {}
  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)
  col({ 236, 224, 170 })
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  -- the toolbar
  local th = math.floor(r.h * 0.13)
  local pad = math.floor(r.w * 0.015)
  col({ 120, 96, 40 })
  lg.rectangle("fill", r.x, r.y, r.w, th)
  local bs = th - pad * 2
  local x = r.x + pad
  local f = ctx.font(bs * 0.42)
  lg.setFont(f)
  local function button(id, w, label, on, draw)
    lg.setColor(1, 1, 1, on and 1 or 0.8)
    lg.rectangle("fill", x, r.y + pad, w, bs, bs * 0.2, bs * 0.2)
    if on then
      lg.setColor(1, 0.75, 0.1, 1)
      lg.setLineWidth(3)
      lg.rectangle("line", x, r.y + pad, w, bs, bs * 0.2, bs * 0.2)
    end
    if draw then draw(x, r.y + pad, w, bs) end
    if label then
      col({ 80, 64, 30 })
      lg.printf(label, x, r.y + pad + (bs - f:getHeight()) / 2, w, "center")
    end
    hit(id, x, r.y, w, th)
    x = x + w + pad
  end
  button("back", bs * 1.6, "Back")
  x = x + pad
  for i, c in ipairs(INKS) do
    button("ink:" .. i, bs, nil, not st.eraser and st.ink == i, function(bx, by, w, h)
      col(c)
      lg.circle("fill", bx + w / 2, by + h / 2, h * 0.3)
    end)
  end
  for i, s in ipairs(SIZES) do
    button("size:" .. i, bs, nil, st.size == i, function(bx, by, w, h)
      col({ 60, 60, 60 })
      lg.circle("fill", bx + w / 2, by + h / 2, math.max(1.5, h * 0.06 * s))
    end)
  end
  button("eraser", bs * 1.3, nil, st.eraser, function(bx, by, w, h)
    lg.setColor(0.95, 0.55, 0.62, 1)
    lg.rectangle("fill", bx + w * 0.22, by + h * 0.3, w * 0.56, h * 0.4, h * 0.08, h * 0.08)
    lg.setColor(0.35, 0.55, 0.85, 1)
    lg.rectangle("fill", bx + w * 0.22, by + h * 0.3, w * 0.2, h * 0.4, h * 0.08, h * 0.08)
  end)
  button("clear", bs * 1.6, st.confirmClear and "Sure?" or "Clear", st.confirmClear)
  -- the page arrows and number, right
  local aw = bs
  x = r.x + r.w - pad - aw * 3 - pad * 2
  button("prev", aw, "<")
  lg.setColor(1, 1, 1, 1)
  lg.printf(("%d/%d"):format(st.page, PAGES), x, r.y + pad + (bs - f:getHeight()) / 2, aw, "center")
  x = x + aw + pad
  button("next", aw, ">")
  -- the page (4:3, as large as fits)
  local ay = r.y + th + pad
  local ah = r.y + r.h - ay - pad
  local aw2 = math.min(r.w - pad * 2, ah * PW / PH)
  ah = aw2 * PH / PW
  local ax = r.x + (r.w - aw2) / 2
  st.area = { x = ax, y = ay, w = aw2, h = ah }
  lg.setColor(0, 0, 0, 0.15)
  lg.rectangle("fill", ax + 3, ay + 4, aw2, ah)
  paper(ax, ay, aw2, ah)
  lg.setColor(1, 1, 1, 1)
  lg.setBlendMode("alpha", "premultiplied")
  lg.draw(canvas(st.page), ax, ay, 0, aw2 / PW, ah / PH)
  lg.setBlendMode("alpha")
  lg.pop()
end

-- the top screen's content (below the 3DS status bar): every page as a card
function N.drawTop(r)
  flushStrokes()
  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)
  col({ 248, 242, 214 })
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  local cols, rows = 8, 2
  local pad = r.w * 0.02
  local tf = ctx.font(r.h * 0.08)
  lg.setFont(tf)
  col({ 150, 110, 30 })
  lg.print("Game Notes", r.x + pad * 1.5, r.y + pad * 0.6)
  local top = r.y + pad + tf:getHeight() * 1.2
  local cw = (r.w - pad * (cols + 1)) / cols
  local ch = cw * PH / PW
  local gy = top + (r.y + r.h - top - rows * ch - pad) / 2
  for p = 1, PAGES do
    local i, j = (p - 1) % cols, math.floor((p - 1) / cols)
    local x = r.x + pad + i * (cw + pad)
    local y = gy + j * (ch + pad)
    local on = p == st.page
    if on then y = y - ch * 0.12 end
    lg.setColor(0, 0, 0, on and 0.25 or 0.12)
    lg.rectangle("fill", x + 2, y + 3, cw, ch)
    paper(x, y, cw, ch)
    local c = st.canvases[p]
    if c == nil and love.filesystem.getInfo(file(p), "file") then c = canvas(p) end
    if c then
      lg.setColor(1, 1, 1, 1)
      lg.setBlendMode("alpha", "premultiplied")
      lg.draw(c, x, y, 0, cw / PW, ch / PH)
      lg.setBlendMode("alpha")
    end
    if on then
      lg.setColor(1, 0.7, 0.05, 1)
      lg.setLineWidth(3)
      lg.rectangle("line", x - 1, y - 1, cw + 2, ch + 2)
    end
    local nf = ctx.font(ch * 0.22)
    lg.setFont(nf)
    col({ 150, 120, 60 })
    lg.print(tostring(p), x + 3, y + ch - nf:getHeight())
  end
  lg.pop()
end

---------------------------------------------------------------- input

local function turn(d)
  local p = math.max(1, math.min(PAGES, st.page + d))
  Sfx.play(p == st.page and "edge" or "strip")
  if p ~= st.page then save() end
  st.page = p
end

local function activate(id)
  if id ~= "clear" then st.confirmClear = false end
  if id == "back" then return "exit" end
  if id == "prev" then turn(-1)
  elseif id == "next" then turn(1)
  elseif id == "eraser" then st.eraser = not st.eraser; Sfx.play("select")
  elseif id == "clear" then
    if st.confirmClear then
      st.confirmClear = false
      into(canvas(st.page), function() lg.clear(0, 0, 0, 0) end)
      st.dirty[st.page] = true
      save()
      Sfx.play("back")
    else
      st.confirmClear = true
      Sfx.play("notice")
    end
  elseif id:match("^ink:") then st.ink = tonumber(id:sub(5)); st.eraser = false; Sfx.play("select")
  elseif id:match("^size:") then st.size = tonumber(id:sub(6)); Sfx.play("select") end
end

local function hitAt(x, y)
  for k = #st.hits, 1, -1 do
    local h = st.hits[k]
    if x >= h.x and y >= h.y and x <= h.x + h.w and y <= h.y + h.h then return h end
  end
end

function N.pressed(id, x, y)
  local px, py = toPage(x, y)
  if px then
    st.touches[id] = { draw = true, px = px, py = py }
    stroke(px, py, px, py)
    return
  end
  local h = hitAt(x, y)
  st.touches[id] = { hit = h and h.id }
end

function N.moved(id, x, y)
  local t = st.touches[id]
  if not t or not t.draw then return end
  local px, py = toPage(x, y)
  if not px then
    local a = st.area
    px = math.max(0, math.min(PW, (x - a.x) / a.w * PW))
    py = math.max(0, math.min(PH, (y - a.y) / a.h * PH))
  end
  stroke(t.px, t.py, px, py)
  t.px, t.py = px, py
end

function N.released(id, x, y)
  local t = st.touches[id]
  st.touches[id] = nil
  if not t then return end
  if t.draw then return end
  local h = hitAt(x, y)
  if h and h.id == t.hit then return activate(h.id) end
end

function N.button(name)
  if name == "home" or name == "b" then return "exit" end
  if name == "left" or name == "l" then turn(-1)
  elseif name == "right" or name == "r" then turn(1)
  elseif name == "x" then activate("eraser")
  elseif name == "y" then
    st.eraser = false
    st.ink = st.ink % #INKS + 1
    Sfx.play("select")
  end
end

function N.init(context) ctx = context end
function N.isOpen() return st.open end
function N.open() st.open = true; st.confirmClear = false; Sfx.play("open") end
function N.close()
  if not st.open then return end
  flushStrokes()
  save()
  st.open = false
  st.touches = {}
  Sfx.play("back")
end
function N.flush() if next(st.dirty) then flushStrokes(); save() end end

return N
