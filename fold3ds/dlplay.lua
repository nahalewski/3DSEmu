-- Download Play (3DS theme, the orange icon on the HOME menu's applet bar):
-- one phone sends a game's files, another nearby receives them, the way a
-- 3DS hands a game to its neighbour.
--
-- What travels: the game itself, ready to play on the other phone, with
-- nothing to pick there:
--   * a gen1recomp game: its ROM (this phone's kept copy, or baseroms/) in
--     one package with its saves (saves/<game>/ and save_<game>.lua, with
--     their backups) and the installed mods; the receiving phone installs
--     the saves and mods and imports the ROM straight away;
--   * a 3DS game (Azahar's library, fold3ds.azahar): the cartridge dump,
--     which lands in the other phone's 3DS games folder, and its folders in
--     Azahar's -- the installed game, its update, its DLC, its save data --
--     which land at the same place in the other phone's Azahar folder.
--
-- The transfer is FoldPlay.java (Google Nearby Connections through
-- love.system.foldCamera("call", "dp.*")): the phones find each other over
-- Bluetooth and the files move over Wi-Fi Direct / Wi-Fi whenever that is
-- faster.  A received package lands in downloadplay/received.zip; installing
-- it moves any file it replaces into downloadplay/backup_<time>/ first.
--
-- The top screen shows the Download Play banner turning in 3D, as the 3DS
-- shows it (D.drawBanner, also used while its icon is picked on the bar).
local D = {}

local lg = love.graphics
local Sfx = require("fold3ds.sfx")

local DIR = "downloadplay"
local CFG = "fold3ds_dlplay.cfg"

local ctx
local st = {
  open = false,
  view = "menu",             -- menu / pick / hosting / searching / receiving / received
  status = {},               -- FoldPlay's status lines
  game = nil,                -- the game being sent
  name = nil,                -- this phone's name on the other's list
  hits = {}, down = nil, touches = {},
  toast = nil,
  t = 0, pollAt = 0,
  confirm = false,
  fake = nil,                -- the desktop stand-in
}

local GAMES = { "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "leafgreen" }
local NAMES = {
  mods = "Mods",
  red = "Pokémon Red", blue = "Pokémon Blue", yellow = "Pokémon Yellow",
  gold = "Pokémon Gold", silver = "Pokémon Silver", crystal = "Pokémon Crystal",
  firered = "Pokémon FireRed", leafgreen = "Pokémon LeafGreen",
}
local SUFFIX = { red = "", blue = "_blue", yellow = "_yellow", gold = "_gold", silver = "_silver",
                 crystal = "_crystal", firered = "_firered", leafgreen = "_leafgreen" }

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function col(c, a) lg.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1) end
local function rrect(mode, x, y, w, h, r) lg.rectangle(mode, x, y, w, h, r, r, 10) end
local function toast(text) st.toast = { text = text, at = st.t } end

local fakeMode = os.getenv("POKEPORT_FOLD_FAKEDP") == "1"

local function bridge(cmd, arg)
  local f = love.system and love.system.foldCamera
  if not f then return nil end
  local ok, out = pcall(f, "call", cmd, arg or "")
  if ok then return out end
  return nil
end

local hasBridge
local function available()
  if hasBridge == nil then hasBridge = bridge("ping") == "ok" end
  return fakeMode or hasBridge
end

---------------------------------------------------------------- the files

-- the save folder paths that make up a game's files (only those present)
local function gameFiles(v, withMods)
  local out = {}
  local function add(p) if love.filesystem.getInfo(p) then out[#out + 1] = p end end
  add("saves/" .. v)
  local main = "save" .. (SUFFIX[v] or ("_" .. v)) .. ".lua"
  add(main)
  add(main .. ".bak")
  if withMods then add("mods") end
  return out
end

local function hasSaves(v)
  for _, p in ipairs(gameFiles(v, false)) do if p ~= "mods" then return true end end
  return false
end

-- the game's ROM on this phone: the kept copy the importer remembers, else
-- the kept copy by its usual name, else baseroms/.  Returns data, file name.
local ROM_EXT = { ".gb", ".gbc", ".gba" }
local function romBytes(v)
  local ok, RS = pcall(require, "src.import.RomSources")
  if ok and RS then
    local okC, cand = pcall(RS.candidate, v, nil)
    if okC and cand and cand.path then
      local okR, data = pcall(RS.readKept, cand.path)
      if okR and type(data) == "string" then return data, cand.path:match("[^/\\]+$") end
    end
    local okP, kept = pcall(RS.keptPath, v)
    if okP and kept then
      local okR, data = pcall(RS.readKept, kept)
      if okR and type(data) == "string" then return data, kept:match("[^/\\]+$") end
    end
  end
  for _, dir in ipairs({ "baseroms", "imports/baseroms" }) do
    for _, ext in ipairs(ROM_EXT) do
      local path = dir .. "/" .. v .. ext
      if love.filesystem.getInfo(path, "file") then
        local data = love.filesystem.read(path)
        if type(data) == "string" then return data, v .. ext end
      end
    end
  end
  return nil
end

local romKnown = {}
local function hasRom(v)
  if romKnown[v] == nil then romKnown[v] = romBytes(v) ~= nil end
  return romKnown[v]
end

local function myName()
  if st.name then return st.name end
  local ok, text = pcall(love.filesystem.read, CFG)
  local n = ok and type(text) == "string" and text:match("name=([%w%-]+)")
  if not n then
    n = ("G1R-%04d"):format(love.math.random(0, 9999))
    pcall(love.filesystem.write, CFG, "name=" .. n .. "\n")
  end
  st.name = n
  return n
end

local function parseStatus(text)
  local s = {}
  for line in (text or ""):gmatch("[^\n]+") do
    local k, v = line:match("^(%w+)=(.*)$")
    if k then s[k] = v end
  end
  local peers = {}
  for id, name in (s.peers or ""):gmatch("([^:;]+):([^;]*);") do
    local who, game = name:match("^(.-)|(.*)$")
    peers[#peers + 1] = { id = id, who = who or name, game = game or "" }
  end
  s.peerList = peers
  s.done, s.total, s.speed = tonumber(s.done) or 0, tonumber(s.total) or 0, tonumber(s.speed) or 0
  return s
end

---------------------------------------------------------------- actions

-- one package: the ROM (downloadplay/rom/<file>), the saves, the mods
local Azahar = require("fold3ds.azahar")

local function s3dsName(game) return type(game) == "string" and game:match("^3DS %- ") ~= nil end

-- the 3DS game with this tile id, from Azahar's library
local function ctrGame(id)
  for _, g in ipairs(Azahar.games()) do if g.id == id then return g end end
end

-- a name another phone's list can show (no : ; | in it)
local function wireName(s) return (s:gsub("[:;|]", " ")) end

local function sendCtr(id)
  local g = ctrGame(id)
  if not g then toast("That 3DS game is gone") Sfx.play("noMove") return end
  local files = Azahar.transferEntries(g)
  if #files == 0 then toast("Couldn't find " .. g.name .. "'s files") Sfx.play("noMove") return end
  st.game = id
  NAMES[id] = g.name
  if fakeMode then
    st.fake = { role = "host", t0 = st.t }
    st.view = "hosting"
    Sfx.play("open")
    return
  end
  local root = love.filesystem.getSaveDirectory()
  love.filesystem.createDirectory(DIR)
  local zip = root .. "/" .. DIR .. "/send_3ds.zip"
  local r = bridge("zip", root .. "|" .. zip .. "|" .. table.concat(files, ";"))
  if not r or not r:match("^ok:[1-9]") then toast("Couldn't pack " .. g.name) Sfx.play("cancel") return end
  bridge("dp.host", zip .. "|" .. myName() .. "|" .. wireName("3DS - " .. g.name))
  st.view = "hosting"
  Sfx.play("open")
end

local function send(v)
  if v:match("^ctr_") then return sendCtr(v) end
  local rom, name = romBytes(v)
  if not rom then
    toast("No ROM for " .. NAMES[v] .. " on this phone -- import it first")
    Sfx.play("noMove")
    return
  end
  love.filesystem.createDirectory(DIR .. "/rom")
  for _, f in ipairs(love.filesystem.getDirectoryItems(DIR .. "/rom")) do
    love.filesystem.remove(DIR .. "/rom/" .. f)
  end
  if not love.filesystem.write(DIR .. "/rom/" .. name, rom) then
    toast("Couldn't pack the ROM") Sfx.play("cancel") return
  end
  local files = { DIR .. "/rom" }
  for _, p in ipairs(gameFiles(v, true)) do files[#files + 1] = p end
  st.game = v
  if fakeMode then
    st.fake = { role = "host", t0 = st.t }
    st.view = "hosting"
    Sfx.play("open")
    return
  end
  local root = love.filesystem.getSaveDirectory()
  love.filesystem.createDirectory(DIR)
  local zip = root .. "/" .. DIR .. "/send_" .. v .. ".zip"
  local r = bridge("zip", root .. "|" .. zip .. "|" .. table.concat(files, ";"))
  if not r or not r:match("^ok") then toast("Couldn't pack the files") Sfx.play("cancel") return end
  bridge("dp.host", zip .. "|" .. myName() .. "|" .. v)
  st.view = "hosting"
  Sfx.play("open")
end

local function receive()
  if fakeMode then
    st.fake = { role = "join", t0 = st.t }
    st.view = "searching"
    Sfx.play("open")
    return
  end
  bridge("dp.receivedTo", love.filesystem.getSaveDirectory() .. "/" .. DIR)
  bridge("dp.join", myName())
  st.view = "searching"
  Sfx.play("open")
end

local function connect(peer)
  if fakeMode then st.fake.connectAt = st.t; st.view = "receiving"; Sfx.play("select") return end
  bridge("dp.connect", peer.id)
  st.view = "receiving"
  Sfx.play("select")
end

local function stopAll()
  if not fakeMode then bridge("dp.stop") end
  st.fake = nil
  st.status = {}
  st.confirm = false
end

local function install()
  if not st.confirm then
    st.confirm = true
    Sfx.play("dialog")
    return
  end
  st.confirm = false
  if fakeMode then toast("Installed (test)") st.view = "menu" return end
  local root = love.filesystem.getSaveDirectory()
  local backup = root .. "/" .. DIR .. "/backup_" .. os.date("%Y%m%d_%H%M%S")
  -- a 3DS game's files go to Azahar's folder and the 3DS games folder
  local r = bridge("unzip", (st.status.file or "") .. "|" .. root .. "|" .. backup
    .. "|" .. (Azahar.userDir() or "") .. "|" .. (Azahar.gamesDir() or ""))
  if r and r:match("^ok") then
    local n = r:match("^ok:(%d+)") or "0"
    toast(("Installed %s files; the old ones are in %s"):format(n, DIR .. "/backup_..."))
    Sfx.play("start")
    -- the game itself: import the ROM that came with it, on the launcher
    local imp = ctx.subject and ctx.subject()
    for _, f in ipairs(love.filesystem.getDirectoryItems(DIR .. "/rom")) do
      local path = DIR .. "/rom/" .. f
      local data = love.filesystem.read(path)
      love.filesystem.remove(path)
      if type(data) == "string" and imp and imp.startData then
        pcall(imp.startData, imp, data, f, nil)
        st.imported = true
      end
    end
    romKnown = {}
    -- a 3DS game: Azahar looks again, and the game joins the HOME menu
    local threeDs = tonumber(r:match("^ok:%d+:%d+:(%d+)") or "0") or 0
    if threeDs > 0 then
      Azahar.open("refresh")
      st.imported = true
    elseif (s3dsName(st.status.game)) and not Azahar.userDir() then
      toast("Set up 3DS on this phone first (the Set Up 3DS icon), then receive again")
    end
  else
    toast("Couldn't install: " .. tostring(r))
    Sfx.play("cancel")
  end
  stopAll()
  st.view = "menu"
end

---------------------------------------------------------------- the banner

-- The Download Play banner in rect r, the two consoles turning in 3D
-- (a solid slab: its edge in darker orange) over the words.
local banner = {}
local function bannerImages()
  if banner.icon == nil then
    local ok, img = pcall(lg.newImage, "fold3ds/dlplay/logo.png")
    if ok then
      img:setFilter("linear", "linear")
      local w, h = img:getDimensions()
      local split = math.floor(h * 0.63)
      banner.img = img
      banner.icon = lg.newQuad(0, 0, w, split, w, h)
      banner.words = lg.newQuad(0, split, w, h - split, w, h)
      banner.w, banner.split, banner.h = w, split, h
    else
      banner.icon = false
    end
  end
  return banner.icon and banner or nil
end

function D.drawBanner(r, t)
  local B = bannerImages()
  if not B then return end
  local s = math.min(r.w * 0.8 / B.w, r.h * 0.92 / B.h)
  local cx = r.x + r.w / 2
  local iy = r.y + (r.h - B.h * s) / 2
  -- a turn every few seconds, eased, with a rest facing front
  local cycle = (t % 5) / 5
  local turn = cycle < 0.3 and 0 or (cycle - 0.3) / 0.7
  turn = turn * turn * (3 - 2 * turn)
  local a = turn * math.pi * 2 + 0.18 * math.sin(t * 1.3)
  local ca, sa = math.cos(a), math.sin(a)
  local depth = B.split * s * 0.14
  local steps = 10
  local bob = math.sin(t * 1.6) * r.h * 0.015
  -- the soft shadow
  lg.setColor(0, 0, 0, 0.12)
  lg.ellipse("fill", cx, iy + B.split * s * 1.02, B.w * s * 0.38 * math.max(0.25, math.abs(ca)), r.h * 0.025)
  -- the edge: layers of the silhouette in dark orange, stepping back
  for k = steps, 1, -1 do
    local off = sa * depth * k / steps
    local sh = 0.55 + 0.25 * (k / steps)
    lg.setColor(0.78 * sh, 0.3 * sh, 0.02 * sh, 1)
    lg.draw(B.img, B.icon, cx + off, iy + bob, 0, s * ca, s, B.w / 2, 0)
  end
  -- the face (its back is the same shape, a little darker)
  local lit = ca >= 0 and 1 or 0.78
  lg.setColor(lit, lit, lit, 1)
  lg.draw(B.img, B.icon, cx, iy + bob, 0, s * ca, s, B.w / 2, 0)
  -- a glint crossing as it turns
  if ca > 0 then
    lg.setColor(1, 1, 1, 0.18 * math.max(0, sa))
    lg.draw(B.img, B.icon, cx, iy + bob, 0, s * ca, s, B.w / 2, 0)
  end
  lg.setColor(1, 1, 1, 1)
  lg.draw(B.img, B.words, cx, iy + B.split * s, 0, s, s, B.w / 2, 0)
end

---------------------------------------------------------------- drawing

local INK = { 60, 62, 66 }
local FACE = { 238, 239, 242 }
local EDGE = { 170, 172, 178 }
local ORANGE = { 246, 124, 20 }

local function hit(id, x, y, w, h, extra)
  local e = extra or {}
  e.id, e.x, e.y, e.w, e.h = id, x, y, w, h
  st.hits[#st.hits + 1] = e
end

local function button(id, x, y, w, h, label, chosen, sub)
  local down = st.down == id
  local r = math.min(w, h) * 0.22
  col({ 120, 122, 128 }, 0.35)
  rrect("fill", x, y + h * 0.05, w, h, r)
  col(chosen and ORANGE or EDGE)
  rrect("fill", x, y + (down and h * 0.04 or 0), w, h, r)
  col(chosen and { 255, 150, 50 } or FACE)
  rrect("fill", x + 2, y + 2 + (down and h * 0.04 or 0), w - 4, h - 4, r * 0.9)
  local f = ctx.font(math.min(h * 0.32, w * 0.09))
  lg.setFont(f)
  col(chosen and { 255, 255, 255 } or INK)
  local ty = y + (sub and h * 0.2 or (h - f:getHeight()) / 2) + (down and h * 0.04 or 0)
  lg.printf(label, x, ty, w, "center")
  if sub then
    local f2 = ctx.font(math.min(h * 0.2, w * 0.06))
    lg.setFont(f2)
    col(chosen and { 255, 240, 220 } or { 110, 112, 118 })
    lg.printf(sub, x + w * 0.05, ty + f:getHeight() * 1.15, w * 0.9, "center")
  end
  hit(id, x, y, w, h)
end

local function waves(cx, cy, s, t)
  for k = 1, 3 do
    local ph = (t * 1.2 + k / 3) % 1
    lg.setColor(ORANGE[1] / 255, ORANGE[2] / 255, ORANGE[3] / 255, 1 - ph)
    lg.setLineWidth(s * 0.06)
    lg.arc("line", "open", cx, cy, s * (0.3 + ph * 0.7), -0.6, 0.6)
    lg.arc("line", "open", cx, cy, s * (0.3 + ph * 0.7), math.pi - 0.6, math.pi + 0.6)
  end
end

local function bar(x, y, w, h, frac)
  col({ 200, 204, 212 })
  rrect("fill", x, y, w, h, h / 2)
  lg.setColor(0.25, 0.62, 0.95, 1)
  if frac > 0 then rrect("fill", x, y, math.max(h, w * clamp(frac, 0, 1)), h, h / 2) end
end

local function human(bytes)
  if bytes >= 1048576 then return ("%.1f MB"):format(bytes / 1048576) end
  return ("%d KB"):format(math.floor(bytes / 1024))
end

function D.drawBottom(r)
  st.hits = {}
  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)
  for i = 0, r.h, 2 do
    local k = i / r.h
    lg.setColor(0.95 - 0.04 * k, 0.955 - 0.04 * k, 0.965 - 0.035 * k, 1)
    lg.rectangle("fill", r.x, r.y + i, r.w, 2)
  end
  local pad = math.floor(r.w * 0.03)
  local rowH = math.floor(r.h * 0.13)
  local tf = ctx.font(rowH * 0.42)
  -- the title bar with the back button
  button("back", r.x + pad, r.y + pad, rowH * 1.6, rowH, "Back")
  lg.setFont(tf)
  col(INK)
  lg.printf("Download Play", r.x, r.y + pad + (rowH - tf:getHeight()) / 2, r.w, "center")
  local y0 = r.y + pad * 2 + rowH
  local h0 = r.h - (y0 - r.y) - pad
  local s = st.status
  local f = ctx.font(rowH * 0.34)
  if not available() then
    lg.setFont(f)
    col(INK, 0.8)
    lg.printf("Download Play works on the phone.", r.x, y0 + h0 / 2 - f:getHeight(), r.w, "center")
  elseif st.view == "menu" then
    local bw, bh = r.w - pad * 2, (h0 - pad) / 2
    button("send", r.x + pad, y0, bw, bh, "Send a game", true,
      "With its saves and your mods")
    button("receive", r.x + pad, y0 + bh + pad, bw, bh, "Receive", false,
      "A game from a phone nearby")
  elseif st.view == "pick" then
    -- the recomp games, then the 3DS games, eight to a page
    local list = {}
    for _, v in ipairs(GAMES) do
      list[#list + 1] = { id = v, name = NAMES[v],
        sub = not hasRom(v) and "no ROM on this phone" or hasSaves(v) and "with its saves" or "no saves yet" }
    end
    for _, g in ipairs(Azahar.games()) do
      list[#list + 1] = { id = g.id, name = g.name, sub = g.installed and "3DS, installed" or "3DS" }
    end
    local cols, rows = 2, 4
    local pages = math.max(1, math.ceil(#list / (cols * rows)))
    st.pickPage = clamp(st.pickPage or 1, 1, pages)
    local arrowsH = pages > 1 and rowH * 0.8 or 0
    local bw = (r.w - pad * 3) / cols
    local bh = (h0 - arrowsH - pad * rows) / rows
    local first = (st.pickPage - 1) * cols * rows
    for i = 1, cols * rows do
      local e = list[first + i]
      if not e then break end
      local cx = r.x + pad + ((i - 1) % cols) * (bw + pad)
      local cy = y0 + math.floor((i - 1) / cols) * (bh + pad)
      button("game:" .. e.id, cx, cy, bw, bh, e.name, false, e.sub)
    end
    if pages > 1 then
      local ay = r.y + r.h - pad - arrowsH
      button("pageprev", r.x + pad, ay, r.w * 0.3, arrowsH, "<", false)
      button("pagenext", r.x + r.w - pad - r.w * 0.3, ay, r.w * 0.3, arrowsH, ">", false)
      lg.setFont(f)
      col(INK, 0.8)
      lg.printf(("%d / %d"):format(st.pickPage, pages), r.x, ay + (arrowsH - f:getHeight()) / 2, r.w, "center")
    end
  elseif st.view == "hosting" or st.view == "searching" or st.view == "receiving" then
    local state = s.state or ""
    lg.setFont(f)
    col(INK)
    local line
    if state == "asking" then line = "Allow Nearby devices in the prompt."
    elseif state == "error" then
      local e = s.error or ""
      if e:match("SETTING_LOCATION") or e:match("LOCATION_MUST_BE_ON") then
        line = "Turn on Location (quick settings), then try again.\nAndroid needs it to find phones nearby."
      elseif e:match("PERMISSION") then
        line = "Download Play needs Nearby devices and Location allowed.\nAndroid uses them to find the other phone."
      elseif e:match("BLUETOOTH") then
        line = "Turn on Bluetooth, then try again."
      else
        line = "Stopped: " .. (e ~= "" and e or "something went wrong")
      end
    elseif st.view == "hosting" and (state == "hosting" or state == "connecting") then line = "Waiting for another phone...\n" .. (NAMES[st.game] or "")
    elseif state == "sending" then line = "Sending to " .. (s.peer or "") .. "..."
    elseif state == "receiving" or state == "connecting" then line = "Receiving from " .. (s.peer or "") .. "..."
    elseif state == "done" and st.view == "hosting" then line = "Sent!"
    elseif st.view == "searching" then line = "Looking for phones that are sending..."
    else line = "" end
    lg.printf(line, r.x + pad, y0, r.w - pad * 2, "center")
    if st.view == "searching" and state ~= "error" then
      local list = s.peerList or {}
      local ly = y0 + f:getHeight() * 1.8
      for i, p in ipairs(list) do
        if i > 4 then break end
        button("peer:" .. i, r.x + pad, ly, r.w - pad * 2, rowH, p.who, false, NAMES[p.game] or p.game)
        ly = ly + rowH + pad * 0.5
      end
      if #list == 0 then waves(r.x + r.w / 2, y0 + h0 * 0.55, h0 * 0.3, st.t) end
    elseif state == "sending" or state == "receiving" or (state == "done") then
      local frac = s.total > 0 and s.done / s.total or 0
      bar(r.x + pad * 2, y0 + h0 * 0.4, r.w - pad * 4, rowH * 0.4, frac)
      lg.setFont(ctx.font(rowH * 0.28))
      col(INK, 0.8)
      local fast = s.speed > 300000 and "a fast link (Wi-Fi)" or s.speed > 0 and "Bluetooth" or ""
      lg.printf(("%s of %s   %s/s   %s"):format(human(s.done), human(s.total), human(s.speed), fast),
        r.x, y0 + h0 * 0.4 + rowH * 0.6, r.w, "center")
    elseif state ~= "error" then
      waves(r.x + r.w / 2, y0 + h0 * 0.55, h0 * 0.3, st.t)
    end
    if state == "error" then
      local e = s.error or ""
      button("retry", r.x + r.w * 0.2, y0 + h0 - rowH * 1.3, r.w * 0.6, rowH * 1.2,
        e:match("PERMISSION") and "Allow and try again" or "Try again", true,
        e:match("PERMISSION") and "If nothing asks, allow them in Android Settings > Apps" or nil)
    end
    if state == "done" and st.view ~= "hosting" then
      button("install", r.x + r.w * 0.2, y0 + h0 - rowH * 1.3, r.w * 0.6, rowH * 1.2,
        st.confirm and "Tap again to install" or "Install on this phone", true,
        st.confirm and "Imports the game; replaced saves go to downloadplay/backup_..."
          or (NAMES[s.game] or s.game or ""))
    end
  end
  -- the toast
  local t = st.toast
  if t and st.t - t.at < 3 then
    local tf2 = ctx.font(rowH * 0.28)
    lg.setFont(tf2)
    local w = math.min(r.w - pad * 2, tf2:getWidth(t.text) + rowH)
    lg.setColor(0, 0, 0, 0.65)
    rrect("fill", r.x + (r.w - w) / 2, r.y + r.h - pad - tf2:getHeight() * 2.2, w, tf2:getHeight() * 1.8, 8)
    lg.setColor(1, 1, 1, 1)
    lg.printf(t.text, r.x + (r.w - w) / 2, r.y + r.h - pad - tf2:getHeight() * 1.8, w, "center")
  end
  lg.pop()
end

-- the top screen's line while the app is open (drawn in its wallpaper panel)
function D.topMessage()
  if not st.open then return nil end
  local s = st.status
  if st.view == "hosting" then return "Sending " .. (NAMES[st.game] or "") end
  if st.view == "searching" then return "Looking for games..." end
  if st.view == "receiving" then
    return s.state == "done" and ("Received " .. (NAMES[s.game] or s.game or "")) or "Receiving..."
  end
  return nil
end

---------------------------------------------------------------- input

local function activate(id)
  if id == "back" then
    if st.view == "menu" then return "exit" end
    stopAll()
    st.view = "menu"
    Sfx.play("back")
  elseif id == "send" then
    romKnown = {}
    st.view = "pick"; Sfx.play("select")
  elseif id == "receive" then
    receive()
  elseif id:match("^game:") then
    send(id:sub(6))
  elseif id == "pageprev" or id == "pagenext" then
    st.pickPage = (st.pickPage or 1) + (id == "pagenext" and 1 or -1)
    Sfx.play("select")
  elseif id:match("^peer:") then
    local p = (st.status.peerList or {})[tonumber(id:sub(6))]
    if p then connect(p) end
  elseif id == "install" then
    install()
  elseif id == "retry" then
    stopAll()
    if st.view == "hosting" and st.game then send(st.game) else receive() end
  end
end

local function hitAt(x, y)
  for k = #st.hits, 1, -1 do
    local h = st.hits[k]
    if x >= h.x and y >= h.y and x <= h.x + h.w and y <= h.y + h.h then return h end
  end
end

function D.pressed(id, x, y)
  local h = hitAt(x, y)
  st.touches[id] = { hit = h and h.id }
  st.down = h and h.id or nil
end

function D.moved(id, x, y)
  local t = st.touches[id]
  if not t then return end
  local h = hitAt(x, y)
  st.down = (h and h.id == t.hit) and t.hit or nil
end

function D.released(id, x, y)
  local t = st.touches[id]
  st.touches[id] = nil
  st.down = nil
  if not t then return end
  local h = hitAt(x, y)
  if h and h.id == t.hit then return activate(h.id) end
end

function D.button(name)
  if name == "home" then return "exit" end
  if name == "b" then return activate("back") end
  if name == "a" and st.view == "menu" then activate("send") end
  if name == "x" and st.view == "menu" then activate("what") end
  if name == "a" and st.status.state == "done" and st.view ~= "hosting" then activate("install") end
end

---------------------------------------------------------------- life

function D.init(context) ctx = context end
function D.isOpen() return st.open end

function D.open()
  st.open = true
  st.view = "menu"
  st.status = {}
  Sfx.play("open")
end

function D.close()
  if not st.open then return end
  stopAll()
  st.open = false
  Sfx.play("back")
end

function D.update(dt)
  st.t = st.t + (dt or 0)
  if not st.open then return end
  -- a game arrived with its ROM: back to the menu, where its import runs
  if st.imported then st.imported = nil; D.close() return end
  if st.fake then
    -- the desktop stand-in: a peer appears, the bytes flow
    local age = st.t - st.fake.t0
    local s = { peer = "G1R-4242", game = st.game or "red", total = 3145728, done = 0, speed = 0, peerList = {} }
    if st.fake.role == "host" then
      s.state = age < 2 and "hosting" or age < 5 and "sending" or "done"
      s.done = clamp((age - 2) / 3, 0, 1) * s.total
    elseif not st.fake.connectAt then
      s.state = "searching"
      if age > 1 then s.peerList = { { id = "x1", who = "G1R-4242", game = "blue" } } end
    else
      local c = st.t - st.fake.connectAt
      s.state = c < 3 and "receiving" or "done"
      s.game = "blue"
      s.done = clamp(c / 3, 0, 1) * s.total
    end
    s.speed = s.state ~= "done" and s.done > 0 and 1100000 or 0
    st.status = s
    return
  end
  if st.view ~= "menu" and st.view ~= "pick" and st.t >= st.pollAt then
    st.pollAt = st.t + 0.25
    local was = st.status.state
    st.status = parseStatus(bridge("dp.status"))
    local now = st.status.state
    if now ~= was then
      if now == "done" then Sfx.play(st.view == "hosting" and "start" or "coin")
      elseif now == "error" then Sfx.play("cancel")
      elseif now == "sending" or now == "receiving" then Sfx.play("select") end
    end
  end
end

return D
