-- fire_fill.lua
-- Fills the active cel with a procedural fire / flame effect.
-- Modes: Full Width (wall of fire), Torch (narrow column), Bonfire (wide mound).
-- Flames rise from the bottom; the envelope and colour are noise-driven.

local sprite = app.sprite
if not sprite then app.alert("No active sprite!") return end

local cel = app.cel
if not cel then app.alert("No active cel!") return end

if not app.layer.isEditable then
  app.alert("Layer is not editable.")
  return
end

if sprite.colorMode ~= ColorMode.RGB then
  app.alert("Fire Fill requires an RGB color mode sprite.")
  return
end

-- ── Dialog ──────────────────────────────────────────────────────────────────
local defaultSeed = math.floor(os.time())

local dlg = Dialog("Fire Fill")

dlg:combobox{
  id      = "mode",
  label   = "Mode:",
  option  = "Full Width",
  options = { "Full Width", "Torch", "Bonfire" },
  onchange = function()
    local isLocal = dlg.data.mode ~= "Full Width"
    dlg:modify{ id="originX",    visible=isLocal }
    dlg:modify{ id="flameWidth", visible=isLocal }
  end
}

dlg:color  { id="coreColor", label="Core Color:",      color=Color{ r=255, g=230, b=80,  a=255 } }
dlg:color  { id="midColor",  label="Mid Color:",        color=Color{ r=255, g=90,  b=10,  a=255 } }
dlg:color  { id="tipColor",  label="Tip Color:",        color=Color{ r=150, g=15,  b=0,   a=180 } }
dlg:slider { id="height",    label="Flame Height (%):", min=5,  max=100, value=70 }
dlg:number { id="seed",      label="Seed:",             text=tostring(defaultSeed), decimals=0 }

dlg:separator{ text="Flame Shape" }
dlg:slider { id="turbulence", label="Turbulence:",      min=1, max=10, value=4 }
dlg:slider { id="taper",      label="Tip Taper:",       min=1, max=10, value=4 }
dlg:slider { id="blockSize",  label="Block Size (px):", min=1, max=8,  value=1 }
dlg:check  { id="embers",     label="Embers:",          text="Floating embers", selected=true }
dlg:check  { id="outline",    label="Outline:",         text="Black outline",   selected=false }

dlg:separator{ text="Localized Flame" }
dlg:slider{ id="originX",    label="Origin X (%):",    min=0,  max=100, value=50, visible=false }
dlg:slider{ id="flameWidth", label="Flame Width (%):", min=1,  max=100, value=20, visible=false }

dlg:separator()
dlg:button { id="ok",     text="Apply", focus=true }
dlg:button { id="cancel", text="Cancel" }

dlg:show()

local data = dlg.data
if not data.ok then return end

-- ── Parameters ───────────────────────────────────────────────────────────────
local img = cel.image
local w   = img.width
local h   = img.height

local coreR = data.coreColor.red
local coreG = data.coreColor.green
local coreB = data.coreColor.blue

local midR = data.midColor.red
local midG = data.midColor.green
local midB = data.midColor.blue

local tipR = data.tipColor.red
local tipG = data.tipColor.green
local tipB = data.tipColor.blue
local tipA = data.tipColor.alpha

local mode        = data.mode
local flameHeight = data.height / 100.0
local turbulence  = data.turbulence
local taper       = data.taper
local seed        = math.floor(data.seed or defaultSeed)
local doEmbers    = data.embers
local blockSize   = math.max(1, math.floor(data.blockSize or 1))
local doOutline   = data.outline

-- Localized-mode parameters
-- originXPx: flame centre in pixels; halfWidthPx: base half-width in pixels.
-- spreadPow controls how quickly the flame narrows horizontally as it rises:
--   Torch  → 1.2 (tapers noticeably from base to tip)
--   Bonfire → 0.6 (stays wide at the base, pinches only near the top)
local isLocal    = (mode == "Torch" or mode == "Bonfire")
local originXPx  = isLocal and ((data.originX  / 100.0) * (w - 1)) or (w / 2)
local halfWidthPx
local spreadPow
if mode == "Torch" then
  halfWidthPx = math.max(1, (data.flameWidth / 100.0) * w * 0.5)
  spreadPow   = 1.2
elseif mode == "Bonfire" then
  halfWidthPx = math.max(1, (data.flameWidth / 100.0) * w * 0.5)
  spreadPow   = 0.6
else
  halfWidthPx = w
  spreadPow   = 1.0
end

-- ── Helpers ──────────────────────────────────────────────────────────────────
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function lerp(a, b, t)    return a + (b - a) * t end
local function smooth(t)        return t * t * (3 - 2 * t) end

-- ── Noise lattice ─────────────────────────────────────────────────────────────
-- Two independent 64×64 value-noise grids used for multi-octave FBM.
-- Rows wrap with modulo so the lattice never goes out of bounds.
local LSIZE = 64
math.randomseed(seed)
local lat1 = {}
local lat2 = {}
for i = 1, LSIZE * LSIZE do
  lat1[i] = math.random()
  lat2[i] = math.random()
end

local function sampleLat(lat, gx, gy)
  return lat[(gy % LSIZE) * LSIZE + (gx % LSIZE) + 1]
end

local function valueNoise(lat, px, py, freq)
  local fx  = px * freq / math.max(w, 1)
  local fy  = py * freq / math.max(h, 1)
  local ix0 = math.floor(fx)
  local iy0 = math.floor(fy)
  local ix1 = ix0 + 1
  local iy1 = iy0 + 1
  local tx  = smooth(fx - ix0)
  local ty  = smooth(fy - iy0)
  return lerp(
    lerp(sampleLat(lat, ix0, iy0), sampleLat(lat, ix1, iy0), tx),
    lerp(sampleLat(lat, ix0, iy1), sampleLat(lat, ix1, iy1), tx),
    ty
  )
end

-- Two-octave FBM: coarse blobs (large features) + fine detail.
-- turbulence 1–10 maps base frequency to the range 4–13.
local function fbm(px, py)
  local base = 3 + turbulence
  return valueNoise(lat1, px, py, base)     * 0.65
       + valueNoise(lat2, px, py, base * 2) * 0.35
end

-- ── Taper power curve ─────────────────────────────────────────────────────────
-- Controls how aggressively the flame narrows toward the tip.
-- taper=1 → full, rounded flame (taperPow≈3); taper=10 → sharp, narrow (taperPow≈0.4).
local taperPow = lerp(3.0, 0.4, (taper - 1) / 9.0)

-- ── Colour gradient ───────────────────────────────────────────────────────────
-- Interpolates three-stop gradient: tip → mid → core
-- fireLevel=0: tip colour (barely alive pixel); fireLevel=1: core colour (dense)
local function fireColor(fireLevel)
  local r, g, b, a
  if fireLevel < 0.5 then
    local u = fireLevel * 2.0
    r = lerp(tipR, midR, u)
    g = lerp(tipG, midG, u)
    b = lerp(tipB, midB, u)
    a = lerp(tipA, 255,  u)
  else
    local u = (fireLevel - 0.5) * 2.0
    r = lerp(midR, coreR, u)
    g = lerp(midG, coreG, u)
    b = lerp(midB, coreB, u)
    a = 255
  end
  return clamp(math.floor(r + 0.5), 0, 255),
         clamp(math.floor(g + 0.5), 0, 255),
         clamp(math.floor(b + 0.5), 0, 255),
         clamp(math.floor(a + 0.5), 0, 255)
end

-- ── Ember positions ───────────────────────────────────────────────────────────
-- Embers are sparse bright sparks scattered above the flame body.
-- Pre-computed into a hash map (key = y*w+x) to keep the pixel loop fast.
local emberSet = {}
local emberPalette = {}

if doEmbers then
  math.randomseed(seed + 3141)

  -- Three slightly different spark colours for variety
  for _ = 1, 4 do
    table.insert(emberPalette, {
      r = math.random(220, 255),
      g = math.random(120, 200),
      b = 0,
      a = math.random(160, 230),
    })
  end

  -- Scatter ~0.3% of pixels as embers; concentrate them near the flame tip zone.
  local emberCount = math.max(1, math.floor(w * h * 0.003))
  -- Pixel y-coordinate of the flame boundary (top of the main flame body)
  local flameBoundY = math.floor((h - 1) * (1.0 - flameHeight))

  -- For localized modes, constrain embers horizontally around the origin.
  -- We use 2× halfWidthPx so sparks can drift a little outside the flame body.
  local emberXMin = isLocal and math.max(0,    math.floor(originXPx - halfWidthPx * 2)) or 0
  local emberXMax = isLocal and math.min(w - 1, math.floor(originXPx + halfWidthPx * 2)) or (w - 1)

  for _ = 1, emberCount do
    local ex = math.random(emberXMin, emberXMax)
    -- Embers float from just inside the flame tip up to the top of the image.
    -- Clamp so embers don't go below the flame body.
    local eyMax = math.max(0, math.floor(flameBoundY + (h - 1 - flameBoundY) * 0.25))
    local ey = math.random(0, eyMax)
    emberSet[ey * w + ex] = emberPalette[math.random(1, #emberPalette)]
  end
end

-- ── Pixel pass ───────────────────────────────────────────────────────────────
local newImage = img:clone()

for it in newImage:pixels() do
  local x = it.x
  local y = it.y

  -- Snap to block origin so every pixel in the same block shares identical noise
  -- and threshold values, producing a chunky pixel-art resolution effect.
  -- When blockSize=1 this is a no-op.
  local sx = math.floor(x / blockSize) * blockSize
  local sy = math.floor(y / blockSize) * blockSize

  -- normY: 0 at the very bottom of the image, 1 at the very top.
  local normY = (h - 1 - sy) / math.max(h - 1, 1)

  -- relY: position relative to the flame height zone (0=base, 1=flame tip, >1=above)
  local relY = normY / math.max(flameHeight, 0.001)

  -- Height-dependent noise threshold.
  -- Below this value the pixel is transparent; at the base it is 0 (always fire).
  local threshold = (relY < 1.0) and (relY ^ taperPow) or 1.0

  -- Localized modes: add a horizontal distance penalty so the flame is a column
  -- rather than spanning the full image width.  The allowed half-width at each
  -- height shrinks toward the tip using spreadPow:
  --   widthAtH = halfWidthPx * (1 - relY)^spreadPow
  -- dx is the distance from the flame centre normalised to that width.
  -- dx² is added to the threshold: pixels far from centre need higher noise to ignite.
  if isLocal and relY <= 1.0 then
    local widthAtH = halfWidthPx * math.max(1.0 - relY, 0.0) ^ spreadPow
    local dx = math.abs(sx - originXPx) / math.max(widthAtH, 0.5)
    threshold = clamp(threshold + dx * dx, 0, 1)
  end

  local n = fbm(sx, sy)

  if n > threshold then
    -- ── Fire body ─────────────────────────────────────────────────────────────
    -- Normalise how far above the threshold this pixel sits (0=tip, 1=core).
    local maxFireLevel = 1.0 - threshold
    local fireLevel = (n - threshold) / math.max(maxFireLevel, 0.001)
    local r, g, b, a = fireColor(clamp(fireLevel, 0, 1))
    it(app.pixelColor.rgba(r, g, b, a))

  elseif doEmbers and emberSet[y * w + x] then
    -- ── Ember spark (only drawn where there is no fire) ───────────────────────
    local ec = emberSet[y * w + x]
    it(app.pixelColor.rgba(ec.r, ec.g, ec.b, ec.a))

  else
    -- ── Transparent (above / outside the flame) ────────────────────────────────
    it(app.pixelColor.rgba(0, 0, 0, 0))
  end
end

-- ── Outline pass ────────────────────────────────────────────────────────────
-- Every transparent pixel that shares an edge with an opaque fire/ember pixel
-- gets painted black.  Candidates are collected first so we never read a pixel
-- that was itself written by this same pass.
if doOutline then
  local outlinePixels = {}
  local dirs = { {-1,0},{1,0},{0,-1},{0,1} }
  for it in newImage:pixels() do
    if app.pixelColor.rgbaA(it()) == 0 then
      local ox, oy = it.x, it.y
      for _, d in ipairs(dirs) do
        local nx, ny = ox + d[1], oy + d[2]
        if nx >= 0 and nx < w and ny >= 0 and ny < h then
          if app.pixelColor.rgbaA(newImage:getPixel(nx, ny)) > 0 then
            table.insert(outlinePixels, {ox, oy})
            break
          end
        end
      end
    end
  end
  local black = app.pixelColor.rgba(0, 0, 0, 255)
  for _, p in ipairs(outlinePixels) do
    newImage:drawPixel(p[1], p[2], black)
  end
end

-- ── Commit as a single undoable action ───────────────────────────────────────
app.transaction("Fire Fill", function()
  sprite:newCel(app.layer, app.frame, newImage, cel.position)
end)

app.refresh()
