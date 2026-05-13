local FlexLove = require("flexlove.FlexLove")
local Color = FlexLove.Color
local C = require("farm.constants")
local State = require("farm.state")

local Modals = {}

local root
local bestiaryRows
local kind

local function closeModal()
  State.openModal = nil
end

local function noop() end

local function destroy()
  if root then
    root:destroy()
    root = nil
  end
  bestiaryRows = nil
  kind = nil
end

local function emojiSlot(parent, size)
  return FlexLove.new({
    parent = parent,
    width = size, height = size,
  })
end

local function textCell(parent, txt, width, align, color)
  return FlexLove.new({
    parent = parent,
    width = width, height = 30,
    text = txt or "",
    textSize = 14,
    textAlign = align or "start",
    textColor = color or Color.new(0.85, 0.85, 0.92, 1),
    positioning = "flex",
    alignItems = "center",
    justifyContent = (align == "center") and "center" or ((align == "end") and "flex-end" or "flex-start"),
  })
end

local function buildBestiary()
  bestiaryRows = {}
  local W, H = 720, 640

  local backdrop = FlexLove.new({
    x = 0, y = 0,
    width = 1920, height = 1080,
    positioning = "flex",
    justifyContent = "center",
    alignItems = "center",
    backgroundColor = Color.new(0, 0, 0, 0.55),
    z = 0,
    onEvent = function(_, e)
      if e.type == "release" or e.type == "click" then closeModal() end
    end,
  })

  local panel = FlexLove.new({
    parent = backdrop,
    width = W, height = H,
    positioning = "flex",
    backgroundColor = Color.new(0.10, 0.10, 0.14, 1),
    borderColor = Color.new(0.55, 0.55, 0.70, 1),
    border = 1,
    cornerRadius = 8,
    padding = 20,
    flexDirection = "vertical",
    gap = 8,
    z = 10,
    onEvent = noop,
  })

  local discoveredCount = 0
  for _, n in pairs(State.discovered or {}) do
    if n > 0 then discoveredCount = discoveredCount + 1 end
  end

  FlexLove.new({
    parent = panel,
    width = "100%", height = 32,
    text = string.format("Bestiary  %d / %d", discoveredCount, #C.CROP_RECIPES),
    textSize = 24,
    textColor = Color.new(1, 0.95, 0.55, 1),
    textAlign = "center",
    positioning = "flex",
    alignItems = "center",
    justifyContent = "center",
  })

  FlexLove.new({
    parent = panel,
    width = "100%", height = 16,
    text = "Esc / B / click outside to close",
    textSize = 12,
    textColor = Color.new(0.55, 0.55, 0.65, 1),
    textAlign = "center",
    positioning = "flex",
    alignItems = "center",
    justifyContent = "center",
  })

  local list = FlexLove.new({
    parent = panel,
    width = "100%",
    flex = 1,
    positioning = "flex",
    flexDirection = "vertical",
    gap = 4,
  })

  for ri, r in ipairs(C.CROP_RECIPES) do
    local count = (State.discovered and State.discovered[ri]) or 0
    local found = count > 0
    local row = FlexLove.new({
      parent = list,
      width = "100%", height = 34,
      positioning = "flex",
      flexDirection = "horizontal",
      alignItems = "center",
      gap = 6,
      backgroundColor = found and Color.new(0.16, 0.22, 0.17, 1) or Color.new(0.14, 0.14, 0.18, 1),
      cornerRadius = 4,
      padding = { top = 0, right = 8, bottom = 0, left = 8 },
    })

    local aCrop = C.CROPS[C.CROP_INDEX[r.a]]
    local bCrop = C.CROPS[C.CROP_INDEX[r.b]]
    local rCrop = C.CROPS[C.CROP_INDEX[r.result]]

    local slotA = emojiSlot(row, 26)
    textCell(row, found and r.a or "???", 86, "start", Color.new(0.88, 0.88, 0.94, 1))
    textCell(row, "+", 12, "center", Color.new(0.7, 0.7, 0.8, 1))
    local slotB = emojiSlot(row, 26)
    textCell(row, found and r.b or "???", 86, "start", Color.new(0.88, 0.88, 0.94, 1))
    textCell(row, "->", 22, "center", Color.new(0.7, 0.7, 0.8, 1))
    local slotR = emojiSlot(row, 26)
    textCell(row, found and r.result or "???", 100, "start", Color.new(1, 0.95, 0.55, 1))
    textCell(row, found and string.format("%d%%", math.floor(r.chance * 100 + 0.5)) or "??%", 50, "end", Color.new(0.7, 0.85, 1, 1))
    textCell(row, found and ("x" .. count) or "", 44, "end", Color.new(0.65, 0.90, 0.65, 1))

    bestiaryRows[#bestiaryRows + 1] = {
      slotA = slotA, slotB = slotB, slotR = slotR,
      glyphA = aCrop.emoji, glyphB = bCrop.emoji, glyphR = rCrop.emoji,
      tintA = aCrop.color, tintB = bCrop.color, tintR = rCrop.color,
      found = found,
    }
  end

  root = backdrop
  kind = "bestiary"
end

local function buildResetConfirm()
  local W, H = 380, 170

  local backdrop = FlexLove.new({
    x = 0, y = 0,
    width = 1920, height = 1080,
    positioning = "flex",
    justifyContent = "center",
    alignItems = "center",
    backgroundColor = Color.new(0, 0, 0, 0.55),
    z = 0,
    onEvent = function(_, e)
      if e.type == "release" or e.type == "click" then closeModal() end
    end,
  })

  local panel = FlexLove.new({
    parent = backdrop,
    width = W, height = H,
    positioning = "flex",
    backgroundColor = Color.new(0.12, 0.12, 0.16, 1),
    borderColor = Color.new(0.6, 0.6, 0.7, 1),
    border = 1,
    cornerRadius = 8,
    padding = 16,
    flexDirection = "vertical",
    gap = 8,
    z = 10,
    onEvent = noop,
  })

  FlexLove.new({
    parent = panel,
    width = "100%", height = 32,
    text = "Reset save?",
    textSize = 22,
    textColor = Color.new(1, 0.95, 0.6, 1),
    textAlign = "center",
    positioning = "flex",
    alignItems = "center",
    justifyContent = "center",
  })

  FlexLove.new({
    parent = panel,
    width = "100%", height = 22,
    text = "All progress will be deleted.",
    textSize = 14,
    textColor = Color.new(0.85, 0.85, 0.9, 1),
    textAlign = "center",
    positioning = "flex",
    alignItems = "center",
    justifyContent = "center",
  })

  local btnRow = FlexLove.new({
    parent = panel,
    width = "100%",
    flex = 1,
    positioning = "flex",
    flexDirection = "horizontal",
    justifyContent = "space-between",
    alignItems = "flex-end",
  })

  FlexLove.new({
    parent = btnRow,
    width = 150, height = 40,
    text = "Yes, reset",
    textSize = 14,
    textColor = Color.new(1, 1, 1, 1),
    textAlign = "center",
    backgroundColor = Color.new(0.55, 0.28, 0.18, 1),
    borderColor = Color.new(0.7, 0.5, 0.3, 1),
    border = 1,
    cornerRadius = 6,
    positioning = "flex",
    alignItems = "center",
    justifyContent = "center",
    onEvent = function(_, e)
      if e.type == "release" or e.type == "click" then
        local Save = require("farm.save")
        Save.reset()
        closeModal()
      end
    end,
  })

  FlexLove.new({
    parent = btnRow,
    width = 150, height = 40,
    text = "Cancel",
    textSize = 14,
    textColor = Color.new(1, 1, 1, 1),
    textAlign = "center",
    backgroundColor = Color.new(0.22, 0.22, 0.28, 1),
    borderColor = Color.new(0.55, 0.55, 0.65, 1),
    border = 1,
    cornerRadius = 6,
    positioning = "flex",
    alignItems = "center",
    justifyContent = "center",
    onEvent = function(_, e)
      if e.type == "release" or e.type == "click" then closeModal() end
    end,
  })

  root = backdrop
  kind = "resetConfirm"
end

function Modals.syncTo(modalName)
  if kind == modalName then return end
  destroy()
  if modalName == "bestiary" then buildBestiary()
  elseif modalName == "resetConfirm" then buildResetConfirm() end
end

function Modals.drawEmojiOverlay(emojiFont, emojiNative)
  if kind ~= "bestiary" or not bestiaryRows then return end
  love.graphics.setFont(emojiFont)
  for _, row in ipairs(bestiaryRows) do
    if row.found then
      local slots = { row.slotA, row.slotB, row.slotR }
      local glyphs = { row.glyphA, row.glyphB, row.glyphR }
      local tints = { row.tintA, row.tintB, row.tintR }
      for i, s in ipairs(slots) do
        local cx = s.x + s.width * 0.5
        local cy = s.y + s.height * 0.5
        local scale = (s.height * 0.95) / emojiNative
        local t = tints[i] or { 1, 1, 1 }
        love.graphics.setColor(t[1], t[2], t[3], 1)
        local w = emojiFont:getWidth(glyphs[i]) * scale
        local h = emojiFont:getHeight() * scale
        love.graphics.print(glyphs[i], cx - w * 0.5, cy - h * 0.5, 0, scale, scale)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Modals
