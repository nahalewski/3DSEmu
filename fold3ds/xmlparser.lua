-- Pure Lua lightweight XML parser for Love2D and gen1recomp skins
local XML = {}

local function parseArgs(s)
  local arg = {}
  string.gsub(s, '([%-%w:_]+)%s*=%s*([\"\'])(.-)%2', function(w, _, a)
    arg[w] = a
  end)
  return arg
end

function XML.parse(xmlText)
  local stack = {}
  local top = { tag = "root", attr = {}, children = {} }
  table.insert(stack, top)

  local i = 1
  while true do
    local ni, j, c, label, empty = string.find(xmlText, "<(%/?)([%w:_]+)(.-)(%/?)>", i)
    if not ni then break end

    local text = string.sub(xmlText, i, ni - 1)
    if not string.find(text, "^%s*$") then
      -- Trim whitespace
      local trimmed = string.match(text, "^%s*(.-)%s*$")
      if trimmed and #trimmed > 0 then
        table.insert(top.children, { tag = "_text", value = trimmed })
        top.text = (top.text or "") .. trimmed
      end
    end

    if empty == "/" then
      -- Self-closing tag
      local node = { tag = label, attr = parseArgs(c), children = {} }
      table.insert(top.children, node)
      top[label] = top[label] or node
    elseif c == "" and string.sub(label, 1, 1) == "?" then
      -- XML declaration: skip
    elseif string.sub(label, 1, 3) == "!--" then
      -- Comment: find end of comment
      local ci, cj = string.find(xmlText, "%-%->", ni)
      if cj then j = cj end
    elseif c ~= "" and string.sub(label, 1, 1) == "?" then
      -- XML declaration: skip
    elseif c ~= "" and string.sub(label, 1, 3) == "!--" then
      -- Comment
      local ci, cj = string.find(xmlText, "%-%->", ni)
      if cj then j = cj end
    elseif c ~= "" and string.sub(label, 1, 1) == "!" then
      -- DOCTYPE or CDATA
    elseif c ~= "" and string.sub(c, -1) == "/" then
      -- Self closing with attributes
      local node = { tag = label, attr = parseArgs(string.sub(c, 1, -2)), children = {} }
      table.insert(top.children, node)
      top[label] = top[label] or node
    elseif c == "" and string.sub(label, 1, 1) == "/" then
      -- End tag
      local closed = table.remove(stack)
      top = stack[#stack]
      if not top then break end
    elseif c ~= "" and string.sub(c, 1, 1) == "/" then
      -- End tag with space
      local closed = table.remove(stack)
      top = stack[#stack]
      if not top then break end
    else
      -- Open tag
      local node = { tag = label, attr = parseArgs(c), children = {} }
      table.insert(top.children, node)
      top[label] = top[label] or node
      table.insert(stack, node)
      top = node
    end
    i = j + 1
  end

  return stack[1] and stack[1].children[1] or nil
end

return XML
