-- Drip — Aseprite script
-- Animates individual drops falling independently from top to bottom.
-- Drops are staggered across the animation and spread horizontally,
-- giving a natural dripping appearance without a connected stream.
--
-- Each drop is a teardrop shape: a filled circle body with a narrow
-- fading tail above it, all with optional shading.

local sprite = app.sprite
if not sprite then app.alert("No active sprite!") return end

local cel = app.cel
if not cel then app.alert("No active cel!") return end

if not app.layer.isEditable then
  app.alert("Layer is not editable.")
  return
end

if sprite.colorMode ~= ColorMode.RGB then
  app.alert("Drip requires an RGB color mode sprite.")
  return
end

local w = sprite.width
local h = sprite.height

-- ── Dialog ────────────────────────────────────────────────────────────────────
local dlg = Dialog("Drip")

dlg:color  { id="color",      label="Liquid Color:",      color=Color{ r=80, g=160, b=220, a=210 } }

dlg:separator{ text="Drop Shape" }
dlg:slider { id="numDrops",   label="Number of Drops:",   min=1,  max=12,  value=3 }
dlg:slider { id="dropRadius", label="Drop Radius (px):",  min=1,  max=10,  value=3 }
dlg:slider { id="tailLength", label="Tail Length (px):",  min=0,  max=16,  value=5 }
dlg:slider { id="spreadPct",  label="Spread (%):",         min=0,  max=100, value=80 }
dlg:number { id="seed",       label="Seed:",              text="42", decimals=0 }

dlg:separator{ text="Animation" }
dlg:slider { id="numFrames",  label="Total Frames:",       min=1,  max=64,  value=24 }
dlg:slider { id="duration",   label="Frame Delay (ms):",  min=20, max=500, value=80 }
dlg:slider { id="fallPct",    label="Fall Duration (%):", min=10, max=100, value=60 }

dlg:separator{ text="Shading" }
dlg:check  { id="highlight",  label="Shine:",  text="Left highlight", selected=true }
dlg:check  { id="shadow",     label="Shadow:", text="Right shadow",   selected=true }
dlg:check  { id="softEdge",   label="Edges:",  text="Soft edge fade", selected=true }

dlg:separator()
dlg:button { id="ok",     text="Apply", focus=true }
dlg:button { id="cancel", text="Cancel" }

dlg:show()
local data = dlg.data
if not data.ok then return end

-- ── Parameters ────────────────────────────────────────────────────────────────
local r0, g0, b0, a0 = data.color.red, data.color.green, data.color.blue, data.color.alpha
local numDrops    = data.numDrops
local dropRadius  = data.dropRadius
local tailLength  = data.tailLength
local spreadPct   = data.spreadPct / 100.0
local seed        = math.floor(data.seed)
local numFrames   = data.numFrames
local frameDurMs  = data.duration
local fallFrac    = math.min(data.fallPct / 100.0, 1.0)

local doHighlight = data.highlight
local doShadow    = data.shadow
local doSoftEdge  = data.softEdge

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function lerp(a, b, t)    return math.floor(a + (b - a) * t + 0.5) end

-- Seeded LCG so drops look different per seed value without depending on os.time
local function makeRng(s)
  s = s % (2 ^ 32)
  return function()
    s = (s * 1664525 + 1013904223) % (2 ^ 32)
    return s / (2 ^ 32)
  end
end

local rng = makeRng(seed ~= 0 and seed or 1)

-- ── Drop Properties ───────────────────────────────────────────────────────────
-- Evenly distribute phase offsets so drops fall one after another.
-- Each drop also gets a slightly jittered horizontal position so the
-- column layout doesn't look perfectly mechanical.
local drops = {}
local spreadW = w * spreadPct
local spreadX = (w - spreadW) / 2.0
-- Maximum start offset so every drop still finishes before the last frame
local maxOffset = math.max(0.0, 1.0 - fallFrac)

for i = 1, numDrops do
  -- Even base phase across the available offset range
  local base   = (numDrops > 1) and ((i - 1) / (numDrops - 1) * maxOffset) or 0.0
  -- ±5 % of maxOffset jitter keeps rhythm natural without making drops collide
  local jitter = (rng() - 0.5) * maxOffset * 0.1
  local phase  = clamp(base + jitter, 0.0, maxOffset)

  -- One horizontal "slot" per drop; jitter within ±30 % of that slot
  local slotW = (numDrops > 1) and (spreadW / numDrops) or spreadW
  local baseX = spreadX + (i - 0.5) * slotW
  local xJit  = (rng() - 0.5) * slotW * 0.6
  local dropX = clamp(baseX + xJit, dropRadius + 1, w - dropRadius - 1)

  drops[i] = { x = dropX, phase = phase }
end

-- ── Shading ───────────────────────────────────────────────────────────────────
-- Shade a pixel at screen-x `px` within the horizontal span [lE, rE] (half-width hw).
local function shadeSpan(px, lE, rE, hw, r, g, b, alpha)
  if doSoftEdge and hw >= 1.0 then
    local edgePx = math.max(1.0, hw * 0.3)
    local rim    = math.min(px - lE, rE - px)
    if rim < edgePx then
      alpha = math.floor(alpha * (rim / edgePx) + 0.5)
    end
  end

  if doHighlight and hw >= 1.0 then
    local hW = math.max(1.0, hw * 0.35)
    local dx = px - lE
    if dx < hW then
      local t = (1.0 - dx / hW) * 0.5
      r = lerp(r, 255, t); g = lerp(g, 255, t); b = lerp(b, 255, t)
    end
  end

  if doShadow and hw >= 1.0 then
    local sW = math.max(1.0, hw * 0.35)
    local dx = rE - px
    if dx < sW then
      local t = (1.0 - dx / sW) * 0.35
      r = lerp(r, 0, t); g = lerp(g, 0, t); b = lerp(b, 0, t)
    end
  end

  return r, g, b, alpha
end

-- ── Per-frame image builder ───────────────────────────────────────────────────
local function buildImage(progress)
  local img = Image(sprite.spec)
  img:clear()

  for it in img:pixels() do
    local px = it.x
    local py = it.y
    local fr, fg, fb, fa = 0, 0, 0, 0
    local hit = false

    for _, drop in ipairs(drops) do
      if hit then break end

      local pEnd = drop.phase + fallFrac

      -- Skip if this drop is not active this frame
      if progress >= drop.phase and progress <= pEnd then
        -- t = 0 when the drop first enters, 1 when its circle fully exits below
        local t  = (progress - drop.phase) / fallFrac
        -- Circle center travels from above the canvas (-radius) to below it (h-1+radius)
        local cy = -dropRadius + t * (h - 1 + 2 * dropRadius)
        local cx = drop.x

        local dx = px - cx
        local dy = py - cy
        local d2 = dx * dx + dy * dy
        local r2 = dropRadius * dropRadius

        if d2 <= r2 then
          -- ── Circle body ─────────────────────────────────────────────────────
          local rowHW = math.sqrt(math.max(0.0, r2 - dy * dy))
          fr, fg, fb, fa = shadeSpan(px, cx - rowHW, cx + rowHW, rowHW, r0, g0, b0, a0)
          hit = true

        elseif tailLength > 0 then
          -- ── Tail: a 1-px column fading up from the circle's top ─────────────
          -- The tail sits directly above the circle, tapering alpha to 0.
          local tailTop = cy - dropRadius - tailLength
          if py >= tailTop and py < cy - dropRadius then
            if px == math.floor(cx + 0.5) then
              local tailT = (py - tailTop) / tailLength   -- 0 at tip, 1 at junction
              fa = math.floor(a0 * tailT + 0.5)
              fr, fg, fb = r0, g0, b0
              hit = true
            end
          end
        end
      end
    end

    if fa > 0 then
      it(app.pixelColor.rgba(clamp(fr,0,255), clamp(fg,0,255), clamp(fb,0,255), clamp(fa,0,255)))
    else
      it(app.pixelColor.rgba(0, 0, 0, 0))
    end
  end

  return img
end

-- ── Commit ────────────────────────────────────────────────────────────────────
local startFrame  = app.frame.frameNumber
local celPosition = cel.position
local label       = numFrames > 1 and "Drip Animation" or "Drip"

app.transaction(label, function()
  for fi = 1, numFrames do
    local frameIdx = startFrame + fi - 1
    local progress = (numFrames > 1) and ((fi - 1) / (numFrames - 1)) or 1.0

    if numFrames > 1 then
      while #sprite.frames < frameIdx do
        sprite:newEmptyFrame(#sprite.frames + 1)
      end
      sprite.frames[frameIdx].duration = frameDurMs
    end

    local img = buildImage(progress)
    sprite:newCel(app.layer, sprite.frames[frameIdx], img, celPosition)
  end
end)

app.refresh()
