-- edge_bg_eraser.lua
-- Automatic background remover for outlined / line-drawn anime characters.
--
-- The script sweeps inward from one or more borders of the image. For every
-- scanline it walks from the chosen side until it reaches an "edge" pixel
-- (a near-black, opaque outline pixel). Every pixel it crossed *before* the
-- edge is erased (made transparent); the edge pixel itself and everything
-- beyond it are considered "inside" the drawing and are kept.
--
-- Sweeping from all four sides removes the outside background while leaving the
-- character (and any fills inside the outline) untouched.

local sprite = app.sprite
if not sprite then
  app.alert("No active sprite!")
  return
end

if sprite.colorMode ~= ColorMode.RGB then
  app.alert("Edge BG Eraser requires an RGB color mode sprite.")
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

local cel = app.cel
if not cel then
  app.alert("No active cel! Make sure there is content on the active layer and frame.")
  return
end

-- ── Dialog ──────────────────────────────────────────────────────────────────
local dlg = Dialog("Edge BG Eraser")

dlg:label {
  id    = "info",
  label = "Sweep from:",
  text  = "(erase up to the outline)",
}
dlg:check { id = "left",   text = "Left",   selected = true }
dlg:check { id = "right",  text = "Right",  selected = true }
dlg:newrow()
dlg:check { id = "top",    text = "Top",    selected = true }
dlg:check { id = "bottom", text = "Bottom", selected = true }
dlg:separator()
dlg:slider {
  id    = "darkness",
  label = "Edge darkness:",
  min   = 0,
  max   = 255,
  value = 64,
}
dlg:slider {
  id    = "edgeAlpha",
  label = "Edge min alpha:",
  min   = 1,
  max   = 255,
  value = 128,
}
dlg:check {
  id       = "eraseEmptyLine",
  label    = "No edge found:",
  text     = "Erase the whole scanline",
  selected = true,
}
dlg:separator()
dlg:button { id = "ok",     text = "Erase", focus = true }
dlg:button { id = "cancel", text = "Cancel" }

dlg:show()
local data = dlg.data
if not data.ok then return end

if not (data.left or data.right or data.top or data.bottom) then
  app.alert("Select at least one side to sweep from.")
  return
end

local darkThresh   = data.darkness
local alphaThresh  = data.edgeAlpha
local eraseEmpty   = data.eraseEmptyLine

-- ── Edge detection ──────────────────────────────────────────────────────────
local rgbaR = app.pixelColor.rgbaR
local rgbaG = app.pixelColor.rgbaG
local rgbaB = app.pixelColor.rgbaB
local rgbaA = app.pixelColor.rgbaA

local srcImage    = cel.image            -- read original pixels from here
local outImage    = srcImage:clone()     -- write erased pixels here
local w           = srcImage.width
local h           = srcImage.height
local transparent = app.pixelColor.rgba(0, 0, 0, 0)

-- A pixel is an outline "edge" when it is sufficiently opaque and every color
-- channel is dark (so the whole pixel is near black).
local function isEdge(x, y)
  local pv = srcImage:getPixel(x, y)
  if rgbaA(pv) < alphaThresh then return false end
  local r = rgbaR(pv)
  local g = rgbaG(pv)
  local b = rgbaB(pv)
  local m = r
  if g > m then m = g end
  if b > m then m = b end
  return m <= darkThresh
end

local erased = 0

-- Walk a single scanline starting at (sx, sy) stepping by (dx, dy) for `count`
-- pixels. Erase every crossed pixel until an edge is hit. If no edge is hit and
-- eraseEmpty is enabled, the entire scanline is erased.
local function sweepLine(sx, sy, dx, dy, count)
  local x, y = sx, sy
  local toErase = {}
  local foundEdge = false
  for _ = 1, count do
    if isEdge(x, y) then
      foundEdge = true
      break
    end
    toErase[#toErase + 1] = { x, y }
    x = x + dx
    y = y + dy
  end

  if foundEdge or eraseEmpty then
    for i = 1, #toErase do
      local p  = toErase[i]
      local pv = outImage:getPixel(p[1], p[2])
      if rgbaA(pv) > 0 then
        outImage:drawPixel(p[1], p[2], transparent)
        erased = erased + 1
      end
    end
  end
end

-- ── Sweep the requested sides ───────────────────────────────────────────────
if data.left then
  for y = 0, h - 1 do sweepLine(0, y, 1, 0, w) end
end
if data.right then
  for y = 0, h - 1 do sweepLine(w - 1, y, -1, 0, w) end
end
if data.top then
  for x = 0, w - 1 do sweepLine(x, 0, 0, 1, h) end
end
if data.bottom then
  for x = 0, w - 1 do sweepLine(x, h - 1, 0, -1, h) end
end

if erased == 0 then
  app.alert("No pixels were erased. Try lowering 'Edge darkness' or 'Edge min alpha'.")
  return
end

-- ── Commit as a single undoable action ──────────────────────────────────────
app.transaction("Edge BG Eraser", function()
  sprite:newCel(layer, app.frame, outImage, cel.position)
end)

app.refresh()
