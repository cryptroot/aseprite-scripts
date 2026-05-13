-- Glass Fill — Aseprite script
-- Fills the active cel with a liquid effect for potion bottles / glass containers.
-- Single mode: paints one frame at the chosen fill level.
-- Fill Animation mode: generates consecutive frames that fill up from a start
-- level to an end level, one equal step per frame (e.g. 10 frames → +10% each).

local sprite = app.sprite
if not sprite then app.alert("No active sprite!") return end

local cel = app.cel
if not cel then app.alert("No active cel!") return end

if not app.layer.isEditable then
  app.alert("Layer is not editable.")
  return
end

if sprite.colorMode ~= ColorMode.RGB then
  app.alert("Glass Fill requires an RGB color mode sprite.")
  return
end

-- ── Dialog ──────────────────────────────────────────────────────────────────
local dlg = Dialog("Glass Fill")

dlg:color  { id="color",     label="Liquid Color:",     color=Color{ r=80, g=160, b=220, a=210 } }

dlg:separator{ text="Fill" }
dlg:combobox { id="mode", label="Mode:", option="Single Frame",
               options={"Single Frame", "Fill Animation"} }
dlg:slider { id="level",      label="Fill Level (%):",  min=0, max=100, value=60 }
dlg:slider { id="startLevel", label="Start Level (%):", min=0, max=100, value=0  }
dlg:slider { id="frames",     label="Frame Count:",     min=2, max=64,  value=10 }
dlg:slider { id="duration",   label="Frame Delay (ms):",min=20,max=500, value=80 }

dlg:separator{ text="Surface Wave" }
dlg:slider { id="amplitude",  label="Wave Height (px):", min=0, max=20, value=3 }
dlg:slider { id="frequency",  label="Wave Frequency:",   min=1, max=10, value=2 }
dlg:slider { id="phase",      label="Wave Phase:",       min=0, max=100, value=0 }
dlg:check  { id="animWave",   label="Animate Wave:",     text="Shift phase across frames",
             selected=true }

dlg:separator{ text="Shading" }
dlg:check  { id="highlight", label="Shine:",   text="Left highlight",   selected=true }
dlg:check  { id="shadow",    label="Shadow:",  text="Right shadow",     selected=true }
dlg:check  { id="depth",     label="Depth:",   text="Darker at bottom", selected=true }

dlg:separator()
dlg:button { id="ok",     text="Apply", focus=true }
dlg:button { id="cancel", text="Cancel" }

dlg:show()

local data = dlg.data
if not data.ok then return end

-- ── Parameters ───────────────────────────────────────────────────────────────
local w = sprite.width
local h = sprite.height

local r0 = data.color.red
local g0 = data.color.green
local b0 = data.color.blue
local a0 = data.color.alpha

local isAnimation = (data.mode == "Fill Animation")
local targetLevel = data.level / 100.0
local startLevel  = isAnimation and (data.startLevel / 100.0) or targetLevel
local numFrames   = isAnimation and data.frames or 1
local frameDurMs  = data.duration
local amplitude   = data.amplitude
local frequency   = data.frequency
local basePhaseRad = (data.phase / 100.0) * 2 * math.pi
local doAnimWave  = data.animWave
local doHighlight = data.highlight
local doShadow    = data.shadow
local doDepth     = data.depth

-- ── Helpers ──────────────────────────────────────────────────────────────────
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function lerp(a, b, t)    return math.floor(a + (b - a) * t + 0.5) end

-- ── Per-frame image builder ──────────────────────────────────────────────────
-- level: fill fraction 0..1
-- phaseRad: wave phase in radians
local function buildImage(fillLevel, phaseRad)
  local img      = Image(sprite.spec)
  img:clear()

  -- Row where the flat surface sits (0 = top of image, h-1 = bottom)
  local baseY = math.floor(h * (1.0 - fillLevel))

  for it in img:pixels() do
    local x = it.x
    local y = it.y

    -- Per-column wave displacement (sinusoidal surface)
    local wave = math.floor(
      amplitude * math.sin(2 * math.pi * frequency * x / math.max(w, 1) + phaseRad)
      + 0.5
    )
    local surfY = baseY + wave

    if y > surfY then
      -- ── Liquid body ───────────────────────────────────────────────────────
      local r, g, b = r0, g0, b0

      -- Depth shading: darken toward the bottom of the liquid column
      if doDepth then
        local liquidHeight = (h - 1) - (surfY + 1)
        if liquidHeight > 0 then
          local t = (y - (surfY + 1)) / liquidHeight * 0.35  -- max 35% dark
          r = lerp(r, 0, t)
          g = lerp(g, 0, t)
          b = lerp(b, 0, t)
        end
      end

      -- Left highlight: blend toward white (light entering the glass)
      if doHighlight and w > 1 then
        local hW = math.max(1, math.floor(w * 0.15))
        if x < hW then
          local t = (1.0 - x / hW) * 0.5  -- up to 50% white
          r = lerp(r, 255, t)
          g = lerp(g, 255, t)
          b = lerp(b, 255, t)
        end
      end

      -- Right shadow: blend toward black
      if doShadow and w > 1 then
        local sW = math.max(1, math.floor(w * 0.15))
        if x >= w - sW then
          local t = ((x - (w - sW)) / sW) * 0.3  -- up to 30% dark
          r = lerp(r, 0, t)
          g = lerp(g, 0, t)
          b = lerp(b, 0, t)
        end
      end

      it(app.pixelColor.rgba(clamp(r, 0, 255), clamp(g, 0, 255), clamp(b, 0, 255), a0))

    elseif y == surfY then
      -- ── Surface line: brightened to simulate the liquid's top reflection ──
      local sr = lerp(r0, 255, 0.5)
      local sg = lerp(g0, 255, 0.5)
      local sb = lerp(b0, 255, 0.5)
      it(app.pixelColor.rgba(clamp(sr, 0, 255), clamp(sg, 0, 255), clamp(sb, 0, 255), a0))

    else
      -- ── Above surface: fully transparent ──────────────────────────────────
      it(app.pixelColor.rgba(0, 0, 0, 0))
    end
  end

  return img
end

-- ── Commit ───────────────────────────────────────────────────────────────────
local startFrame = app.frame.frameNumber
local celPosition = cel.position   -- capture before the transaction invalidates the cel
local label      = isAnimation and "Glass Fill Animation" or "Glass Fill"

app.transaction(label, function()
  for fi = 1, numFrames do
    local frameIdx = startFrame + fi - 1

    -- Normalised progress: frame 1 → startLevel, frame numFrames → targetLevel
    local t         = fi / numFrames
    local fillLevel = startLevel + (targetLevel - startLevel) * t

    -- Optionally shift wave phase per frame to simulate sloshing
    local phaseRad  = basePhaseRad
    if isAnimation and doAnimWave then
      phaseRad = phaseRad + (fi - 1) * (2 * math.pi / numFrames)
    end

    if isAnimation then
      -- Extend sprite with empty frames as needed
      while #sprite.frames < frameIdx do
        sprite:newEmptyFrame(#sprite.frames + 1)
      end
      sprite.frames[frameIdx].duration = frameDurMs
    end

    local img = buildImage(fillLevel, phaseRad)
    sprite:newCel(app.layer, sprite.frames[frameIdx], img, celPosition)
  end
end)

app.refresh()
