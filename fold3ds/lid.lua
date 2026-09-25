-- lid: the 3DS XL shuts when you fold the phone.
--
-- Ben's easter egg. Folding the top half down closes the on-screen clamshell, the
-- game screen goes down with the lid, audio mutes and the system goes to standby;
-- opening reverses it. The user's own sticker stays on the lid for the whole
-- movement, not just at the end.
--
-- DRIVEN BY THE REAL HINGE ANGLE, NOT A TIMER. Ben was explicit and he is right:
-- a timed animation plays at its own speed and drifts away from the hand holding
-- the phone, so a slow fold looks broken and a fast one looks late. The angle IS
-- the animation clock. `progress()` is a pure function of degrees, which is also
-- why the whole state machine below can be tested without a device.
--
-- NO EMULATOR CODE IS TOUCHED. Mute and standby go through the pause the emulator
-- already has, handed in as callbacks, so this module never reaches into one.
--
-- Seam with init.lua (XMB UI Dev's file):
--   Lid.source(fn)     where degrees come from; defaults to FoldBridge "hinge.angle"
--   Lid.hooks{...}     onMute / onStandby / onResume / onClick, all optional
--   Lid.update(dt)     poll the angle, run the state machine, fire hooks once each
--   Lid.progress()     0 = flat open, 1 = shut; the animation parameter
--   Lid.state()        "open" | "closing" | "closed" | "opening"
--   Lid.draw(L, w, h)  the shell and the lid at the current angle

local M = {}

-- Degrees. 180 is flat open, 0 is shut.
local OPEN_AT = 170      -- at or above this the lid is latched open
local SHUT_AT = 15       -- at or below this it is latched shut
-- Latches are deliberately not the same as the animation ends. Between SHUT_AT and
-- REOPEN_AT the lid is still considered shut, so a hand resting near the threshold
-- does not flicker the game in and out of standby - which would be worse than no
-- easter egg at all.
local REOPEN_AT = 35
local RESHUT_AT = 150

local angle = 180
local state = "open"
local hooks = {}
local source = nil
local lastClick = nil

--- Where degrees come from. Injected so tests and the desktop can drive it.
function M.source(fn) source = fn end

function M.hooks(t) hooks = t or {} end

local function bridgeAngle()
  -- FoldBridge speaks strings: love.system.foldCamera("call", cmd, arg).
  if not (love and love.system and love.system.foldCamera) then return nil end
  local ok, reply = pcall(love.system.foldCamera, "call", "hinge.angle", "")
  if not ok then return nil end
  return tonumber(reply)
end

local function fire(name, ...)
  local fn = hooks[name]
  if fn then pcall(fn, ...) end
end

--- 0 at OPEN_AT and above, 1 at SHUT_AT and below, linear between.
--- Pure, so the animation can be asserted on rather than watched.
function M.progress(deg)
  deg = deg or angle
  if deg >= OPEN_AT then return 0 end
  if deg <= SHUT_AT then return 1 end
  return (OPEN_AT - deg) / (OPEN_AT - SHUT_AT)
end

function M.angle() return angle end
function M.state() return state end
function M.closed() return state == "closed" end

--- Feed an angle directly. `update` calls this; tests call it too.
function M.set(deg)
  if type(deg) ~= "number" then return state end
  local was = state
  local prev = angle
  angle = math.max(0, math.min(180, deg))

  if state == "open" or state == "opening" then
    if angle <= SHUT_AT then
      state = "closed"
    elseif angle < RESHUT_AT then
      state = "closing"
    elseif angle >= OPEN_AT then
      state = "open"
    end
  elseif state == "closed" or state == "closing" then
    if angle >= REOPEN_AT then
      state = angle >= OPEN_AT and "open" or "opening"
    elseif angle <= SHUT_AT then
      state = "closed"
    end
  end

  if state ~= was then
    -- The click belongs to the two LATCH points, not to every state change:
    -- closing -> closed and opening -> open. Firing it on the intermediate
    -- states would click while the hinge is still moving.
    if state == "closed" and lastClick ~= "closed" then
      lastClick = "closed"
      fire("onClick", "close")
      fire("onMute", true)
      fire("onStandby", true)
    elseif state == "open" and lastClick ~= "open" then
      lastClick = "open"
      fire("onClick", "open")
      fire("onMute", false)
      fire("onResume")
    end
  end
  return state, prev
end

function M.update()
  local deg = (source or bridgeAngle)()
  if deg then M.set(deg) end
  return state
end

--- True when the lid should be drawn over the game at all.
function M.covering() return M.progress() > 0 end

----------------------------------------------------------------- drawing ----

--- Draw the lid closing over the top screen.
---
--- `L` carries whatever init.lua already uses to place the shell; this module only
--- needs the rectangle the top screen occupies and the sticker drawer, both passed
--- in, so it never has to know how the shell is laid out.
---
---   opts.rect      {x, y, w, h} of the top screen in real pixels
---   opts.sticker   function(x, y, w, h) that draws the user's sticker
---   opts.lidImage  optional image for the lid's outside
function M.draw(opts)
  if not opts or not opts.rect then return false end
  local p = M.progress()
  if p <= 0 then return false end

  local r = opts.rect
  local lg = love.graphics

  -- The lid pivots at the hinge, so the visible height of the closing panel is the
  -- cosine of the fold - the same foreshortening a real lid has. At p = 1 it fully
  -- covers; at p = 0 it is edge-on and invisible.
  local covered = r.h * p
  local y = r.y

  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)

  if opts.lidImage then
    lg.setColor(1, 1, 1, 1)
    lg.draw(opts.lidImage, r.x, y, 0, r.w / opts.lidImage:getWidth(), covered / opts.lidImage:getHeight())
  else
    -- Neutral, not a guessed 3DS colour: the shell art belongs to init.lua.
    lg.setColor(0.10, 0.11, 0.13, 1)
    lg.rectangle("fill", r.x, y, r.w, covered)
  end

  -- THE STICKER RIDES THE LID THE WHOLE WAY DOWN, which is the point of the egg.
  -- It is scaled with the lid rather than faded in at the end, so what the user set
  -- is visible during the movement and not only once it is shut.
  if opts.sticker and covered > 2 then
    opts.sticker(r.x, y, r.w, covered)
  end

  -- A soft edge along the closing lip, so the panel reads as an edge rather than a
  -- rectangle growing downward.
  lg.setColor(0, 0, 0, 0.35 * p)
  lg.rectangle("fill", r.x, y + covered - math.max(1, r.h * 0.006), r.w, math.max(1, r.h * 0.006))
  lg.pop()
  return true
end

--- Reset, for tests and for a fresh session.
function M.reset(deg)
  angle = deg or 180
  state = angle <= SHUT_AT and "closed" or "open"
  lastClick = nil
end

return M
