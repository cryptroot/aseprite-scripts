-- color_eraser.lua
-- Erases pixels on the active layer that match a target color, including
-- "close" colors within a tolerance. Useful when a region uses several
-- nearly-identical shades (e.g. 252,204,181 vs 255,206,182) that should
-- all be removed together.

local sprite = app.sprite
if not sprite then
  app.alert("No active sprite!")
  return
end

if sprite.colorMode ~= ColorMode.RGB then
  app.alert("Color Eraser requires an RGB color mode sprite.")
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
local dlg = Dialog("Color Eraser")

dlg:color {
  id    = "target",
  label = "Erase color:",
  color = app.fgColor,
}
dlg:slider {
  id    = "tolerance",
  label = "Tolerance:",
  min   = 0,
  max   = 255,
  value = 16,
}
dlg:combobox {
  id      = "metric",
  label   = "Match by:",
  option  = "Per-channel (max difference)",
  options = { "Per-channel (max difference)", "Euclidean distance" },
}
dlg:check {
  id       = "matchAlpha",
  label    = "Also match alpha:",
  text     = "Compare alpha channel too",
  selected = false,
}
dlg:separator()
dlg:button { id = "ok",     text = "Erase", focus = true }
dlg:button { id = "cancel", text = "Cancel" }

dlg:show()
local data = dlg.data
if not data.ok then return end

local target     = data.target
local tr, tg, tb = target.red, target.green, target.blue
local ta         = target.alpha
local tol        = data.tolerance
local euclidean  = data.metric == "Euclidean distance"
local matchAlpha = data.matchAlpha

-- For Euclidean matching, compare against the squared tolerance to avoid sqrt.
local tolSq = tol * tol

local rgbaR = app.pixelColor.rgbaR
local rgbaG = app.pixelColor.rgbaG
local rgbaB = app.pixelColor.rgbaB
local rgbaA = app.pixelColor.rgbaA

local function matches(pv)
  local dr = rgbaR(pv) - tr
  local dg = rgbaG(pv) - tg
  local db = rgbaB(pv) - tb
  local da = matchAlpha and (rgbaA(pv) - ta) or 0

  if euclidean then
    return (dr * dr + dg * dg + db * db + da * da) <= tolSq
  else
    if dr < 0 then dr = -dr end
    if dg < 0 then dg = -dg end
    if db < 0 then db = -db end
    if da < 0 then da = -da end
    local m = dr
    if dg > m then m = dg end
    if db > m then m = db end
    if da > m then m = da end
    return m <= tol
  end
end

-- ── Build the erased image ──────────────────────────────────────────────────
local newImage    = cel.image:clone()
local transparent = app.pixelColor.rgba(0, 0, 0, 0)
local erased      = 0

for it in newImage:pixels() do
  local pv = it()
  if rgbaA(pv) > 0 and matches(pv) then
    it(transparent)
    erased = erased + 1
  end
end

if erased == 0 then
  app.alert("No matching pixels found within the given tolerance.")
  return
end

-- ── Commit as a single undoable action ──────────────────────────────────────
app.transaction("Color Eraser", function()
  sprite:newCel(layer, app.frame, newImage, cel.position)
end)

app.refresh()
