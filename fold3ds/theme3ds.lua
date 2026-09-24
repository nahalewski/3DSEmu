-- The "3DS" launcher theme: the bottom screen dressed like the 3DS HOME
-- menu -- light grey rounded tiles on a softly striped pale field, white
-- panels, dark grey type, and the HOME menu's blue for whatever is
-- selected (white text on it).
--
-- It re-colours the launcher kit's one shared palette IN PLACE (every card
-- variant and button kind holds references to those same colour tables),
-- remembering the originals so switching back restores them exactly.
local T = {}

local COLORS = {
  field      = { 226, 228, 232 },
  bg         = { 236, 237, 240 },
  surface    = { 250, 250, 251 },
  rowBg      = { 242, 243, 245 },
  raised     = { 226, 236, 248 },
  ink        = { 30, 136, 240 },   -- HOME menu blue: selection and focus
  line       = { 150, 156, 166 },
  lineStrong = { 30, 136, 240 },
  heading    = { 58, 60, 66 },
  text       = { 66, 68, 74 },
  detail     = { 92, 95, 102 },
  muted      = { 120, 124, 132 },
  caption    = { 118, 122, 130 },
  faint      = { 160, 164, 170 },
  inverse    = { 255, 255, 255 },  -- type on a blue / coloured fill
  green      = { 46, 170, 84 },
  yellow     = { 236, 166, 0 },
  red        = { 226, 56, 60 },
  blue       = { 24, 124, 226 },
  buttonBlue = { 30, 136, 240 },
  steel      = { 170, 170, 176 },
}
local RADIUS = { button = 14, card = 14 }

local saved = nil
local fieldOrig = nil
T.active = false

local function kit()
  local okT, Theme = pcall(require, "src.ui.kit.Theme")
  local okK, Kit = pcall(require, "src.ui.kit.Kit")
  return okT and Theme or nil, okK and Kit or nil
end

-- the HOME menu's pale field with its faint vertical stripes
local function stripedField()
  local g = love.graphics
  local f = COLORS.field
  g.clear(f[1] / 255, f[2] / 255, f[3] / 255, 1)
  local w, h = g.getDimensions()
  local step = math.max(6, math.floor(w / 60))
  g.push("all")
  g.setColor(1, 1, 1, 0.35)
  for x = 0, w, step * 2 do g.rectangle("fill", x, 0, step, h) end
  g.pop()
end

function T.set(on)
  on = on and true or false
  if on == T.active then return end
  local Theme, Kit = kit()
  if not Theme then return end
  local PAL = Theme.PAL
  if on then
    saved = { pal = {}, radius = { button = Theme.BUTTON.radius, card = Theme.CARD.radius } }
    for k, c in pairs(COLORS) do
      local p = PAL[k]
      if p then
        saved.pal[k] = { p[1], p[2], p[3] }
        p[1], p[2], p[3] = c[1], c[2], c[3]
      end
    end
    Theme.BUTTON.radius, Theme.CARD.radius = RADIUS.button, RADIUS.card
    -- blue buttons carry white type, not the (now dark) heading colour
    if Kit and Kit.KINDS and Kit.KINDS.accent then
      saved.accentInk = Kit.KINDS.accent.ink
      Kit.KINDS.accent.ink = PAL.inverse
    end
    fieldOrig = Theme.field
    Theme.field = stripedField
  else
    for k, c in pairs(saved and saved.pal or {}) do
      local p = PAL[k]
      p[1], p[2], p[3] = c[1], c[2], c[3]
    end
    if saved then
      Theme.BUTTON.radius, Theme.CARD.radius = saved.radius.button, saved.radius.card
      if Kit and Kit.KINDS and Kit.KINDS.accent and saved.accentInk then
        Kit.KINDS.accent.ink = saved.accentInk
      end
    end
    if fieldOrig then Theme.field = fieldOrig end
    saved, fieldOrig = nil, nil
  end
  T.active = on
  -- cached text measures and glyph colours belong to the old look
  if Kit and Kit.clearCaches then pcall(Kit.clearCaches) end
end

-- colours the fold layer's own chrome (the scroll arrows) borrows
T.arrowFill = { 0.93, 0.93, 0.95 }
T.arrowInk = { 30 / 255, 136 / 255, 240 / 255 }

return T
