local C = require("farm.constants")
local State = require("farm.state")

local Modals = {}

local fonts = {}
local buttons = {}
local scroll = 0
local scrollMax = 0
local lastModal

local function close()
  State.openModal = nil
end

local function hitBtn(x, y, w, h, onClick)
  buttons[#buttons + 1] = { x = x, y = y, w = w, h = h, onClick = onClick }
end

local function isHover(x, y, w, h)
  local mx, my = love.mouse.getPosition()
  return mx >= x and mx <= x + w and my >= y and my <= y + h
end

local function centerEmoji(font, glyph, cx, cy, scale, tint)
  love.graphics.setFont(font)
  local c = tint or { 1, 1, 1 }
  love.graphics.setColor(c[1], c[2], c[3], 1)
  local w = font:getWidth(glyph) * scale
  local h = font:getHeight() * scale
  love.graphics.print(glyph, cx - w * 0.5, cy - h * 0.5, 0, scale, scale)
end

local function centerText(font, txt, cx, y)
  love.graphics.setFont(font)
  local w = font:getWidth(txt)
  love.graphics.print(txt, cx - w * 0.5, y)
end

function Modals.setFonts(f)
  fonts = f
end

local function drawBestiary()
  local W, H = 960, 860
  local px = (1920 - W) * 0.5
  local py = (1080 - H) * 0.5

  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", 0, 0, 1920, 1080)
  hitBtn(0, 0, 1920, 1080, close)

  love.graphics.setColor(0.10, 0.10, 0.14, 1)
  love.graphics.rectangle("fill", px, py, W, H, 8, 8)
  love.graphics.setColor(0.55, 0.55, 0.70, 1)
  love.graphics.rectangle("line", px, py, W, H, 8, 8)
  hitBtn(px, py, W, H, function() end)

  local discoveredCount = 0
  for _, n in pairs(State.discovered or {}) do
    if n > 0 then discoveredCount = discoveredCount + 1 end
  end

  love.graphics.setColor(1, 0.95, 0.55, 1)
  centerText(fonts.uiBig, string.format("Bestiary  %d / %d", discoveredCount, #C.CROP_RECIPES), px + W * 0.5, py + 20)

  love.graphics.setColor(0.55, 0.55, 0.65, 1)
  centerText(fonts.uiSmall, "Esc / B / click outside to close", px + W * 0.5, py + 56)

  local listX = px + 16
  local listY = py + 84
  local listW = W - 32
  local listH = H - 84 - 16

  local rowH = 38
  local rowGap = 4
  local stride = rowH + rowGap
  local contentH = #C.CROP_RECIPES * stride - rowGap
  scrollMax = math.max(0, contentH - listH)
  if scroll > scrollMax then scroll = scrollMax end
  if scroll < 0 then scroll = 0 end

  love.graphics.setScissor(listX, listY, listW, listH)

  local emojiNative = fonts.emojiNative
  local slot = 28
  local emojiScale = (slot * 0.95) / emojiNative

  for ri, r in ipairs(C.CROP_RECIPES) do
    local count = (State.discovered and State.discovered[ri]) or 0
    local found = count > 0 or State.debugRevealAll
    local rowY = listY + (ri - 1) * stride - scroll
    if rowY + rowH >= listY and rowY <= listY + listH then
      if found then
        love.graphics.setColor(0.16, 0.22, 0.17, 1)
      else
        love.graphics.setColor(0.14, 0.14, 0.18, 1)
      end
      love.graphics.rectangle("fill", listX, rowY, listW, rowH, 4, 4)

      local aCrop = C.CROPS[C.CROP_INDEX[r.a]]
      local bCrop = C.CROPS[C.CROP_INDEX[r.b]]
      local rCrop = C.CROPS[C.CROP_INDEX[r.result]]

      local cy = rowY + rowH * 0.5
      local textY = cy - fonts.ui:getHeight() * 0.5
      local cx = listX + 12

      local function drawCropCell(crop, name, nameColor, nameW)
        centerEmoji(fonts.emoji, crop.emoji, cx + slot * 0.5, cy, emojiScale, crop.color)
        cx = cx + slot + 6
        love.graphics.setFont(fonts.ui)
        love.graphics.setColor(nameColor[1], nameColor[2], nameColor[3], 1)
        love.graphics.print(name, cx, textY)
        cx = cx + nameW
      end

      local function drawHiddenCell(nameW)
        love.graphics.setColor(0.30, 0.30, 0.38, 1)
        love.graphics.rectangle("fill", cx, cy - slot * 0.5, slot, slot, 4, 4)
        cx = cx + slot + 6
        love.graphics.setFont(fonts.ui)
        love.graphics.setColor(0.55, 0.55, 0.62, 1)
        love.graphics.print("???", cx, textY)
        cx = cx + nameW
      end

      local nameColor = { 0.88, 0.88, 0.94 }
      if found then
        drawCropCell(aCrop, r.a, nameColor, 96)
      else
        drawHiddenCell(96)
      end

      love.graphics.setFont(fonts.ui)
      love.graphics.setColor(0.7, 0.7, 0.8, 1)
      love.graphics.print("+", cx, textY); cx = cx + 14

      if found then
        drawCropCell(bCrop, r.b, nameColor, 96)
      else
        drawHiddenCell(96)
      end

      love.graphics.setColor(0.7, 0.7, 0.8, 1)
      love.graphics.print("->", cx, textY); cx = cx + 24

      if found then
        drawCropCell(rCrop, r.result, { 1, 0.95, 0.55 }, 108)
      else
        drawHiddenCell(108)
      end

      if count > 0 then
        love.graphics.setColor(0.65, 0.90, 0.65, 1)
        local txt = "x" .. count
        love.graphics.print(txt, cx, textY)
        cx = cx + fonts.ui:getWidth(txt) + 10
      end

      if State.debugRevealAll then
        local chanceTxt = string.format("%d%%", math.floor(r.chance * 100 + 0.5))
        love.graphics.setColor(0.75, 0.80, 0.95, 1)
        love.graphics.print(chanceTxt, cx, textY)
      end
    end
  end

  love.graphics.setScissor()

  if scrollMax > 0 then
    local barX = listX + listW - 6
    love.graphics.setColor(0.15, 0.15, 0.18, 1)
    love.graphics.rectangle("fill", barX, listY, 5, listH, 2, 2)
    local thumbH = math.max(20, listH * (listH / (listH + scrollMax)))
    local thumbY = listY + (scroll / scrollMax) * (listH - thumbH)
    love.graphics.setColor(0.55, 0.55, 0.65, 1)
    love.graphics.rectangle("fill", barX, thumbY, 5, thumbH, 2, 2)
  end

  love.graphics.setColor(1, 1, 1, 1)
end

local function drawConfirmButton(x, y, w, h, label, bg, border, onClick)
  local hover = isHover(x, y, w, h)
  local r, g, b = bg[1], bg[2], bg[3]
  if hover then
    r = math.min(1, r + 0.10)
    g = math.min(1, g + 0.10)
    b = math.min(1, b + 0.10)
  end
  love.graphics.setColor(r, g, b, 1)
  love.graphics.rectangle("fill", x, y, w, h, 6, 6)
  love.graphics.setColor(border[1], border[2], border[3], 1)
  love.graphics.rectangle("line", x, y, w, h, 6, 6)
  love.graphics.setFont(fonts.ui)
  love.graphics.setColor(1, 1, 1, 1)
  local lw = fonts.ui:getWidth(label)
  local lh = fonts.ui:getHeight()
  love.graphics.print(label, x + (w - lw) * 0.5, y + (h - lh) * 0.5)
  hitBtn(x, y, w, h, onClick)
end

local function drawResetConfirm()
  local W, H = 380, 170
  local px = (1920 - W) * 0.5
  local py = (1080 - H) * 0.5

  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", 0, 0, 1920, 1080)
  hitBtn(0, 0, 1920, 1080, close)

  love.graphics.setColor(0.12, 0.12, 0.16, 1)
  love.graphics.rectangle("fill", px, py, W, H, 8, 8)
  love.graphics.setColor(0.6, 0.6, 0.7, 1)
  love.graphics.rectangle("line", px, py, W, H, 8, 8)
  hitBtn(px, py, W, H, function() end)

  love.graphics.setColor(1, 0.95, 0.6, 1)
  centerText(fonts.uiBig, "Reset save?", px + W * 0.5, py + 16)

  love.graphics.setColor(0.85, 0.85, 0.9, 1)
  centerText(fonts.ui, "All progress will be deleted.", px + W * 0.5, py + 56)

  local btnW, btnH = 150, 40
  local btnY = py + H - btnH - 16
  drawConfirmButton(px + 16, btnY, btnW, btnH, "Yes, reset",
    { 0.55, 0.28, 0.18 }, { 0.7, 0.5, 0.3 },
    function()
      require("farm.save").reset()
      close()
    end)
  drawConfirmButton(px + W - btnW - 16, btnY, btnW, btnH, "Cancel",
    { 0.22, 0.22, 0.28 }, { 0.55, 0.55, 0.65 },
    close)
end

function Modals.draw()
  buttons = {}
  if State.openModal ~= lastModal then
    scroll = 0
    lastModal = State.openModal
  end
  if State.openModal == "bestiary" then
    drawBestiary()
  elseif State.openModal == "resetConfirm" then
    drawResetConfirm()
  end
end

function Modals.mousepressed(x, y, mbtn)
  if not State.openModal then return false end
  if mbtn ~= 1 then return true end
  for i = #buttons, 1, -1 do
    local b = buttons[i]
    if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
      b.onClick()
      return true
    end
  end
  return true
end

function Modals.wheelmoved(_, dy)
  if State.openModal ~= "bestiary" then return false end
  scroll = math.max(0, math.min(scrollMax, scroll - dy * 36))
  return true
end

return Modals
