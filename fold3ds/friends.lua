-- Friend List (3DS theme, on the HOME menu's applet bar), after the 3DS's
-- own: your friend card -- name, friend code, a one-line comment and the
-- game you are playing most -- and the friends you have registered by
-- their friend code.
--
-- Bottom screen: the friends as cards on a grid (register a friend, edit
-- your card); top screen: the card of whoever is picked.  Names and
-- comments are typed on the phone's keyboard; codes on a number pad.
-- Kept in fold3ds_friends.cfg.
local F = {}

local lg = love.graphics
local Sfx = require("fold3ds.sfx")

local FILE = "fold3ds_friends.cfg"
local ORANGE = { 246, 136, 30 }
local INK = { 70, 60, 50 }
local MAX = 100
local PER = 8          -- cards per page (4 x 2)

local ctx
local data = { me = nil, friends = {}, loaded = false }
local st = {
  open = false, sel = 0, page = 1,     -- sel 0: your own card
  mode = "list",                        -- list | code | text | delete
  code = "", text = nil,                -- the pad's digits; { field, value, target }
  hits = {}, touches = {},
}

local function col(c, a) lg.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1) end
local function clean(s) return (s or ""):gsub("[|\n\r\t]", " ") end

local function fmtCode(c)
  c = (c or ""):gsub("[^%d_]", "")
  return (c:sub(1, 4) .. (#c > 4 and "-" .. c:sub(5, 8) or "") .. (#c > 8 and "-" .. c:sub(9, 12) or ""))
end

---------------------------------------------------------------- the record

local function save()
  local out = {}
  local me = data.me
  out[#out + 1] = ("M|%s|%s|%s"):format(me.code, clean(me.name), clean(me.comment))
  for _, f in ipairs(data.friends) do
    out[#out + 1] = ("F|%s|%s|%s|%s"):format(f.code, clean(f.name), clean(f.comment), f.added or "")
  end
  pcall(love.filesystem.write, FILE, table.concat(out, "\n") .. "\n")
end

local function load()
  if data.loaded then return end
  data.loaded = true
  local ok, text = pcall(love.filesystem.read, FILE)
  if ok and type(text) == "string" then
    for line in text:gmatch("[^\n]+") do
      local kind, code, name, comment, added = line:match("^(%a)|([^|]*)|([^|]*)|([^|]*)|?([^|]*)$")
      if kind == "M" then
        data.me = { code = code, name = name, comment = comment }
      elseif kind == "F" then
        data.friends[#data.friends + 1] = { code = code, name = name, comment = comment, added = added }
      end
    end
  end
  if not data.me then
    -- a friend code of your own, kept for good
    math.randomseed(os.time() + math.floor((os.clock() % 1) * 1e6))
    local d = {}
    for i = 1, 12 do d[i] = tostring(math.random(i == 1 and 1 or 0, 9)) end
    data.me = { code = table.concat(d), name = "Player", comment = "Hello!" }
    save()
  end
end

local function current()
  if st.sel == 0 then return data.me, true end
  return data.friends[st.sel], false
end

---------------------------------------------------------------- drawing

-- a friend card: the colour band with the initial, the name, the code and
-- the comment (and, for you, your most-played game)
local function card(x, y, w, h, who, mine, big)
  lg.setColor(0, 0, 0, 0.14)
  lg.rectangle("fill", x + 2, y + 3, w, h, h * 0.1, h * 0.1)
  lg.setColor(1, 1, 1, 1)
  lg.rectangle("fill", x, y, w, h, h * 0.1, h * 0.1)
  local c = mine and ORANGE or { 70, 160, 220 }
  col(c)
  local band = big and h * 0.3 or h * 0.42
  lg.rectangle("fill", x, y, w, band, h * 0.1, h * 0.1)
  lg.rectangle("fill", x, y + band * 0.5, w, band * 0.5)
  -- the badge: the name's first letter
  local bs = band * 0.8
  local bx, by = x + band * 0.1, y + band * 0.1
  lg.setColor(1, 1, 1, 1)
  lg.circle("fill", bx + bs / 2, by + bs / 2, bs / 2)
  local initial = (who.name or "?"):match("^[%z\1-\127\194-\244][\128-\191]*") or "?"
  local f = ctx.font(bs * 0.55)
  lg.setFont(f)
  col(c)
  lg.printf(initial:upper(), bx, by + (bs - f:getHeight()) / 2, bs, "center")
  local nf = ctx.font(band * (big and 0.42 or 0.36))
  lg.setFont(nf)
  lg.setColor(1, 1, 1, 1)
  lg.printf(who.name or "", bx + bs + band * 0.15, y + (band - nf:getHeight()) / 2, w - bs - band * 0.4, "left")
  if not big then
    local sf = ctx.font(math.min(h * 0.15, w * 0.085))
    lg.setFont(sf)
    col(INK)
    lg.printf(fmtCode(who.code), x, y + band + (h - band - sf:getHeight()) / 2, w, "center")
    return
  end
  local pad = h * 0.06
  local lf = ctx.font(h * 0.062)
  local vf = ctx.font(h * 0.085)
  local ly = y + band + pad
  local function row(label, value)
    lg.setFont(lf)
    col({ 150, 140, 130 })
    lg.print(label, x + pad * 2, ly)
    lg.setFont(vf)
    col(INK)
    lg.printf(value, x + pad * 2, ly + lf:getHeight(), w - pad * 4, "left")
    ly = ly + lf:getHeight() + vf:getHeight() * 1.25
  end
  row("Friend Code", fmtCode(who.code))
  row("Comment", who.comment ~= "" and who.comment or "-")
  if mine and ctx.favourite then
    local fav = ctx.favourite()
    if fav then row("Playing the most", fav) end
  elseif who.added and who.added ~= "" then
    row("Registered", who.added)
  end
end

local function hit(id, x, y, w, h) st.hits[#st.hits + 1] = { id = id, x = x, y = y, w = w, h = h } end

local function pill(id, x, y, w, h, label, on, colour)
  col(colour or (on and ORANGE or { 255, 255, 255 }))
  lg.rectangle("fill", x, y, w, h, h * 0.3, h * 0.3)
  col({ 200, 190, 180 })
  lg.setLineWidth(1)
  lg.rectangle("line", x, y, w, h, h * 0.3, h * 0.3)
  local f = ctx.font(h * 0.42)
  lg.setFont(f)
  if colour or on then lg.setColor(1, 1, 1, 1) else col(INK) end
  lg.printf(label, x, y + (h - f:getHeight()) / 2, w, "center")
  hit(id, x, y, w, h)
end

local function drawPad(r, pad)
  local top = r.y + r.h * 0.14
  local f = ctx.font(r.h * 0.09)
  lg.setFont(f)
  col(INK)
  lg.printf("Enter your friend's friend code", r.x, top, r.w, "center")
  local want = #st.code < 12 and ("_"):rep(12 - #st.code) or ""
  lg.setFont(ctx.font(r.h * 0.1))
  col(ORANGE)
  lg.printf(fmtCode(st.code .. want), r.x, top + f:getHeight() * 1.3, r.w, "center")
  local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "del", "0", "ok" }
  local kw, kh = r.w * 0.15, r.h * 0.12
  local gx = r.x + (r.w - kw * 3 - pad * 2) / 2
  local gy = top + f:getHeight() * 3
  for i, k in ipairs(keys) do
    local cx = gx + ((i - 1) % 3) * (kw + pad)
    local cy = gy + math.floor((i - 1) / 3) * (kh + pad)
    local label = k == "del" and "Delete" or k == "ok" and "OK" or k
    pill("key:" .. k, cx, cy, kw, kh, label, false, k == "ok" and (#st.code == 12 and ORANGE or { 200, 190, 180 }) or nil)
  end
  pill("cancel", r.x + pad, r.y + pad, r.w * 0.2, r.h * 0.1, "Cancel")
end

local function drawText(r, pad)
  local t = st.text
  local f = ctx.font(r.h * 0.085)
  lg.setFont(f)
  col(INK)
  lg.printf(t.prompt, r.x, r.y + r.h * 0.2, r.w, "center")
  local bx, by, bw, bh = r.x + r.w * 0.1, r.y + r.h * 0.36, r.w * 0.8, r.h * 0.14
  lg.setColor(1, 1, 1, 1)
  lg.rectangle("fill", bx, by, bw, bh, bh * 0.2, bh * 0.2)
  col(ORANGE)
  lg.setLineWidth(2)
  lg.rectangle("line", bx, by, bw, bh, bh * 0.2, bh * 0.2)
  local vf = ctx.font(bh * 0.5)
  lg.setFont(vf)
  col(INK)
  local caret = (love.timer.getTime() % 1 < 0.5) and "|" or ""
  lg.printf(t.value .. caret, bx + bh * 0.2, by + (bh - vf:getHeight()) / 2, bw - bh * 0.4, "left")
  pill("text:ok", r.x + r.w * 0.55, r.y + r.h * 0.6, r.w * 0.3, r.h * 0.12, "OK", true)
  pill("text:cancel", r.x + r.w * 0.15, r.y + r.h * 0.6, r.w * 0.3, r.h * 0.12, "Cancel")
  local hf = ctx.font(r.h * 0.055)
  lg.setFont(hf)
  col({ 150, 140, 130 })
  lg.printf("Type on the keyboard, then OK", r.x, r.y + r.h * 0.8, r.w, "center")
end

function F.drawBottom(r)
  st.hits = {}
  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)
  col({ 252, 246, 236 })
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  local pad = math.floor(r.w * 0.02)
  if st.mode == "code" then drawPad(r, pad) lg.pop() return end
  if st.mode == "text" then drawText(r, pad) lg.pop() return end
  -- the bar: Back, your card, register
  local bh = math.floor(r.h * 0.11)
  pill("back", r.x + pad, r.y + pad, r.w * 0.18, bh, "Back")
  pill("me", r.x + pad * 2 + r.w * 0.18, r.y + pad, r.w * 0.24, bh, "My Card", st.sel == 0)
  pill("add", r.x + r.w - pad - r.w * 0.3, r.y + pad, r.w * 0.3, bh, "Register Friend", false, ORANGE)
  local top = r.y + bh + pad * 2
  local foot = math.floor(r.h * 0.12)
  -- the grid
  local cols, rows = 4, 2
  local gw = r.w - pad * 2
  local gh = r.y + r.h - foot - pad - top
  local cw = (gw - pad * (cols - 1)) / cols
  local ch = math.min((gh - pad * (rows - 1)) / rows, cw * 0.8)
  local pages = math.max(1, math.ceil(#data.friends / PER))
  st.page = math.max(1, math.min(pages, st.page))
  if #data.friends == 0 then
    local f = ctx.font(r.h * 0.065)
    lg.setFont(f)
    col({ 150, 140, 130 })
    lg.printf("No friends registered yet.\nTap Register Friend and enter\ntheir friend code.", r.x + pad,
      top + gh * 0.3, r.w - pad * 2, "center")
  end
  for k = 1, PER do
    local i = (st.page - 1) * PER + k
    local who = data.friends[i]
    if not who then break end
    local cx = r.x + pad + ((k - 1) % cols) * (cw + pad)
    local cy = top + math.floor((k - 1) / cols) * (ch + pad)
    card(cx, cy, cw, ch, who, false, false)
    if st.sel == i then
      col(ORANGE)
      lg.setLineWidth(3)
      lg.rectangle("line", cx - 2, cy - 2, cw + 4, ch + 4, ch * 0.1, ch * 0.1)
    end
    hit("sel:" .. i, cx, cy, cw, ch)
  end
  -- the foot: pages, and what can be done with the picked card
  local fy = r.y + r.h - foot
  local f = ctx.font(foot * 0.4)
  lg.setFont(f)
  col(INK)
  lg.printf(("%d / %d   (%d friends)"):format(st.page, pages, #data.friends), r.x, fy + (foot - f:getHeight()) / 2, r.w, "center")
  pill("prev", r.x + pad, fy + foot * 0.15, r.w * 0.1, foot * 0.7, "<")
  pill("next", r.x + r.w * 0.9 - pad, fy + foot * 0.15, r.w * 0.1, foot * 0.7, ">")
  local who, mine = current()
  if who then
    if mine then
      pill("edit:name", r.x + pad * 2 + r.w * 0.1, fy + foot * 0.15, r.w * 0.2, foot * 0.7, "Name")
      pill("edit:comment", r.x + r.w * 0.7 - pad, fy + foot * 0.15, r.w * 0.2, foot * 0.7, "Comment")
    elseif st.mode == "delete" then
      pill("delete", r.x + r.w * 0.7 - pad, fy + foot * 0.15, r.w * 0.2, foot * 0.7, "Sure?", false, { 214, 60, 60 })
    else
      pill("edit:fname", r.x + pad * 2 + r.w * 0.1, fy + foot * 0.15, r.w * 0.2, foot * 0.7, "Rename")
      pill("delete", r.x + r.w * 0.7 - pad, fy + foot * 0.15, r.w * 0.2, foot * 0.7, "Delete")
    end
  end
  lg.pop()
end

-- the top screen's content (below the 3DS status bar): the picked card
function F.drawTop(r)
  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)
  for y = 0, r.h, 2 do
    local k = y / r.h
    lg.setColor(1, 0.97 - 0.05 * k, 0.9 - 0.08 * k, 1)
    lg.rectangle("fill", r.x, r.y + y, r.w, 2)
  end
  local who, mine = current()
  local pad = r.h * 0.06
  if st.mode == "code" or st.mode == "text" then who, mine = data.me, true end
  if who then
    local w = r.w * 0.7
    card(r.x + (r.w - w) / 2, r.y + pad, w, r.h - pad * 2, who, mine, true)
  end
  lg.pop()
end

---------------------------------------------------------------- input

local function startText(field, prompt, value, target)
  st.mode = "text"
  st.text = { field = field, prompt = prompt, value = value or "", target = target }
  if love.keyboard and love.keyboard.setTextInput then pcall(love.keyboard.setTextInput, true) end
  Sfx.play("open")
end

local function endText(keep)
  local t = st.text
  st.mode, st.text = "list", nil
  if love.keyboard and love.keyboard.setTextInput then pcall(love.keyboard.setTextInput, false) end
  if not (keep and t) then Sfx.play("back") return end
  local v = t.value:gsub("^%s+", ""):gsub("%s+$", "")
  if t.field == "name" then
    if v ~= "" then data.me.name = v end
  elseif t.field == "comment" then
    data.me.comment = v
  elseif t.field == "fname" and t.target then
    if v ~= "" then t.target.name = v end
  end
  save()
  Sfx.play("select")
end

local function activate(id)
  if st.mode == "delete" and id ~= "delete" then st.mode = "list" end
  if id == "back" then return "exit" end
  if id == "cancel" then st.mode = "list"; Sfx.play("back") return end
  if id == "me" then st.sel = 0; Sfx.play("select")
  elseif id == "add" then
    if #data.friends >= MAX then Sfx.play("error") return end
    st.mode, st.code = "code", ""
    Sfx.play("open")
  elseif id == "prev" or id == "next" then
    local pages = math.max(1, math.ceil(#data.friends / PER))
    local p = math.max(1, math.min(pages, st.page + (id == "next" and 1 or -1)))
    Sfx.play(p == st.page and "edge" or "strip")
    st.page = p
  elseif id:match("^sel:") then
    st.sel = tonumber(id:sub(5)); Sfx.play("over")
  elseif id:match("^key:") then
    local k = id:sub(5)
    if k == "del" then st.code = st.code:sub(1, -2); Sfx.play("back")
    elseif k == "ok" then
      if #st.code < 12 then Sfx.play("error") return end
      if st.code == data.me.code then Sfx.play("error") return end
      for i, f in ipairs(data.friends) do
        if f.code == st.code then st.sel = i; st.mode = "list"; Sfx.play("notice") return end
      end
      local f = { code = st.code, name = ("Friend %d"):format(#data.friends + 1), comment = "", added = os.date("%Y-%m-%d") }
      data.friends[#data.friends + 1] = f
      st.sel = #data.friends
      st.page = math.ceil(st.sel / PER)
      save()
      Sfx.play("gift")
      startText("fname", "Your friend's name", "", f)
    elseif #st.code < 12 then st.code = st.code .. k; Sfx.play("over") end
  elseif id == "text:ok" then endText(true)
  elseif id == "text:cancel" then endText(false)
  elseif id == "edit:name" then startText("name", "Your name", data.me.name)
  elseif id == "edit:comment" then startText("comment", "Your comment", data.me.comment)
  elseif id == "edit:fname" then
    local who = current()
    if who then startText("fname", "Your friend's name", who.name, who) end
  elseif id == "delete" then
    if st.mode == "delete" then
      table.remove(data.friends, st.sel)
      st.sel = math.min(st.sel, #data.friends)
      st.mode = "list"
      save()
      Sfx.play("back")
    else
      st.mode = "delete"
      Sfx.play("notice")
    end
  end
end

local function hitAt(x, y)
  for k = #st.hits, 1, -1 do
    local h = st.hits[k]
    if x >= h.x and y >= h.y and x <= h.x + h.w and y <= h.y + h.h then return h end
  end
end

function F.pressed(id, x, y)
  local h = hitAt(x, y)
  st.touches[id] = { hit = h and h.id, x0 = x, y0 = y }
end

function F.moved() end

function F.released(id, x, y)
  local t = st.touches[id]
  st.touches[id] = nil
  if not t then return end
  if st.mode == "list" and math.abs(x - t.x0) > 60 and math.abs(x - t.x0) > math.abs(y - t.y0) then
    return activate(x < t.x0 and "next" or "prev")
  end
  local h = hitAt(x, y)
  if h and h.id == t.hit then return activate(h.id) end
end

function F.button(name)
  if st.mode == "text" then
    if name == "a" then endText(true) elseif name == "b" then endText(false) end
    return
  end
  if st.mode == "code" then
    if name == "b" then activate("cancel") elseif name == "a" then activate("key:ok") end
    return
  end
  if name == "home" or name == "b" then return "exit" end
  local n = #data.friends
  if name == "left" and st.sel > 0 then st.sel = st.sel - 1; Sfx.play("over")
  elseif name == "right" and st.sel < n then st.sel = st.sel + 1; Sfx.play("over")
  elseif name == "up" and st.sel > 4 then st.sel = st.sel - 4; Sfx.play("over")
  elseif name == "down" and st.sel + 4 <= n then st.sel = math.max(1, st.sel + 4); Sfx.play("over")
  elseif name == "x" then activate("add")
  elseif name == "y" then activate("me") end
  if st.sel > 0 then st.page = math.ceil(st.sel / PER) end
end

-- typing, while a name or comment is being entered (true: taken)
function F.textinput(t)
  if not (st.open and st.mode == "text") then return false end
  if #st.text.value < 32 then st.text.value = st.text.value .. t end
  return true
end

function F.keypressed(key)
  if not st.open then return false end
  if st.mode == "text" then
    if key == "backspace" then
      local ok, utf8 = pcall(require, "utf8")
      local v = st.text.value
      local off = ok and utf8.offset(v, -1)
      st.text.value = off and v:sub(1, off - 1) or v:sub(1, -2)
    elseif key == "return" or key == "kpenter" then endText(true)
    elseif key == "escape" then endText(false) end
    return true
  end
  if st.mode == "code" then
    local d = key:match("^kp(%d)$") or key:match("^(%d)$")
    if d then activate("key:" .. d) return true end
    if key == "backspace" then activate("key:del") return true end
    if key == "return" then activate("key:ok") return true end
  end
  return false
end

function F.init(context) ctx = context; load() end
function F.isOpen() return st.open end
function F.open() load(); st.open = true; st.mode = "list"; st.sel = 0; Sfx.play("open") end
function F.close()
  if not st.open then return end
  if st.mode == "text" then endText(false) end
  st.open = false
  st.mode = "list"
  Sfx.play("back")
end

return F
