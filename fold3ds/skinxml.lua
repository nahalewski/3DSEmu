-- skinxml: a small XML reader for skin.xml, plus the accessors the skin model needs.
--
-- Pure Lua. It touches no love API, which is deliberate: it can be run and tested
-- outside the app, and a skin that fails to parse says so on a desktop instead of
-- on a handset.
--
-- WHAT IT DELIBERATELY DOES NOT DO. It is not a general XML parser and should not
-- grow into one. No namespaces, no DTDs, no entities beyond the five standard ones,
-- no CDATA. skin.xml is a layout file written by hand and by Ben's sprite tool; the
-- job is to read that file faithfully and to fail loudly on anything else, not to
-- accept arbitrary XML.
--
-- A node is { tag, attr = {name = value}, kids = {node...}, text = "..." }.

local M = {}

local ENTITIES = { lt = "<", gt = ">", amp = "&", quot = '"', apos = "'" }

local function unescape(s)
  return (s:gsub("&(#?%w+);", function(e)
    if ENTITIES[e] then return ENTITIES[e] end
    local dec = e:match("^#(%d+)$")
    if dec then return string.char(tonumber(dec) % 256) end
    local hex = e:match("^#x(%x+)$")
    if hex then return string.char(tonumber(hex, 16) % 256) end
    return "&" .. e .. ";"     -- unknown entity: leave it rather than guess
  end))
end

local function attrs(s)
  local t = {}
  for name, _, value in s:gmatch("([%w_:%-]+)%s*=%s*([\"'])(.-)%2") do
    t[name] = unescape(value)
  end
  return t
end

--- Parse XML text into a node tree. Returns nil, message on malformed input.
function M.parse(text)
  if type(text) ~= "string" or text == "" then return nil, "empty document" end

  -- Strip the declaration and comments first. Comments can hold anything, including
  -- angle brackets, so removing them up front keeps the main scan simple.
  text = text:gsub("<%?.-%?>", "")
  text = text:gsub("<!%-%-[%s%S]-%-%->", "")

  local root, stack, pos = nil, {}, 1
  while true do
    local s, e, closing, tag, rest, selfclose = text:find("<(/?)([%w_:%-]+)(.-)(/?)>", pos)
    if not s then break end

    -- Text between the previous tag and this one belongs to the open element.
    local between = text:sub(pos, s - 1):match("^%s*(.-)%s*$")
    local top = stack[#stack]
    if top and between ~= "" then top.text = (top.text or "") .. unescape(between) end

    if closing == "/" then
      if not top then return nil, "closing </" .. tag .. "> with nothing open" end
      if top.tag ~= tag then
        return nil, "</" .. tag .. "> closes <" .. top.tag .. ">"
      end
      table.remove(stack)
    else
      local node = { tag = tag, attr = attrs(rest), kids = {} }
      if top then
        table.insert(top.kids, node)
      elseif root then
        return nil, "second root element <" .. tag .. ">"
      else
        root = node
      end
      if selfclose ~= "/" then table.insert(stack, node) end
    end
    pos = e + 1
  end

  if #stack > 0 then return nil, "<" .. stack[#stack].tag .. "> is never closed" end
  if not root then return nil, "no elements found" end
  return root
end

--- First direct child with this tag, or nil.
function M.child(node, tag)
  if not node then return nil end
  for _, k in ipairs(node.kids) do
    if k.tag == tag then return k end
  end
  return nil
end

--- Every direct child with this tag, in document order.
function M.children(node, tag)
  local out = {}
  if not node then return out end
  for _, k in ipairs(node.kids) do
    if k.tag == tag then table.insert(out, k) end
  end
  return out
end

--- Follow a path of tags: find(root, "Theme", "Colors") -> the Colors node or nil.
function M.find(node, ...)
  for _, tag in ipairs({ ... }) do
    node = M.child(node, tag)
    if not node then return nil end
  end
  return node
end

--- An attribute, or `default` when the node or attribute is absent.
function M.attr(node, name, default)
  if not node or node.attr[name] == nil then return default end
  return node.attr[name]
end

function M.num(node, name, default)
  return tonumber(M.attr(node, name)) or default
end

--- XML says "true"/"false"; anything else, including absence, takes the default.
function M.bool(node, name, default)
  local v = M.attr(node, name)
  if v == nil then return default end
  return v == "true" or v == "1"
end

--- Trimmed text of a child element: text(theme, "Variant") -> "light".
function M.text(node, tag)
  local k = tag and M.child(node, tag) or node
  if not k or not k.text then return nil end
  return (k.text:match("^%s*(.-)%s*$"))
end

--- "#RRGGBB" or "#RRGGBBAA" -> r, g, b, a in 0..1. Returns nil on anything else,
--- so a typo in a colour shows up as a missing colour rather than as black.
function M.color(s, alpha)
  if type(s) ~= "string" then return nil end
  local hex = s:match("^#(%x+)$")
  if not hex or (#hex ~= 6 and #hex ~= 8) then return nil end
  local r = tonumber(hex:sub(1, 2), 16) / 255
  local g = tonumber(hex:sub(3, 4), 16) / 255
  local b = tonumber(hex:sub(5, 6), 16) / 255
  local a = #hex == 8 and tonumber(hex:sub(7, 8), 16) / 255 or (alpha or 1)
  return r, g, b, a
end

return M
