-- potions.lua — Aseprite script
-- Procedurally generates a pixel-art alchemy potion item sprite on a new layer.
-- Draws the full bottle silhouette, glass shading, liquid fill, cork, and highlights.

local sprite = app.sprite
if not sprite then app.alert("No active sprite!") return end

if sprite.colorMode ~= ColorMode.RGB then
  app.alert("Potions requires an RGB color mode sprite.")
  return
end

-- ── Dialog ────────────────────────────────────────────────────────────────────
local dlg = Dialog("Potion Generator")

dlg:separator{ text = "Bottle Shape" }
dlg:combobox {
  id      = "bottle_style",
  label   = "Style:",
  option  = "Round",
  options = { "Round", "Flask", "Vial", "Square" }
}
dlg:slider { id = "size",   label = "Size (px wide):", min = 8,  max = 64, value = 16 }

dlg:separator{ text = "Liquid" }
dlg:color  { id = "liquid_color", label = "Liquid Color:",   color = Color{ r=200, g=50,  b=220, a=220 } }
dlg:slider { id = "fill_level",   label = "Fill Level (%):", min=10, max=95, value=65 }
dlg:check  { id = "bubbles",      label = "Details:",        text="Bubbles",        selected=true }
dlg:check  { id = "shimmer",      label   = "",              text="Liquid shimmer", selected=true }

dlg:separator{ text = "Glass" }
dlg:color  { id = "glass_tint",   label = "Glass Tint:",   color = Color{ r=180, g=220, b=240, a=80 } }
dlg:check  { id = "dark_outline", label = "Outline:",      text="Dark outline",  selected=true }
dlg:check  { id = "highlight",    label = "Shine:",        text="Left highlight", selected=true }
dlg:check  { id = "shadow_side",  label = "Shadow:",       text="Right shadow",   selected=true }

dlg:separator{ text = "Cork" }
dlg:check  { id = "show_cork",    label = "Cork:",  text="Show cork",   selected=true }
dlg:color  { id = "cork_color",   label = "Color:", color = Color{ r=160, g=110, b=60, a=255 } }

dlg:separator{ text = "Output" }
dlg:check  { id = "new_layer",    label = "Layer:",  text="Draw on new layer", selected=true }

dlg:separator()
dlg:button { id = "ok",     text = "Generate", focus = true }
dlg:button { id = "cancel", text = "Cancel" }

dlg:show()

local data = dlg.data
if not data.ok then return end

-- ── Helpers ───────────────────────────────────────────────────────────────────
local pc = app.pixelColor

local function rgba(r, g, b, a)
  return pc.rgba(
    math.max(0, math.min(255, math.floor(r))),
    math.max(0, math.min(255, math.floor(g))),
    math.max(0, math.min(255, math.floor(b))),
    math.max(0, math.min(255, math.floor(a)))
  )
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function lerp(a, b, t) return a + (b - a) * t end

-- Blend src colour over dst colour (alpha compositing)
local function blend(dstR, dstG, dstB, dstA, srcR, srcG, srcB, srcA)
  local sa = srcA / 255
  local da = dstA / 255
  local outA = sa + da * (1 - sa)
  if outA <= 0 then return 0, 0, 0, 0 end
  local outR = (srcR * sa + dstR * da * (1 - sa)) / outA
  local outG = (srcG * sa + dstG * da * (1 - sa)) / outA
  local outB = (srcB * sa + dstB * da * (1 - sa)) / outA
  return outR, outG, outB, outA * 255
end

-- Draw a filled circle on an image (pixel value fn receives x, y)
local function circle(img, cx, cy, radius, pixelFn)
  local r2 = radius * radius
  for dy = -radius, radius do
    for dx = -radius, radius do
      if dx*dx + dy*dy <= r2 then
        local px, py = cx + dx, cy + dy
        if px >= 0 and py >= 0 and px < img.width and py < img.height then
          local v = pixelFn(px, py)
          if v then img:drawPixel(px, py, v) end
        end
      end
    end
  end
end

-- ── Layout maths ─────────────────────────────────────────────────────────────
local bottleStyle = data.bottle_style
local W           = math.floor(data.size)          -- must be even for symmetry
if W % 2 ~= 0 then W = W + 1 end
local H           = math.floor(W * 1.6)            -- overall canvas height
if H < 12 then H = 12 end

-- Ensure canvas is large enough
if sprite.width < W or sprite.height < H then
  app.alert(
    string.format(
      "Sprite is too small. Please use a canvas of at least %d×%d px.",
      W, H
    )
  )
  return
end

-- Body geometry — varies per style
-- All measurements are in pixels relative to the top of the image.
local bodyX1, bodyX2, bodyY1, bodyY2  -- body bounding box (inclusive)
local neckX1, neckX2, neckY1, neckY2 -- neck bounding box
local bodyRadius                       -- used for Round / Flask

local cx = math.floor(W / 2)          -- horizontal centre

-- Cork parameters (placed above the neck)
local corkH = math.max(2, math.floor(W * 0.12))
local corkW

if bottleStyle == "Round" then
  -- Large round body, short narrow neck
  bodyRadius = math.floor(W * 0.42)
  local neckW = math.max(2, math.floor(W * 0.22))
  neckW = neckW + (neckW % 2)           -- keep even
  neckX1 = cx - math.floor(neckW / 2)
  neckX2 = cx + math.floor(neckW / 2) - 1
  neckY2 = H - 2
  bodyY2 = neckY2
  bodyY1 = neckY2 - bodyRadius * 2 + 1
  neckY1 = bodyY1 - math.floor(H * 0.22)
  corkW  = neckW + 2

elseif bottleStyle == "Flask" then
  -- Flat-bottomed hex-shoulder flask
  local neckW = math.max(2, math.floor(W * 0.26))
  neckW = neckW + (neckW % 2)
  bodyX1 = 1
  bodyX2 = W - 2
  bodyY2 = H - 2
  bodyY1 = math.floor(H * 0.38)
  neckX1 = cx - math.floor(neckW / 2)
  neckX2 = cx + math.floor(neckW / 2) - 1
  neckY1 = 1
  neckY2 = bodyY1 - 1
  bodyRadius = nil
  corkW  = neckW + 2

elseif bottleStyle == "Vial" then
  -- Tall narrow tube, rounded bottom
  bodyX1 = math.floor(W * 0.2)
  bodyX2 = W - bodyX1 - 1
  bodyY2 = H - 2
  bodyY1 = 1
  -- No distinct neck for vial — reuse body dims for neck
  neckX1 = bodyX1
  neckX2 = bodyX2
  neckY1 = bodyY1
  neckY2 = math.floor(H * 0.15)
  bodyRadius = math.floor((bodyX2 - bodyX1) / 2)
  corkW  = (bodyX2 - bodyX1) + 2

else -- Square
  bodyX1 = 1
  bodyX2 = W - 2
  bodyY2 = H - 2
  bodyY1 = math.floor(H * 0.28)
  local neckW = math.max(2, math.floor(W * 0.30))
  neckW = neckW + (neckW % 2)
  neckX1 = cx - math.floor(neckW / 2)
  neckX2 = cx + math.floor(neckW / 2) - 1
  neckY1 = 1
  neckY2 = bodyY1 - 1
  bodyRadius = nil
  corkW  = neckW + 2
end

local corkX1 = cx - math.floor(corkW / 2)
local corkX2 = cx + math.floor(corkW / 2) - 1
local corkY2 = neckY1 - 1
local corkY1 = corkY2 - corkH + 1

-- ── Liquid fill bounds ────────────────────────────────────────────────────────
-- Fill level measured from the bottom of the body upward.
local fillRatio  = data.fill_level / 100.0

-- ── Colour values ─────────────────────────────────────────────────────────────
local liqR = data.liquid_color.red
local liqG = data.liquid_color.green
local liqB = data.liquid_color.blue
local liqA = data.liquid_color.alpha

local gtR = data.glass_tint.red
local gtG = data.glass_tint.green
local gtB = data.glass_tint.blue
local gtA = data.glass_tint.alpha

local ckR = data.cork_color.red
local ckG = data.cork_color.green
local ckB = data.cork_color.blue

local TRANSPARENT = rgba(0, 0, 0, 0)
local OUTLINE     = rgba(20, 15, 30, 255)

-- ── Build target layer / image ────────────────────────────────────────────────
local targetLayer
local targetFrame = app.frame

app.transaction("Generate Potion", function()

  if data.new_layer then
    targetLayer = sprite:newLayer()
    targetLayer.name = "Potion – " .. bottleStyle
  else
    targetLayer = app.layer
  end

  -- Create a blank image the size of the sprite canvas
  local img = Image(sprite.spec)
  img:clear(TRANSPARENT)

  -- ── Helper: is pixel inside the bottle body? ────────────────────────────────
  -- Returns true / false, and the local x-fraction within the body [0..1].
  local function inBody(x, y)
    if bottleStyle == "Round" then
      local bodyCX = cx
      local bodyCY = math.floor((bodyY1 + bodyY2) / 2)
      local dx = x - bodyCX
      local dy = y - bodyCY
      -- Squash vertically slightly for a rounder look
      local rx = bodyRadius
      local ry = bodyRadius
      return (dx*dx)/(rx*rx) + (dy*dy)/(ry*ry) <= 1.0
    elseif bottleStyle == "Vial" then
      if x < bodyX1 or x > bodyX2 then return false end
      -- Rounded cap at bottom
      if y <= bodyY2 - bodyRadius then
        return true  -- straight tube section
      else
        -- semicircle cap
        local capCY = bodyY2 - bodyRadius
        local dx = x - cx
        local dy = y - capCY
        return dx*dx + dy*dy <= bodyRadius * bodyRadius
      end
    else
      -- Flask / Square: rectangular body
      return x >= bodyX1 and x <= bodyX2 and y >= bodyY1 and y <= bodyY2
    end
  end

  local function inNeck(x, y)
    return x >= neckX1 and x <= neckX2 and y >= neckY1 and y <= neckY2
  end

  local function inCork(x, y)
    if not data.show_cork then return false end
    return x >= corkX1 and x <= corkX2 and y >= corkY1 and y <= corkY2
  end

  -- ── Fill level surface row ──────────────────────────────────────────────────
  -- We compute a per-column surface considering body geometry.
  -- For simplicity, use a flat liquid surface row.
  local liquidTopY
  if bottleStyle == "Round" then
    local bodyH = bodyY2 - bodyY1
    liquidTopY = bodyY2 - math.floor(bodyH * fillRatio)
  elseif bottleStyle == "Vial" then
    local bodyH = bodyY2 - bodyY1
    liquidTopY = bodyY2 - math.floor(bodyH * fillRatio)
  else
    local bodyH = bodyY2 - bodyY1
    liquidTopY = bodyY2 - math.floor(bodyH * fillRatio)
  end

  -- Also fill the neck if liquid is at the top
  local neckFilled = fillRatio >= 0.95

  -- ── Draw each pixel ──────────────────────────────────────────────────────────
  math.randomseed(42)  -- deterministic decorations

  -- Pre-generate bubble positions
  local bubbles = {}
  if data.bubbles then
    local numBubbles = math.max(1, math.floor(W * 0.4))
    for i = 1, numBubbles do
      local bx, by, br
      if bottleStyle == "Round" then
        bx = cx + math.random(-bodyRadius + 3, bodyRadius - 3)
        by = math.random(liquidTopY + 2, bodyY2 - 2)
        br = math.random(1, math.max(1, math.floor(W * 0.07)))
      elseif bottleStyle == "Vial" then
        local halfW = math.floor((bodyX2 - bodyX1) / 2) - 1
        bx = cx + math.random(-halfW + 1, halfW - 1)
        by = math.random(liquidTopY + 2, bodyY2 - 3)
        br = math.random(1, math.max(1, math.floor(W * 0.07)))
      else
        bx = math.random(bodyX1 + 2, bodyX2 - 2)
        by = math.random(liquidTopY + 2, bodyY2 - 2)
        br = math.random(1, math.max(1, math.floor(W * 0.07)))
      end
      bubbles[#bubbles + 1] = { x=bx, y=by, r=br }
    end
  end

  local function isBubble(x, y)
    for _, b in ipairs(bubbles) do
      local dx = x - b.x
      local dy = y - b.y
      if dx*dx + dy*dy <= b.r * b.r then return true end
    end
    return false
  end

  -- ── Pass 1: body fill (liquid + glass tint) ─────────────────────────────────
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local isBottleBody = inBody(x, y)
      local isNeck       = inNeck(x, y)
      local isCork       = inCork(x, y)

      if isCork then
        -- Cork: flat colour with simple shading
        local shade = 1.0
        local corkW2 = corkX2 - corkX1
        local tx = (x - corkX1) / math.max(1, corkW2)
        shade = lerp(1.1, 0.75, tx)   -- lighter left, darker right
        -- Grain lines
        if (y - corkY1) % math.max(2, math.floor(corkH / 3)) == 0 then shade = shade * 0.88 end
        img:drawPixel(x, y, rgba(ckR * shade, ckG * shade, ckB * shade, 255))

      elseif isBottleBody or isNeck then
        -- Determine if this pixel is in the liquid zone
        local inLiquid = false
        if isBottleBody and y >= liquidTopY then
          inLiquid = true
        elseif isNeck and neckFilled then
          inLiquid = true
        end

        -- Width of the container at this row (for shading x-fraction)
        local rowX1, rowX2
        if isNeck or (not isBottleBody) then
          rowX1, rowX2 = neckX1, neckX2
        elseif bottleStyle == "Round" then
          -- Chord width of the circle at row y
          local bodyCY = math.floor((bodyY1 + bodyY2) / 2)
          local dy2 = (y - bodyCY) * (y - bodyCY)
          local chord = math.floor(math.sqrt(math.max(0, bodyRadius * bodyRadius - dy2)))
          rowX1 = cx - chord
          rowX2 = cx + chord
        elseif bottleStyle == "Vial" then
          rowX1, rowX2 = bodyX1, bodyX2
        else
          rowX1, rowX2 = bodyX1, bodyX2
        end

        local rowW = math.max(1, rowX2 - rowX1)
        local tx   = (x - rowX1) / rowW   -- 0 = left edge, 1 = right edge

        -- ── Bubble check (draws bright outline ring) ──────────────────────────
        if inLiquid and data.bubbles and isBubble(x, y) then
          -- Bubble is slightly lighter than liquid
          local br2, bg2, bb2 = liqR * 1.4, liqG * 1.4, liqB * 1.4
          img:drawPixel(x, y, rgba(br2, bg2, bb2, liqA))

        elseif inLiquid then
          -- ── Liquid pixel ────────────────────────────────────────────────────
          local r, g, b, a = liqR, liqG, liqB, liqA

          -- Depth shading: darker near bottom
          local bodyH = bodyY2 - liquidTopY
          local depthT = bodyH > 0 and (y - liquidTopY) / bodyH or 0
          r = lerp(r * 1.15, r * 0.65, depthT)
          g = lerp(g * 1.15, g * 0.65, depthT)
          b = lerp(b * 1.15, b * 0.65, depthT)

          -- Side shading: darker at edges, brighter in centre
          local edgeDist = math.min(tx, 1 - tx) * 2   -- 0 at edge, 1 at centre
          r = lerp(r * 0.6, r, edgeDist)
          g = lerp(g * 0.6, g, edgeDist)
          b = lerp(b * 0.6, b, edgeDist)

          -- Shimmer: a subtle bright stripe at the liquid surface
          if data.shimmer and y == liquidTopY then
            r = clamp(r * 1.5, 0, 255)
            g = clamp(g * 1.5, 0, 255)
            b = clamp(b * 1.5, 0, 255)
          end

          img:drawPixel(x, y, rgba(r, g, b, a))

        else
          -- ── Empty glass pixel ────────────────────────────────────────────────
          -- Composite glass tint over transparency
          local r, g, b, a = gtR, gtG, gtB, gtA

          -- Highlight: bright streak on left ~15% width
          if data.highlight and tx < 0.18 then
            local hStrength = (0.18 - tx) / 0.18
            r = lerp(r, 255, hStrength * 0.7)
            g = lerp(g, 255, hStrength * 0.7)
            b = lerp(b, 255, hStrength * 0.7)
            a = clamp(lerp(a, 220, hStrength * 0.6), 0, 255)
          end

          -- Shadow: darker on right ~15% width
          if data.shadow_side and tx > 0.82 then
            local sStrength = (tx - 0.82) / 0.18
            r = lerp(r, 0, sStrength * 0.55)
            g = lerp(g, 0, sStrength * 0.55)
            b = lerp(b, 0, sStrength * 0.55)
            a = clamp(lerp(a, 180, sStrength * 0.4), 0, 255)
          end

          img:drawPixel(x, y, rgba(r, g, b, a))
        end
      end
    end
  end

  -- ── Pass 2: dark outline (1-px border around the full bottle silhouette) ────
  if data.dark_outline then
    -- Collect a set of bottle pixels first so we can reference neighbours
    local bottleSet = {}
    for y = 0, H - 1 do
      bottleSet[y] = {}
      for x = 0, W - 1 do
        local isCork = inCork(x, y)
        local isGlass = inBody(x, y) or inNeck(x, y)
        bottleSet[y][x] = isGlass or isCork
      end
    end

    for y = 0, H - 1 do
      for x = 0, W - 1 do
        if bottleSet[y][x] then
          -- Check 4-neighbours
          local onEdge = false
          if x == 0 or not bottleSet[y][x-1] then onEdge = true end
          if x == W-1 or not bottleSet[y][x+1] then onEdge = true end
          if y == 0 or not bottleSet[y-1][x] then onEdge = true end
          if y == H-1 or not bottleSet[y+1][x] then onEdge = true end
          if onEdge then img:drawPixel(x, y, OUTLINE) end
        end
      end
    end
  end

  -- ── Commit ────────────────────────────────────────────────────────────────
  sprite:newCel(targetLayer, targetFrame, img, Point(0, 0))

end)  -- end app.transaction

app.refresh()
