-- Activity Log (3DS theme, on the HOME menu's applet bar), after the 3DS's
-- own: how long each game has been played, how many times, which days, and
-- how far the player walked.
--
--   * gen1recomp games are timed while they run in the app (A.tick, fed
--     the running game's version by init.lua);
--   * Azahar's 3DS games are timed from the moment one is opened in Azahar
--     until the HOME menu comes back into focus (Azahar.play is wrapped;
--     love.focus ends the session);
--   * steps: the day's pedometer count (init.lua's step reading) is kept
--     per day.
--
-- Kept in fold3ds_activity.cfg: one line per title (seconds, plays, first
-- and last day) and one per day (seconds played, steps).
-- Bottom screen: Play Time (every title ranked, with its icon, total time,
-- times played and the average) and This Week (a bar per day).  Top screen:
-- the chosen title's record, or the week's walking and playing, with the
-- Activity Log's walking figures.
local A = {}

local lg = love.graphics
local Sfx = require("fold3ds.sfx")

local FILE = "fold3ds_activity.cfg"
local TEAL = { 26, 170, 150 }
local INK = { 60, 62, 68 }

local ctx
local data = { titles = {}, days = {}, loaded = false, dirty = false, saveAt = 0 }
local st = {
  open = false, view = "time", sel = 1, page = 1,
  hits = {}, down = nil, touches = {}, t = 0,
  current = nil,          -- { id, name, since } for the running gen1 game
  external = nil,         -- { id, name, started } for an Azahar game
  unfocusedAt = nil,
  images = {},
}

local function col(c, a) lg.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1) end
local function rrect(mode, x, y, w, h, r) lg.rectangle(mode, x, y, w, h, r, r, 10) end
local function today() return os.date("%Y-%m-%d") end

local function img(path)
  if st.images[path] == nil then
    local ok, i = pcall(lg.newImage, path)
    st.images[path] = ok and i or false
    if ok then i:setFilter("linear", "linear") end
  end
  return st.images[path] or nil
end

---------------------------------------------------------------- the record

local function load()
  if data.loaded then return end
  data.loaded = true
  local ok, text = pcall(love.filesystem.read, FILE)
  if not ok or type(text) ~= "string" then return end
  for line in text:gmatch("[^\n]+") do
    local kind, a, b, c, d, e, f = line:match("^(%a)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|?([^|]*)$")
    if kind == "T" then
      data.titles[a] = { id = a, name = b, seconds = tonumber(c) or 0, plays = tonumber(d) or 0,
        first = e ~= "" and e or nil, last = f ~= "" and f or nil }
    elseif kind == "D" then
      data.days[a] = { seconds = tonumber(b) or 0, steps = tonumber(c) or 0 }
    end
  end
end

local function save()
  local out = {}
  for id, t in pairs(data.titles) do
    out[#out + 1] = ("T|%s|%s|%d|%d|%s|%s"):format(id, (t.name or id):gsub("[|\n]", " "),
      math.floor(t.seconds), t.plays, t.first or "", t.last or "")
  end
  for day, d in pairs(data.days) do
    out[#out + 1] = ("D|%s|%d|%d||"):format(day, math.floor(d.seconds), d.steps or 0)
  end
  pcall(love.filesystem.write, FILE, table.concat(out, "\n") .. "\n")
  data.dirty = false
end

local function title(id, name)
  load()
  local t = data.titles[id]
  if not t then
    t = { id = id, name = name or id, seconds = 0, plays = 0 }
    data.titles[id] = t
  end
  if name then t.name = name end
  return t
end

local function day(d)
  d = d or today()
  data.days[d] = data.days[d] or { seconds = 0, steps = 0 }
  return data.days[d]
end

local function credit(id, name, seconds)
  if seconds <= 0 then return end
  local t = title(id, name)
  t.seconds = t.seconds + seconds
  t.last = today()
  t.first = t.first or t.last
  day().seconds = day().seconds + seconds
  data.dirty = true
end

-- a gen1recomp game is running (version id and its name), or none (nil)
function A.playing(id, name, dt)
  load()
  if id then
    if not st.current or st.current.id ~= id then
      st.current = { id = id, name = name }
      local t = title(id, name)
      t.plays = t.plays + 1
      t.last = today()
      t.first = t.first or t.last
      data.dirty = true
    end
    credit(id, name, dt or 0)
  else
    st.current = nil
  end
end

-- an Azahar game opened (its HOME tile)
function A.launched(tile)
  if not tile then return end
  load()
  st.external = { id = tile.id, name = tile.name, started = os.time() }
  local t = title(tile.id, tile.name)
  t.plays = t.plays + 1
  t.last = today()
  t.first = t.first or t.last
  data.dirty = true
  save()
end

-- the app lost or got back the focus: an Azahar session ends on the way back
function A.focus(f)
  if f and st.external then
    local e = st.external
    st.external = nil
    -- a session longer than a day is not believed
    credit(e.id, e.name, math.min(os.time() - e.started, 86400))
    save()
  end
end

-- the day's steps from the pedometer
function A.steps(n)
  if not n or n < 0 then return end
  load()
  local d = day()
  if n ~= d.steps then d.steps = n; data.dirty = true end
end

function A.tick(dt, now)
  if data.dirty and (now or 0) >= data.saveAt then
    data.saveAt = (now or 0) + 20
    save()
  end
end

function A.flush() if data.dirty then save() end end

---------------------------------------------------------------- figures

local function hm(seconds)
  seconds = math.floor(seconds or 0)
  local h, m = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
  if h > 0 then return ("%dh %02dm"):format(h, m) end
  return ("%dm"):format(m)
end

local function ranked()
  load()
  local list = {}
  for _, t in pairs(data.titles) do list[#list + 1] = t end
  table.sort(list, function(a, b)
    if a.seconds ~= b.seconds then return a.seconds > b.seconds end
    return (a.name or a.id) < (b.name or b.id)
  end)
  return list
end

local function week()
  load()
  local out = {}
  local now = os.time()
  for k = 6, 0, -1 do
    local t = now - k * 86400
    local d = os.date("%Y-%m-%d", t)
    local rec = data.days[d] or { seconds = 0, steps = 0 }
    out[#out + 1] = { day = d, label = os.date("%a", t), seconds = rec.seconds, steps = rec.steps or 0 }
  end
  return out
end

---------------------------------------------------------------- drawing

local function hit(id, x, y, w, h)
  st.hits[#st.hits + 1] = { id = id, x = x, y = y, w = w, h = h }
end

local function tabs(x, y, w, h)
  local list = { { "time", "Play Time" }, { "week", "This Week" } }
  local tw = w / #list
  for k, v in ipairs(list) do
    local on = st.view == v[1]
    col(on and { 255, 255, 255 } or { 214, 236, 232 })
    rrect("fill", x + (k - 1) * tw + 1, y, tw - 2, h, h * 0.25)
    if on then col(TEAL) lg.rectangle("fill", x + (k - 1) * tw + tw * 0.25, y + h - 3, tw * 0.5, 3) end
    local f = ctx.font(h * 0.42)
    lg.setFont(f)
    col(on and TEAL or { 100, 130, 124 })
    lg.printf(v[2], x + (k - 1) * tw, y + (h - f:getHeight()) / 2, tw, "center")
    hit("view:" .. v[1], x + (k - 1) * tw, y, tw, h)
  end
end

local function drawTime(r, y0, pad)
  local list = ranked()
  local h0 = r.y + r.h - y0 - pad
  local per = 4
  local rh = (h0 - h0 * 0.15) / per
  local pages = math.max(1, math.ceil(#list / per))
  st.page = math.max(1, math.min(pages, st.page))
  if #list == 0 then
    local f = ctx.font(rh * 0.24)
    lg.setFont(f)
    col(INK, 0.7)
    lg.printf("Nothing played yet.\nPlay a game and it shows up here.", r.x, y0 + h0 * 0.35, r.w, "center")
  end
  for k = 1, per do
    local i = (st.page - 1) * per + k
    local t = list[i]
    if not t then break end
    local ry = y0 + (k - 1) * rh
    local chosen = i == st.sel
    col(chosen and { 232, 250, 246 } or { 255, 255, 255 })
    rrect("fill", r.x + pad, ry + 2, r.w - pad * 2, rh - 4, rh * 0.14)
    col(chosen and TEAL or { 206, 222, 218 })
    rrect("line", r.x + pad, ry + 2, r.w - pad * 2, rh - 4, rh * 0.14)
    -- rank and icon
    local f = ctx.font(rh * 0.3)
    lg.setFont(f)
    col(TEAL)
    lg.printf(tostring(i), r.x + pad, ry + (rh - f:getHeight()) / 2, rh * 0.5, "center")
    local s = rh - 14
    if ctx.drawIcon then ctx.drawIcon(t.id, r.x + pad + rh * 0.5, ry + 7, s) end
    local wx = r.x + pad + rh * 0.5 + s + 10
    local f2 = ctx.font(rh * 0.24)
    lg.setFont(f2)
    col(INK)
    lg.print(t.name or t.id, wx, ry + rh * 0.12)
    local f3 = ctx.font(rh * 0.19)
    lg.setFont(f3)
    col({ 110, 116, 120 })
    local avg = t.plays > 0 and t.seconds / t.plays or 0
    lg.print(("%s   played %d time%s   about %s each"):format(hm(t.seconds), t.plays, t.plays == 1 and "" or "s", hm(avg)),
      wx, ry + rh * 0.12 + f2:getHeight() * 1.05)
    hit("sel:" .. i, r.x + pad, ry, r.w - pad * 2, rh)
  end
  -- page dots
  local fy = y0 + h0 - h0 * 0.1
  for p = 1, math.min(pages, 10) do
    local px = r.x + r.w / 2 + (p - (math.min(pages, 10) + 1) / 2) * h0 * 0.05
    if p == st.page then col(TEAL) else lg.setColor(0.78, 0.8, 0.8, 1) end
    lg.circle("fill", px, fy, h0 * 0.013)
  end
  hit("prev", r.x, fy - h0 * 0.05, r.w / 2, h0 * 0.1)
  hit("next", r.x + r.w / 2, fy - h0 * 0.05, r.w / 2, h0 * 0.1)
end

local function bars(x, y, w, h, days, field, color, fmt)
  local maxv = 1
  for _, d in ipairs(days) do maxv = math.max(maxv, d[field]) end
  local bw = w / #days
  local f = ctx.font(h * 0.09)
  lg.setFont(f)
  for k, d in ipairs(days) do
    local v = d[field]
    local bh = (h - f:getHeight() * 2.4) * v / maxv
    local bx = x + (k - 1) * bw + bw * 0.18
    col({ 220, 236, 232 })
    rrect("fill", bx, y + f:getHeight() * 1.2, bw * 0.64, h - f:getHeight() * 2.4, 4)
    col(color)
    if bh > 0 then rrect("fill", bx, y + h - f:getHeight() * 1.2 - bh, bw * 0.64, bh, 4) end
    col(INK, 0.8)
    lg.printf(d.label, x + (k - 1) * bw, y + h - f:getHeight(), bw, "center")
    if v > 0 then lg.printf(fmt(v), x + (k - 1) * bw - 6, y + h - f:getHeight() * 2.3 - bh, bw + 12, "center") end
  end
end

local function drawWeek(r, y0, pad)
  local days = week()
  local h0 = r.y + r.h - y0 - pad
  local f = ctx.font(h0 * 0.06)
  lg.setFont(f)
  col(TEAL)
  lg.print("Time played", r.x + pad, y0)
  bars(r.x + pad, y0 + f:getHeight(), r.w - pad * 2, h0 - f:getHeight() - pad, days, "seconds", TEAL, hm)
end

function A.drawBottom(r)
  st.hits = {}
  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)
  for i = 0, r.h, 2 do
    local k = i / r.h
    lg.setColor(0.95 - 0.03 * k, 0.985 - 0.03 * k, 0.975 - 0.03 * k, 1)
    lg.rectangle("fill", r.x, r.y + i, r.w, 2)
  end
  local pad = math.floor(r.w * 0.025)
  local hh = math.floor(r.h * 0.12)
  -- the title bar: back, the Activity Log's name
  col(TEAL)
  lg.rectangle("fill", r.x, r.y, r.w, hh)
  lg.setColor(1, 1, 1, 0.25)
  lg.rectangle("fill", r.x, r.y, r.w, hh * 0.4)
  local f = ctx.font(hh * 0.46)
  lg.setFont(f)
  lg.setColor(1, 1, 1, 1)
  lg.printf("Activity Log", r.x, r.y + (hh - f:getHeight()) / 2, r.w, "center")
  local bw = hh * 1.4
  lg.setColor(1, 1, 1, st.down == "back" and 0.5 or 0.3)
  rrect("fill", r.x + pad * 0.5, r.y + hh * 0.15, bw, hh * 0.7, hh * 0.2)
  lg.setColor(1, 1, 1, 1)
  local bf = ctx.font(hh * 0.32)
  lg.setFont(bf)
  lg.printf("Back", r.x + pad * 0.5, r.y + (hh - bf:getHeight()) / 2, bw, "center")
  hit("back", r.x, r.y, bw + pad, hh)
  local th = math.floor(r.h * 0.09)
  tabs(r.x + pad, r.y + hh + pad * 0.5, r.w - pad * 2, th)
  local y0 = r.y + hh + pad + th
  if st.view == "time" then drawTime(r, y0, pad) else drawWeek(r, y0, pad) end
  lg.pop()
end

-- the top screen's content (below the 3DS status bar)
function A.drawTop(r)
  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)
  for y = 0, r.h, 2 do
    local k = y / r.h
    lg.setColor(0.93 + 0.05 * k, 0.99, 0.97, 1)
    lg.rectangle("fill", r.x, r.y + y, r.w, 2)
  end
  local pad = r.h * 0.05
  if st.view == "time" then
    local t = ranked()[st.sel]
    if t then
      local s = r.h * 0.5
      if ctx.drawIcon then ctx.drawIcon(t.id, r.x + pad * 2, r.y + pad * 1.5, s) end
      local wx = r.x + pad * 3 + s
      local f = ctx.font(r.h * 0.085)
      lg.setFont(f)
      col(INK)
      lg.printf(t.name or t.id, wx, r.y + pad * 1.5, r.x + r.w - wx - pad, "left")
      local f2 = ctx.font(r.h * 0.06)
      lg.setFont(f2)
      col({ 80, 110, 104 })
      local lines = {
        ("Total play time: %s"):format(hm(t.seconds)),
        ("Times played: %d"):format(t.plays),
        ("First played: %s"):format(t.first or "-"),
        ("Last played: %s"):format(t.last or "-"),
      }
      lg.print(table.concat(lines, "\n"), wx, r.y + pad * 1.5 + f:getHeight() * 1.4)
    end
  else
    -- the week's walking, with the Activity Log's figures
    local days = week()
    local walker = img("fold3ds/banners/activity_walker.png")
    local total = 0
    for _, d in ipairs(days) do total = total + d.steps end
    if walker then
      local iw, ih = walker:getDimensions()
      local s = r.h * 0.28 / ih
      lg.setColor(1, 1, 1, 1)
      lg.draw(walker, r.x + pad * 1.5, r.y + pad, 0, s, s)
    end
    local f = ctx.font(r.h * 0.07)
    lg.setFont(f)
    col(TEAL)
    lg.print(("%d steps this week"):format(total), r.x + pad * 2 + r.h * 0.2, r.y + pad * 1.4)
    bars(r.x + pad * 3, r.y + r.h * 0.34, r.w - pad * 6, r.h * 0.6, days, "steps", { 60, 190, 120 },
      function(v) return tostring(v) end)
  end
  lg.pop()
end

---------------------------------------------------------------- input

local function activate(id)
  if id == "back" then return "exit" end
  if id:match("^view:") then
    local v = id:sub(6)
    if v ~= st.view then st.view = v; Sfx.play("select") end
  elseif id:match("^sel:") then
    local i = tonumber(id:sub(5))
    if i ~= st.sel then st.sel = i; Sfx.play("over") end
  elseif id == "prev" or id == "next" then
    local n = math.max(1, math.ceil(#ranked() / 4))
    local p = math.max(1, math.min(n, st.page + (id == "next" and 1 or -1)))
    Sfx.play(p == st.page and "edge" or "strip")
    st.page = p
    st.sel = (p - 1) * 4 + 1
  end
end

local function hitAt(x, y)
  for k = #st.hits, 1, -1 do
    local h = st.hits[k]
    if x >= h.x and y >= h.y and x <= h.x + h.w and y <= h.y + h.h then return h end
  end
end

function A.pressed(id, x, y)
  local h = hitAt(x, y)
  st.touches[id] = { hit = h and h.id, x0 = x, y0 = y }
  st.down = h and h.id or nil
end

function A.moved(id, x, y)
  local t = st.touches[id]
  if not t then return end
  local h = hitAt(x, y)
  st.down = (h and h.id == t.hit) and t.hit or nil
end

function A.released(id, x, y)
  local t = st.touches[id]
  st.touches[id] = nil
  st.down = nil
  if not t then return end
  if math.abs(x - t.x0) > 60 and math.abs(x - t.x0) > math.abs(y - t.y0) then
    return activate(x < t.x0 and "next" or "prev")
  end
  local h = hitAt(x, y)
  if h and h.id == t.hit then return activate(h.id) end
end

function A.button(name)
  if name == "home" or name == "b" then return "exit" end
  if name == "l" or name == "r" then return activate("view:" .. (st.view == "time" and "week" or "time")) end
  if st.view == "time" then
    local n = #ranked()
    if name == "up" then st.sel = math.max(1, st.sel - 1); Sfx.play("over")
    elseif name == "down" then st.sel = math.min(math.max(1, n), st.sel + 1); Sfx.play("over")
    elseif name == "left" then return activate("prev")
    elseif name == "right" then return activate("next") end
    st.page = math.floor((st.sel - 1) / 4) + 1
  end
end

-- the most-played title's name (the Friend List's card)
function A.favourite()
  local t = ranked()[1]
  return t and (t.name or t.id) or nil
end

function A.init(context) ctx = context; load() end
function A.isOpen() return st.open end
function A.open() st.open = true; st.view = "time"; st.sel, st.page = 1, 1; Sfx.play("open") end
function A.close() if st.open then st.open = false; Sfx.play("back") end end

return A
