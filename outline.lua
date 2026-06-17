-- outline.lua
-- Adds a 1px black inset outline around the content on the active layer.
-- The outline is placed on a new layer directly above the current one,
-- painting the outermost opaque pixels of the sprite so it sits on top of the art.

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
  app.alert("Outline requires an RGB color mode sprite.")
  return
end

local cel = app.cel
if not cel then
  app.alert("No active cel! Make sure there is content on the active layer and frame.")
  return
end

-- ── Dialog ──────────────────────────────────────────────────────────────────
local dlg = Dialog("1px Outline")

dlg:combobox {
  id      = "connectivity",
  label   = "Outline Style:",
  option  = "8-way (includes diagonals)",
  options = { "4-way (no diagonals)", "8-way (includes diagonals)" }
}

dlg:separator()
dlg:button { id = "ok",     text = "Apply",  focus = true }
dlg:button { id = "cancel", text = "Cancel" }

dlg:show()
if not dlg.data.ok then return end

local use8way = dlg.data.connectivity == "8-way (includes diagonals)"

-- ── Build outline image ─────────────────────────────────────────────────────
local srcImage = cel.image
local srcPos   = cel.position
local sw, sh   = srcImage.width, srcImage.height
local spW, spH = sprite.width, sprite.height

local dirs4 = { {-1,0}, {1,0}, {0,-1}, {0,1} }
local dirs8 = { {-1,-1}, {0,-1}, {1,-1},
                {-1, 0},          {1, 0},
                {-1, 1}, {0, 1}, {1, 1} }
local dirs  = use8way and dirs8 or dirs4

local black = app.pixelColor.rgba(0, 0, 0, 255)

-- Use a sprite-sized canvas so any cel offset is handled correctly.
local outImg = Image(spW, spH, ColorMode.RGB)
outImg:clear()  -- initialise to fully transparent

for y = 0, sh - 1 do
  for x = 0, sw - 1 do
    local pv = srcImage:getPixel(x, y)
    if app.pixelColor.rgbaA(pv) > 0 then
      -- Check whether any neighbour is transparent; if so, this pixel is
      -- a border pixel and should receive the inset outline.
      local isBorder = false
      for _, d in ipairs(dirs) do
        local nx = x + d[1]
        local ny = y + d[2]
        local nAlpha = 0
        if nx >= 0 and ny >= 0 and nx < sw and ny < sh then
          nAlpha = app.pixelColor.rgbaA(srcImage:getPixel(nx, ny))
        end
        if nAlpha == 0 then
          isBorder = true
          break
        end
      end

      if isBorder then
        -- Paint at the sprite-coordinate of this opaque border pixel.
        local sx = srcPos.x + x
        local sy = srcPos.y + y
        if sx >= 0 and sy >= 0 and sx < spW and sy < spH then
          outImg:drawPixel(sx, sy, black)
        end
      end
    end
  end
end

-- ── Commit as a single undoable action ──────────────────────────────────────
-- Capture the stack index so we can place the outline layer above the source.
local targetIndex = layer.stackIndex + 1

app.transaction("Add 1px Inset Outline", function()
  local outlineLayer        = sprite:newLayer()
  outlineLayer.name         = layer.name .. " Outline"
  -- Move the new layer to sit directly above the source layer.
  outlineLayer.stackIndex   = targetIndex
  sprite:newCel(outlineLayer, app.frame, outImg, Point(0, 0))
end)

app.refresh()
