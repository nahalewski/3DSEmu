-- Every emulator on the 3DS HOME menu, one way: the menu asks this list for
-- their tiles and hands each tap back to the emulator that owns the tile.
-- The look stays the HOME menu's own; an emulator only supplies its games,
-- its folder of settings and tools, and how to open them.
--
-- An emulator is a module (fold3ds.<name>) whose `provider` table has:
--
--   id           "azahar"; also the id of its folder tile on the grid
--   system       what its games are, "Nintendo 3DS" (a game's default subtitle)
--   folder       { name = "Azahar", sub = "...", items = { {id,name,sub,url}, ... } }
--                -- the folder of its settings and tools (icons: fold3ds/icons3ds/<id>.png)
--   setupTile    { id, name, sub, url }  shown while status() is "setup"
--   addTile      { id, name, sub, url }  shown while status() is "ready"
--   status()     nil (no word yet) | "setup" | "ready"
--   games()      its game tiles: { id (unique, [%w_]), name, sub, ... }
--   icon(t)      the game's icon Image, or nil
--   iconPath(t)  that icon's file in the save folder, or nil (optional)
--   cart(t)      a photo of the game's cartridge / card, or nil
--   open(url)    open one of its own links (a folder icon, setup, add)
--   play(t)      start game t
--   manual(t)    the game's options (the Manual button), optional
--   init(), poll(time)   optional
--   transferEntries(t)   Download Play: the game's files, optional
--
-- Emulators show on the grid in the order of MODULES; a module that is not
-- there (not built in) is skipped.
local E = {}

local MODULES = { "fold3ds.azahar", "fold3ds.melonds", "fold3ds.vc", "fold3ds.eden" }

local list, byId = nil, {}

local function providers()
  if list then return list end
  list = {}
  for _, name in ipairs(MODULES) do
    local ok, m = pcall(require, name)
    local p = ok and type(m) == "table" and m.provider or nil
    if p and p.id then
      list[#list + 1] = p
      byId[p.id] = p
    end
  end
  return list
end

function E.providers() return providers() end

-- the emulator a tile belongs to
function E.owner(t)
  providers()
  return t and t.emu and byId[t.emu] or nil
end

function E.init()
  for _, p in ipairs(providers()) do if p.init then pcall(p.init) end end
end

function E.poll(time)
  for _, p in ipairs(providers()) do if p.poll then pcall(p.poll, time) end end
end

local function stamp(t, p, extra)
  t.emu = p.id
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

-- every emulator's tiles for the grid, in order: its folder, its set-up tile
-- (until it is set up), its games, its add-games tile.  add(id, tile)
function E.addTiles(add)
  for _, p in ipairs(providers()) do
    if p.folder then
      local items = {}
      for i, it in ipairs(p.folder.items or {}) do items[i] = stamp(it, p) end
      add(p.id, stamp({ id = p.id, folder = true, name = p.folder.name, sub = p.folder.sub,
        items = items }, p))
    end
    local status = p.status and p.status()
    if status == "setup" and p.setupTile then add(p.setupTile.id, stamp(p.setupTile, p)) end
    for _, g in ipairs(p.games and p.games() or {}) do
      add(g.id, stamp(g, p, { emuGame = true, sub = g.sub or p.system }))
    end
    if status == "ready" and p.addTile then add(p.addTile.id, stamp(p.addTile, p)) end
  end
end

-- every emulator's games (Download Play's list)
function E.games()
  local out = {}
  for _, p in ipairs(providers()) do
    for _, g in ipairs(p.games and p.games() or {}) do
      out[#out + 1] = stamp(g, p, { emuGame = true, sub = g.sub or p.system })
    end
  end
  return out
end

function E.icon(t)
  local p = E.owner(t)
  return p and p.icon and p.icon(t) or nil
end

-- the icon's file, for reading its colours (the top screen's banner)
function E.iconPath(t)
  local p = E.owner(t)
  return p and p.iconPath and p.iconPath(t) or nil
end

function E.cart(t)
  local p = E.owner(t)
  return p and p.cart and p.cart(t) or nil
end

function E.open(t)
  local p = E.owner(t)
  if p and p.open and t.url then return p.open(t.url) end
end

function E.play(t)
  local p = E.owner(t)
  if p and p.play then return p.play(t) end
end

function E.manual(t)
  local p = E.owner(t)
  if p and p.manual then return p.manual(t) end
end

function E.hasManual(t)
  local p = E.owner(t)
  return p ~= nil and p.manual ~= nil
end

function E.system(t)
  local p = E.owner(t)
  return p and p.system or nil
end

-- a name's first character, whole (UTF-8), for the stand-in icons
function E.initial(name)
  name = name or ""
  local ok, utf8 = pcall(require, "utf8")
  local stop = ok and utf8.offset(name, 2) or 2
  local c = name:sub(1, (stop or #name + 1) - 1)
  return c ~= "" and c or "?"
end

return E
