---
description: "Use when writing, editing, or reviewing Aseprite Lua scripts (.lua files). Covers the Aseprite scripting API, correct object access, undo patterns, dialog construction, and color mode handling."
applyTo: "**/*.lua"
---
# Aseprite Lua Scripting

Reference: https://github.com/aseprite/api

## Scripts Basics

- Scripts are `.lua` files placed in `%APPDATA%\Aseprite\scripts\` (or the platform equivalent).
- They appear under **File > Scripts** after Aseprite is restarted.
- Aseprite embeds Lua 5.3. Standard Lua libraries are available (math, string, table, os, io) except `os.exit`, `os.tmpname`. `os.execute` and `io.open` ask the user for permission.

---

## Accessing the Active Context

Always guard against `nil` before use:

```lua
local sprite = app.sprite
if not sprite then app.alert("No active sprite!") return end

local layer = app.layer     -- active layer
local frame = app.frame     -- active Frame object (frame.frameNumber for the integer)
local cel   = app.cel       -- active Cel object (has .image and .position)
local image = app.image     -- shorthand for cel.image
```

### Deprecated names — never use these
| Old (deprecated) | New |
|---|---|
| `app.activeSprite` | `app.sprite` |
| `app.activeLayer` | `app.layer` |
| `app.activeFrame` | `app.frame` |
| `app.activeCel` | `app.cel` |
| `app.activeImage` | `app.image` |
| `app.activeTag` | `app.tag` |
| `app.activeTool` | `app.tool` |
| `app.activeBrush` | `app.brush` |

---

## Color Modes

Use `sprite.colorMode` (or `image.colorMode`) and `ColorMode.*` constants.

| Constant | Mode |
|---|---|
| `ColorMode.RGB` | 32-bit RGBA |
| `ColorMode.GRAY` | Grayscale + alpha |
| `ColorMode.INDEXED` | Palette index |

### Pixel color helpers (`app.pixelColor`)

```lua
-- RGB
local pv = app.pixelColor.rgba(r, g, b, a)
local r  = app.pixelColor.rgbaR(pv)
local g  = app.pixelColor.rgbaG(pv)
local b  = app.pixelColor.rgbaB(pv)
local a  = app.pixelColor.rgbaA(pv)

-- Grayscale
local pv = app.pixelColor.graya(v, a)
local v  = app.pixelColor.grayaV(pv)
local a  = app.pixelColor.grayaA(pv)

-- Indexed: pixel value is just the palette index (integer 0-based)
```

---

## Modifying Pixels (with Undo)

**Critical pattern**: `image:drawPixel()` and `image:pixels()` iterator writes do NOT generate undo info on their own. The correct workflow is:

1. Clone the cel's image.
2. Modify the clone freely.
3. Replace the cel inside `app.transaction()` using `sprite:newCel()`.

```lua
local cel      = app.cel
local newImage = cel.image:clone()

-- Modify newImage as needed (drawPixel, pixels iterator, etc.)
for it in newImage:pixels() do
  it(app.pixelColor.rgba(255, 0, 0, 255))  -- set every pixel red
end

-- Commit as a single undoable action
app.transaction("My Action Label", function()
  app.sprite:newCel(app.layer, app.frame, newImage, cel.position)
end)

app.refresh()  -- if canvas doesn't update automatically
```

### Pixel iterator

```lua
for it in image:pixels() do
  local pv = it()       -- read pixel value
  it(newValue)          -- write pixel value
  print(it.x, it.y)    -- coordinates
end

-- Or iterate a sub-rectangle:
for it in image:pixels(Rectangle(x, y, w, h)) do ... end
```

---

## Transactions

Group multiple sprite modifications into a single undo/redo entry:

```lua
app.transaction("Descriptive Label", function()
  -- sprite modifications here
  -- calling error() inside rolls back everything
end)
```

---

## Layer Guards

Check editability before modifying:

```lua
if not layer.isEditable then
  app.alert("Layer is locked or hidden.")
  return
end
```

---

## Dialogs

```lua
local dlg = Dialog("Window Title")

dlg:slider   { id="density",  label="Density:",  min=1, max=100, value=100 }
dlg:number   { id="seed",     label="Seed:",     text="42", decimals=0 }
dlg:check    { id="opt",      label="Options:",  text="Enable X", selected=false }
dlg:color    { id="col",      label="Color:",    color=app.fgColor }
dlg:combobox { id="mode",     label="Mode:",     option="A", options={"A","B","C"} }
dlg:entry    { id="name",     label="Name:",     text="default" }
dlg:separator()
dlg:button   { id="ok",       text="Apply", focus=true }
dlg:button   { id="cancel",   text="Cancel" }

dlg:show()

local data = dlg.data
if not data.ok then return end  -- user cancelled

-- Access values: data.density, data.seed, data.opt, data.col, data.mode, data.name
```

- `Dialog()` returns `nil` when UI is unavailable (batch/CLI mode); guard if needed.
- All `dlg:widget{}` calls return the dialog, so method chaining works.
- `dlg:show{ wait=false }` opens non-blocking (script continues immediately).

---

## Palette Access (Indexed mode)

```lua
local palette   = sprite.palettes[1]   -- sprites usually have one palette
local numColors = #palette
local color     = palette:getColor(index)  -- returns a Color object (0-based index)
```

---

## Common Object Properties

```lua
-- Sprite
sprite.width; sprite.height; sprite.colorMode; sprite.spec
sprite.layers; sprite.frames; sprite.cels; sprite.palettes

-- Layer
layer.name; layer.isVisible; layer.isEditable; layer.opacity; layer.blendMode

-- Cel
cel.image; cel.position; cel.opacity; cel.layer; cel.frame

-- Image
image.width; image.height; image.colorMode; image.bounds  -- Rectangle at (0,0)
image:clone(); image:clear(); image:resize(w, h)
image:getPixel(x, y); image:drawPixel(x, y, pixelValue)
image:saveAs(filename)

-- Frame
frame.frameNumber   -- 1-based integer index
frame.duration      -- in milliseconds
```

---

## Example Script Skeleton

```lua
local sprite = app.sprite
if not sprite then app.alert("No active sprite!") return end

local cel = app.cel
if not cel then app.alert("No active cel!") return end

if not app.layer.isEditable then
  app.alert("Layer is not editable.")
  return
end

-- Show configuration dialog
local dlg = Dialog("My Script")
dlg:button{ id="ok", text="Run", focus=true }
dlg:button{ id="cancel", text="Cancel" }
dlg:show()
if not dlg.data.ok then return end

-- Work on a clone, then commit
local newImage = cel.image:clone()
-- ... modify newImage ...

app.transaction("My Script", function()
  sprite:newCel(app.layer, app.frame, newImage, cel.position)
end)

app.refresh()
```
