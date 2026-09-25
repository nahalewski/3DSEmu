-- The Camera applet (3DS theme, the camera icon on the HOME menu's applet
-- bar), as the 3DS's own camera: the live picture fills the top screen and
-- the bottom screen holds the controls.
--
--   Camera   Shoot (the big button, A, L or R), Photos, Settings, zoom + / -
--            (or up / down), the rear / front camera switch (X), the
--            filters (the chip, or left / right), and the modes: Auto,
--            Video (Shoot starts and stops; up to ten minutes, with sound),
--            Multi (four shots, half a second apart, in one picture) and
--            Self-Timer (three seconds).
--   Photos   the pictures taken, newest first, a page of them at a time
--            (swipe or left / right); the chosen one fills the top screen;
--            info and delete.
--   Settings the camera, the shutter sound, grid lines, and whether a copy
--            of every picture goes to the phone's gallery (Pictures /
--            Gen1Recomp).
--
-- Videos are saved as videos/HNV_0001.mp4 (FoldRecorder.java encodes the
-- frames drawn here, so the filters are in them) and play in the phone's
-- video player from their gallery copy.
-- Pictures are saved as photos/HNI_0001.png, ... in the save folder: what
-- the top screen shows, at the camera's own resolution.  The frames come
-- from love.system.foldCamera (Android: FoldCamera.java through liblove);
-- without it (a desktop) POKEPORT_FOLD_FAKECAM=1 shows a test picture.
local C = {}

local lg = love.graphics
local Sfx = require("fold3ds.sfx")
local Filters = require("fold3ds.camfilters")

local CFG = "fold3ds_camera.cfg"
local DIR = "photos"
local PER_PAGE = 10          -- photos on a page: 5 across, 2 down
local ZOOM_MAX = 4
local TIMER = 3
local VDIR = "videos"
local REC_FPS = 30
local REC_MAX = 10 * 60      -- ten minutes, as the 3DS

local ctx
local st = {
  open = false,
  view = "camera",           -- camera / photos / settings
  facing = 0,                -- 0 rear, 1 front
  mode = "auto",             -- auto / video / multi / timer
  filter = "none",           -- camfilters.lua
  rec = nil,                 -- the video being recorded
  sound = true, gallery = true, grid = false,
  zoom = 1,
  camState = 0,              -- FoldCamera's state; "none" without a camera
  retryAt = 0,
  data = nil, image = nil,   -- the newest frame
  info = nil,                -- { w, h, rot, mirror }
  hits = {},
  down = nil,                -- the pressed control's id
  touches = {},
  flash = -10,               -- when the shutter last fired
  timerAt = nil,             -- self-timer: when it fires
  multi = nil,               -- { shots = {canvas...}, next = t }
  captures = 0,              -- captures to take on the next top-screen draw
  photos = nil,              -- file names, newest first
  sel = 1, page = 1,
  thumbs = {}, full = nil, fullName = nil,
  confirmDelete = nil,
  toast = nil,
  t = 0,
}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function col(c, a) lg.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1) end
local function rrect(mode, x, y, w, h, r) lg.rectangle(mode, x, y, w, h, r, r, 10) end

-- Draw into a canvas.  The scissor is lifted first and put back after:
-- LÖVE restores it while the canvas is still bound, which would clip
-- everything drawn on the screen afterwards.
local function offscreen(canvas, clear, fn)
  local sx, sy, sw, sh = lg.getScissor()
  lg.setScissor()
  lg.push("all")
  lg.setCanvas(canvas)
  lg.origin()
  lg.setShader()
  lg.setStencilTest()
  lg.clear(clear[1], clear[2], clear[3], clear[4] or 1)
  lg.setColor(1, 1, 1, 1)
  fn()
  lg.pop()
  if sx then lg.setScissor(sx, sy, sw, sh) end
end

---------------------------------------------------------------- settings

local function loadCfg()
  local ok, text = pcall(love.filesystem.read, CFG)
  text = ok and type(text) == "string" and text or ""
  st.facing = tonumber(text:match("facing=(%d)")) == 1 and 1 or 0
  local m = text:match("mode=(%a+)")
  if m == "auto" or m == "video" or m == "multi" or m == "timer" then st.mode = m end
  st.filter = Filters.get(text:match("filter=(%a+)") or "none").id
  st.sound = text:match("sound=0") == nil
  st.gallery = text:match("gallery=0") == nil
  st.grid = text:match("grid=1") ~= nil
end

local function saveCfg()
  pcall(love.filesystem.write, CFG, ("facing=%d\nmode=%s\nfilter=%s\nsound=%d\ngallery=%d\ngrid=%d\n"):format(
    st.facing, st.mode, st.filter, st.sound and 1 or 0, st.gallery and 1 or 0, st.grid and 1 or 0))
end

local function toast(text) st.toast = { text = text, at = st.t } end

---------------------------------------------------------------- sounds

local sounds = {}
local function synth(name)
  if sounds[name] ~= nil then return sounds[name] or nil end
  -- the 3DS camera's own shutter
  if name == "shutter" then
    local ok, src = pcall(love.audio.newSource, "fold3ds/sounds/home_camera.wav", "static")
    if ok then sounds[name] = src return src end
  end
  local ok, src = pcall(function()
    local rate = 44100
    local len = name == "shutter" and 0.24 or 0.09
    local n = math.floor(rate * len)
    local sd = love.sound.newSoundData(n, rate, 16, 1)
    for i = 0, n - 1 do
      local t = i / rate
      local v
      if name == "shutter" then
        -- the two clicks of a shutter: open, and close a moment later
        local a = math.exp(-t * 180) + 0.8 * (t > 0.085 and math.exp(-(t - 0.085) * 150) or 0)
        v = (love.math.random() * 2 - 1) * a * 0.55
      else
        local hz = name == "recStart" and 880 or name == "recStop" and 660 or 1320
        v = math.sin(t * 2 * math.pi * hz) * math.min(1, (len - t) * 60) * 0.35
      end
      sd:setSample(i, v)
    end
    return love.audio.newSource(sd, "static")
  end)
  sounds[name] = ok and src or false
  return sounds[name] or nil
end

local function beep(name)
  if not st.sound or not love.audio then return end
  local s = synth(name)
  if s then pcall(function() s:stop(); s:play() end) end
end

---------------------------------------------------------------- the camera

local fake = os.getenv("POKEPORT_FOLD_FAKECAM") == "1"

local function api()
  return love.system and love.system.foldCamera
end

local function startCamera()
  st.data, st.image, st.info = nil, nil, nil
  local f = api()
  if f then
    local ok, s = pcall(f, "start", st.facing, 1280)
    st.camState = ok and s or "none"
    if st.camState == nil then st.camState = "none" end
  elseif fake then
    st.camState = 3
  else
    st.camState = "none"
  end
end

local function stopCamera()
  local f = api()
  if f then pcall(f, "stop") end
  st.camState = 0
end

-- a moving test card for the desktop (as a camera sideways in its sensor)
local function fakeFrame()
  local w, h = 320, 240
  if not st.data then st.data = love.image.newImageData(w, h) end
  local t = st.t
  st.data:mapPixel(function(x, y)
    local bar = math.floor(x / (w / 7))
    local c = ({ { 1, 1, 1 }, { 1, 1, 0 }, { 0, 1, 1 }, { 0, 1, 0 }, { 1, 0, 1 }, { 1, 0, 0 }, { 0, 0, 1 } })[bar + 1]
    local k = y < h * 0.66 and 0.85 or 0.35
    local cx, cy = w / 2 + math.cos(t) * w * 0.3, h / 2 + math.sin(t * 1.3) * h * 0.3
    if (x - cx) ^ 2 + (y - cy) ^ 2 < 400 then return 1, 0.5, 0.1, 1 end
    if x < 24 and y < 24 then return 0, 0, 0, 1 end  -- marks the picture's top-left
    return c[1] * k, c[2] * k, c[3] * k, 1
  end)
  st.info = { w = w, h = h, rot = 90, mirror = st.facing == 1 }
  if st.image then st.image:replacePixels(st.data) else st.image = lg.newImage(st.data) end
end

-- the newest frame into st.image
local function pullFrame()
  local f = api()
  if not f then
    if fake and st.camState == 3 then fakeFrame() end
    return
  end
  local ok, w, h, rot, mirror = pcall(f, "info")
  if not ok or not w or w <= 0 or h <= 0 then return end
  st.info = { w = w, h = h, rot = rot or 0, mirror = mirror == 1 }
  if not st.data or st.data:getWidth() ~= w or st.data:getHeight() ~= h then
    st.data = love.image.newImageData(w, h, "rgba8")
    st.image = nil
  end
  local ok2, fresh = pcall(f, "frame", st.data)
  if ok2 and fresh then
    if st.image then st.image:replacePixels(st.data) else st.image = lg.newImage(st.data) end
    st.image:setFilter("linear", "linear")
  end
end

---------------------------------------------------------------- the album

-- The album: pictures (photos/HNI_####.png) and videos (videos/HNV_####.mp4,
-- with the first frame as HNV_####.png and the gallery copy's URI in
-- HNV_####.uri), newest first.
local function listPhotos()
  local out = {}
  for _, name in ipairs(love.filesystem.getDirectoryItems(DIR) or {}) do
    local n = name:match("^(HNI_%d+)%.png$")
    if n then out[#out + 1] = { name = n, path = DIR .. "/" .. name } end
  end
  for _, name in ipairs(love.filesystem.getDirectoryItems(VDIR) or {}) do
    local n = name:match("^(HNV_%d+)%.mp4$")
    if n then
      out[#out + 1] = { name = n, video = true, path = VDIR .. "/" .. n .. ".png",
        mp4 = VDIR .. "/" .. name, uriPath = VDIR .. "/" .. n .. ".uri" }
    end
  end
  for _, it in ipairs(out) do
    local info = love.filesystem.getInfo(it.video and it.mp4 or it.path)
    it.time = info and info.modtime or 0
    it.size = info and info.size or 0
  end
  table.sort(out, function(a, b)
    if a.time ~= b.time then return a.time > b.time end
    return a.name > b.name
  end)
  st.photos = out
  st.sel = clamp(st.sel, 1, math.max(1, #out))
  return out
end

local function nextName(prefix, dir, ext)
  local top = 0
  for _, name in ipairs(love.filesystem.getDirectoryItems(dir) or {}) do
    top = math.max(top, tonumber(name:match("^" .. prefix .. "_(%d+)%." .. ext .. "$")) or 0)
  end
  return ("%s_%04d"):format(prefix, top + 1)
end

local function savePicture(imageData)
  love.filesystem.createDirectory(DIR)
  local name = nextName("HNI", DIR, "png")
  local path = DIR .. "/" .. name .. ".png"
  local ok, err = pcall(function() imageData:encode("png", path) end)
  if not ok then toast("Couldn't save the picture") print("fold3ds camera: " .. tostring(err)) return end
  if st.gallery and love.system and love.system.exportImage then pcall(love.system.exportImage, path) end
  st.thumbs[path] = nil
  listPhotos()
  st.sel = 1
  toast(name .. " saved")
end

---------------------------------------------------------------- drawing the picture

-- the frame as it stands upright: its size after turning
local function upright()
  local i = st.info
  if not i then return 0, 0 end
  if i.rot == 90 or i.rot == 270 then return i.h, i.w end
  return i.w, i.h
end

-- draw the frame upright, filling (cropping) a w x h box at x, y
local function drawRaw(x, y, w, h, zoom)
  local img, i = st.image, st.info
  if not img or not i then return false end
  local ew, eh = upright()
  local s = math.max(w / ew, h / eh) * (zoom or 1)
  lg.push()
  lg.translate(x + w / 2, y + h / 2)
  if i.mirror then lg.scale(-1, 1) end
  lg.rotate(math.rad(i.rot))
  lg.draw(img, 0, 0, 0, s, s, i.w / 2, i.h / 2)
  lg.pop()
  return true
end

-- a canvas of this size, kept for reuse
local canvases = {}
local function canvasOf(w, h)
  w, h = math.max(2, math.floor(w)), math.max(2, math.floor(h))
  local key = w .. "x" .. h
  if not canvases[key] then
    canvases[key] = lg.newCanvas(w, h)
    canvases[key]:setFilter("linear", "linear")
  end
  return canvases[key]
end

-- the frame upright and through the filter, filling a w x h box at x, y
local function drawFrame(x, y, w, h, zoom)
  if not st.image or not st.info then return false end
  local shader = Filters.shader(st.filter, w, h, st.t)
  if not shader then return drawRaw(x, y, w, h, zoom) end
  local c = canvasOf(w, h)
  offscreen(c, { 0, 0, 0 }, function() drawRaw(0, 0, c:getWidth(), c:getHeight(), zoom) end)
  lg.push("all")
  lg.setShader(shader)
  lg.setColor(1, 1, 1, 1)
  lg.draw(c, x, y, 0, w / c:getWidth(), h / c:getHeight())
  lg.pop()
  return true
end

-- the picture the top screen shows (aspect a), at the camera's resolution
local function captureCanvas(aspect)
  local ew, eh = upright()
  if ew == 0 then return nil end
  local cw, ch = ew, ew / aspect
  if ch > eh then ch, cw = eh, eh * aspect end
  cw, ch = math.floor(cw / st.zoom), math.floor(ch / st.zoom)
  local c = lg.newCanvas(cw, ch)
  offscreen(c, { 0, 0, 0 }, function() drawFrame(0, 0, cw, ch, st.zoom) end)
  return c
end

-- four shots in one picture, two by two
local function composeMulti(shots)
  local w, h = shots[1]:getDimensions()
  local c = lg.newCanvas(w, h)
  offscreen(c, { 1, 1, 1 }, function()
    local g = math.max(2, math.floor(w * 0.006))
    for k, s in ipairs(shots) do
      local cx, cy = (k - 1) % 2, math.floor((k - 1) / 2)
      lg.draw(s, cx * (w / 2) + g / 2, cy * (h / 2) + g / 2, 0, (w / 2 - g) / w, (h / 2 - g) / h)
    end
  end)
  return c
end

local function takeShot(aspect)
  local c = captureCanvas(aspect)
  if not c then toast("No picture from the camera yet") return end
  st.flash = st.t
  beep("shutter")
  if st.mode == "multi" then
    st.multi = st.multi or { shots = {} }
    table.insert(st.multi.shots, c)
    if #st.multi.shots >= 4 then
      local img = composeMulti(st.multi.shots)
      st.multi = nil
      savePicture(img:newImageData())
    else
      st.multi.next = st.t + 0.55
    end
    return
  end
  savePicture(c:newImageData())
end

---------------------------------------------------------------- video

local function recording() return st.rec ~= nil end

local function startRecording()
  local f = api()
  if not f and not fake then toast("Video recording works on the phone") return end
  love.filesystem.createDirectory(VDIR)
  local name = nextName("HNV", VDIR, "mp4")
  -- the top screen's shape, 480 lines, sizes the encoder likes (16s)
  local a = st.topAspect or 5 / 3
  local h = 480
  local w = math.floor(h * a / 16 + 0.5) * 16
  local full = love.filesystem.getSaveDirectory() .. "/" .. VDIR .. "/" .. name .. ".mp4"
  if not f then
    -- the desktop test camera: frames drawn and read back, nothing encoded
    st.rec = { name = name, w = w, h = h, t0 = st.t, next = st.t, frames = 0, stub = true }
    beep("recStart")
    return
  end
  local ok, s = pcall(f, "recStart", full, w, h, REC_FPS)
  if not ok or s ~= 1 then toast("The video couldn't start") Sfx.play("cancel") return end
  st.rec = { name = name, w = w, h = h, t0 = st.t, next = st.t, frames = 0 }
  beep("recStart")
end

local function stopRecording(quiet)
  local r = st.rec
  if not r then return end
  st.rec = nil
  if r.stub then
    love.filesystem.remove(VDIR .. "/" .. r.name .. ".png")
    toast(("Test video: %d frames of %dx%d"):format(r.frames, r.w, r.h))
    return
  end
  local f = api()
  local ok, uri = pcall(f, "recStop", st.gallery)
  if not ok or uri == nil then
    love.filesystem.remove(VDIR .. "/" .. r.name .. ".png")
    if not quiet then toast("Nothing was recorded") end
    return
  end
  if uri ~= "" then pcall(love.filesystem.write, VDIR .. "/" .. r.name .. ".uri", uri) end
  beep("recStop")
  listPhotos()
  st.sel = 1
  if not quiet then toast(("%s saved (%d:%02d)"):format(r.name, math.floor((st.t - r.t0) / 60), math.floor(st.t - r.t0) % 60)) end
end

-- during the top screen's drawing: the next frame of the video
local function recordFrame(aspect)
  local r = st.rec
  if not r or st.t < r.next or not st.image then return end
  r.next = math.max(r.next + 1 / REC_FPS, st.t)
  local out = lg.newCanvas(r.w, r.h)
  offscreen(out, { 0, 0, 0 }, function() drawFrame(0, 0, r.w, r.h, st.zoom) end)
  local data = out:newImageData()
  out:release()
  if r.frames == 0 then pcall(function() data:encode("png", VDIR .. "/" .. r.name .. ".png") end) end
  if not r.stub then pcall(api(), "recFrame", data) end
  data:release()
  r.frames = r.frames + 1
  if st.t - r.t0 >= REC_MAX then stopRecording() end
end

local function shoot()
  if type(st.camState) == "number" and (st.camState < 0 or st.camState == 0) then
    -- refused, failed or missing: try again
    startCamera()
    Sfx.play("button")
    return
  end
  if st.camState ~= 3 or not st.image then
    toast(st.camState == "none" and "No camera" or "The camera isn't ready")
    return
  end
  if st.mode == "video" then
    if recording() then stopRecording() else startRecording() end
    return
  end
  if st.timerAt or st.multi then return end
  if st.mode == "timer" then
    st.timerAt = st.t + TIMER
    st.timerBeep = TIMER
    beep("beep")
    return
  end
  st.captures = st.captures + 1
end

local function setFilter(id)
  st.filter = id
  saveCfg()
  toast(Filters.get(id).name)
  Sfx.play("screen")
end

---------------------------------------------------------------- glyphs

local INK = { 60, 62, 66 }
local FACE = { 238, 239, 242 }
local EDGE = { 170, 172, 178 }
local YELLOW = { 255, 236, 140 }

local G = {}
function G.camera(x, y, s)
  rrect("fill", x + s * 0.08, y + s * 0.3, s * 0.84, s * 0.56, s * 0.1)
  rrect("fill", x + s * 0.3, y + s * 0.18, s * 0.4, s * 0.2, s * 0.06)
end
function G.cameraLens(x, y, s, bg)
  col(bg)
  lg.circle("fill", x + s * 0.5, y + s * 0.58, s * 0.17)
end
function G.gear(x, y, s)
  local cx, cy = x + s / 2, y + s / 2
  for k = 0, 7 do
    local a = k * math.pi / 4
    lg.push()
    lg.translate(cx, cy)
    lg.rotate(a)
    lg.rectangle("fill", -s * 0.09, -s * 0.46, s * 0.18, s * 0.2, s * 0.03)
    lg.pop()
  end
  lg.circle("fill", cx, cy, s * 0.33)
end
function G.photo(x, y, s)
  lg.setColor(1, 1, 1, 1)
  rrect("fill", x + s * 0.06, y + s * 0.14, s * 0.88, s * 0.72, s * 0.05)
  lg.setColor(0.36, 0.66, 0.95, 1)
  lg.rectangle("fill", x + s * 0.12, y + s * 0.2, s * 0.76, s * 0.6)
  lg.setColor(1, 0.86, 0.3, 1)
  lg.circle("fill", x + s * 0.68, y + s * 0.36, s * 0.08)
  lg.setColor(0.3, 0.62, 0.3, 1)
  lg.polygon("fill", x + s * 0.12, y + s * 0.8, x + s * 0.36, y + s * 0.48, x + s * 0.56, y + s * 0.8)
  lg.setColor(0.24, 0.54, 0.26, 1)
  lg.polygon("fill", x + s * 0.4, y + s * 0.8, x + s * 0.64, y + s * 0.54, x + s * 0.88, y + s * 0.8)
end
function G.back(x, y, s)
  lg.setLineWidth(s * 0.13)
  lg.arc("line", "open", x + s * 0.52, y + s * 0.55, s * 0.26, -math.pi / 2, math.pi * 0.62)
  lg.polygon("fill", x + s * 0.16, y + s * 0.29, x + s * 0.5, y + s * 0.08, x + s * 0.5, y + s * 0.5)
end
function G.plus(x, y, s)
  lg.rectangle("fill", x + s * 0.2, y + s * 0.44, s * 0.6, s * 0.12, s * 0.04)
  lg.rectangle("fill", x + s * 0.44, y + s * 0.2, s * 0.12, s * 0.6, s * 0.04)
end
function G.minus(x, y, s)
  lg.rectangle("fill", x + s * 0.2, y + s * 0.44, s * 0.6, s * 0.12, s * 0.04)
end
function G.film(x, y, s, bg)
  rrect("fill", x + s * 0.2, y + s * 0.1, s * 0.6, s * 0.8, s * 0.04)
  col(bg or FACE)
  for k = 0, 4 do
    lg.rectangle("fill", x + s * 0.25, y + s * (0.16 + k * 0.14), s * 0.07, s * 0.08)
    lg.rectangle("fill", x + s * 0.68, y + s * (0.16 + k * 0.14), s * 0.07, s * 0.08)
  end
  lg.rectangle("fill", x + s * 0.37, y + s * 0.18, s * 0.26, s * 0.28)
  lg.rectangle("fill", x + s * 0.37, y + s * 0.54, s * 0.26, s * 0.28)
end
function G.wrench(x, y, s)
  lg.push()
  lg.translate(x + s / 2, y + s / 2)
  lg.rotate(math.rad(45))
  lg.rectangle("fill", -s * 0.07, -s * 0.1, s * 0.14, s * 0.5, s * 0.05)
  lg.circle("fill", 0, -s * 0.22, s * 0.17)
  lg.pop()
end
function G.multi(x, y, s)
  for i = 0, 1 do for j = 0, 1 do
    rrect("fill", x + s * (0.14 + i * 0.38), y + s * (0.14 + j * 0.38), s * 0.33, s * 0.33, s * 0.05)
  end end
end
function G.timer(x, y, s, bg)
  lg.circle("fill", x + s * 0.36, y + s * 0.3, s * 0.16)
  lg.arc("fill", x + s * 0.36, y + s * 0.82, s * 0.3, math.pi, math.pi * 2)
  col(bg)
  lg.circle("fill", x + s * 0.7, y + s * 0.66, s * 0.22)
  lg.setColor(0.25, 0.25, 0.27, 1)
  lg.circle("fill", x + s * 0.7, y + s * 0.66, s * 0.17)
  col(bg)
  lg.setLineWidth(math.max(1, s * 0.05))
  lg.line(x + s * 0.7, y + s * 0.56, x + s * 0.7, y + s * 0.66, x + s * 0.78, y + s * 0.66)
end
function G.video(x, y, s)
  rrect("fill", x + s * 0.06, y + s * 0.26, s * 0.62, s * 0.5, s * 0.08)
  lg.polygon("fill", x + s * 0.66, y + s * 0.44, x + s * 0.94, y + s * 0.26, x + s * 0.94, y + s * 0.76, x + s * 0.66, y + s * 0.58)
end
function G.play(x, y, s)
  lg.polygon("fill", x + s * 0.28, y + s * 0.18, x + s * 0.82, y + s * 0.5, x + s * 0.28, y + s * 0.82)
end
function G.flip(x, y, s)
  G.camera(x, y, s)
end
function G.info(x, y, s, bg)
  lg.circle("fill", x + s / 2, y + s / 2, s * 0.4)
  col(bg)
  lg.circle("fill", x + s / 2, y + s * 0.3, s * 0.06)
  lg.rectangle("fill", x + s * 0.45, y + s * 0.42, s * 0.1, s * 0.32, s * 0.03)
end
function G.trash(x, y, s)
  lg.rectangle("fill", x + s * 0.18, y + s * 0.2, s * 0.64, s * 0.08, s * 0.03)
  lg.rectangle("fill", x + s * 0.4, y + s * 0.12, s * 0.2, s * 0.1, s * 0.03)
  lg.polygon("fill", x + s * 0.24, y + s * 0.32, x + s * 0.76, y + s * 0.32, x + s * 0.7, y + s * 0.88, x + s * 0.3, y + s * 0.88)
end
function G.zoomIn(x, y, s)
  lg.setLineWidth(s * 0.09)
  lg.circle("line", x + s * 0.42, y + s * 0.42, s * 0.26)
  lg.line(x + s * 0.62, y + s * 0.62, x + s * 0.86, y + s * 0.86)
  lg.rectangle("fill", x + s * 0.3, y + s * 0.39, s * 0.24, s * 0.06)
  lg.rectangle("fill", x + s * 0.39, y + s * 0.3, s * 0.06, s * 0.24)
end
function G.zoomOut(x, y, s)
  lg.setLineWidth(s * 0.09)
  lg.circle("line", x + s * 0.42, y + s * 0.42, s * 0.26)
  lg.line(x + s * 0.62, y + s * 0.62, x + s * 0.86, y + s * 0.86)
  lg.rectangle("fill", x + s * 0.3, y + s * 0.39, s * 0.24, s * 0.06)
end

-- the applet icon: an orange rounded square with a white camera
function C.drawIcon(x, y, s)
  local r = s * 0.24
  lg.setColor(0.93, 0.45, 0.02, 1)
  rrect("fill", x, y + s * 0.03, s, s, r)
  lg.setColor(1, 0.6, 0.08, 1)
  rrect("fill", x, y, s, s, r)
  lg.setColor(1, 0.72, 0.3, 0.7)
  rrect("fill", x + s * 0.08, y + s * 0.05, s * 0.84, s * 0.34, r * 0.7)
  lg.setColor(1, 1, 1, 1)
  G.camera(x + s * 0.1, y + s * 0.1, s * 0.8)
  G.cameraLens(x + s * 0.1, y + s * 0.1, s * 0.8, { 250, 140, 20 })
end

---------------------------------------------------------------- controls


local function hit(id, x, y, w, h, round)
  st.hits[#st.hits + 1] = { id = id, x = x, y = y, w = w, h = h, round = round }
end

-- a rounded grey key, pale yellow when chosen, sunk while held
local function key(id, x, y, w, h, glyph, label, chosen)
  local down = st.down == id
  local r = math.min(w, h) * 0.24
  col({ 120, 122, 128 }, 0.35)
  rrect("fill", x, y + h * 0.05, w, h, r)
  col(EDGE)
  rrect("fill", x, y + (down and h * 0.04 or 0), w, h, r)
  col(chosen and YELLOW or FACE)
  rrect("fill", x + 2, y + 2 + (down and h * 0.04 or 0), w - 4, h - 4, r * 0.9)
  if not chosen then
    lg.setColor(1, 1, 1, 0.6)
    rrect("fill", x + 4, y + 4 + (down and h * 0.04 or 0), w - 8, (h - 8) * 0.45, r * 0.7)
  end
  local oy = down and h * 0.04 or 0
  local s = label and math.min(w, h) * 0.5 or math.min(w, h) * 0.6
  local gx, gy = x + (w - s) / 2, y + (label and h * 0.1 or (h - s) / 2) + oy
  col(INK)
  if glyph then glyph(gx, gy, s, chosen and YELLOW or FACE) end
  if label then
    local f = ctx.font(h * 0.2)
    lg.setFont(f)
    col(INK)
    lg.printf(label, x, y + h * 0.66 + oy, w, "center")
  end
  hit(id, x, y, w, h)
end

-- a round key (the Shoot / Photos / Settings buttons)
local function roundKey(id, cx, cy, rad, draw)
  local down = st.down == id
  col({ 120, 122, 128 }, 0.35)
  lg.circle("fill", cx, cy + rad * 0.06, rad)
  col({ 196, 198, 204 })
  lg.circle("fill", cx, cy, rad)
  col({ 250, 250, 252 })
  lg.circle("fill", cx, cy, rad * 0.93)
  col(EDGE)
  lg.circle("fill", cx, cy + (down and rad * 0.03 or 0), rad * 0.8)
  col(down and { 214, 216, 222 } or { 234, 235, 239 })
  lg.circle("fill", cx, cy + (down and rad * 0.03 or 0), rad * 0.76)
  lg.setColor(1, 1, 1, 0.5)
  lg.arc("fill", cx, cy + (down and rad * 0.03 or 0), rad * 0.72, math.pi * 1.05, math.pi * 1.95)
  draw(cx, cy + (down and rad * 0.03 or 0), rad)
  hit(id, cx - rad, cy - rad, rad * 2, rad * 2, true)
end

-- the view tabs: camera | photos | settings
local function tabs(x, y, w, h)
  local views = { { "camera", G.camera }, { "photos", G.film }, { "settings", G.wrench } }
  local r = h * 0.3
  col({ 120, 122, 128 }, 0.35)
  rrect("fill", x, y + h * 0.05, w, h, r)
  col(EDGE)
  rrect("fill", x, y, w, h, r)
  local tw = w / #views
  for k, v in ipairs(views) do
    local tx = x + (k - 1) * tw
    local on = st.view == v[1]
    lg.stencil(function() rrect("fill", x + 2, y + 2, w - 4, h - 4, r * 0.9) end, "replace", 1)
    lg.setStencilTest("greater", 0)
    col(on and YELLOW or FACE)
    lg.rectangle("fill", tx, y, tw, h)
    lg.setStencilTest()
    if k > 1 then col(EDGE) lg.rectangle("fill", tx, y + 2, 2, h - 4) end
    local s = h * 0.62
    col(INK)
    v[2](tx + (tw - s) / 2, y + (h - s) / 2, s, on and YELLOW or FACE)
    if v[1] == "camera" then G.cameraLens(tx + (tw - s) / 2, y + (h - s) / 2, s, on and YELLOW or FACE) end
    hit("view:" .. v[1], tx, y, tw, h)
  end
end

local function wallpaper(r)
  for i = 0, r.h, 2 do
    local k = i / r.h
    lg.setColor(0.95 - 0.04 * k, 0.955 - 0.04 * k, 0.965 - 0.035 * k, 1)
    lg.rectangle("fill", r.x, r.y + i, r.w, 2)
  end
end

---------------------------------------------------------------- the bottom screen

local function drawCameraControls(r, pad, rowH)
  -- the round keys: Photos, Shoot, Settings
  local cy = r.y + r.h * 0.5
  local big = r.h * 0.2
  roundKey("shoot", r.x + r.w * 0.43, cy, big, function(x, y, rad)
    lg.setColor(0.2, 0.2, 0.22, 1)
    lg.circle("line", x, y, rad * 0.72)
    if st.mode == "video" then
      -- record: a red dot; recording: a red square
      lg.setColor(0.86, 0.16, 0.14, 1)
      if recording() then
        local q = rad * 0.52
        lg.rectangle("fill", x - q / 2, y - q / 2, q, q, q * 0.15)
      else
        lg.circle("fill", x, y, rad * 0.36)
      end
      return
    end
    local s = rad * 0.9
    col({ 56, 58, 62 })
    G.camera(x - s / 2, y - s / 2, s)
    G.cameraLens(x - s / 2, y - s / 2, s, { 234, 235, 239 })
  end)
  local small = r.h * 0.13
  roundKey("photos", r.x + r.w * 0.15, cy, small, function(x, y, rad)
    local s = rad * 1.05
    G.photo(x - s / 2, y - s / 2, s)
  end)
  roundKey("settings", r.x + r.w * 0.71, cy, small, function(x, y, rad)
    local s = rad * 1.05
    col({ 56, 58, 62 })
    G.gear(x - s / 2, y - s / 2, s)
    col({ 234, 235, 239 })
    lg.circle("fill", x, y, s * 0.13)
  end)
  -- zoom: the magnifiers, one pill
  local zw, zh = r.w * 0.1, r.h * 0.42
  local zx, zy = r.x + r.w - pad - zw, cy - zh / 2
  col({ 120, 122, 128 }, 0.35)
  rrect("fill", zx, zy + zh * 0.02, zw, zh, zw * 0.3)
  col(EDGE)
  rrect("fill", zx, zy, zw, zh, zw * 0.3)
  for k, id in ipairs({ "zoomIn", "zoomOut" }) do
    local hy = zy + (k - 1) * zh / 2
    local can = (id == "zoomIn" and st.zoom < ZOOM_MAX) or (id == "zoomOut" and st.zoom > 1)
    col(st.down == id and { 214, 216, 222 } or FACE)
    lg.stencil(function() rrect("fill", zx + 2, zy + 2, zw - 4, zh - 4, zw * 0.28) end, "replace", 1)
    lg.setStencilTest("greater", 0)
    lg.rectangle("fill", zx, hy, zw, zh / 2)
    lg.setStencilTest()
    local s = zw * 0.7
    col(INK, can and 1 or 0.3)
    G[id](zx + (zw - s) / 2, hy + (zh / 2 - s) / 2, s)
    hit(id, zx, hy, zw, zh / 2)
  end
  col(EDGE)
  lg.rectangle("fill", zx + zw * 0.15, zy + zh / 2 - 1, zw * 0.7, 2)
  -- zoom level
  if st.zoom > 1 then
    local f = ctx.font(rowH * 0.3)
    lg.setFont(f)
    col(INK)
    lg.printf(("x%.1f"):format(st.zoom), zx - zw * 0.3, zy + zh + pad * 0.3, zw * 1.6, "center")
  end
  -- the filter: tap its left half for the one before, right for the next
  local fw, fh = r.w * 0.34, rowH * 0.78
  local fx, fy = r.x + pad, r.y + pad * 2 + rowH
  key("filterChip", fx, fy, fw, fh, nil, nil, st.filter ~= "none")
  st.hits[#st.hits] = nil
  hit("filterPrev", fx, fy, fw / 2, fh)
  hit("filterNext", fx + fw / 2, fy, fw / 2, fh)
  local ff = ctx.font(fh * 0.42)
  lg.setFont(ff)
  col(INK)
  lg.printf(Filters.get(st.filter).name, fx, fy + (fh - ff:getHeight()) / 2, fw, "center")
  local ah = fh * 0.22
  lg.polygon("fill", fx + fh * 0.3, fy + fh / 2, fx + fh * 0.3 + ah, fy + fh / 2 - ah, fx + fh * 0.3 + ah, fy + fh / 2 + ah)
  lg.polygon("fill", fx + fw - fh * 0.3, fy + fh / 2, fx + fw - fh * 0.3 - ah, fy + fh / 2 - ah, fx + fw - fh * 0.3 - ah, fy + fh / 2 + ah)
  -- the modes
  local modes = { { "auto", "Auto", G.camera }, { "video", "Video", G.video },
                  { "multi", "Multi", G.multi }, { "timer", "Self-Timer", G.timer } }
  local mw = r.w * 0.19
  local mh = rowH * 1.25
  local gap = pad
  local total = #modes * mw + (#modes - 1) * gap
  local mx = r.x + (r.w - total) / 2
  local my = r.y + r.h - pad - mh
  for k, m in ipairs(modes) do
    local on = st.mode == m[1]
    key("mode:" .. m[1], mx + (k - 1) * (mw + gap), my, mw, mh, function(x, y, s, bg)
      m[3](x, y, s, bg)
      if m[1] == "auto" then G.cameraLens(x, y, s, bg) end
    end, m[2], on)
  end
end

local function thumb(path)
  local t = st.thumbs[path]
  if t ~= nil then return t or nil end
  if st.thumbBudget <= 0 then return nil end
  st.thumbBudget = st.thumbBudget - 1
  local ok, img = pcall(lg.newImage, path)
  if not ok then st.thumbs[path] = false return nil end
  local w, h = img:getDimensions()
  local tw = 200
  local th = math.max(1, math.floor(tw * h / w))
  local c = lg.newCanvas(tw, th)
  offscreen(c, { 0, 0, 0 }, function() lg.draw(img, 0, 0, 0, tw / w, th / h) end)
  img:release()
  c:setFilter("linear", "linear")
  st.thumbs[path] = c
  return c
end

local function pages()
  return math.max(1, math.ceil(#(st.photos or {}) / PER_PAGE))
end

local function brackets(x, y, w, h, color, len)
  len = len or math.min(w, h) * 0.22
  local th = math.max(2, len * 0.22)
  col(color)
  for _, p in ipairs({ { x, y, 1, 1 }, { x + w, y, -1, 1 }, { x, y + h, 1, -1 }, { x + w, y + h, -1, -1 } }) do
    lg.rectangle("fill", p[3] > 0 and p[1] or p[1] - len, p[4] > 0 and p[2] or p[2] - th, len, th, th / 2, th / 2)
    lg.rectangle("fill", p[3] > 0 and p[1] or p[1] - th, p[4] > 0 and p[2] or p[2] - len, th, len, th / 2, th / 2)
  end
end

local function drawPhotos(r, pad, rowH)
  local list = st.photos or listPhotos()
  st.thumbBudget = 2
  local gy = r.y + pad * 2 + rowH
  local gh = r.h - (gy - r.y) - pad * 2 - rowH
  if #list == 0 then
    local f = ctx.font(rowH * 0.36)
    lg.setFont(f)
    col(INK, 0.7)
    lg.printf("No pictures or videos yet.\nTake one with the camera.", r.x, gy + gh / 2 - f:getHeight(), r.w, "center")
  end
  st.page = clamp(st.page, 1, pages())
  local cols, rows = 5, 2
  local cw = (r.w - pad * (cols + 1)) / cols
  local ch = (gh - pad * (rows + 1)) / rows
  local first = (st.page - 1) * PER_PAGE
  for k = 1, PER_PAGE do
    local i = first + k
    local item = list[i]
    if not item then break end
    local cx = r.x + pad + ((k - 1) % cols) * (cw + pad)
    local cy = gy + pad + math.floor((k - 1) / cols) * (ch + pad)
    col({ 120, 122, 128 }, 0.3)
    rrect("fill", cx, cy + 3, cw, ch, 6)
    lg.setColor(1, 1, 1, 1)
    rrect("fill", cx, cy, cw, ch, 6)
    local t = thumb(item.path)
    if t then
      local tw, th = t:getDimensions()
      local s = math.min((cw - 8) / tw, (ch - 8) / th)
      lg.setColor(1, 1, 1, 1)
      lg.draw(t, cx + (cw - tw * s) / 2, cy + (ch - th * s) / 2, 0, s, s)
    end
    if item.video then
      -- a video: the film edge and a play mark
      lg.setColor(0.1, 0.1, 0.12, 0.85)
      lg.rectangle("fill", cx + 4, cy + 4, cw * 0.12, ch - 8)
      lg.setColor(1, 1, 1, 0.9)
      for k2 = 0, 3 do lg.rectangle("fill", cx + 4 + cw * 0.03, cy + 8 + k2 * (ch - 16) / 4, cw * 0.06, (ch - 16) / 8) end
      local ps = math.min(cw, ch) * 0.34
      lg.setColor(0, 0, 0, 0.45)
      lg.circle("fill", cx + cw / 2, cy + ch / 2, ps * 0.62)
      lg.setColor(1, 1, 1, 0.95)
      G.play(cx + cw / 2 - ps / 2, cy + ch / 2 - ps / 2, ps)
    end
    if i == st.sel then
      local pulse = 0.75 + 0.25 * math.sin(st.t * 5)
      brackets(cx - 4, cy - 4, cw + 8, ch + 8, { 60, 200, 80, 255 * pulse }, math.min(cw, ch) * 0.28)
    end
    hit("photo:" .. i, cx, cy, cw, ch)
  end
  -- the bottom row: page dots, info, delete
  local by = r.y + r.h - pad - rowH
  local n = pages()
  local dw = math.min(r.w * 0.36, n * rowH * 0.5 + rowH * 0.4)
  local dx = r.x + (r.w - dw) / 2
  col({ 120, 122, 128 }, 0.35)
  rrect("fill", dx, by + rowH * 0.05, dw, rowH, rowH / 2)
  col(EDGE)
  rrect("fill", dx, by, dw, rowH, rowH / 2)
  col(FACE)
  rrect("fill", dx + 2, by + 2, dw - 4, rowH - 4, rowH / 2 - 2)
  local step = math.min(rowH * 0.5, (dw - rowH * 0.4) / n)
  for p = 1, n do
    local px = dx + dw / 2 + (p - (n + 1) / 2) * step
    if p == st.page then lg.setColor(1, 0.6, 0.1, 1) else lg.setColor(0.72, 0.73, 0.76, 1) end
    lg.circle("fill", px, by + rowH / 2, math.min(rowH * 0.18, step * 0.38))
  end
  hit("pagePrev", dx, by, dw / 2, rowH)
  hit("pageNext", dx + dw / 2, by, dw / 2, rowH)
  key("info", r.x + pad, by, rowH * 1.3, rowH, G.info, nil)
  key("delete", r.x + r.w - pad - rowH * 1.3, by, rowH * 1.3, rowH, G.trash, nil, st.confirmDelete ~= nil)
end

local function drawSettings(r, pad, rowH)
  local rows = {
    { id = "facing", name = "Camera", value = st.facing == 1 and "Front" or "Rear" },
    { id = "filter", name = "Filter", value = Filters.get(st.filter).name },
    { id = "sound", name = "Shutter sound", value = st.sound and "On" or "Off" },
    { id = "grid", name = "Grid lines", value = st.grid and "On" or "Off" },
    { id = "gallery", name = "Copy to phone gallery", value = st.gallery and "On" or "Off" },
  }
  local y = r.y + pad * 2 + rowH
  local h = (r.h - (y - r.y) - pad * 2) / #rows
  local f = ctx.font(math.min(rowH * 0.38, h * 0.32))
  for _, row in ipairs(rows) do
    col({ 250, 250, 252 })
    rrect("fill", r.x + pad, y, r.w - pad * 2, h - pad * 0.6, 10)
    lg.setFont(f)
    col(INK)
    lg.print(row.name, r.x + pad * 2.5, y + (h - pad * 0.6 - f:getHeight()) / 2)
    local bw = r.w * 0.24
    key("set:" .. row.id, r.x + r.w - pad * 2 - bw, y + h * 0.12, bw, h * 0.62, nil, nil, false)
    lg.setFont(f)
    col(INK)
    lg.printf(row.value, r.x + r.w - pad * 2 - bw, y + h * 0.12 + (h * 0.62 - f:getHeight()) / 2, bw, "center")
    y = y + h
  end
end

function C.drawBottom(r)
  st.hits = {}
  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)
  wallpaper(r)
  local pad = math.floor(r.w * 0.025)
  local rowH = math.floor(r.h * 0.13)
  -- top row: back, the view tabs, and the camera switch / delete
  key("back", r.x + pad, r.y + pad, rowH * 1.5, rowH, G.back)
  tabs(r.x + r.w * 0.28, r.y + pad, r.w * 0.44, rowH)
  if st.view == "camera" then
    key("flip", r.x + r.w - pad - rowH * 1.5, r.y + pad, rowH * 1.5, rowH, function(x, y, s, bg)
      G.camera(x, y, s)
      col(bg)
      local cx, cy = x + s * 0.5, y + s * 0.58
      lg.setLineWidth(math.max(1, s * 0.06))
      lg.arc("line", "open", cx, cy, s * 0.17, math.pi * 0.1, math.pi * 1.1)
      lg.polygon("fill", cx - s * 0.2, cy - s * 0.12, cx - s * 0.08, cy - s * 0.02, cx - s * 0.24, cy + s * 0.02)
    end, nil, st.facing == 1)
  end
  if st.view == "camera" then
    drawCameraControls(r, pad, rowH)
  elseif st.view == "photos" then
    drawPhotos(r, pad, rowH)
  else
    drawSettings(r, pad, rowH)
  end
  lg.pop()
end

---------------------------------------------------------------- the top screen

local function message(r, title, body, color)
  lg.setColor(0.1, 0.1, 0.12, 1)
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  brackets(r.x + r.w * 0.2, r.y + r.h * 0.2, r.w * 0.6, r.h * 0.6, color or { 230, 80, 70 })
  local f = ctx.font(r.h * 0.07)
  lg.setFont(f)
  lg.setColor(1, 1, 1, 1)
  lg.printf(title, r.x, r.y + r.h * 0.4, r.w, "center")
  if body then
    local f2 = ctx.font(r.h * 0.045)
    lg.setFont(f2)
    lg.setColor(1, 1, 1, 0.75)
    lg.printf(body, r.x + r.w * 0.1, r.y + r.h * 0.4 + f:getHeight() * 1.3, r.w * 0.8, "center")
  end
end

local function drawToast(r)
  local t = st.toast
  if not t then return end
  local age = st.t - t.at
  if age > 2 then st.toast = nil return end
  local a = math.min(1, (2 - age) * 3)
  local f = ctx.font(r.h * 0.055)
  lg.setFont(f)
  local w = f:getWidth(t.text) + r.h * 0.08
  local h = f:getHeight() * 1.5
  lg.setColor(0, 0, 0, 0.6 * a)
  rrect("fill", r.x + (r.w - w) / 2, r.y + r.h - h - r.h * 0.04, w, h, h / 2)
  lg.setColor(1, 1, 1, a)
  lg.printf(t.text, r.x, r.y + r.h - h - r.h * 0.04 + (h - f:getHeight()) / 2, r.w, "center")
end

local function drawViewfinder(r)
  local s = st.camState
  if s == "none" then
    message(r, "No camera", "The camera works on the phone.")
    return
  elseif s == 1 then
    message(r, "Camera access", "Allow the camera in the prompt to take pictures.", { 250, 210, 60 })
    return
  elseif s == -3 then
    message(r, "Camera access was refused", "Tap Shoot to ask again, or allow it in Android's app settings.")
    return
  elseif s == -2 then
    message(r, "No " .. (st.facing == 1 and "front" or "rear") .. " camera", "Try the other camera.")
    return
  elseif type(s) == "number" and s < 0 then
    message(r, "The camera couldn't start", "It may be in use by another app. Tap Shoot to try again.")
    return
  end
  lg.setColor(0, 0, 0, 1)
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  lg.setColor(1, 1, 1, 1)
  if not drawFrame(r.x, r.y, r.w, r.h, st.zoom) then
    local f = ctx.font(r.h * 0.06)
    lg.setFont(f)
    lg.setColor(1, 1, 1, 0.7)
    lg.printf("Starting the camera...", r.x, r.y + r.h / 2 - f:getHeight() / 2, r.w, "center")
  end
  if st.grid then
    lg.setColor(1, 1, 1, 0.35)
    for k = 1, 2 do
      lg.rectangle("fill", r.x + r.w * k / 3, r.y, 1, r.h)
      lg.rectangle("fill", r.x, r.y + r.h * k / 3, r.w, 1)
    end
  end
  -- the corner brackets: white; yellow counting down; green as it shoots;
  -- red while a video records
  local color = { 255, 255, 255, 220 }
  if recording() then color = { 235, 70, 60 } end
  if st.timerAt then color = { 250, 214, 60 } end
  if st.t - st.flash < 0.5 then color = { 70, 210, 90 } end
  local m = r.h * 0.12
  brackets(r.x + m * 1.6, r.y + m, r.w - m * 3.2, r.h - m * 2, color, r.h * 0.1)
  if st.timerAt then
    local left = math.ceil(st.timerAt - st.t)
    local f = ctx.font(r.h * 0.3)
    lg.setFont(f)
    lg.setColor(0, 0, 0, 0.35)
    lg.printf(tostring(left), r.x + 3, r.y + r.h / 2 - f:getHeight() / 2 + 3, r.w, "center")
    lg.setColor(1, 0.86, 0.3, 1)
    lg.printf(tostring(left), r.x, r.y + r.h / 2 - f:getHeight() / 2, r.w, "center")
  end
  if recording() then
    local secs = math.floor(st.t - st.rec.t0)
    local f = ctx.font(r.h * 0.06)
    lg.setFont(f)
    local label = ("REC  %d:%02d"):format(math.floor(secs / 60), secs % 60)
    local w = f:getWidth(label) + f:getHeight() * 1.6
    lg.setColor(0, 0, 0, 0.45)
    rrect("fill", r.x + r.w - w - r.h * 0.03, r.y + r.h * 0.03, w, f:getHeight() * 1.3, f:getHeight() * 0.3)
    if math.floor(st.t * 2) % 2 == 0 then
      lg.setColor(0.95, 0.2, 0.15, 1)
      lg.circle("fill", r.x + r.w - w - r.h * 0.03 + f:getHeight() * 0.7, r.y + r.h * 0.03 + f:getHeight() * 0.65, f:getHeight() * 0.28)
    end
    lg.setColor(1, 1, 1, 1)
    lg.print(label, r.x + r.w - w - r.h * 0.03 + f:getHeight() * 1.2, r.y + r.h * 0.03 + f:getHeight() * 0.15)
  end
  if st.filter ~= "none" then
    local f = ctx.font(r.h * 0.045)
    lg.setFont(f)
    local label = Filters.get(st.filter).name
    local w = f:getWidth(label) + f:getHeight()
    lg.setColor(0, 0, 0, 0.4)
    rrect("fill", r.x + r.h * 0.03, r.y + r.h - f:getHeight() * 1.4 - r.h * 0.03, w, f:getHeight() * 1.4, f:getHeight() * 0.3)
    lg.setColor(1, 1, 1, 0.95)
    lg.print(label, r.x + r.h * 0.03 + f:getHeight() * 0.5, r.y + r.h - f:getHeight() * 1.2 - r.h * 0.03)
  end
  if st.multi then
    local f = ctx.font(r.h * 0.06)
    lg.setFont(f)
    lg.setColor(1, 1, 1, 0.9)
    lg.printf(("%d / 4"):format(#st.multi.shots + 1), r.x, r.y + r.h * 0.03, r.w - r.h * 0.04, "right")
  end
  -- the shutter's white flash
  local fl = st.t - st.flash
  if fl < 0.25 then
    lg.setColor(1, 1, 1, (0.25 - fl) / 0.25 * 0.85)
    lg.rectangle("fill", r.x, r.y, r.w, r.h)
  end
end

local function drawAlbumTop(r)
  lg.setColor(0.08, 0.08, 0.1, 1)
  lg.rectangle("fill", r.x, r.y, r.w, r.h)
  local list = st.photos or listPhotos()
  local item = list[st.sel]
  if not item then
    local f = ctx.font(r.h * 0.06)
    lg.setFont(f)
    lg.setColor(1, 1, 1, 0.7)
    lg.printf("No pictures or videos", r.x, r.y + r.h / 2 - f:getHeight() / 2, r.w, "center")
    return
  end
  if st.fullName ~= item.path then
    if st.full then st.full:release() end
    local ok, img = pcall(lg.newImage, item.path)
    st.full, st.fullName = ok and img or nil, item.path
    if st.full then st.full:setFilter("linear", "linear") end
  end
  if st.full then
    local w, h = st.full:getDimensions()
    local s = math.min(r.w / w, r.h / h)
    lg.setColor(1, 1, 1, 1)
    lg.draw(st.full, r.x + (r.w - w * s) / 2, r.y + (r.h - h * s) / 2, 0, s, s)
  end
  local f = ctx.font(r.h * 0.05)
  if item.video then
    -- a video: its first frame, a play button, and how to play it
    local ps = r.h * 0.26
    lg.setColor(0, 0, 0, 0.45)
    lg.circle("fill", r.x + r.w / 2, r.y + r.h / 2, ps * 0.62)
    lg.setColor(1, 1, 1, 0.95)
    G.play(r.x + r.w / 2 - ps / 2, r.y + r.h / 2 - ps / 2, ps)
    lg.setFont(f)
    lg.setColor(0, 0, 0, 0.45)
    lg.rectangle("fill", r.x, r.y + r.h - f:getHeight() * 1.5, r.w, f:getHeight() * 1.5)
    lg.setColor(1, 1, 1, 1)
    lg.printf("A: play in the phone's video player", r.x, r.y + r.h - f:getHeight() * 1.25, r.w, "center")
  end
  lg.setFont(f)
  lg.setColor(0, 0, 0, 0.45)
  lg.rectangle("fill", r.x, r.y, r.w, f:getHeight() * 1.4)
  lg.setColor(1, 1, 1, 1)
  lg.print(item.name, r.x + r.h * 0.03, r.y + f:getHeight() * 0.2)
  lg.printf(("%d / %d"):format(st.sel, #list), r.x, r.y + f:getHeight() * 0.2, r.w - r.h * 0.03, "right")
end

function C.drawTop(r)
  lg.push("all")
  lg.setScissor(r.x, r.y, r.w, r.h)
  -- shots waiting to be taken are taken here, with the frame on screen
  st.topAspect = r.w / r.h
  while st.captures > 0 do
    st.captures = st.captures - 1
    takeShot(r.w / r.h)
  end
  if st.view ~= "photos" then recordFrame() end
  if st.view == "photos" then drawAlbumTop(r) else drawViewfinder(r) end
  drawToast(r)
  lg.pop()
end

---------------------------------------------------------------- input

local function setView(v)
  if st.view == v then return end
  if v == "photos" then stopRecording() end
  st.view = v
  st.confirmDelete = nil
  if v == "photos" then listPhotos(); st.page = math.floor((st.sel - 1) / PER_PAGE) + 1 end
  Sfx.play("select")
end

local function flip()
  stopRecording()
  st.facing = 1 - st.facing
  saveCfg()
  st.zoom = 1
  startCamera()
  Sfx.play("button")
  toast(st.facing == 1 and "Front camera" or "Rear camera")
end

local function zoom(dir)
  local z = clamp(st.zoom + dir * 0.5, 1, ZOOM_MAX)
  if z == st.zoom then Sfx.play("noMove") return end
  st.zoom = z
  Sfx.play(dir > 0 and "zoomIn" or "zoomOut")
end

local function pick(i)
  local n = #(st.photos or {})
  if n == 0 then return end
  i = clamp(i, 1, n)
  if i ~= st.sel then Sfx.play("over") end
  st.sel = i
  st.page = math.floor((i - 1) / PER_PAGE) + 1
  st.confirmDelete = nil
end

local function deletePhoto()
  local item = (st.photos or {})[st.sel]
  if not item then return end
  if st.confirmDelete ~= item.path then
    st.confirmDelete = item.path
    Sfx.play("dialog")
    toast("Tap the bin again to delete " .. item.name)
    return
  end
  love.filesystem.remove(item.path)
  if item.video then
    love.filesystem.remove(item.mp4)
    love.filesystem.remove(item.uriPath)
  end
  st.thumbs[item.path] = nil
  if st.fullName == item.path then st.fullName = nil end
  st.confirmDelete = nil
  listPhotos()
  Sfx.play("cancel")
  toast(item.video and "Deleted (the gallery copy stays)" or "Deleted")
end

-- a video plays in the phone's own player, from its gallery copy
local function playVideo(item)
  local ok, uri = pcall(love.filesystem.read, item.uriPath)
  if ok and type(uri) == "string" and uri:match("^content://") and love.system and love.system.openURL then
    Sfx.play("open")
    love.system.openURL(uri)
  else
    toast("Turn on Copy to phone gallery to play videos")
    Sfx.play("noMove")
  end
end

local function activate(id)
  if id == "back" then
    if st.view ~= "camera" then setView("camera") return end
    return "exit"
  elseif id:match("^view:") then
    setView(id:sub(6))
  elseif id == "shoot" then
    shoot()
  elseif id == "photos" then
    setView("photos")
  elseif id == "settings" then
    setView("settings")
  elseif id == "flip" then
    flip()
  elseif id == "zoomIn" then
    zoom(1)
  elseif id == "zoomOut" then
    zoom(-1)
  elseif id:match("^mode:") then
    if id ~= "mode:video" then stopRecording() end
    st.mode = id:sub(6)
    st.multi, st.timerAt = nil, nil
    saveCfg()
    Sfx.play("button")
  elseif id:match("^photo:") then
    local i = tonumber(id:sub(7))
    local item = (st.photos or {})[i]
    if i ~= st.sel then pick(i)
    elseif item and item.video then playVideo(item)
    else setView("camera") end
  elseif id == "pagePrev" or id == "pageNext" then
    local p = clamp(st.page + (id == "pageNext" and 1 or -1), 1, pages())
    if p == st.page then Sfx.play("edge") else Sfx.play("strip") end
    st.page = p
    pick((p - 1) * PER_PAGE + 1)
  elseif id == "info" then
    local item = (st.photos or {})[st.sel]
    if item then
      local when = item.time > 0 and os.date("%Y/%m/%d %H:%M", item.time) or ""
      toast(("%s  %s  %d KB"):format(item.name, when, math.floor(item.size / 1024)))
      Sfx.play("dialog")
    end
  elseif id == "delete" then
    deletePhoto()
  elseif id == "set:facing" then
    flip()
  elseif id == "filterNext" or id == "set:filter" then
    setFilter(Filters.step(st.filter, 1))
  elseif id == "filterPrev" then
    setFilter(Filters.step(st.filter, -1))
  elseif id == "set:sound" then
    st.sound = not st.sound; saveCfg(); Sfx.play(st.sound and "on" or "off")
  elseif id == "set:grid" then
    st.grid = not st.grid; saveCfg(); Sfx.play(st.grid and "on" or "off")
  elseif id == "set:gallery" then
    st.gallery = not st.gallery; saveCfg(); Sfx.play(st.gallery and "on" or "off")
  end
end

local function hitAt(x, y)
  for k = #st.hits, 1, -1 do
    local h = st.hits[k]
    if h.round then
      local cx, cy, rad = h.x + h.w / 2, h.y + h.h / 2, h.w / 2
      if (x - cx) ^ 2 + (y - cy) ^ 2 <= rad * rad then return h end
    elseif x >= h.x and y >= h.y and x <= h.x + h.w and y <= h.y + h.h then
      return h
    end
  end
  return nil
end

-- touches: a press on a control, released on it, activates it; in Photos a
-- swipe turns the page.  Returns "exit" when the applet should close.
function C.pressed(id, x, y)
  local h = hitAt(x, y)
  st.touches[id] = { x0 = x, y0 = y, x = x, y = y, hit = h and h.id }
  st.down = h and h.id or nil
end

function C.moved(id, x, y)
  local t = st.touches[id]
  if not t then return end
  t.x, t.y = x, y
  local h = hitAt(x, y)
  st.down = (h and h.id == t.hit) and t.hit or nil
end

function C.released(id, x, y)
  local t = st.touches[id]
  st.touches[id] = nil
  st.down = nil
  if not t then return end
  if st.view == "photos" and math.abs(x - t.x0) > 60 and math.abs(x - t.x0) > math.abs(y - t.y0) then
    return activate(x < t.x0 and "pageNext" or "pagePrev")
  end
  local h = hitAt(x, y)
  if h and h.id == t.hit then return activate(h.id) end
end

-- the shell's buttons; returns "exit" to close
function C.button(name)
  if name == "home" then return "exit" end
  if name == "b" then return activate("back") end
  if st.view == "camera" then
    if name == "a" or name == "l" or name == "r" or name == "zl" or name == "zr" then shoot()
    elseif name == "x" then flip()
    elseif name == "y" then setView("photos")
    elseif name == "up" then zoom(1)
    elseif name == "down" then zoom(-1)
    elseif name == "left" then setFilter(Filters.step(st.filter, -1))
    elseif name == "right" then setFilter(Filters.step(st.filter, 1))
    end
  elseif st.view == "photos" then
    if name == "left" then pick(st.sel - 1)
    elseif name == "right" then pick(st.sel + 1)
    elseif name == "up" then pick(st.sel - 5)
    elseif name == "down" then pick(st.sel + 5)
    elseif name == "a" then
      local item = (st.photos or {})[st.sel]
      if item and item.video then playVideo(item) else setView("camera") end
    elseif name == "y" then setView("camera")
    elseif name == "x" then deletePhoto()
    elseif name == "l" then activate("pagePrev")
    elseif name == "r" then activate("pageNext")
    end
  elseif st.view == "settings" then
    if name == "y" then setView("photos") end
  end
end

---------------------------------------------------------------- life

function C.init(context)
  ctx = context
  loadCfg()
end

function C.isOpen() return st.open end

function C.open()
  st.open = true
  st.view = "camera"
  st.zoom = 1
  st.captures, st.timerAt, st.multi = 0, nil, nil
  listPhotos()
  startCamera()
  Sfx.play("open")
end

function C.close()
  if not st.open then return end
  stopRecording()
  st.open = false
  stopCamera()
  st.data, st.image, st.info = nil, nil, nil
  st.touches, st.down = {}, nil
  if st.full then st.full:release() st.full, st.fullName = nil, nil end
  Sfx.play("back")
end

-- every frame; `showing` is false while the phone is folded (the camera
-- rests until it opens again)
function C.update(dt, showing)
  st.t = st.t + (dt or 0)
  if not st.open then return end
  if not showing then
    stopRecording()
    if st.camState ~= 0 and st.camState ~= "none" then stopCamera(); st.paused = true end
    return
  end
  if st.paused then st.paused = false; startCamera() end
  local f = api()
  if f and type(st.camState) == "number" then
    local ok, s = pcall(f, "state")
    if ok and s then st.camState = s end
    -- the system took the camera away (another app, a pause): ask again
    if st.camState == 0 and st.t >= st.retryAt then
      st.retryAt = st.t + 1
      startCamera()
    end
  end
  if st.camState == 3 then pullFrame() end
  -- the self-timer
  if st.timerAt then
    local left = math.ceil(st.timerAt - st.t)
    if left < st.timerBeep and left > 0 then st.timerBeep = left; beep("beep") end
    if st.t >= st.timerAt then
      st.timerAt = nil
      st.captures = st.captures + 1
    end
  end
  -- the rest of a Multi's four shots
  if st.multi and st.multi.next and st.t >= st.multi.next then
    st.multi.next = nil
    st.captures = st.captures + 1
  end
end

return C
