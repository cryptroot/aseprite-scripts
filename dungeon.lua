-- dungeon.lua
-- Detailed dungeon background generator.
-- Parameters: brick structure, degradation levels, passageway with optional
-- arched top, wall holes, wall-mounted torches with warm glow.

local sprite = app.sprite
if not sprite then app.alert("No active sprite!") return end

local cel = app.cel
if not cel then app.alert("No active cel!") return end

local layer = app.layer
if not layer.isEditable then app.alert("Layer is not editable.") return end

if sprite.colorMode ~= ColorMode.RGB then
  app.alert("Dungeon Generator requires an RGB color mode sprite.")
  return
end

local w  = sprite.width
local h  = sprite.height
local pc = app.pixelColor

-- ── Helpers ──────────────────────────────────────────────────────────────────
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function ci(v)            return clamp(math.floor(v + 0.5), 0, 255) end
local function setpx(r, g, b)   return pc.rgba(ci(r), ci(g), ci(b), 255) end
local function lerp(a, b, t)    return a + (b - a) * t end

-- ── Dialog ───────────────────────────────────────────────────────────────────
local defaultSeed = math.floor(os.time())

local dlg = Dialog("Dungeon Generator")

dlg:separator{ text = "Brick Structure" }
dlg:number{ id = "brick_w",  label = "Brick Width:",  text = "16", decimals = 0 }
dlg:number{ id = "brick_h",  label = "Brick Height:", text = "8",  decimals = 0 }
dlg:number{ id = "mortar_t", label = "Mortar Size:",  text = "1",  decimals = 0 }

dlg:separator{ text = "Degradation" }
dlg:slider{ id = "degrade", label = "Level (0–4):", min = 0, max = 4, value = 1 }

dlg:separator{ text = "Passageway" }
dlg:check{    id = "passage_on",  label = "Enable:",    text = "Show passageway", selected = true }
dlg:combobox{ id = "passage_pos", label = "Position:",  option = "Middle",
              options = { "Top", "Middle", "Bottom" } }
dlg:slider{   id = "passage_h",   label = "Height (%):", min = 10, max = 60, value = 30 }
dlg:check{    id = "arch_on",     label = "Arch:",       text = "Arched top",     selected = true }

dlg:separator{ text = "Wall Holes" }
dlg:slider{ id = "hole_count", label = "Count:",  min = 0, max = 8,  value = 2 }
dlg:slider{ id = "hole_size",  label = "Radius:", min = 3, max = 20, value = 7 }

dlg:separator{ text = "Torches" }
dlg:slider{ id = "torch_count", label = "Count:",       min = 0, max = 6,  value = 2 }
dlg:check{  id = "torch_glow",  label = "Glow Effect:", text = "Enable",  selected = true }

dlg:separator{ text = "Appearance" }
dlg:combobox{ id = "scheme", label = "Stone Type:",
  option = "Dark Stone",
  options = { "Dark Stone", "Sandstone", "Obsidian", "Mossy Stone" } }

dlg:separator()
dlg:number{ id = "seed", label = "Seed:", text = tostring(defaultSeed), decimals = 0 }
dlg:button{ id = "ok",     text = "Generate", focus = true }
dlg:button{ id = "cancel", text = "Cancel" }

dlg:show()

local data = dlg.data
if not data.ok then return end

-- ── Read parameters ───────────────────────────────────────────────────────────
local seed       = math.floor(data.seed or defaultSeed)
local bW         = math.max(4, math.floor(data.brick_w  or 16))
local bH         = math.max(2, math.floor(data.brick_h  or 8))
local mT         = math.max(1, math.floor(data.mortar_t or 1))
local degrade    = data.degrade or 1
local passOn     = data.passage_on
local passPos    = data.passage_pos or "Middle"
local passPct    = (data.passage_h or 30) / 100.0
local archOn     = data.arch_on
local holeCount  = math.floor(data.hole_count or 2)
local holeRadius = math.floor(data.hole_size  or 7)
local torchCount = math.floor(data.torch_count or 2)
local doTorchGlow = data.torch_glow
local scheme     = data.scheme or "Dark Stone"

-- ── Tileable value noise ──────────────────────────────────────────────────────
-- All lattices are GRID×GRID; all freq args must be ≤ GRID for seamless tiling.
local GRID = 16

local function buildLattice(s)
  math.randomseed(s)
  local t = {}
  for i = 1, GRID * GRID do t[i] = math.random() end
  return t
end

local lat1 = buildLattice(seed)           -- macro surface variation
local lat2 = buildLattice(seed + 7919)    -- fine detail / moss
local lat3 = buildLattice(seed + 3141)    -- staining / moisture

local function smooth(t) return t * t * (3 - 2 * t) end

local function sampleLat(lat, gx, gy, freq)
  return lat[(gy % freq) * freq + (gx % freq) + 1]
end

local function valueNoise(lat, nx, ny, freq)
  local fx  = (nx / w) * freq
  local fy  = (ny / h) * freq
  local ix0 = math.floor(fx) % freq
  local iy0 = math.floor(fy) % freq
  local ix1 = (ix0 + 1) % freq
  local iy1 = (iy0 + 1) % freq
  local tx  = smooth(fx - math.floor(fx))
  local ty  = smooth(fy - math.floor(fy))
  return lerp(
    lerp(sampleLat(lat, ix0, iy0, freq), sampleLat(lat, ix1, iy0, freq), tx),
    lerp(sampleLat(lat, ix0, iy1, freq), sampleLat(lat, ix1, iy1, freq), tx),
    ty
  )
end

local function fbm(nx, ny)
  return valueNoise(lat1, nx, ny, 8)  * 0.65
       + valueNoise(lat2, nx, ny, 16) * 0.35
end

-- ── Color schemes ─────────────────────────────────────────────────────────────
-- micro: 0–1 fine noise. brickVar: 0–1 per-brick brightness hash.
local function brickRGB(micro, brickVar)
  local base = 55 + brickVar * 24 + micro * 20
  if scheme == "Dark Stone"  then return base - 2, base - 4, base + 1 end
  if scheme == "Sandstone"   then return base + 50, base + 35, base + 10 end
  if scheme == "Obsidian"    then local b = base * 0.4; return b + 5, b, b + 8 end
  if scheme == "Mossy Stone" then return base - 5, base + 4, base - 3 end
  return base, base, base
end

local function mortarRGB()
  if scheme == "Dark Stone"  then return 22, 22, 26 end
  if scheme == "Sandstone"   then return 55, 48, 32 end
  if scheme == "Obsidian"    then return  8,  8, 12 end
  if scheme == "Mossy Stone" then return 20, 28, 18 end
  return 22, 22, 26
end

-- ── Passageway geometry ───────────────────────────────────────────────────────
local passY1, passY2 = 0, -1  -- sentinel: no passage

if passOn then
  local pH = math.max(4, math.floor(h * passPct))
  if passPos == "Top" then
    passY1, passY2 = 0, pH
  elseif passPos == "Bottom" then
    passY1, passY2 = h - pH, h
  else  -- Middle
    passY1 = math.floor((h - pH) / 2)
    passY2 = passY1 + pH
  end
end

-- Returns true when pixel (vx, vy) is inside the open passage void.
-- With archOn, the top of the opening is an elliptical arch that narrows
-- toward the apex, giving a classic stone-arch shape.
local function inVoid(vx, vy)
  if not passOn then return false end
  if vy < passY1 or vy >= passY2 then return false end
  if not archOn then return true end
  -- Lower 55% of the passage is fully open (rectangular floor section).
  local archDepth = math.max(1, math.floor((passY2 - passY1) * 0.45))
  local archBase  = passY1 + archDepth   -- y at which the opening is full-width
  if vy >= archBase then return true end
  -- Arch zone: inside an ellipse that widens from apex (passY1) to base (archBase).
  local cx    = (w - 1) / 2.0
  local halfW = (w - 1) / 2.0
  local dy    = vy - archBase              -- negative in arch zone
  local hw    = halfW * math.sqrt(math.max(0, 1 - (dy / archDepth) ^ 2))
  return math.abs(vx - cx) <= hw
end

-- ── Wall holes ────────────────────────────────────────────────────────────────
math.randomseed(seed + 1234)
local holes = {}

for _ = 1, holeCount do
  local hx, hy
  local placed = false
  for _ = 1, 50 do
    hx = math.random(holeRadius + 2, math.max(holeRadius + 3, w - holeRadius - 3))
    hy = math.random(holeRadius + 2, math.max(holeRadius + 3, h - holeRadius - 3))
    -- Only place holes in solid wall sections, not inside the passage.
    if not inVoid(hx, hy) then placed = true; break end
  end
  if placed then
    table.insert(holes, {
      x  = hx,
      y  = hy,
      rx = holeRadius,
      ry = math.max(2, math.floor(holeRadius * 0.6)),
    })
  end
end

-- Returns a depth value in [0, 1]: 0 outside, ~1 at centre.
-- The rim zone (depth ≤ RIM_THRESH) blends into the surrounding brick.
local RIM_THRESH = 0.18

local function holeDepth(vx, vy)
  local best = 0
  for _, hole in ipairs(holes) do
    local dx = vx - hole.x
    local dy = vy - hole.y
    local d  = (dx / hole.rx) ^ 2 + (dy / hole.ry) ^ 2
    if d < 1.0 then
      local depth = 1.0 - d
      if depth > best then best = depth end
    end
  end
  return best
end

-- ── Torches ───────────────────────────────────────────────────────────────────
-- Each torch is mounted on a brick face; its bracket sits at (x, y) and the
-- flame rises three pixels above it. The base flame pixel is one pixel wide on
-- each side for a flicker-of-life silhouette.

math.randomseed(seed + 9876)
local torches = {}

for _ = 1, torchCount do
  local tx, ty
  local placed = false
  for _ = 1, 60 do
    local row    = math.random(1, math.max(1, math.floor(h / bH) - 1))
    local offset = (row % 2 == 0) and 0 or math.floor(bW / 2)
    local col    = math.random(0, math.floor(w / bW))
    tx = col * bW - offset + math.floor(bW / 2)
    tx = ((tx % w) + w) % w
    ty = row * bH + math.floor(bH * 0.5)
    -- Bracket and tallest flame pixel must both be on-screen and in solid wall.
    if ty >= 4 and ty < h - 1
       and not inVoid(tx, ty)
       and not inVoid(tx, ty - 3)
       and holeDepth(tx, ty) == 0 then
      placed = true; break
    end
  end
  if placed then
    table.insert(torches, { x = tx, y = ty })
  end
end

-- Glow: warm orange light radiates outward from each torch flame.
local GLOW_RADIUS = math.max(bW, bH) * 3.5

local function torchGlowAt(vx, vy)
  if not doTorchGlow or #torches == 0 then return 0, 0, 0 end
  local tr, tg, tb = 0, 0, 0
  for _, torch in ipairs(torches) do
    local dist = math.sqrt((vx - torch.x) ^ 2 + (vy - torch.y) ^ 2)
    local inf  = math.max(0.0, 1.0 - dist / GLOW_RADIUS)
    inf = inf * inf  -- quadratic falloff for a softer penumbra
    tr  = tr + inf * 90
    tg  = tg + inf * 40
    tb  = tb + inf * 5
  end
  return tr, tg, tb
end

-- Returns the rendering role of pixel (vx, vy) relative to torch sprites.
-- "bracket" | "flame_base" | "flame_mid" | "flame_tip" | nil
local function torchRole(vx, vy)
  for _, torch in ipairs(torches) do
    local dx = vx - torch.x
    local dy = vy - torch.y
    if dx == 0 and dy == 0  then return "bracket"    end
    if dy == -1 and math.abs(dx) <= 1 then return "flame_base" end  -- 3-px wide base
    if dy == -2 and dx == 0 then return "flame_mid"  end
    if dy == -3 and dx == 0 then return "flame_tip"  end
  end
  return nil
end

-- ── Degradation ───────────────────────────────────────────────────────────────
-- Level 0: pristine.  Level 1: staining.  Level 2: hairline cracks appear.
-- Level 3: cracks widen + corners chip away.  Level 4: heavy ruin.

local function isCrack(bx, by_, col, row)
  if degrade < 2 then return false end
  -- Vertical hairline from the top mortar joint, frequency rises with level.
  local h1 = (col * 317 + row * 211) % 100
  if h1 < 20 + degrade * 9 then
    local cx       = mT + 1 + (h1 % math.max(1, bW - mT * 2 - 2))
    local crackLen = degrade
    if bx == cx and by_ >= mT and by_ <= mT + crackLen then return true end
  end
  -- Horizontal crack through the brick centre (level 3+).
  if degrade >= 3 then
    local h2 = (col * 191 + row * 373) % 100
    if h2 < 30 then
      local cy = math.floor(bH * 0.45)
      if by_ == cy and bx >= mT + 1 and bx <= mT + degrade then return true end
    end
  end
  return false
end

-- Returns a darkness factor [0, 1] for missing corner chunks (level 3+).
-- 0 means the pixel is intact; ≥ 0.95 means fully missing (void).
local function chunkDarkness(bx, by_, col, row)
  if degrade < 3 then return 0 end
  local threshold = (degrade - 2) * 22
  -- Top-left corner
  local h1 = (col * 251 + row * 173) % 100
  if h1 < threshold then
    local cx = mT + 1 + degrade
    local cy = mT + 1 + degrade
    if bx <= cx and by_ <= cy then
      return math.min(1.0, 0.45 + (cx - bx + cy - by_) * 0.15)
    end
  end
  -- Bottom-right corner
  local h2 = (col * 137 + row * 421) % 100
  if h2 < threshold then
    local cx = bW - mT - 2 - degrade
    local cy = bH - mT - 2 - degrade
    if bx >= cx and by_ >= cy then
      return math.min(1.0, 0.45 + (bx - cx + by_ - cy) * 0.15)
    end
  end
  return 0
end

-- ── Passage floor (flagstone pattern) ─────────────────────────────────────────
local function floorRGB(vx, vy, v)
  local fW = bW
  local fH = math.max(2, math.floor(bH * 0.75))
  local fx  = vx % fW
  local fy  = vy % fH
  -- Flagstone mortar joint
  if fx < 1 or fy < 1 then
    if scheme == "Sandstone"  then return 45, 38, 22 end
    if scheme == "Obsidian"   then return  6,  6,  8 end
    return 18, 18, 20
  end
  local flagVar = ((math.floor(vx / fW) * 137 + math.floor(vy / fH) * 89) % 48) / 48.0
  local base    = 30 + flagVar * 18 + v * 10
  if scheme == "Sandstone"   then return base + 20, base + 12, base - 5 end
  if scheme == "Obsidian"    then return base * 0.45, base * 0.45, base * 0.55 end
  if scheme == "Mossy Stone" then return base - 4, base + 2, base - 4 end
  return base, base, base + 2
end

-- ── Render ────────────────────────────────────────────────────────────────────
local newImage  = cel.image:clone()

-- Pre-compute the Y at which the passage floor begins (bottom 28% of passage).
local floorStart = passOn and (passY2 - math.floor((passY2 - passY1) * 0.28)) or (h + 1)

for it in newImage:pixels() do
  local x, y = it.x, it.y
  local v    = fbm(x, y)

  -- ── 1. Torches ─────────────────────────────────────────────────────────────
  -- Torch pixels are drawn on solid wall only (skip if void or inside a hole).
  if not inVoid(x, y) and holeDepth(x, y) == 0 then
    local role = torchRole(x, y)
    if role then
      if     role == "bracket"    then it(setpx( 75,  62,  48))
      elseif role == "flame_base" then it(setpx(255, 120,  10))
      elseif role == "flame_mid"  then it(setpx(255, 200,  30))
      else                             it(setpx(255, 240, 140))  -- flame_tip
      end
      goto continue
    end
  end

  -- ── 2. Passage void ────────────────────────────────────────────────────────
  if inVoid(x, y) then
    local gr, gg, gb = torchGlowAt(x, y)
    if y >= floorStart then
      -- Flagstone floor at the base of the passageway
      local fr, fg, fb = floorRGB(x, y, v)
      it(setpx(fr + gr, fg + gg, fb + gb))
    else
      -- Ceiling / upper void: near-black with very faint glow bleed
      local dark = valueNoise(lat3, x, y, 16) * 8
      it(setpx(dark + gr * 0.25, dark + gg * 0.25, dark + gb * 0.25))
    end
    goto continue
  end

  -- ── 3. Wall holes ──────────────────────────────────────────────────────────
  local depth = holeDepth(x, y)
  if depth > 0 then
    if depth > RIM_THRESH then
      -- Interior void: pure darkness
      it(setpx(0, 0, 0))
    else
      -- Rim shadow: brick colour fades to black toward the hole edge
      local t      = depth / RIM_THRESH   -- 0 at outer rim → 1 at inner edge
      local fade   = 1.0 - t
      local row    = math.floor(y / bH)
      local offset = (row % 2 == 0) and 0 or math.floor(bW / 2)
      local col    = math.floor((x + offset) / bW)
      local bv     = ((col * 137 + row * 89) % 64) / 64.0
      local micro  = valueNoise(lat1, x, y, 16) * 0.12
      local br, bg, bb = brickRGB(micro, bv)
      it(setpx(br * fade, bg * fade, bb * fade))
    end
    goto continue
  end

  -- ── 4. Brick wall ──────────────────────────────────────────────────────────
  do
    local row    = math.floor(y / bH)
    local offset = (row % 2 == 0) and 0 or math.floor(bW / 2)
    local bx     = (x + offset) % bW
    local by_    = y % bH
    local col    = math.floor((x + offset) / bW)
    local gr, gg, gb = torchGlowAt(x, y)

    -- Mortar joint
    if bx < mT or by_ < mT then
      local mr, mg, mb = mortarRGB()
      if degrade >= 3 then
        -- Moisture / mineral staining seeps into aged mortar
        local stain = valueNoise(lat3, x, y, 8) * 10
        mr = mr + stain * 0.3
        mg = mg + stain * 0.5
        mb = mb + stain * 0.2
      end
      it(setpx(mr + gr, mg + gg, mb + gb))
      goto continue
    end

    -- Cracks within the brick face
    if isCrack(bx, by_, col, row) then
      local mr, mg, mb = mortarRGB()
      it(setpx(mr * 0.7 + gr * 0.4, mg * 0.7 + gg * 0.4, mb * 0.7 + gb * 0.4))
      goto continue
    end

    -- Missing corner chunk
    local chunkD = chunkDarkness(bx, by_, col, row)
    if chunkD >= 0.95 then
      -- Fully chipped away — show shadow/void behind
      it(setpx(gr * 0.25, gg * 0.25, gb * 0.25))
      goto continue
    end

    -- Normal brick surface (possibly with partial chunk shadow or staining)
    local bv     = ((col * 137 + row * 89) % 64) / 64.0
    local micro  = valueNoise(lat1, x, y, 16) * 0.12
    local fade   = 1.0 - chunkD  -- partial shadow for partly-chipped corners

    -- Surface staining: uneven discolouration that worsens with degradation
    local stainMult = 1.0
    if degrade >= 1 then
      stainMult = 0.85 + valueNoise(lat3, x, y, 8) * 0.28
    end

    -- Moss / algae growth (Mossy Stone scheme, intensifies with degradation)
    local mossG = 0
    if scheme == "Mossy Stone" then
      local mossN = valueNoise(lat2, x, y, 8)
      local strength = 0.30 + degrade * 0.07
      if mossN < strength then mossG = (strength - mossN) * 30 end
    end

    local br, bg, bb = brickRGB(micro, bv)
    it(setpx(
      br             * stainMult * fade + gr,
      (bg + mossG)   * stainMult * fade + gg,
      bb             * stainMult * fade + gb
    ))
  end

  ::continue::
end

-- ── Commit ────────────────────────────────────────────────────────────────────
app.transaction("Generate Dungeon", function()
  sprite:newCel(layer, app.frame, newImage, cel.position)
end)

app.refresh()
