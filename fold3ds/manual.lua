-- The electronic manual (3DS theme): the HOME menu's Manual on a recomp
-- game opens it, as the 3DS opens a game's manual from the same button.
--
-- Bottom screen: the page, under a bar in the game's colour (Close, the
-- chapter's name, Contents) and over the page arrows (and Game Options, the
-- game's manage page).  Drag or the + Pad up / down scroll a long page; left
-- / right, L / R or the arrows turn it.  Contents lists every page; tap one,
-- or pick it with the + Pad and A.  Top screen: the game's name and the
-- contents, the chapter being read lifted out.
--
-- The words are fold3ds.manualtext (written for this app, knowing the
-- recomp).  Scans of your own printed manual go in front of them: every
-- .png / .jpg in fold3ds/manuals/<version>/ (the app) or
-- fold3ds_manuals/<version>/ (its save folder), in name order, become an
-- "Original Manual" chapter.  The page last read is remembered per game
-- (fold3ds_manual.cfg).
local M = {}

local lg = love.graphics
local Sfx = require("fold3ds.sfx")
local Text = require("fold3ds.manualtext")

local CFG = "fold3ds_manual.cfg"
local SCAN_DIRS = { "fold3ds/manuals/", "fold3ds_manuals/" }
local INK = { 50, 52, 58 }
local PAPER = { 252, 252, 250 }

local ctx
local st = {
  open = false, version = nil, manual = nil, pages = {},
  page = 1, scroll = 0, maxScroll = 0,
  contents = false, csel = 1, cscroll = 0, cmax = 0,
  hits = {}, touches = {}, body = nil,
  images = {}, last = nil, onOptions = nil,
}

local function col(c, a) lg.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function mix(c, t, w) return { c[1] + (t[1] - c[1]) * w, c[2] + (t[2] - c[2]) * w, c[3] + (t[3] - c[3]) * w } end

---------------------------------------------------------------- the pages

local function loadLast()
  st.last = {}
  local ok, text = pcall(love.filesystem.read, CFG)
  if not (ok and type(text) == "string") then return end
  for v, n in text:gmatch("([%w_]+)=(%d+)") do st.last[v] = tonumber(n) end
end

local function saveLast()
  if not st.last then return end
  local out = {}
  for v, n in pairs(st.last) do out[#out + 1] = ("%s=%d\n"):format(v, n) end
  table.sort(out)
  pcall(love.filesystem.write, CFG, table.concat(out))
end

-- scans of the printed manual, in name order
local function scans(v)
  local out, seen = {}, {}
  for _, d in ipairs(SCAN_DIRS) do
    local dir = d .. v
    local ok, items = pcall(love.filesystem.getDirectoryItems, dir)
    if ok and items then
      for _, name in ipairs(items) do
        local low = name:lower()
        if (low:match("%.png$") or low:match("%.jpe?g$")) and not seen[low] then
          seen[low] = true
          out[#out + 1] = { name = name, path = dir .. "/" .. name }
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

local function build(v)
  local m = Text.get(v)
  local pages, chapters = {}, {}
  local found = scans(v)
  if #found > 0 then
    chapters[#chapters + 1] = { title = "Original Manual", first = #pages + 1 }
    for i, s in ipairs(found) do
      pages[#pages + 1] = { chapter = #chapters, title = ("Page %d"):format(i), image = s.path }
    end
  end
  for _, c in ipairs(m and m.chapters or {}) do
    chapters[#chapters + 1] = { title = c.title, first = #pages + 1 }
    for _, s in ipairs(c.sections) do
      pages[#pages + 1] = { chapter = #chapters, title = s.title, blocks = s.blocks }
    end
  end
  return m, pages, chapters
end

-- the contents' rows: each chapter, then its pages (a run of scans is one row)
local function contentsRows(pages, chapters)
  local rows = {}
  for i, c in ipairs(chapters) do
    rows[#rows + 1] = { chapter = true, title = c.title, page = c.first, n = i }
    for pi = c.first, #pages do
      local p = pages[pi]
      if p.chapter ~= i then break end
      if not (p.image and pi > c.first) then
        rows[#rows + 1] = { title = p.image and ("%d pages"):format(#pages - pi + 1) or p.title, page = pi }
      end
    end
  end
  return rows
end

local function image(path)
  if st.images[path] == nil then
    local ok, img = pcall(lg.newImage, path)
    st.images[path] = ok and img or false
    if ok then img:setFilter("linear", "linear") end
  end
  return st.images[path] or nil
end

---------------------------------------------------------------- drawing

local function hit(id, x, y, w, h) st.hits[#st.hits + 1] = { id = id, x = x, y = y, w = w, h = h } end

local function button(id, x, y, w, h, label, f, on)
  lg.setColor(1, 1, 1, on == false and 0.35 or 0.95)
  lg.rectangle("fill", x, y, w, h, h * 0.25, h * 0.25)
  col(INK, on == false and 0.4 or 1)
  lg.setFont(f)
  lg.printf(label, x, y + (h - f:getHeight()) / 2, w, "center")
  if on ~= false then hit(id, x, y, w, h) end
end

-- one page's blocks, laid out to width w; returns its height (draws when
-- draw is true)
local function layout(page, x, y, w, unit, draw)
  local body, head, small = ctx.font(unit), ctx.font(unit * 1.25), ctx.font(unit * 0.92)
  local color = st.manual and st.manual.color or { 120, 120, 120 }
  local cy = y
  local gap = unit * 0.55
  for i, b in ipairs(page.blocks or {}) do
    local kind = b[1]
    if kind == "h" then
      if i > 1 then cy = cy + gap end
      if draw then
        lg.setFont(head)
        col(mix(color, { 0, 0, 0 }, 0.25))
        lg.print(b[2], x, cy)
        lg.rectangle("fill", x, cy + head:getHeight() + 1, math.min(w, head:getWidth(b[2]) + unit), 2)
      end
      cy = cy + head:getHeight() + gap
    elseif kind == "p" then
      local _, lines = body:getWrap(b[2], w)
      if draw then
        lg.setFont(body)
        col(INK)
        lg.printf(b[2], x, cy, w, "left")
      end
      cy = cy + #lines * body:getHeight() + gap
    elseif kind == "k" then
      local kw = math.min(w * 0.36, math.max(small:getWidth(b[2]) + unit, unit * 2))
      local _, kl = small:getWrap(b[2], kw - unit * 0.5)
      local _, dl = body:getWrap(b[3], w - kw - unit * 0.5)
      local rh = math.max(#kl * small:getHeight(), #dl * body:getHeight())
      if draw then
        col(mix(color, { 255, 255, 255 }, 0.82))
        lg.rectangle("fill", x, cy, kw, #kl * small:getHeight() + unit * 0.2, unit * 0.3, unit * 0.3)
        lg.setFont(small)
        col(mix(color, { 0, 0, 0 }, 0.35))
        lg.printf(b[2], x + unit * 0.25, cy + unit * 0.1, kw - unit * 0.5, "center")
        lg.setFont(body)
        col(INK)
        lg.printf(b[3], x + kw + unit * 0.5, cy + unit * 0.1, w - kw - unit * 0.5, "left")
      end
      cy = cy + rh + unit * 0.2 + unit * 0.3
    elseif kind == "tip" then
      local _, lines = small:getWrap(b[2], w - unit * 1.2)
      local th = #lines * small:getHeight() + unit * 0.8
      if draw then
        col({ 255, 246, 200 })
        lg.rectangle("fill", x, cy, w, th, unit * 0.3, unit * 0.3)
        col({ 214, 176, 60 })
        lg.rectangle("fill", x, cy, unit * 0.2, th)
        lg.setFont(small)
        col({ 96, 80, 30 })
        lg.printf(b[2], x + unit * 0.6, cy + unit * 0.4, w - unit * 1.2, "left")
      end
      cy = cy + th + gap
    end
  end
  return cy - y
end

local function drawPage(r, unit)
  local page = st.pages[st.page]
  if not page then return end
  local pad = unit
  if page.image then
    local img = image(page.image)
    if not img then
      lg.setFont(ctx.font(unit))
      col(INK)
      lg.printf("This page could not be read.", r.x, r.y + r.h / 2, r.w, "center")
      st.maxScroll = 0
      return
    end
    local iw, ih = img:getDimensions()
    local s = (r.w - pad) / iw
    st.maxScroll = math.max(0, ih * s + pad - r.h)
    st.scroll = clamp(st.scroll, 0, st.maxScroll)
    lg.setColor(1, 1, 1, 1)
    lg.draw(img, r.x + pad / 2, r.y + pad / 2 - st.scroll, 0, s, s)
    return
  end
  local w = r.w - pad * 2
  local total = layout(page, 0, 0, w, unit, false)
  st.maxScroll = math.max(0, total + pad * 2 - r.h)
  st.scroll = clamp(st.scroll, 0, st.maxScroll)
  layout(page, r.x + pad, r.y + pad - st.scroll, w, unit, true)
end

local function drawContents(r, unit)
  local f, bf = ctx.font(unit), ctx.font(unit * 1.1)
  local rowH = f:getHeight() * 1.7
  local color = st.manual.color
  local rows = st.rows
  st.csel = clamp(st.csel, 1, #rows)
  st.cmax = math.max(0, #rows * rowH + unit - r.h)
  -- keep the + Pad's pick in view
  local selY = (st.csel - 1) * rowH
  if st.cfollow then
    if selY - st.cscroll < 0 then st.cscroll = selY end
    if selY + rowH - st.cscroll > r.h - unit then st.cscroll = selY + rowH - r.h + unit end
    st.cfollow = false
  end
  st.cscroll = clamp(st.cscroll, 0, st.cmax)
  for i, row in ipairs(rows) do
    local y = r.y + unit * 0.5 + (i - 1) * rowH - st.cscroll
    if y + rowH > r.y and y < r.y + r.h then
      local current = st.pages[st.page] and (row.chapter and st.pages[st.page].chapter == row.n or row.page == st.page)
      if i == st.csel then
        col(mix(color, { 255, 255, 255 }, 0.78))
        lg.rectangle("fill", r.x + unit * 0.4, y, r.w - unit * 0.8, rowH, unit * 0.3, unit * 0.3)
      end
      if row.chapter then
        lg.setFont(bf)
        col(mix(color, { 0, 0, 0 }, 0.3))
        lg.print(row.title, r.x + unit, y + (rowH - bf:getHeight()) / 2)
      else
        lg.setFont(f)
        col(INK, current and 1 or 0.8)
        lg.print(row.title, r.x + unit * 2.2, y + (rowH - f:getHeight()) / 2)
        if current then
          col(color)
          lg.circle("fill", r.x + unit * 1.4, y + rowH / 2, unit * 0.22)
        end
      end
      hit("row:" .. i, r.x, math.max(r.y, y), r.w, math.min(rowH, r.y + r.h - y))
    end
  end
end

function M.drawBottom(r)
  st.hits = {}
  if not st.manual then return end
  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)
  local color = st.manual.color
  col(PAPER)
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  local bh = math.floor(r.h * 0.12)
  local pad = math.floor(bh * 0.14)
  local unit = r.h * 0.048
  local bf = ctx.font(bh * 0.4)
  -- the bar: Close, the chapter, Contents
  col(color)
  lg.rectangle("fill", r.x, r.y, r.w, bh)
  local page = st.pages[st.page]
  local chapter = page and st.chapters[page.chapter]
  local bw = bh * 2.1
  button("close", r.x + pad, r.y + pad, bw, bh - pad * 2, "Close", bf)
  button("contents", r.x + r.w - pad - bw, r.y + pad, bw, bh - pad * 2, st.contents and "Page" or "Contents", bf)
  lg.setFont(ctx.font(bh * 0.44))
  lg.setColor(1, 1, 1, 1)
  local title = st.contents and "Contents" or (chapter and chapter.title or st.manual.name)
  lg.printf(title, r.x + bw + pad * 2, r.y + (bh - lg.getFont():getHeight()) / 2, r.w - (bw + pad * 2) * 2, "center")
  -- the page (or the contents)
  local body = { x = r.x, y = r.y + bh, w = r.w, h = r.h - bh * 2 }
  st.body = body
  lg.setScissor(body.x, body.y, body.w, body.h)
  if st.contents then drawContents(body, unit) else drawPage(body, unit) end
  -- a scroll bar when it is longer than the screen
  local max, sc = st.contents and st.cmax or st.maxScroll, st.contents and st.cscroll or st.scroll
  if max > 0 then
    local th = body.h * body.h / (body.h + max)
    col(color, 0.6)
    lg.rectangle("fill", body.x + body.w - unit * 0.35, body.y + (body.h - th) * sc / max, unit * 0.2, th, 2, 2)
  end
  lg.setScissor(r.x, r.y, r.w, r.h)
  -- the page arrows, the page number, Game Options
  local fy = r.y + r.h - bh
  col(mix(color, { 255, 255, 255 }, 0.85))
  lg.rectangle("fill", r.x, fy, r.w, bh)
  col(mix(color, { 255, 255, 255 }, 0.5))
  lg.rectangle("fill", r.x, fy, r.w, 1)
  local aw = bh * 1.3
  button("prev", r.x + pad, fy + pad, aw, bh - pad * 2, "<", bf, st.page > 1)
  lg.setFont(bf)
  col(INK)
  lg.printf(("%d / %d"):format(st.page, #st.pages), r.x + pad + aw, fy + (bh - bf:getHeight()) / 2, aw * 1.6, "center")
  button("next", r.x + pad * 1 + aw * 2.6, fy + pad, aw, bh - pad * 2, ">", bf, st.page < #st.pages)
  if st.onOptions then
    local ow = bh * 3.4
    button("options", r.x + r.w - pad - ow, fy + pad, ow, bh - pad * 2, "Game Options", bf)
  end
  lg.pop()
end

-- the top screen's content (below the 3DS status bar): the game's name and
-- the contents, the chapter being read lifted out
function M.drawTop(r)
  if not st.manual then return end
  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)
  local color = st.manual.color
  col(mix(color, { 255, 255, 255 }, 0.9))
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  local pad = r.w * 0.03
  -- the cover: the game's colour, its name, "Instruction Manual"
  local cw = r.w * 0.36
  col(color)
  lg.rectangle("fill", r.x + pad, r.y + pad, cw, r.h - pad * 2, pad * 0.5, pad * 0.5)
  lg.setColor(1, 1, 1, 0.18)
  lg.circle("fill", r.x + pad + cw * 0.78, r.y + r.h * 0.3, cw * 0.4)
  local tf = ctx.font(r.h * 0.085)
  lg.setFont(tf)
  lg.setColor(1, 1, 1, 1)
  lg.printf(st.manual.name, r.x + pad * 2, r.y + r.h * 0.42, cw - pad * 2, "left")
  local sf = ctx.font(r.h * 0.05)
  lg.setFont(sf)
  lg.setColor(1, 1, 1, 0.85)
  lg.printf("Instruction Manual", r.x + pad * 2, r.y + r.h - pad * 2 - sf:getHeight(), cw - pad * 2, "left")
  -- the contents
  local lx = r.x + pad * 2 + cw
  local lw = r.w - (lx - r.x) - pad
  local n = #st.chapters
  local rowH = math.min(r.h * 0.13, (r.h - pad * 2) / math.max(1, n))
  local cf = ctx.font(rowH * 0.42)
  local cur = st.pages[st.page] and st.pages[st.page].chapter
  local y = r.y + (r.h - rowH * n) / 2
  for i, c in ipairs(st.chapters) do
    local on = i == cur
    local x = lx + (on and 0 or pad * 0.6)
    lg.setColor(0, 0, 0, on and 0.14 or 0.06)
    lg.rectangle("fill", x + 2, y + 3, lw - (on and 0 or pad * 0.6), rowH * 0.84, rowH * 0.15, rowH * 0.15)
    if on then col(color) else lg.setColor(1, 1, 1, 1) end
    lg.rectangle("fill", x, y, lw - (on and 0 or pad * 0.6), rowH * 0.84, rowH * 0.15, rowH * 0.15)
    lg.setFont(cf)
    if on then lg.setColor(1, 1, 1, 1) else col(INK, 0.85) end
    lg.print(c.title, x + rowH * 0.3, y + (rowH * 0.84 - cf:getHeight()) / 2)
    y = y + rowH
  end
  lg.pop()
end

---------------------------------------------------------------- input

local function goPage(n, quiet)
  n = clamp(n, 1, #st.pages)
  if n == st.page then
    if not quiet then Sfx.play("edge") end
    return
  end
  st.page, st.scroll = n, 0
  st.last[st.version] = n
  if not quiet then Sfx.play("strip") end
end

local function toggleContents()
  st.contents = not st.contents
  if st.contents then
    -- start on the page being read
    st.csel = 1
    for i, row in ipairs(st.rows or {}) do
      if not row.chapter and row.page == st.page then st.csel = i end
    end
    st.cfollow = true
  end
  Sfx.play("select")
end

local function pick(i)
  local row = st.rows and st.rows[i]
  if not row then return end
  goPage(row.page, true)
  st.contents = false
  Sfx.play("open")
end

local function activate(id)
  if id == "close" then return "exit" end
  if id == "contents" then toggleContents()
  elseif id == "prev" then goPage(st.page - 1)
  elseif id == "next" then goPage(st.page + 1)
  elseif id == "options" then return "options"
  elseif id:match("^row:") then pick(tonumber(id:sub(5))) end
end

local function hitAt(x, y)
  for k = #st.hits, 1, -1 do
    local h = st.hits[k]
    if x >= h.x and y >= h.y and x <= h.x + h.w and y <= h.y + h.h then return h end
  end
end

local function inBody(x, y)
  local b = st.body
  return b and x >= b.x and y >= b.y and x <= b.x + b.w and y <= b.y + b.h
end

-- what the manual's answers mean to the shell: "exit" closes it; "options"
-- closes it and opens the game's manage page
local function done(r)
  if r == "options" then
    local fn = st.onOptions
    M.close(true)
    if fn then fn() end
    return nil
  end
  return r
end

function M.pressed(id, x, y)
  local h = hitAt(x, y)
  st.touches[id] = { x0 = x, y0 = y, hit = h and h.id, body = inBody(x, y),
    scroll0 = st.contents and st.cscroll or st.scroll, drag = false }
end

function M.moved(id, x, y)
  local t = st.touches[id]
  if not t or not t.body then return end
  local dy = y - t.y0
  if not t.drag and math.abs(dy) > 10 then t.drag = true end
  if t.drag then
    if st.contents then st.cscroll = clamp(t.scroll0 - dy, 0, st.cmax)
    else st.scroll = clamp(t.scroll0 - dy, 0, st.maxScroll) end
  end
end

function M.released(id, x, y)
  local t = st.touches[id]
  st.touches[id] = nil
  if not t then return end
  if t.drag then return end
  -- a sideways swipe on a page turns it
  local dx = x - t.x0
  if t.body and not st.contents and math.abs(dx) > (st.body.w * 0.18) then
    goPage(st.page + (dx < 0 and 1 or -1))
    return
  end
  local h = hitAt(x, y)
  if h and h.id == t.hit then return done(activate(h.id)) end
end

function M.button(name)
  if name == "home" then return "exit" end
  if st.contents then
    local n = st.rows and #st.rows or 0
    if name == "b" or name == "x" then toggleContents()
    elseif name == "up" or name == "down" then
      local s = clamp(st.csel + (name == "down" and 1 or -1), 1, math.max(1, n))
      Sfx.play(s ~= st.csel and "over" or "edge")
      st.csel, st.cfollow = s, true
    elseif name == "a" then pick(st.csel) end
    return nil
  end
  if name == "b" then return "exit" end
  if name == "left" or name == "l" then goPage(st.page - 1)
  elseif name == "right" or name == "r" then goPage(st.page + 1)
  elseif name == "up" or name == "down" then
    local step = (st.body and st.body.h or 200) * 0.3
    local s = clamp(st.scroll + (name == "down" and step or -step), 0, st.maxScroll)
    if s == st.scroll then Sfx.play("noMove") else Sfx.play("scroll") end
    st.scroll = s
  elseif name == "x" then toggleContents()
  elseif name == "y" and st.onOptions then return done("options") end
  return nil
end

---------------------------------------------------------------- open / close

function M.init(context) ctx = context end
function M.isOpen() return st.open end
-- is there a manual for this recomp game?
function M.has(version) return Text.has(version) end

-- open version's manual; onOptions (optional) opens the game's manage page
-- from the manual's Game Options
function M.open(version, onOptions)
  local m, pages, chapters = build(version)
  if not m or #pages == 0 then return false end
  if not st.last then loadLast() end
  st.open, st.version, st.manual = true, version, m
  st.pages, st.chapters = pages, chapters
  st.page = clamp(st.last[version] or 1, 1, #pages)
  st.scroll, st.contents, st.csel, st.cscroll = 0, false, 1, 0
  st.rows = contentsRows(pages, chapters)
  st.onOptions = onOptions
  st.touches = {}
  Sfx.play("open")
  return true
end

function M.close(quiet)
  if not st.open then return end
  st.open = false
  st.touches = {}
  st.images = {}
  saveLast()
  if not quiet then Sfx.play("back") end
end

return M
