-- random_noise.lua
-- Generates random noise on the current layer's active cel.
-- Supports RGB, Grayscale, and Indexed color modes.

local sprite = app.sprite
if not sprite then
  app.alert("No active sprite!")
  return
end

local cel = app.cel
if not cel then
  app.alert("No active cel! Make sure there is content on the active layer and frame.")
  return
end

local layer = app.layer
if not layer.isEditable then
  app.alert("The active layer is not editable (it may be locked or hidden).")
  return
end

-- Use current time as a varying default seed
local defaultSeed = math.floor(os.time())

local dlg = Dialog("Random Noise")

dlg:combobox{
  id      = "noise_type",
  label   = "Noise Type:",
  option  = "Color",
  options = { "Color", "Monochrome" }
}

dlg:slider{
  id    = "density",
  label = "Density (%):",
  min   = 1,
  max   = 100,
  value = 100
}

dlg:check{
  id       = "randomize_alpha",
  label    = "Alpha:",
  text     = "Randomize alpha",
  selected = false
}

dlg:number{
  id       = "seed",
  label    = "Random Seed:",
  text     = tostring(defaultSeed),
  decimals = 0
}

dlg:separator()
dlg:button{ id = "ok",     text = "Apply", focus = true }
dlg:button{ id = "cancel", text = "Cancel" }
dlg:show()

local data = dlg.data
if not data.ok then
  return
end

-- Parse options
local noiseType      = data.noise_type
local density        = data.density / 100.0
local randomizeAlpha = data.randomize_alpha
local seed           = math.floor(data.seed or defaultSeed)

math.randomseed(seed)

local colorMode = sprite.colorMode
local srcImage  = cel.image
local newImage  = srcImage:clone()

-- Apply noise to the cloned image
for it in newImage:pixels() do
  if math.random() <= density then
    local pv

    if colorMode == ColorMode.RGB then
      local mono = math.random(0, 255)
      local r    = (noiseType == "Monochrome") and mono or math.random(0, 255)
      local g    = (noiseType == "Monochrome") and mono or math.random(0, 255)
      local b    = (noiseType == "Monochrome") and mono or math.random(0, 255)
      -- Preserve existing alpha unless the user wants it randomized
      local a    = randomizeAlpha and math.random(0, 255)
                   or app.pixelColor.rgbaA(it())
      pv = app.pixelColor.rgba(r, g, b, a)

    elseif colorMode == ColorMode.GRAY then
      local v = math.random(0, 255)
      local a = randomizeAlpha and math.random(0, 255)
                or app.pixelColor.grayaA(it())
      pv = app.pixelColor.graya(v, a)

    elseif colorMode == ColorMode.INDEXED then
      -- Pick a random palette index
      local numEntries = #sprite.palettes[1]
      pv = math.random(0, numEntries - 1)
    end

    it(pv)
  end
end

-- Replace the cel's content as one undoable transaction
app.transaction("Random Noise", function()
  sprite:newCel(layer, app.frame, newImage, cel.position)
end)

app.refresh()
