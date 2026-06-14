-- export_mask.lua
-- Exports a two-colour mask PNG of the current sprite:
--   transparent pixels  → one configurable colour (default: black)
--   non-transparent pixels → another configurable colour (default: white)

local sprite = app.sprite
if not sprite then
  app.alert("No active sprite!")
  return
end

-- Derive a sensible default save path from the sprite's filename
local defaultFilename = "mask.png"
if sprite.filename and sprite.filename ~= "" then
  defaultFilename = sprite.filename:gsub("%.[^%.]+$", "_mask.png")
end

local dlg = Dialog("Export Sprite Mask")
dlg:color{
  id    = "color_transparent",
  label = "Transparent areas:",
  color = Color{ r=0, g=0, b=0, a=255 },
}
dlg:color{
  id    = "color_solid",
  label = "Non-transparent areas:",
  color = Color{ r=255, g=255, b=255, a=255 },
}
dlg:file{
  id        = "output",
  label     = "Save PNG as:",
  save      = true,
  filetypes = { "png" },
  filename  = defaultFilename,
}
dlg:separator()
dlg:button{ id="ok",     text="Export", focus=true }
dlg:button{ id="cancel", text="Cancel" }
dlg:show()

local data = dlg.data
if not data.ok then return end

local outputPath = data.output
if not outputPath or outputPath == "" then
  app.alert("No output file specified.")
  return
end

-- Guarantee a .png extension
if not outputPath:match("%.png$") then
  outputPath = outputPath .. ".png"
end

local w        = sprite.width
local h        = sprite.height
local frameNum = app.frame.frameNumber

-- Composite all visible layers for the current frame into an RGB image.
-- drawSprite handles all colour modes and layer blending so we always
-- get a clean RGBA result to inspect alpha values from.
local composited = Image(w, h, ColorMode.RGB)
composited:drawSprite(sprite, frameNum)

-- Build the two-colour mask
local mask = Image(w, h, ColorMode.RGB)

local tc = data.color_transparent
local sc = data.color_solid
local transparentPV = app.pixelColor.rgba(tc.red, tc.green, tc.blue, 255)
local solidPV       = app.pixelColor.rgba(sc.red, sc.green, sc.blue, 255)

for it in composited:pixels() do
  local alpha = app.pixelColor.rgbaA(it())
  mask:drawPixel(it.x, it.y, alpha == 0 and transparentPV or solidPV)
end

mask:saveAs(outputPath)
app.alert{ title="Export Complete", text="Mask saved to:\n" .. outputPath }
