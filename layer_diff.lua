-- layer_diff.lua
-- Boolean "diff" of two layers: keeps only the pixels that differ between them.
-- The result is written to a new layer at the top of the stack.
--
--   Shape mode  → a pixel differs when exactly one layer is opaque there
--                 (symmetric difference of the two silhouettes).
--   Color mode  → a pixel differs when the two layers have different RGBA
--                 values there (covers shape *and* recoloured pixels).

local sprite = app.sprite
if not sprite then
  app.alert("No active sprite!")
  return
end

if sprite.colorMode ~= ColorMode.RGB then
  app.alert("Layer Diff requires an RGB color mode sprite.")
  return
end

-- ── Collect selectable image layers (recursing into groups) ─────────────────
local layerList = {}   -- ordered array of image layers
local function collect(layers)
  for _, l in ipairs(layers) do
    if l.isGroup then
      collect(l.layers)
    elseif l.isImage then
      layerList[#layerList + 1] = l
    end
  end
end
collect(sprite.layers)

if #layerList < 2 then
  app.alert("Layer Diff needs at least two image layers.")
  return
end

-- Build disambiguated option labels ("1: Name") so duplicate names still work.
local options    = {}
local labelToIdx = {}
for i, l in ipairs(layerList) do
  local label    = i .. ": " .. l.name
  options[i]     = label
  labelToIdx[label] = i
end

-- Sensible defaults: the active layer as A, the next distinct layer as B.
local defaultAIdx = 1
for i, l in ipairs(layerList) do
  if l == app.layer then defaultAIdx = i break end
end
local defaultBIdx = (defaultAIdx % #layerList) + 1

-- ── Dialog ──────────────────────────────────────────────────────────────────
local dlg = Dialog("Layer Diff")

dlg:combobox {
  id      = "layerA",
  label   = "Layer A:",
  option  = options[defaultAIdx],
  options = options,
}
dlg:combobox {
  id      = "layerB",
  label   = "Layer B:",
  option  = options[defaultBIdx],
  options = options,
}
dlg:separator()
dlg:combobox {
  id      = "mode",
  label   = "Compare by:",
  option  = "Shape (alpha)",
  options = { "Shape (alpha)", "Color (exact pixels)" },
}
dlg:combobox {
  id      = "result",
  label   = "Show diff as:",
  option  = "Original colors",
  options = { "Original colors", "Highlight color" },
}
dlg:color {
  id    = "highlight",
  label = "Highlight color:",
  color = Color{ r = 255, g = 0, b = 255, a = 255 },
}
dlg:separator()
dlg:button { id = "ok",     text = "Apply", focus = true }
dlg:button { id = "cancel", text = "Cancel" }

dlg:show()
local data = dlg.data
if not data.ok then return end

local idxA = labelToIdx[data.layerA]
local idxB = labelToIdx[data.layerB]
if idxA == idxB then
  app.alert("Pick two different layers to diff.")
  return
end

local layerA = layerList[idxA]
local layerB = layerList[idxB]

local byColor      = data.mode == "Color (exact pixels)"
local useHighlight = data.result == "Highlight color"

-- ── Render each layer's active-frame cel onto a sprite-sized canvas ─────────
local spW, spH = sprite.width, sprite.height
local frameNum = app.frame.frameNumber

local function renderLayer(layer)
  local img = Image(spW, spH, ColorMode.RGB)
  img:clear()
  local cel = layer:cel(frameNum)
  if cel then
    img:drawImage(cel.image, cel.position)
  end
  return img
end

local imgA = renderLayer(layerA)
local imgB = renderLayer(layerB)

-- ── Build the diff image ────────────────────────────────────────────────────
local alpha        = app.pixelColor.rgbaA
local highlightPV  = app.pixelColor.rgba(
  data.highlight.red, data.highlight.green, data.highlight.blue, 255)
local transparent  = app.pixelColor.rgba(0, 0, 0, 0)

local out = Image(spW, spH, ColorMode.RGB)
out:clear()

for y = 0, spH - 1 do
  for x = 0, spW - 1 do
    local av = imgA:getPixel(x, y)
    local bv = imgB:getPixel(x, y)
    local aOpaque = alpha(av) > 0
    local bOpaque = alpha(bv) > 0

    local differs, sourcePV
    if byColor then
      differs  = av ~= bv
      -- Prefer the pixel that actually carries content for the output color.
      sourcePV = aOpaque and av or bv
    else
      differs  = aOpaque ~= bOpaque
      sourcePV = aOpaque and av or bv
    end

    if differs then
      out:drawPixel(x, y, useHighlight and highlightPV or sourcePV)
    else
      out:drawPixel(x, y, transparent)
    end
  end
end

-- ── Commit as a single undoable action ──────────────────────────────────────
app.transaction("Layer Diff", function()
  local diffLayer = sprite:newLayer()
  diffLayer.name  = "Diff (" .. layerA.name .. " vs " .. layerB.name .. ")"
  sprite:newCel(diffLayer, app.frame, out, Point(0, 0))
end)

app.refresh()
