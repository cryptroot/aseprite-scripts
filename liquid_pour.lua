-- Liquid Pour — Aseprite script
-- Animates a stream of liquid: drip → steady flow → widening flood.
-- Designed to be placed on a layer above a container opening and paired
-- with the Glass Fill script for a complete pouring animation.
--
-- Phases (each configurable as a % of total frames):
--   Drip  — stream tip descends from the top, trailing a teardrop cap
--   Flow  — full-length stream with animated side wobble
--   Flood — stream base widens, simulating liquid accumulating / splashing

local sprite = app.sprite
if not sprite then app.alert("No active sprite!") return end

local cel = app.cel
if not cel then app.alert("No active cel!") return end

if not app.layer.isEditable then
  app.alert("Layer is not editable.")
  return
end

if sprite.colorMode ~= ColorMode.RGB then
  app.alert("Liquid Pour requires an RGB color mode sprite.")
  return
end

local w = sprite.width
local h = sprite.height

-- ── Dialog ───────────────────────────────────────────────────────────────────
local dlg = Dialog("Liquid Pour")

dlg:color  { id="color",     label="Liquid Color:",      color=Color{ r=80, g=160, b=220, a=210 } }

dlg:separator{ text="Stream Shape" }
dlg:slider { id="centerX",   label="Center X (px):",     min=0, max=w-1,
             value=math.floor(w / 2) }
dlg:slider { id="streamW",   label="Stream Width (px):", min=1,
             max=math.max(1, math.floor(w / 2)),
             value=math.max(1, math.floor(w * 0.18)) }
dlg:slider { id="taper",     label="Taper (%):",          min=0, max=100, value=30 }

dlg:separator{ text="Animation" }
dlg:slider { id="numFrames", label="Total Frames:",       min=1,  max=64,  value=20 }
dlg:slider { id="duration",  label="Frame Delay (ms):",   min=20, max=500, value=80 }
dlg:slider { id="dripPct",   label="Drip Phase (%):",     min=0,  max=90,  value=40 }
dlg:slider { id="floodPct",  label="Flood Phase (%):",    min=0,  max=90,  value=25 }

dlg:separator{ text="Wobble" }
dlg:slider { id="amplitude", label="Wobble Amount (px):", min=0, max=8,  value=1 }
dlg:slider { id="frequency", label="Wobble Frequency:",   min=1, max=10, value=4 }

dlg:separator{ text="Shading" }
dlg:check  { id="highlight", label="Shine:",  text="Left highlight", selected=true }
dlg:check  { id="shadow",    label="Shadow:", text="Right shadow",   selected=true }
dlg:check  { id="softEdge",  label="Edges:",  text="Soft edge fade", selected=true }

dlg:separator()
dlg:button { id="ok",     text="Apply", focus=true }
dlg:button { id="cancel", text="Cancel" }

dlg:show()
local data = dlg.data
if not data.ok then return end

-- ── Parameters ────────────────────────────────────────────────────────────────
local r0, g0, b0, a0 = data.color.red, data.color.green, data.color.blue, data.color.alpha

local centerX    = data.centerX
local maxHW      = math.max(0, math.floor(data.streamW / 2))

-- taperFrac: fraction of maxHW present at the very top row.
--   taper=0   → constant width throughout (no taper)
--   taper=100 → zero width at the top, grows to full width at the bottom
local taperFrac  = 1.0 - (data.taper / 100.0)

local numFrames  = data.numFrames
local frameDurMs = data.duration
local dripEnd    = data.dripPct  / 100.0
local floodStart = 1.0 - (data.floodPct / 100.0)

local amplitude  = data.amplitude
local frequency  = data.frequency

local doHighlight = data.highlight
local doShadow    = data.shadow
local doSoftEdge  = data.softEdge

-- ── Helpers ───────────────────────────────────────────────────────────────────
local pi = math.pi
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function lerp(a, b, t)    return math.floor(a + (b - a) * t + 0.5) end

-- Apply highlight / shadow / soft-edge shading to a pixel at position x,
-- spanning [leftE, rightE] with half-width hw.  Returns r, g, b, alpha.
local function shade(x, leftE, rightE, hw, r, g, b, alpha)
  -- Soft edge: fade alpha toward the stream boundary
  if doSoftEdge and hw >= 2.0 then
    local edgePx  = math.max(1.0, hw * 0.25)
    local nearest = math.min(x - leftE, rightE - x)
    if nearest < edgePx then
      alpha = math.floor(alpha * (nearest / edgePx) + 0.5)
    end
  end

  -- Left highlight: bright streak simulating refracted light
  if doHighlight and hw >= 1.0 then
    local hW = math.max(1.0, hw * 0.3)
    local dx = x - leftE
    if dx < hW then
      local t = (1.0 - dx / hW) * 0.5
      r = lerp(r, 255, t)
      g = lerp(g, 255, t)
      b = lerp(b, 255, t)
    end
  end

  -- Right shadow: darker edge on the opposite side
  if doShadow and hw >= 1.0 then
    local sW = math.max(1.0, hw * 0.3)
    local dx = rightE - x
    if dx < sW then
      local t = (1.0 - dx / sW) * 0.35
      r = lerp(r, 0, t)
      g = lerp(g, 0, t)
      b = lerp(b, 0, t)
    end
  end

  return r, g, b, alpha
end

-- ── Per-frame image builder ───────────────────────────────────────────────────
-- progress: 0..1 overall animation timeline
-- frameIdx: 0-based frame index (used for wobble phase)
local function buildImage(progress, frameIdx)
  local img = Image(sprite.spec)
  img:clear()

  -- ── Drip phase: stream tip descends from top to bottom ────────────────────
  local tipY = h - 1
  if dripEnd > 0 and progress < dripEnd then
    tipY = math.floor((progress / dripEnd) * (h - 1))
  end

  -- ── Flood phase: base-widening multiplier (0..1) ──────────────────────────
  local floodT = 0.0
  local floodRange = 1.0 - floodStart
  if floodRange > 0 and progress > floodStart then
    floodT = clamp((progress - floodStart) / floodRange, 0, 1)
  end

  -- ── Wobble: cycles continuously across all frames ─────────────────────────
  local wobPh = (frameIdx / math.max(numFrames, 1)) * 2 * pi * frequency

  -- Stream center at the tip row (drop cap must match stream sway there)
  local tipSway = amplitude * math.sin(2 * pi * frequency * tipY / math.max(h, 1) + wobPh)
  local dropCX  = centerX + tipSway
  local dropR   = maxHW   -- teardrop cap matches the stream's full half-width

  for it in img:pixels() do
    local x = it.x
    local y = it.y

    if y > tipY then
      -- ── Teardrop cap (below stream tip) ───────────────────────────────────
      -- A semicircle centered at (dropCX, tipY) with radius dropR gives the
      -- characteristic rounded leading edge of a liquid drop.
      if dropR > 0 then
        local dx = x - dropCX
        local dy = y - tipY
        if dx * dx + dy * dy <= dropR * dropR then
          local capHW = math.sqrt(math.max(0.0, dropR * dropR - dy * dy))
          local lE    = dropCX - capHW
          local rE    = dropCX + capHW
          local r, g, b, alpha = shade(x, lE, rE, capHW, r0, g0, b0, a0)
          it(app.pixelColor.rgba(clamp(r,0,255), clamp(g,0,255), clamp(b,0,255), clamp(alpha,0,255)))
        else
          it(app.pixelColor.rgba(0, 0, 0, 0))
        end
      else
        it(app.pixelColor.rgba(0, 0, 0, 0))
      end

    else
      -- ── Stream body ────────────────────────────────────────────────────────
      local rowT = (h > 1) and (y / (h - 1)) or 1.0

      -- Tapered half-width: narrow at the top (pour point), full at the bottom.
      -- Physics: liquid accelerates as it falls, narrowing the column, but
      -- for pixel art we reverse this so the pour point is visually distinct.
      local hw = maxHW * (taperFrac + (1.0 - taperFrac) * rowT)

      -- Flood widening: expand the stream base during the flood phase.
      -- Only affects the lower ~45% of the canvas so the pour point stays clean.
      if floodT > 0 then
        local fzT = clamp((rowT - 0.55) / 0.45, 0, 1)
        hw = hw + maxHW * floodT * fzT * 2.0
      end

      -- Sinusoidal side-sway (the stream bends slightly as it falls)
      local sway = amplitude * math.sin(2 * pi * frequency * y / math.max(h, 1) + wobPh)
      local cx   = centerX + sway
      local lE   = cx - hw
      local rE   = cx + hw

      if x >= lE and x <= rE then
        local r, g, b, alpha = shade(x, lE, rE, hw, r0, g0, b0, a0)
        it(app.pixelColor.rgba(clamp(r,0,255), clamp(g,0,255), clamp(b,0,255), clamp(alpha,0,255)))
      else
        it(app.pixelColor.rgba(0, 0, 0, 0))
      end
    end
  end

  return img
end

-- ── Commit ────────────────────────────────────────────────────────────────────
local startFrame  = app.frame.frameNumber
local celPosition = cel.position
local label       = numFrames > 1 and "Liquid Pour Animation" or "Liquid Pour"

app.transaction(label, function()
  for fi = 1, numFrames do
    local frameIdx = startFrame + fi - 1
    -- progress: 0 at first frame, 1 at last frame (guard against numFrames=1)
    local progress = (numFrames > 1) and ((fi - 1) / (numFrames - 1)) or 1.0

    if numFrames > 1 then
      while #sprite.frames < frameIdx do
        sprite:newEmptyFrame(#sprite.frames + 1)
      end
      sprite.frames[frameIdx].duration = frameDurMs
    end

    local img = buildImage(progress, fi - 1)
    sprite:newCel(app.layer, sprite.frames[frameIdx], img, celPosition)
  end
end)

app.refresh()
