-- Controllers, for every screen the shell draws (the 3DS HOME menu, the
-- Switch HOME menu, the apps, the emulators playing in the shell) and for
-- the recomp games: a controller works as soon as it connects.
--
-- Each controller is recognised by its USB / Bluetooth ids and its name:
--
--   * Nintendo Switch Pro Controller, a Joy-Con pair (or the grip), a
--     single Joy-Con held sideways, and other Nintendo-layout pads;
--   * the Razer Kishi (all versions) and other Xbox-layout pads.
--
-- The buttons follow their labels: on a Nintendo pad A is the right face
-- button, on an Xbox-layout pad (the Kishi) the bottom one, and either way
-- the button marked A is A.  SDL names the face buttons by position (south
-- "a", east "b", ...), so a Nintendo pad gets them swapped here.  If a pad's
-- labels come out wrong, System Settings > Controllers (Switch HOME menu)
-- sets the layout by hand: Automatic, Nintendo or Xbox.
--
-- A single Joy-Con is recognised and named, and SDL (which already turns a
-- single Joy-Con for sideways play) gives its buttons.  The left stick
-- moves like the + Pad, the right stick is the C-Stick, the
-- triggers are ZL / ZR.
local P = {}

local CFG = "fold3ds_pads.cfg"
local ON, OFF = 0.5, 0.3           -- stick push / let go, for the + Pad
local NINTENDO = 0x057e
local RAZER = 0x1532

local st = { layout = "auto", loaded = false, pads = {}, held = {} }

local function load()
  st.loaded = true
  local ok, text = pcall(love.filesystem.read, CFG)
  local l = ok and type(text) == "string" and text:match("layout=(%a+)")
  if l == "nintendo" or l == "xbox" or l == "auto" then st.layout = l end
end

function P.layoutSetting() if not st.loaded then load() end return st.layout end
function P.setLayout(l)
  st.layout = l
  pcall(love.filesystem.write, CFG, "layout=" .. l .. "\n")
end

---------------------------------------------------------------- recognising

-- what a controller is: { kind, name, layout = "nintendo" | "xbox" }
local function identify(j)
  local name = (j.getName and j:getName() or "") or ""
  local low = name:lower()
  local vendor, product = 0, 0
  if j.getDeviceInfo then
    local ok, v, p = pcall(j.getDeviceInfo, j)
    if ok then vendor, product = v or 0, p or 0 end
  end
  local nintendo = vendor == NINTENDO or low:find("nintendo") or low:find("pro controller")
    or low:find("joy%-con") or low:find("joycon")
  if nintendo then
    if product == 0x2006 or (low:find("joy%-con") and low:find("%(l%)")) then
      return { kind = "joycon_l", name = "Joy-Con (L)", layout = "nintendo" }
    elseif product == 0x2007 or (low:find("joy%-con") and low:find("%(r%)")) then
      return { kind = "joycon_r", name = "Joy-Con (R)", layout = "nintendo" }
    elseif product == 0x200e or low:find("joy%-con") then
      return { kind = "joycon_pair", name = "Joy-Con", layout = "nintendo" }
    end
    return { kind = "switch_pro", name = "Pro Controller", layout = "nintendo" }
  end
  if low:find("kishi") or (vendor == RAZER and (low:find("kishi") or low == "")) then
    return { kind = "kishi", name = "Razer Kishi", layout = "xbox" }
  end
  return { kind = "gamepad", name = name ~= "" and name or "Controller", layout = "xbox" }
end

local function info(j)
  local id = j.getID and j:getID() or tostring(j)
  local p = st.pads[id]
  if not p then
    p = identify(j)
    st.pads[id] = p
  end
  return p
end

local function layoutOf(p)
  if not st.loaded then load() end
  if st.layout ~= "auto" then return st.layout end
  return p.layout
end

---------------------------------------------------------------- buttons

local SWAP = { a = "b", b = "a", x = "y", y = "x" }

-- the SDL button a press means, by its label (what the recomp games get)
function P.sdl(j, b)
  local p = info(j)
  if layoutOf(p) == "nintendo" then b = SWAP[b] or b end
  return b
end

-- the shell's button for an SDL button (nil: none)
local SHELL = { a = "a", b = "b", x = "x", y = "y", start = "start", back = "select", guide = "home",
  dpup = "up", dpdown = "down", dpleft = "left", dpright = "right",
  leftshoulder = "l", rightshoulder = "r", rightstick = "cstick", misc1 = "home" }
function P.shell(j, b) return SHELL[P.sdl(j, b)] end

---------------------------------------------------------------- sticks

-- the left stick as the + Pad, the right stick as the C-Stick, the
-- triggers as ZL / ZR.  Returns a list of { "press" | "release", button }.
function P.axis(j, axis, v)
  local id = j.getID and j:getID() or tostring(j)
  local held = st.held[id] or {}
  st.held[id] = held
  local out = {}
  local function set(btn, on)
    if on and not held[btn] then held[btn] = true; out[#out + 1] = { "press", btn }
    elseif not on and held[btn] then held[btn] = nil; out[#out + 1] = { "release", btn } end
  end
  local function edge(btn, value)
    set(btn, value > (held[btn] and OFF or ON))
  end
  if axis == "leftx" then edge("right", v); edge("left", -v)
  elseif axis == "lefty" then edge("down", v); edge("up", -v)
  elseif axis == "rightx" or axis == "righty" then edge("cstick", math.abs(v))
  elseif axis == "triggerleft" then edge("zl", v)
  elseif axis == "triggerright" then edge("zr", v) end
  return out
end

---------------------------------------------------------------- connecting

-- a controller connected: its name, for a toast
function P.added(j)
  local id = j.getID and j:getID() or tostring(j)
  st.pads[id] = nil
  st.held[id] = nil
  return info(j).name
end

function P.removed(j)
  local id = j.getID and j:getID() or tostring(j)
  local held = st.held[id] or {}
  st.pads[id], st.held[id] = nil, nil
  local out = {}
  for btn in pairs(held) do out[#out + 1] = { "release", btn } end
  return out
end

-- the connected controllers, for System Settings: { name, layout }
function P.list()
  local out = {}
  local ok, js = pcall(love.joystick.getJoysticks)
  for _, j in ipairs(ok and js or {}) do
    if j:isGamepad() or info(j).kind ~= "gamepad" then
      local p = info(j)
      out[#out + 1] = { name = p.name, layout = layoutOf(p) }
    end
  end
  return out
end

P.identify = identify   -- for the tests

return P
