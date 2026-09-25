-- The Camera applet's filters, after the 3DS camera's effects and lenses:
-- each is a shader run over the upright picture, so the viewfinder, the
-- pictures and the videos all get it.
local F = {}

local lg = love.graphics

local LUMA = "float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }\n"

F.LIST = {
  { id = "none", name = "Normal" },
  { id = "sepia", name = "Sepia", code = LUMA .. [[
vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
  float l = luma(Texel(t, uv).rgb);
  return vec4(clamp(vec3(l * 1.07 + 0.06, l * 0.88 + 0.03, l * 0.64), 0.0, 1.0), 1.0) * c;
}]] },
  { id = "mono", name = "Black & White", code = LUMA .. [[
vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
  float l = clamp((luma(Texel(t, uv).rgb) - 0.5) * 1.2 + 0.5, 0.0, 1.0);
  return vec4(l, l, l, 1.0) * c;
}]] },
  { id = "negative", name = "Negative", code = [[
vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
  return vec4(1.0 - Texel(t, uv).rgb, 1.0) * c;
}]] },
  { id = "posterize", name = "Posterize", code = LUMA .. [[
vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
  vec3 p = Texel(t, uv).rgb;
  p = mix(vec3(luma(p)), p, 1.5);
  return vec4(floor(clamp(p, 0.0, 1.0) * 3.99) / 3.0, 1.0) * c;
}]] },
  { id = "pinhole", name = "Pinhole", code = LUMA .. [[
extern vec2 size;
vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
  vec3 p = Texel(t, uv).rgb;
  p = mix(vec3(luma(p)), p, 1.35);
  p = (p - 0.5) * 1.2 + 0.5;
  vec2 d = (uv - 0.5) * vec2(size.x / size.y, 1.0);
  float v = smoothstep(0.78, 0.22, length(d));
  return vec4(clamp(p, 0.0, 1.0) * v, 1.0) * c;
}]] },
  { id = "fisheye", name = "Fisheye", code = [[
extern vec2 size;
vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
  float a = size.x / size.y;
  vec2 d = (uv - 0.5) * vec2(a, 1.0);
  float r = length(d);
  if (r > 0.5) return vec4(0.0, 0.0, 0.0, 1.0) * c;
  float f = mix(0.55, 1.0, (r / 0.5) * (r / 0.5));
  vec2 q = 0.5 + d * f / vec2(a, 1.0);
  float edge = smoothstep(0.5, 0.47, r);
  return vec4(Texel(t, q).rgb * edge, 1.0) * c;
}]] },
  { id = "mosaic", name = "Mosaic", code = [[
extern vec2 size;
vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
  float cell = size.y / 26.0;
  vec2 px = (floor(uv * size / cell) + 0.5) * cell;
  return vec4(Texel(t, px / size).rgb, 1.0) * c;
}]] },
  { id = "mirror", name = "Mirror", code = [[
vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
  if (uv.x > 0.5) uv.x = 1.0 - uv.x;
  return vec4(Texel(t, uv).rgb, 1.0) * c;
}]] },
  { id = "sparkle", name = "Sparkle", code = LUMA .. [[
extern vec2 size;
extern number time;
vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
  vec3 p = Texel(t, uv).rgb;
  float cell = max(12.0, size.y / 16.0);
  vec2 px = uv * size;
  vec2 id = floor(px / cell);
  vec2 q = fract(px / cell) - 0.5;
  float h = fract(sin(dot(id, vec2(12.9898, 78.233))) * 43758.5453);
  float bright = luma(Texel(t, (id + 0.5) * cell / size).rgb);
  float star = 0.0;
  if (h > 0.5 && bright > 0.68) {
    float tw = 0.5 + 0.5 * sin(time * 4.0 + h * 40.0);
    float a = max(0.0, 1.0 - abs(q.x) * 12.0) * max(0.0, 1.0 - abs(q.y) * 2.2);
    float b = max(0.0, 1.0 - abs(q.y) * 12.0) * max(0.0, 1.0 - abs(q.x) * 2.2);
    star = tw * (a + b) + tw * max(0.0, 1.0 - length(q) * 6.0);
  }
  return vec4(clamp(p + vec3(star), 0.0, 1.0), 1.0) * c;
}]] },
  { id = "sketch", name = "Sketch", code = LUMA .. [[
extern vec2 size;
vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
  vec2 o = 1.0 / size;
  float tl = luma(Texel(t, uv + vec2(-o.x, -o.y)).rgb);
  float tm = luma(Texel(t, uv + vec2(0.0, -o.y)).rgb);
  float tr = luma(Texel(t, uv + vec2(o.x, -o.y)).rgb);
  float ml = luma(Texel(t, uv + vec2(-o.x, 0.0)).rgb);
  float mr = luma(Texel(t, uv + vec2(o.x, 0.0)).rgb);
  float bl = luma(Texel(t, uv + vec2(-o.x, o.y)).rgb);
  float bm = luma(Texel(t, uv + vec2(0.0, o.y)).rgb);
  float br = luma(Texel(t, uv + vec2(o.x, o.y)).rgb);
  float gx = tr + 2.0 * mr + br - tl - 2.0 * ml - bl;
  float gy = bl + 2.0 * bm + br - tl - 2.0 * tm - tr;
  float e = smoothstep(0.1, 0.45, length(vec2(gx, gy)));
  float shade = 0.82 + 0.18 * luma(Texel(t, uv).rgb);
  vec3 paper = vec3(0.97, 0.96, 0.92) * shade;
  return vec4(mix(paper, vec3(0.18, 0.18, 0.22), e), 1.0) * c;
}]] },
}

local byId, shaders = {}, {}
for i, f in ipairs(F.LIST) do f.index = i; byId[f.id] = f end

function F.get(id) return byId[id] or F.LIST[1] end

-- the filter's shader, ready for a w x h picture at time t (nil: none)
function F.shader(id, w, h, t)
  local f = byId[id]
  if not f or not f.code then return nil end
  if shaders[id] == nil then
    local ok, s = pcall(lg.newShader, f.code)
    if not ok then print("fold3ds camera filter " .. id .. ": " .. tostring(s)) end
    shaders[id] = ok and s or false
  end
  local s = shaders[id]
  if not s then return nil end
  if s:hasUniform("size") then s:send("size", { w, h }) end
  if s:hasUniform("time") then s:send("time", t or 0) end
  return s
end

-- the next (or previous) filter's id
function F.step(id, dir)
  local i = F.get(id).index + (dir or 1)
  if i > #F.LIST then i = 1 elseif i < 1 then i = #F.LIST end
  return F.LIST[i].id
end

return F
