-- vibration_lines.lua
-- Draws the curved "emphasis / vibration lines" that anime & manga use to imply
-- that an object is shaking, trembling or surprised — a form of *manpu* (漫符).
-- These are the white parenthesis-like arcs that bracket a head/object, e.g.
--   ( ( (  o_o  ) ) )
--
-- The script finds the silhouette of the artwork on the active cel and lays
-- nested arcs just outside it. The arcs HUG the contour (so they curve around a
-- head) and bow outward in the middle for the classic vibration look.
--
-- Pairs well with motion.lua: use motion.lua for the running smear and this for
-- the trembling/surprise emphasis lines.

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
  app.alert("Vibration Lines requires an RGB color mode sprite.")
  return
end

local cel = app.cel
if not cel then
  app.alert("No active cel! Make sure the posed character is on the active layer and frame.")
  return
end

local srcImage = cel.image
if srcImage.width == 0 or srcImage.height == 0 then
  app.alert("The active cel is empty.")
  return
end

-- ── Dialog ──────────────────────────────────────────────────────────────────
local dlg = Dialog("Vibration Lines")

dlg:color { id = "color", label = "Line Color:", color = Color { r = 255, g = 255, b = 255, a = 255 } }

dlg:check  { id = "useBacking", label = "Backing:",            text = "2nd colour underneath", selected = false }
dlg:color  { id = "backColor",  label = "Backing Color:",      color = Color { r = 0, g = 0, b = 0, a = 255 } }
dlg:slider { id = "backWidth",  label = "Backing Offset (px):", min = 1, max = 8, value = 2 }

dlg:combobox {
  id      = "sides",
  label   = "Sides:",
  option  = "Left & Right (shake)",
  options = { "Left & Right (shake)", "Top & Bottom (nod)", "All around (surprise)" }
}

dlg:separator { text = "Arcs" }
dlg:slider { id = "lines",     label = "Lines per side:",   min = 1,  max = 6,  value = 3 }
dlg:slider { id = "gap",       label = "Gap from art (px):", min = 0, max = 32, value = 3 }
dlg:slider { id = "spacing",   label = "Line spacing (px):", min = 1, max = 16, value = 3 }
dlg:slider { id = "coverage",  label = "Length (%):",        min = 20, max = 100, value = 60 }
dlg:slider { id = "curvature", label = "Curvature (px):",    min = 0,  max = 32, value = 6 }
dlg:slider { id = "thickness", label = "Thickness (px):",    min = 1,  max = 6,  value = 1 }
dlg:check  { id = "shorten",   label = "Outer lines:", text = "Shorten outer arcs", selected = true }

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
local useBacking = data.useBacking
local backColor  = data.backColor
local backWidth  = data.backWidth
local sides     = data.sides
local numLines  = data.lines
local gap       = data.gap
local spacing   = data.spacing
local coverage  = data.coverage / 100.0
local curvature = data.curvature
local thickness = data.thickness
local shorten   = data.shorten
local blurAmount = data.blur
local placement = data.placement

local doL = (sides ~= "Top & Bottom (nod)")
local doR = (sides ~= "Top & Bottom (nod)")
local doT = (sides ~= "Left & Right (shake)")
local doB = (sides ~= "Left & Right (shake)")
if sides == "Top & Bottom (nod)" then doL, doR = false, false end
if sides == "Left & Right (shake)" then doT, doB = false, false end

-- ── Helpers ─────────────────────────────────────────────────────────────────
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function iround(v) return math.floor(v + 0.5) end

local pc          = app.pixelColor
local colPV       = pc.rgba(lineColor.red, lineColor.green, lineColor.blue, lineColor.alpha)
local radius      = math.floor(thickness / 2)
local W, H        = sprite.width, sprite.height
local ALPHA_THRESH = 32

-- ── Silhouette scan (sprite coordinates) ────────────────────────────────────
local sw, sh   = srcImage.width, srcImage.height
local px0, py0 = cel.position.x, cel.position.y
local rowL, rowR = {}, {} -- leftmost / rightmost opaque sprite-X, keyed by sprite-Y
local colT, colB = {}, {} -- topmost / bottommost opaque sprite-Y, keyed by sprite-X
local minX, minY = math.huge, math.huge
local maxX, maxY = -math.huge, -math.huge

for iy = 0, sh - 1 do
  local sy = py0 + iy
  for ix = 0, sw - 1 do
    local a = pc.rgbaA(srcImage:getPixel(ix, iy))
    if a > ALPHA_THRESH then
      local sx = px0 + ix
      if rowL[sy] == nil or sx < rowL[sy] then rowL[sy] = sx end
      if rowR[sy] == nil or sx > rowR[sy] then rowR[sy] = sx end
      if colT[sx] == nil or sy < colT[sx] then colT[sx] = sy end
      if colB[sx] == nil or sy > colB[sx] then colB[sx] = sy end
      if sx < minX then minX = sx end
      if sx > maxX then maxX = sx end
      if sy < minY then minY = sy end
      if sy > maxY then maxY = sy end
    end
  end
end

if minX == math.huge then
  app.alert("The active cel has no visible pixels.")
  return
end

local cx   = (minX + maxX) / 2
local cy   = (minY + maxY) / 2
local objW = maxX - minX + 1
local objH = maxY - minY + 1

-- Smoothed contour lookups (window of ±2, pushed outward to convexify).
local function edgeRight(y)
  local best for d = -2, 2 do local v = rowR[y + d] if v and (not best or v > best) then best = v end end return best
end
local function edgeLeft(y)
  local best for d = -2, 2 do local v = rowL[y + d] if v and (not best or v < best) then best = v end end return best
end
local function edgeTop(x)
  local best for d = -2, 2 do local v = colT[x + d] if v and (not best or v < best) then best = v end end return best
end
local function edgeBottom(x)
  local best for d = -2, 2 do local v = colB[x + d] if v and (not best or v > best) then best = v end end return best
end

-- ── Drawing primitives (target image + colour aware) ────────────────────────
local function putPixel(img, x, y, col)
  if x >= 0 and y >= 0 and x < W and y < H then img:drawPixel(x, y, col) end
end

local function stampDisk(img, x, y, r, col)
  if r <= 0 then putPixel(img, x, y, col) return end
  local r2 = r * r + 0.5
  for dy = -r, r do
    for dx = -r, r do
      if dx * dx + dy * dy <= r2 then putPixel(img, x + dx, y + dy, col) end
    end
  end
end

local function thickLine(img, x0, y0, x1, y1, r, col)
  local dx, dy = x1 - x0, y1 - y0
  local steps  = math.max(math.abs(dx), math.abs(dy))
  if steps == 0 then stampDisk(img, x0, y0, r, col) return end
  for s = 0, steps do
    local t = s / steps
    stampDisk(img, iround(x0 + dx * t), iround(y0 + dy * t), r, col)
  end
end

-- ── Arc drawers ─────────────────────────────────────────────────────────────
-- A "vertical" arc runs down one side (left/right); a "horizontal" arc runs
-- across the top/bottom. `dir` = +1 pushes the arc outward (right/down), -1
-- pushes it inward (left/up). The middle of each arc bows out by `curvature`.

local function drawVerticalArc(img, r, col, offset, k, isRight)
  local cov      = coverage * (shorten and (1 - k * 0.18) or 1)
  cov            = clamp(cov, 0.15, 1.0)
  local halfSpan = math.max((objH / 2) * cov, 1)
  local yTop     = clamp(iround(cy - halfSpan), minY, maxY)
  local yBot     = clamp(iround(cy + halfSpan), minY, maxY)
  local dir      = isRight and 1 or -1
  local prevX, prevY
  for y = yTop, yBot do
    local e = isRight and edgeRight(y) or edgeLeft(y)
    if e then
      local p   = (y - cy) / halfSpan
      local bow = math.max(0, 1 - p * p)
      local x   = iround(e + dir * (gap + k * spacing + curvature * bow + offset))
      if prevX then thickLine(img, prevX, prevY, x, y, r, col) else stampDisk(img, x, y, r, col) end
      prevX, prevY = x, y
    else
      prevX, prevY = nil, nil -- break the stroke across silhouette gaps
    end
  end
end

local function drawHorizontalArc(img, r, col, offset, k, isBottom)
  local cov      = coverage * (shorten and (1 - k * 0.18) or 1)
  cov            = clamp(cov, 0.15, 1.0)
  local halfSpan = math.max((objW / 2) * cov, 1)
  local xL       = clamp(iround(cx - halfSpan), minX, maxX)
  local xR       = clamp(iround(cx + halfSpan), minX, maxX)
  local dir      = isBottom and 1 or -1
  local prevX, prevY
  for x = xL, xR do
    local e = isBottom and edgeBottom(x) or edgeTop(x)
    if e then
      local p   = (x - cx) / halfSpan
      local bow = math.max(0, 1 - p * p)
      local y   = iround(e + dir * (gap + k * spacing + curvature * bow + offset))
      if prevX then thickLine(img, prevX, prevY, x, y, r, col) else stampDisk(img, x, y, r, col) end
      prevX, prevY = x, y
    else
      prevX, prevY = nil, nil
    end
  end
end

-- Render every arc (all enabled sides, all lines) into `img` at radius `r`.
-- `offset` shifts each arc along its outward axis: negative = inward (toward art).
local function renderArcs(img, r, col, offset)
  for k = 0, numLines - 1 do
    if doR then drawVerticalArc(img, r, col, offset, k, true) end
    if doL then drawVerticalArc(img, r, col, offset, k, false) end
    if doB then drawHorizontalArc(img, r, col, offset, k, true) end
    if doT then drawHorizontalArc(img, r, col, offset, k, false) end
  end
end

-- ── Optional blur ───────────────────────────────────────────────────────────
-- Softens the arcs into a glow. Each colour layer is blurred on its OWN alpha
-- coverage (the colour is uniform per layer, so there are no muddy mixed-colour
-- halos). A separable box blur run twice approximates a smooth Gaussian falloff.
local function applyBlur(img, col, radius)
  if radius < 1 then return end
  local win = radius * 2 + 1
  local cov = {}
  for y = 0, H - 1 do
    local base = y * W
    for x = 0, W - 1 do
      cov[base + x + 1] = (pc.rgbaA(img:getPixel(x, y)) > 0) and 1.0 or 0.0
    end
  end
  local tmp = {}
  for _ = 1, 2 do
    -- Horizontal pass (cov -> tmp), sliding-window sum with edge extension.
    for y = 0, H - 1 do
      local base = y * W
      local sum  = 0
      for k = -radius, radius do sum = sum + cov[base + clamp(k, 0, W - 1) + 1] end
      for x = 0, W - 1 do
        tmp[base + x + 1] = sum / win
        sum = sum - cov[base + clamp(x - radius, 0, W - 1) + 1]
                  + cov[base + clamp(x + radius + 1, 0, W - 1) + 1]
      end
    end
    -- Vertical pass (tmp -> cov).
    for x = 0, W - 1 do
      local sum = 0
      for k = -radius, radius do sum = sum + tmp[clamp(k, 0, H - 1) * W + x + 1] end
      for y = 0, H - 1 do
        cov[y * W + x + 1] = sum / win
        sum = sum - tmp[clamp(y - radius, 0, H - 1) * W + x + 1]
                  + tmp[clamp(y + radius + 1, 0, H - 1) * W + x + 1]
      end
    end
  end
  -- Rebuild the layer from the blurred coverage, modulated by its colour alpha.
  local lr, lg, lb, la = col.red, col.green, col.blue, col.alpha
  img:clear()
  for y = 0, H - 1 do
    local base = y * W
    for x = 0, W - 1 do
      local a = clamp(iround(cov[base + x + 1] * la), 0, 255)
      if a > 0 then img:drawPixel(x, y, pc.rgba(lr, lg, lb, a)) end
    end
  end
end

-- ── Build the final image: backing underneath, primary line on top ────────
local out = Image(sprite.spec)
out:clear()

if useBacking then
  -- The backing is the SAME line at the SAME thickness, offset INWARD (toward
  -- the art) by `backWidth`. So it only peeks out behind/underneath the primary
  -- line instead of ringing it as a halo (a full halo would blur to grey).
  local bImg = Image(sprite.spec)
  bImg:clear()
  local backPV = pc.rgba(backColor.red, backColor.green, backColor.blue, backColor.alpha)
  renderArcs(bImg, radius, backPV, -backWidth)
  applyBlur(bImg, backColor, blurAmount)
  out:drawImage(bImg, Point(0, 0), 255, BlendMode.NORMAL)
end

local pImg = Image(sprite.spec)
pImg:clear()
renderArcs(pImg, radius, colPV, 0)
applyBlur(pImg, lineColor, blurAmount)
out:drawImage(pImg, Point(0, 0), 255, BlendMode.NORMAL)

-- ── Commit as a single undoable action ──────────────────────────────────────
local srcIndex = layer.stackIndex

app.transaction("Vibration Lines", function()
  if placement == "Current layer" then
    -- Keep the art crisp on top of the surrounding lines, on the same layer.
    out:drawImage(srcImage, Point(px0, py0), 255, BlendMode.NORMAL)
    sprite:newCel(layer, app.frame, out, Point(0, 0))
  else
    local vLayer = sprite:newLayer()
    vLayer.name  = layer.name .. " Vibration"
    if placement == "New layer (below)" then
      vLayer.stackIndex = srcIndex     -- directly below the source layer
    else
      vLayer.stackIndex = srcIndex + 1 -- directly above the source layer
    end
    sprite:newCel(vLayer, app.frame, out, Point(0, 0))
  end
end)

app.refresh()
