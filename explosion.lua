-- Explosion Animation — Aseprite script
-- Generates frames of an expanding explosion on the active layer,
-- starting from the active frame.  Works similarly to glass_fill.lua:
-- each frame is built on a cloned / fresh Image and committed inside a
-- single app.transaction() so the whole animation is one undo step.

local sprite = app.sprite
if not sprite then app.alert("No active sprite!") return end

local layer = app.layer
if not layer then app.alert("No active layer!") return end

if not layer.isEditable then
  app.alert("Layer is not editable.")
  return
end

if sprite.colorMode ~= ColorMode.RGB then
  app.alert("Explosion Animation requires an RGB color mode sprite.")
  return
end

-- ── Dialog ───────────────────────────────────────────────────────────────────
local dlg = Dialog("Explosion Animation")

dlg:slider { id="frames",     label="Frame Count:",      min=4,  max=32,  value=12 }
dlg:slider { id="duration",   label="Frame Delay (ms):", min=20, max=500, value=80 }
dlg:slider { id="radius",     label="Max Radius (px):",  min=8,  max=200, value=60 }
dlg:slider { id="jaggedness", label="Edge Jaggedness:",  min=0,  max=100, value=45 }

dlg:separator{ text="Effects" }
dlg:check  { id="sparks", label="Sparks:", text="Flying embers",   selected=true }
dlg:check  { id="smoke",  label="Smoke:",  text="Billowing smoke", selected=true }

dlg:separator{ text="Randomization" }
dlg:number { id="seed", label="Seed:", text=tostring(math.floor(os.time())), decimals=0 }

dlg:separator()
dlg:button { id="ok",     text="Generate", focus=true }
dlg:button { id="cancel", text="Cancel" }

dlg:show()

local data = dlg.data
if not data.ok then return end

-- ── Parameters ────────────────────────────────────────────────────────────────
local numFrames  = data.frames
local frameDurMs = data.duration
local maxRadius  = data.radius
local jaggedness = data.jaggedness / 100.0
local doSparks   = data.sparks
local doSmoke    = data.smoke
local seed       = math.floor(data.seed or os.time())

math.randomseed(seed)

local w  = sprite.width
local h  = sprite.height
local cx = w / 2.0
local cy = h / 2.0
local pc = app.pixelColor

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function lerp(a, b, t)    return a + (b - a) * t end
local function ci(v)            return clamp(math.floor(v + 0.5), 0, 255) end

-- Evaluate a multi-stop color gradient at position t ∈ [0, 1].
-- stops: array of { t, r, g, b } sorted ascending by t.
local function sampleGradient(stops, t)
  if t <= stops[1][1] then return stops[1][2], stops[1][3], stops[1][4] end
  if t >= stops[#stops][1] then
    local s = stops[#stops]; return s[2], s[3], s[4]
  end
  for i = 1, #stops - 1 do
    local s0, s1 = stops[i], stops[i + 1]
    if t >= s0[1] and t <= s1[1] then
      local f = (t - s0[1]) / (s1[1] - s0[1])
      return lerp(s0[2], s1[2], f), lerp(s0[3], s1[3], f), lerp(s0[4], s1[4], f)
    end
  end
  return 0, 0, 0
end

-- Fire hue ramp — color of the expanding fire ring keyed to animation t
local fireRamp = {
  { 0.00, 255, 255, 210 },  -- white-yellow flash
  { 0.15, 255, 230,  55 },  -- bright yellow
  { 0.35, 255, 125,  15 },  -- orange
  { 0.60, 220,  42,   8 },  -- red-orange
  { 0.80, 130,  18,   5 },  -- deep red
  { 1.00,  75,  68,  62 },  -- ash gray
}

-- Smoke color ramp — interior burned region
local smokeRamp = {
  { 0.00,  40,  28,  18 },  -- charred near-black
  { 0.50,  62,  58,  52 },  -- dark gray
  { 1.00, 105,  98,  92 },  -- medium gray
}

-- ── Polar noise for organic boundary distortion ───────────────────────────────
-- Build a random set of sinusoidal harmonics once.  Evaluating them at a pixel's
-- angle gives a smooth, blob-like distortion of the circular explosion boundary.
local NUM_H = 7
local harmonics = {}
for i = 1, NUM_H do
  harmonics[i] = {
    amp   = math.random() / NUM_H,   -- amplitude ∈ (0, 1/NUM_H]
    freq  = math.random(2, 8),
    phase = math.random() * 2 * math.pi,
  }
end

-- Returns ~[-0.5, 0.5]; multiply by jaggedness to get actual boundary shift
local function polarNoise(angle)
  local v = 0
  for i = 1, NUM_H do
    local h = harmonics[i]
    v = v + h.amp * math.sin(h.freq * angle + h.phase)
  end
  return v
end

-- ── Sparks (flying embers) ────────────────────────────────────────────────────
local sparks = {}
if doSparks then
  local numSparks = 18 + math.random(0, 14)
  for i = 1, numSparks do
    sparks[i] = {
      angle  = math.random() * 2 * math.pi,
      speed  = 0.75 + math.random() * 0.65,  -- radial speed as fraction of maxRadius/t
      birthT = math.random() * 0.25,          -- spark spawns during first quarter
      deathT = 0.45 + math.random() * 0.50,  -- spark fades out mid-to-late
    }
  end
end

-- ── Starting frame (generate forward from the active frame) ───────────────────
local startFrame = app.frame.frameNumber

-- ── Main generation loop — one undoable transaction ──────────────────────────
app.transaction("Explosion Animation", function()
  for fi = 1, numFrames do
    local frameIdx = startFrame + fi - 1

    -- Extend the sprite with blank frames as needed
    while #sprite.frames < frameIdx do
      sprite:newEmptyFrame(#sprite.frames + 1)
    end
    sprite.frames[frameIdx].duration = frameDurMs

    -- Normalized animation time: 0 = start, 1 = end
    local t = (fi - 1) / math.max(numFrames - 1, 1)

    -- Radius uses a √t curve (fast initial expansion, slower later).
    -- Offset by half a frame so the very first frame shows a visible flash
    -- instead of a zero-radius blank.
    local tRadius = (fi - 0.5) / numFrames
    local curR    = math.sqrt(tRadius) * maxRadius

    -- Ring geometry: the fire occupies a ring behind the expanding front.
    -- The ring is wide early (more fire), narrower late (more smoke inside).
    local ringFrac  = lerp(0.62, 0.30, t)
    local ringW     = curR * ringFrac
    local outerBase = curR
    local innerBase = math.max(0.0, outerBase - ringW)

    -- Overall opacity envelope: full opacity until 70% of the animation,
    -- then fades to zero so the explosion disappears cleanly.
    local envelope = t < 0.70 and 1.0 or (1.0 - (t - 0.70) / 0.30)

    -- Build a fresh transparent frame image
    local img = Image(sprite.spec)
    img:clear()

    -- ── Pixel pass ────────────────────────────────────────────────────────────
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local dx = x - cx + 0.5
        local dy = y - cy + 0.5
        local d  = math.sqrt(dx * dx + dy * dy)

        -- Quick cull: skip pixels well outside the explosion boundary
        if d <= outerBase * 1.55 + 2 then
          local angle = math.atan(dy, dx)
          local noise = polarNoise(angle)    -- ∈ approx [-0.5, 0.5]
          local jag   = noise * jaggedness   -- scaled distortion amount

          -- Apply jaggedness to both boundaries; outer boundary is distorted
          -- more than the inner one so the ring thickness stays reasonable.
          local outerR = outerBase * (1.0 + jag * 0.45)
          local innerR = math.max(0.0, innerBase * (1.0 + jag * 0.25))

          if d <= outerR then

            if d <= innerR then
              -- ── Smoke / burned interior ──────────────────────────────────
              if doSmoke then
                -- Smoke presence grows from 0 → full between t=0.10 and t=0.40
                local smokePresence = math.max(0.0, math.min(1.0, (t - 0.10) / 0.30))
                local sa = ci(195 * smokePresence * envelope)
                if sa > 0 then
                  local sr, sg, sb = sampleGradient(smokeRamp, t)
                  -- Darker toward center (depth cue inside the smoke cloud)
                  local depthFade = d / math.max(innerR, 1)
                  sr = ci(sr * lerp(0.55, 1.0, depthFade))
                  sg = ci(sg * lerp(0.55, 1.0, depthFade))
                  sb = ci(sb * lerp(0.55, 1.0, depthFade))
                  img:drawPixel(x, y, pc.rgba(sr, sg, sb, sa))
                end
              end

            else
              -- ── Fire ring ────────────────────────────────────────────────
              -- ringPos: 0 = inner edge of ring, 1 = outer (leading) edge
              local ringPos = (d - innerR) / math.max(outerR - innerR, 1)

              local fr, fg, fb = sampleGradient(fireRamp, t)

              -- Brighten the leading edge to simulate the fire front
              local brightFactor = ringPos ^ 1.5
              fr = lerp(fr, 255, brightFactor * 0.55)
              fg = lerp(fg, 255, brightFactor * 0.30)
              fb = lerp(fb, 255, brightFactor * 0.08)

              -- Alpha slightly reduced toward the inner edge for a soft blend
              local alphaFade = lerp(0.65, 1.0, ringPos)
              local fa = ci(255 * alphaFade * envelope)

              img:drawPixel(x, y, pc.rgba(ci(fr), ci(fg), ci(fb), fa))
            end
          end
        end
      end
    end

    -- ── Sparks ────────────────────────────────────────────────────────────────
    if doSparks then
      for _, sp in ipairs(sparks) do
        if t >= sp.birthT and t <= sp.deathT then
          local sparkLife = (t - sp.birthT) / (sp.deathT - sp.birthT)
          local sparkDist = sp.speed * tRadius * maxRadius
          local sx = math.floor(cx + math.cos(sp.angle) * sparkDist)
          local sy = math.floor(cy + math.sin(sp.angle) * sparkDist)

          if sx >= 0 and sx < w and sy >= 0 and sy < h then
            -- Sparks are bright white-yellow cooling to orange as they age
            local sa = ci(255 * (1.0 - sparkLife) * envelope)
            local sr = 255
            local sg = ci(lerp(235, 65, sparkLife))
            local sb = ci(lerp(130, 0,  sparkLife))

            -- 2×2 pixel embers so they are visible at small sprite sizes
            img:drawPixel(sx, sy, pc.rgba(sr, sg, sb, sa))
            if sx + 1 < w then img:drawPixel(sx + 1, sy,     pc.rgba(sr, sg, sb, sa)) end
            if sy + 1 < h then img:drawPixel(sx,     sy + 1, pc.rgba(sr, sg, sb, sa)) end
          end
        end
      end
    end

    -- Commit the composed image as a cel on the target frame
    sprite:newCel(layer, sprite.frames[frameIdx], img, Point(0, 0))
  end
end)

app.refresh()
