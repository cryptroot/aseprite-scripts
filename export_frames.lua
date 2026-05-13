-- Export Frames — Aseprite script
-- Exports every frame of the current sprite (or a selected range) as
-- individual PNG files using a customisable naming pattern.
--
-- Naming tokens available in the "Name Pattern" field:
--   {number}   — frame number with the chosen zero-padding
--   {name}     — sprite filename without extension (falls back to "sprite")
--   {width}    — sprite width in pixels
--   {height}   — sprite height in pixels

local sprite = app.sprite
if not sprite then app.alert("No active sprite!") return end

-- ── Derive a sensible default base name from the sprite's filename ─────────
local spriteName = "sprite"
if sprite.filename and sprite.filename ~= "" then
  local base = app.fs.fileName(sprite.filename)                  -- e.g. "glass.aseprite"
  spriteName = base:match("^(.-)%.[^%.]*$") or base             -- strip extension
end

local frameCount    = #sprite.frames
local defaultOutput = app.fs.userDocsPath                       -- sensible default dir

-- ── Dialog ────────────────────────────────────────────────────────────────────
local dlg = Dialog("Export Frames as PNG")

dlg:separator{ text = "Output Folder" }
dlg:file {
  id      = "folder",
  label   = "Save to:",
  title   = "Choose output folder",
  load    = false,                  -- we are saving, not loading
  save    = true,                   -- makes it a save-path picker
  filename= defaultOutput .. "/frame_001.png",
  filetypes = { "png" }
}

dlg:separator{ text = "Naming" }
dlg:entry {
  id    = "pattern",
  label = "Name Pattern:",
  text  = "frame_{number}"
}
dlg:combobox {
  id      = "padding",
  label   = "Number Padding:",
  option  = "3 digits  (001)",
  options = {
    "No padding  (1)",
    "2 digits  (01)",
    "3 digits  (001)",
    "4 digits  (0001)",
  }
}

dlg:separator{ text = "Frame Range" }
dlg:number { id = "from", label = "From frame:", text = "1",            decimals = 0 }
dlg:number { id = "to",   label = "To frame:",   text = tostring(frameCount), decimals = 0 }

dlg:separator{ text = "Layer" }
dlg:combobox {
  id      = "layerMode",
  label   = "Layers:",
  option  = "Flatten (all layers)",
  options = { "Flatten (all layers)", "Active layer only" }
}

dlg:separator()
dlg:button { id = "ok",     text = "Export", focus = true }
dlg:button { id = "cancel", text = "Cancel" }

dlg:show()

local data = dlg.data
if not data.ok then return end

-- ── Resolve output directory from the file picker ──────────────────────────
-- The file widget returns a full file path; we only need the directory part.
local outputFile = data.folder or ""
local outputDir

if outputFile ~= "" then
  -- Strip the filename portion to get the directory
  outputDir = app.fs.filePath(outputFile)
  if not outputDir or outputDir == "" then
    outputDir = outputFile  -- user may have typed a bare directory path
  end
else
  outputDir = defaultOutput
end

-- Normalise: remove a trailing separator if present
outputDir = outputDir:gsub("[/\\]+$", "")

if outputDir == "" then
  app.alert("No output folder selected.")
  return
end

-- ── Padding helper ──────────────────────────────────────────────────────────
local paddingFmt = {
  ["No padding  (1)"]  = "%d",
  ["2 digits  (01)"]   = "%02d",
  ["3 digits  (001)"]  = "%03d",
  ["4 digits  (0001)"] = "%04d",
}
local numFmt = paddingFmt[data.padding] or "%03d"

-- ── Frame range ─────────────────────────────────────────────────────────────
local fromFrame = math.max(1, math.floor(data.from or 1))
local toFrame   = math.min(frameCount, math.floor(data.to   or frameCount))
if fromFrame > toFrame then
  app.alert("'From frame' must be less than or equal to 'To frame'.")
  return
end

-- ── Pattern token replacer ──────────────────────────────────────────────────
local function makeFilename(pattern, frameNum)
  local numStr = string.format(numFmt, frameNum)
  local result = pattern
  result = result:gsub("{number}", numStr)
  result = result:gsub("{name}",   spriteName)
  result = result:gsub("{width}",  tostring(sprite.width))
  result = result:gsub("{height}", tostring(sprite.height))
  return result .. ".png"
end

-- ── Export ──────────────────────────────────────────────────────────────────
local activeLayerMode = (data.layerMode == "Active layer only")
local activeLayer     = app.layer

local exported = 0
local errors   = {}

for fi = fromFrame, toFrame do
  local frame    = sprite.frames[fi]
  local filename = makeFilename(data.pattern, fi)
  local fullPath = outputDir .. "/" .. filename

  -- Build a flat image for this frame
  local img

  if activeLayerMode then
    -- Export only the active layer's cel at this frame
    local cel = activeLayer:cel(fi)
    if cel then
      -- Place cel image onto a full-sprite-size canvas
      img = Image(sprite.spec)
      img:clear()
      img:drawImage(cel.image, cel.position)
    else
      -- Empty cel — export a transparent image
      img = Image(sprite.spec)
      img:clear()
    end
  else
    -- Flatten all visible layers into one image
    img = Image(sprite.spec)
    img:clear()
    for _, layer in ipairs(sprite.layers) do
      if layer.isVisible and not layer.isGroup then
        local cel = layer:cel(fi)
        if cel then
          img:drawImage(cel.image, cel.position)
        end
      end
    end
  end

  local ok, err = pcall(function() img:saveAs(fullPath) end)
  if ok then
    exported = exported + 1
  else
    errors[#errors + 1] = filename .. " — " .. tostring(err)
  end
end

-- ── Result summary ───────────────────────────────────────────────────────────
if #errors == 0 then
  app.alert(string.format("Exported %d frame(s) to:\n%s", exported, outputDir))
else
  local msg = string.format(
    "Exported %d frame(s).\n%d error(s):\n\n%s",
    exported, #errors, table.concat(errors, "\n")
  )
  app.alert(msg)
end
