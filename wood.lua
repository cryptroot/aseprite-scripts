-- wood.lua
-- Applies a procedural wood grain effect to the active layer's RGB cel.
--
-- Features:
--   • Organic grain rings with noise warp
--   • Knots that pull rings into radial bullseye patterns
--   • Rot patches (dark, desaturated, slightly greenish)
--   • Cracks / splits (thin branching dark lines via noise level-sets)
--   • Breakage / chipping (pixels erased to transparent)
--
-- The effect reads the existing pixel colours and modifies them, so it
-- works on any brown (or other) base the user has painted.

-- ── Guards ───────────────────────────────────────────────────────────────────
local sprite = app.sprite
if not sprite then app.alert("No active sprite!") return end

local cel = app.cel
if not cel then app.alert("No active cel!") return end

local layer = app.layer
if not layer.isEditable then app.alert("Layer is not editable.") return end

if sprite.colorMode ~= ColorMode.RGB then
  app.alert("Wood Effect requires RGB colour mode.")
  return
end

-- ── Dialog ───────────────────────────────────────────────────────────────────
local defaultSeed = math.floor(os.time()) % 99999

local dlg = Dialog("Wood Effect")

dlg:combobox{
  id      = "direction",
  label   = "Grain Direction:",
  option  = "Horizontal",
  options = { "Horizontal", "Vertical" }
}
dlg:slider{ id = "scale",     label = "Scale:",           min = 10, max = 400, value = 100 }
dlg:slider{ id = "ring_freq", label = "Ring Frequency:",  min = 1,  max = 30,  value = 8   }
dlg:slider{ id = "warp",      label = "Warp Amount:",     min = 0,  max = 100, value = 40  }
dlg:slider{ id = "knots",     label = "Knots:",           min = 0,  max = 8,   value = 2   }
dlg:separator()
dlg:slider{ id = "cracks",    label = "Cracks:",          min = 0, max = 100, value = 25 }
dlg:slider{ id = "rot",       label = "Rot:",             min = 0, max = 100, value = 15 }
dlg:slider{ id = "breakage",  label = "Breakage:",        min = 0, max = 100, value = 10 }
dlg:slider{ id = "splinter",  label = "Splintered Ends:", min = 0, max = 100, value = 0  }
dlg:separator()
dlg:number{ id = "seed", label = "Random Seed:", text = tostring(defaultSeed), decimals = 0 }
dlg:button{ id = "ok",     text = "Apply",  focus = true }
dlg:button{ id = "cancel", text = "Cancel" }
dlg:show()

local d = dlg.data
if not d.ok then return end

-- ── Parameters ───────────────────────────────────────────────────────────────
local direction  = d.direction
local featureScale = d.scale / 100.0      -- 0.1..4.0
local ringFreq   = d.ring_freq
local warpAmt    = d.warp     / 100.0   -- 0..1
local knotCount  = math.floor(d.knots)
local crackLevel    = d.cracks   / 100.0   -- 0..1
local rotLevel      = d.rot      / 100.0   -- 0..1
local breakLevel    = d.breakage / 100.0   -- 0..1
local splinterLevel = d.splinter / 100.0   -- 0..1
local seed          = math.floor(d.seed or defaultSeed)

-- ── Math helpers ─────────────────────────────────────────────────────────────
local function lerp(a, b, t)    return a + (b - a) * t end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function smoothstep(t)    return t * t * (3 - 2 * t) end

-- ── Noise system ─────────────────────────────────────────────────────────────
-- Pre-build four independent 64×64 tiling noise tables.
-- All randomness for the pixel pass comes from these; math.randomseed is
-- never called again after setup, so the main RNG state stays clean.
local NW, NH = 64, 64

local function buildNoise(s)
  math.randomseed(s)
  local t = {}
  for i = 1, NW * NH do t[i] = math.random() end
  return t
end

local nA = buildNoise(seed)
local nB = buildNoise(seed + 7919)
local nC = buildNoise(seed + 15731)
local nD = buildNoise(seed + 29347)

-- Smooth bilinear sample from a tiling noise table.
-- cellSize controls the spatial frequency (larger = smoother).
local function sampleNoise(tbl, x, y, cellSize)
  local nx = (x / cellSize) % NW
  local ny = (y / cellSize) % NH
  local ix = math.floor(nx)
  local iy = math.floor(ny)
  local fx = smoothstep(nx - ix)
  local fy = smoothstep(ny - iy)
  local function n(gx, gy)
    return tbl[(gy % NH) * NW + (gx % NW) + 1]
  end
  return lerp(
    lerp(n(ix,   iy),   n(ix+1, iy),   fx),
    lerp(n(ix,   iy+1), n(ix+1, iy+1), fx),
    fy
  )
end

-- ── Image setup ──────────────────────────────────────────────────────────────
local src  = cel.image
local imgW = src.width
local imgH = src.height
local dst  = src:clone()

local mainLen    = (direction == "Horizontal") and imgH or imgW
local bigDim     = math.max(imgW, imgH)
local warpCell   = math.max(4, bigDim * 0.45 * featureScale)
local rotCell    = math.max(4, bigDim * 0.35 * featureScale)
local crackCell  = math.max(4, bigDim * 0.38 * featureScale)
local detailCell = math.max(2, bigDim * 0.06 * featureScale)
local breakCell1    = math.max(4, bigDim * 0.18 * featureScale)
local breakCell2    = math.max(2, bigDim * 0.07 * featureScale)
-- Splinter end cells: sized relative to the along-grain dimension
local fiberDim      = (direction == "Horizontal") and imgW or imgH
local splinterCell1 = math.max(3, fiberDim * 0.15 * featureScale)  -- coarse fiber groups
local splinterCell2 = math.max(2, fiberDim * 0.04 * featureScale)  -- fine fiber edges

-- ── Knots (pre-computed positions) ───────────────────────────────────────────
math.randomseed(seed + 3)
local knots = {}
for i = 1, knotCount do
  local minR = math.max(3, bigDim // 12)
  local maxR = math.max(5, bigDim //  3)
  knots[i] = {
    x = math.random(0, imgW - 1),
    y = math.random(0, imgH - 1),
    r = math.random(minR, maxR),
  }
end

-- ── Pixel pass ───────────────────────────────────────────────────────────────
local pc  = app.pixelColor
local TAU = 2 * math.pi

for it in dst:pixels() do
  local pv   = it()
  local srcA = pc.rgbaA(pv)

  if srcA > 0 then
    local px = it.x
    local py = it.y

    local srcR = pc.rgbaR(pv)
    local srcG = pc.rgbaG(pv)
    local srcB = pc.rgbaB(pv)

    -- ── 1. Base ring coordinate ───────────────────────────────────────────
    local axis   = (direction == "Horizontal") and py or px
    local ring_t = (axis / mainLen) * ringFreq   -- 0..ringFreq total cycles

    -- ── 2. Noise warp (three overlapping octaves, two noise fields) ───────
    local w1 = sampleNoise(nA, px,        py,        warpCell     ) - 0.5
    local w2 = sampleNoise(nB, px,        py,        warpCell     ) - 0.5
    local w3 = sampleNoise(nA, px * 2.1,  py * 2.1,  warpCell     ) - 0.5
    ring_t = ring_t
           + w1 * warpAmt * ringFreq * 0.50
           + w2 * warpAmt * ringFreq * 0.15
           + w3 * warpAmt * ringFreq * 0.08

    -- ── 3. Knot distortion (radial ring contribution near knot centres) ───
    for _, k in ipairs(knots) do
      local dx   = px - k.x
      local dy   = py - k.y
      local dist = math.sqrt(dx * dx + dy * dy)
      local fade = 1 - clamp(dist / (k.r * 3.5), 0, 1)
      fade = smoothstep(smoothstep(fade))  -- double-smoothed falloff
      if fade > 0 then
        ring_t = ring_t + (dist / math.max(1, k.r)) * ringFreq * 0.3 * fade
      end
    end

    -- ── 4. Grain brightness factor ────────────────────────────────────────
    -- sin oscillates 0..1; power-sharpening makes late-wood bands narrow.
    local s       = (math.sin(ring_t * TAU) + 1) * 0.5   -- 0..1
    local lateBand = (1 - s) ^ 2.8                        -- 0..1 (peaks at troughs)
    local detail   = sampleNoise(nB, px, py, detailCell) * 0.12 - 0.06
    local grain    = 1.0 - lateBand * 0.42 + detail       -- ~0.52..1.06

    -- ── 5. Rot patches ────────────────────────────────────────────────────
    -- Low-frequency noise spots that are dark, desaturated and slightly green.
    local rotBlend = 0.0
    local rotDesat = 0.0
    if rotLevel > 0 then
      local rn     = sampleNoise(nC, px, py, rotCell) ^ 1.5   -- bias low
      local rotMask = clamp((rn - (1 - rotLevel * 1.3)) / 0.3, 0, 1)
      rotMask   = smoothstep(rotMask)
      rotBlend  = rotMask * 0.55   -- up to 55% darkening
      rotDesat  = rotMask * 0.65   -- up to 65% desaturation
    end

    -- ── 6. Cracks ─────────────────────────────────────────────────────────
    -- Two noise fields are blended; their combined level-set at 0.57 forms
    -- a branching network of thin dark lines resembling wood splits.
    local crackDark = 0.0
    if crackLevel > 0 then
      local cn1      = sampleNoise(nC, px, py, crackCell)
      local cn2      = sampleNoise(nD, px, py, crackCell * 0.55) * 0.45
      local combined = cn1 * 0.7 + cn2        -- range 0..1.15
      local field    = math.abs(combined - 0.57)  -- 0 at crack centre-line
      local width    = crackLevel * 0.07
      if field < width then
        crackDark = smoothstep(1 - field / width) * 0.88
      end
    end

    -- ── 7. Breakage / chipping ────────────────────────────────────────────
    -- Two scales of noise blended together define which regions are "missing".
    local broken = false
    if breakLevel > 0 then
      local bn1 = sampleNoise(nD, px,                 py,                 breakCell1)
      local bn2 = sampleNoise(nB, px + imgW * 0.4,    py + imgH * 0.6,    breakCell2)
      local bv  = bn1 * 0.65 + bn2 * 0.35
      broken = bv > (1 - breakLevel * 0.65)
    end

    -- ── 8. Splintered ends ────────────────────────────────────────────────
    -- Noise-driven per-fiber boundaries eat into the two end-grain faces.
    -- fiberPos runs along the grain; endPos runs into the plank end.
    local splintered = false
    if splinterLevel > 0 then
      local fiberPos = (direction == "Horizontal") and px or py
      local endPos   = (direction == "Horizontal") and py or px
      local totalLen = (direction == "Horizontal") and imgH or imgW
      local maxDepth = totalLen * splinterLevel * 0.42

      -- Only run the calculation near the ends (skip the bulk of the plank)
      if endPos < maxDepth * 1.6 or endPos > (totalLen - 1 - maxDepth * 1.6) then
        -- Top/left end: two octaves of noise along the fiber axis
        local sn1t = sampleNoise(nA, fiberPos,       0,   splinterCell1)
        local sn2t = sampleNoise(nD, fiberPos,       17,  splinterCell2)
        local depthTop = (sn1t * 0.65 + sn2t * 0.35) * maxDepth

        -- Bottom/right end: independent noise (offset sample coordinates)
        local sn1b = sampleNoise(nC, fiberPos + fiberDim * 0.37, 0,  splinterCell1)
        local sn2b = sampleNoise(nD, fiberPos + fiberDim * 0.73, 17, splinterCell2)
        local depthBot = (sn1b * 0.65 + sn2b * 0.35) * maxDepth

        splintered = endPos < depthTop or endPos > (totalLen - 1 - depthBot)
      end
    end

    -- ── 9. Compose final colour ───────────────────────────────────────────
    if broken or splintered then
      it(pc.rgba(0, 0, 0, 0))
    else
      local r = srcR * grain * (1 - rotBlend)
      local g = srcG * grain * (1 - rotBlend)
      local b = srcB * grain * (1 - rotBlend)

      -- Rot colour tint: damp, slightly greenish, warm shadow offset
      if rotDesat > 0 then
        local lum = 0.299 * r + 0.587 * g + 0.114 * b
        r = lerp(r, lum * 0.85 + 4, rotDesat)
        g = lerp(g, lum * 1.00 + 7, rotDesat)
        b = lerp(b, lum * 0.75,     rotDesat)
      end

      -- Crack: sharp darkening
      if crackDark > 0 then
        local cd = 1 - crackDark
        r = r * cd
        g = g * cd
        b = b * cd
      end

      it(pc.rgba(
        clamp(math.floor(r + 0.5), 0, 255),
        clamp(math.floor(g + 0.5), 0, 255),
        clamp(math.floor(b + 0.5), 0, 255),
        srcA
      ))
    end
  end
end

-- ── Commit as a single undoable action ───────────────────────────────────────
app.transaction("Wood Effect", function()
  sprite:newCel(layer, app.frame, dst, cel.position)
end)

app.refresh()
