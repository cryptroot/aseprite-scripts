-- focus_lines.lua
-- Manga "concentration / focus lines" (集中線, shūchūsen): straight emphasis
-- lines that radiate from the frame edges INWARD toward a focal point, leaving a
-- clear elliptical hole around the subject. They imply a sudden rush forward —
-- the subject lunging toward the viewer / away from the camera.
--
-- Lines start at the rim of the clear zone and taper to fine points as they
-- converge, thick where they meet the frame border. Angle, length and width are
-- jittered so the burst looks hand-drawn rather than mechanical.
--
-- Pairs with motion.lua (running smear) and vibration_lines.lua (trembling).

local sprite = app.sprite
if not sprite then
  app.alert("No active sprite!")
  return
end

local layer = app.layer
if not layer then
  app.alert("No active layer!")
  return
end

if not layer.isEditable then
  app.alert("The active layer is not editable (it may be locked or hidden).")
  return
end

if sprite.colorMode ~= ColorMode.RGB then
  app.alert("Focus Lines requires an RGB color mode sprite.")
  return
end

local W, H = sprite.width, sprite.height

-- Default the focal point to the active selection's center, else the canvas center.
local sel       = sprite.selection
local hasSel    = sel and not sel.isEmpty
local fb        = hasSel and sel.bounds or Rectangle(0, 0, W, H)
local defFocusX = math.floor(fb.x + fb.width / 2 + 0.5)
local defFocusY = math.floor(fb.y + fb.height / 2 + 0.5)

-- ── Dialog ──────────────────────────────────────────────────────────────────
local dlg = Dialog("Focus Lines")

dlg:color { id = "color", label = "Line Color:", color = Color { r = 0, g = 0, b = 0, a = 255 } }

dlg:separator { text = "Focus" }
dlg:number { id = "fx",    label = "Focus X:", text = tostring(defFocusX), decimals = 0 }
dlg:number { id = "fy",    label = "Focus Y:", text = tostring(defFocusY), decimals = 0 }
dlg:slider { id = "clear", label = "Clear zone (%):", min = 0, max = 90, value = 25 }

dlg:separator { text = "Lines" }
dlg:slider { id = "count", label = "Line count:",   min = 30, max = 600, value = 200 }
dlg:slider { id = "width", label = "Line width (px):", min = 1, max = 12, value = 3 }
dlg:combobox {
  id      = "taper",
  label   = "Taper:",
  option  = "Point inward (thick edge)",
  options = { "Point inward (thick edge)", "Point outward (thick center)", "Uniform" }
}
dlg:slider  { id = "irregular", label = "Irregularity (%):", min = 0, max = 100, value = 50 }
dlg:number  { id = "seed",      label = "Seed:", text = "42", decimals = 0 }

dlg:separator { text = "Outline (optional)" }
dlg:check  { id = "useOutline",   label = "Outline:", text = "Outline each line", selected = false }
dlg:color  { id = "outlineColor", label = "Outline Color:", color = Color { r = 255, g = 255, b = 255, a = 255 } }
dlg:slider { id = "outlineWidth", label = "Outline width (px):", min = 1, max = 4, value = 1 }

dlg:separator { text = "Softness" }
dlg:slider { id = "blur", label = "Blur (px):", min = 0, max = 8, value = 0 }

dlg:separator { text = "Placement" }
dlg:combobox {
  id      = "placement",
  label   = "Draw on:",
  option  = "New layer (above)",
  options = { "New layer (above)", "New layer (below)", "Current layer" }
}

dlg:separator()
dlg:button { id = "ok",     text = "Apply", focus = true }
dlg:button { id = "cancel", text = "Cancel" }

dlg:show()
local data = dlg.data
if not data.ok then return end

-- ── Parameters ──────────────────────────────────────────────────────────────
local lineColor = data.color
local clearFrac = data.clear / 100.0
local count     = data.count
local lineWidth = data.width
local taper     = data.taper
local irr       = data.irregular / 100.0
local seed      = math.floor(data.seed or 42)
local useOutline   = data.useOutline
local outlineColor = data.outlineColor
local outlineWidth = data.outlineWidth
local blurAmount   = data.blur
local placement = data.placement

-- ── Helpers ─────────────────────────────────────────────────────────────────
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function iround(v) return math.floor(v + 0.5) end

local function makeRng(s)
  s = s % (2 ^ 32)
  if s == 0 then s = 1 end
  return function()
    s = (s * 1664525 + 1013904223) % (2 ^ 32)
    return s / (2 ^ 32)
  end
end
local rng = makeRng(seed)
local function srand() return rng() * 2 - 1 end -- -1..1

local pc    = app.pixelColor
local colPV        = pc.rgba(lineColor.red, lineColor.green, lineColor.blue, lineColor.alpha)
local outlineColPV = pc.rgba(outlineColor.red, outlineColor.green, outlineColor.blue, outlineColor.alpha)

-- Focal point, kept inside the canvas so the outward rays always hit a border.
local fx = clamp(data.fx, 0, W)
local fy = clamp(data.fy, 0, H)

-- Clear-zone ellipse radii (scaled to the canvas).
local cax = (W / 2) * clearFrac
local cay = (H / 2) * clearFrac

-- ── Output images + primitives ────────────────────────────────────
-- The line core and its outline are drawn into separate images so the outline
-- can taper WITH the line and sit cleanly underneath the core.
local lineImg = Image(sprite.spec)
lineImg:clear()
local outlineImg
if useOutline then
  outlineImg = Image(sprite.spec)
  outlineImg:clear()
end

local function stampDisk(img, cx, cy, r, colPV)
  if r <= 0 then
    if cx >= 0 and cy >= 0 and cx < W and cy < H then img:drawPixel(cx, cy, colPV) end
    return
  end
  local ri = math.ceil(r)
  local r2 = r * r + 0.25
  for dy = -ri, ri do
    for dx = -ri, ri do
      if dx * dx + dy * dy <= r2 then
        local nx, ny = cx + dx, cy + dy
        if nx >= 0 and ny >= 0 and nx < W and ny < H then img:drawPixel(nx, ny, colPV) end
      end
    end
  end
end

-- Radius of the clear ellipse along a given unit direction.
local function innerRadius(cosA, sinA)
  if cax <= 0 or cay <= 0 then return 0 end
  local nx, ny = cosA / cax, sinA / cay
  local d = math.sqrt(nx * nx + ny * ny)
  if d <= 0 then return 0 end
  return 1 / d
end

-- Distance from the focus to the canvas border along a unit direction.
local function exitDist(cosA, sinA)
  local tx, ty
  if cosA > 1e-9 then tx = (W - fx) / cosA
  elseif cosA < -1e-9 then tx = -fx / cosA
  else tx = math.huge end
  if sinA > 1e-9 then ty = (H - fy) / sinA
  elseif sinA < -1e-9 then ty = -fy / sinA
  else ty = math.huge end
  return math.min(tx, ty)
end

-- ── Draw the burst ──────────────────────────────────────────────────────────
local step = (2 * math.pi) / count

for i = 0, count - 1 do
  local jr = srand() * 0.6 * irr        -- inner-radius jitter (ragged hole)
  local jw = srand() * 0.4 * irr        -- width jitter
  local ja = srand() * 0.5 * irr * step -- angular jitter

  local angle = i * step + ja
  local cosA, sinA = math.cos(angle), math.sin(angle)

  local inR  = math.max(0, innerRadius(cosA, sinA) * (1 + jr))
  local outT = exitDist(cosA, sinA)

  if outT > inR + 0.5 then
    local ix, iy = fx + cosA * inR, fy + sinA * inR
    local ox, oy = fx + cosA * outT, fy + sinA * outT
    local edgeR  = math.max(0, (lineWidth * (1 + jw) - 1) / 2)
    local steps  = math.max(1, math.ceil(outT - inR))
    -- Outline radius scales WITH the line radius, so the border is widest at the
    -- thick part (outlineWidth there) and tapers to nothing at the point, keeping
    -- the tip line-colored instead of collapsing into the outline color.
    local oScale = useOutline and ((edgeR + outlineWidth) / math.max(edgeR, 0.5)) or 1

    for s = 0, steps do
      local t = s / steps
      local rr
      if taper == "Point inward (thick edge)" then
        rr = edgeR * t
      elseif taper == "Point outward (thick center)" then
        rr = edgeR * (1 - t)
      else
        rr = edgeR
      end
      local px, py = iround(ix + (ox - ix) * t), iround(iy + (oy - iy) * t)
      if outlineImg then stampDisk(outlineImg, px, py, rr * oScale, outlineColPV) end
      stampDisk(lineImg, px, py, rr, colPV)
    end
  end
end

-- ── Optional blur ───────────────────────────────────────────────────────────
-- Blur: separable box blur (run twice) in premultiplied-alpha space so the line
-- and outline colors soften into a glow without dark halos.
local function boxBlurRGBA(img, radius)
  if radius < 1 then return end
  local w, h = img.width, img.height
  local pr, pg, pb, pa = {}, {}, {}, {}
  for y = 0, h - 1 do
    local base = y * w
    for x = 0, w - 1 do
      local v   = img:getPixel(x, y)
      local a   = pc.rgbaA(v)
      local f   = a / 255
      local idx = base + x + 1
      pr[idx] = pc.rgbaR(v) * f
      pg[idx] = pc.rgbaG(v) * f
      pb[idx] = pc.rgbaB(v) * f
      pa[idx] = a
    end
  end
  local win = radius * 2 + 1
  local tmp = {}
  local function blurChannel(src)
    for _ = 1, 2 do
      for y = 0, h - 1 do
        local base = y * w
        local sum  = 0
        for k = -radius, radius do sum = sum + src[base + clamp(k, 0, w - 1) + 1] end
        for x = 0, w - 1 do
          tmp[base + x + 1] = sum / win
          sum = sum - src[base + clamp(x - radius, 0, w - 1) + 1]
                    + src[base + clamp(x + radius + 1, 0, w - 1) + 1]
        end
      end
      for x = 0, w - 1 do
        local sum = 0
        for k = -radius, radius do sum = sum + tmp[clamp(k, 0, h - 1) * w + x + 1] end
        for y = 0, h - 1 do
          src[y * w + x + 1] = sum / win
          sum = sum - tmp[clamp(y - radius, 0, h - 1) * w + x + 1]
                    + tmp[clamp(y + radius + 1, 0, h - 1) * w + x + 1]
        end
      end
    end
  end
  blurChannel(pr); blurChannel(pg); blurChannel(pb); blurChannel(pa)
  for y = 0, h - 1 do
    local base = y * w
    for x = 0, w - 1 do
      local idx = base + x + 1
      local a   = pa[idx]
      local ai  = clamp(iround(a), 0, 255)
      if ai > 0 then
        local f = 255 / a
        img:drawPixel(x, y, pc.rgba(
          clamp(iround(pr[idx] * f), 0, 255),
          clamp(iround(pg[idx] * f), 0, 255),
          clamp(iround(pb[idx] * f), 0, 255),
          ai))
      else
        img:drawPixel(x, y, pc.rgba(0, 0, 0, 0))
      end
    end
  end
end

-- Compose the outline underneath the line core, then soften everything. Both
-- shapes share the same taper, so the border fades to nothing at the point and
-- the tip keeps the line color instead of turning into the outline color.
local out = Image(sprite.spec)
out:clear()
if outlineImg then out:drawImage(outlineImg, Point(0, 0), 255, BlendMode.NORMAL) end
out:drawImage(lineImg, Point(0, 0), 255, BlendMode.NORMAL)
boxBlurRGBA(out, blurAmount)

-- ── Commit as a single undoable action ──────────────────────────────────────
local srcIndex = layer.stackIndex
local cel      = app.cel

app.transaction("Focus Lines", function()
  if placement == "Current layer" then
    -- Composite the lines ON TOP of the existing art on this layer.
    local base = Image(sprite.spec)
    base:clear()
    if cel then base:drawImage(cel.image, cel.position, 255, BlendMode.NORMAL) end
    base:drawImage(out, Point(0, 0), 255, BlendMode.NORMAL)
    sprite:newCel(layer, app.frame, base, Point(0, 0))
  else
    local fLayer = sprite:newLayer()
    fLayer.name  = layer.name .. " Focus"
    if placement == "New layer (below)" then
      fLayer.stackIndex = srcIndex     -- directly below the source layer
    else
      fLayer.stackIndex = srcIndex + 1 -- directly above the source layer
    end
    sprite:newCel(fLayer, app.frame, out, Point(0, 0))
  end
end)

app.refresh()
