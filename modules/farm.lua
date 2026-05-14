local C = require("farm.constants")
local State = require("farm.state")
local Sim = require("farm.sim")
local Genetics = require("farm.genetics")
local Sounds = require("farm.sounds")
local Save = require("farm.save")
local Modals = require("farm.modals")

local Farm = {}

local fontEmoji
local fontEmojiBig
local fontEmojiHuge
local fontUI
local fontUIBig
local fontUISmall

local EMOJI_NATIVE = 109
local function loadFonts()
  local rawFont = love.graphics.newFont("assets/fonts/NotoEmoji-Regular.ttf", EMOJI_NATIVE)
  fontEmoji     = rawFont
  fontEmojiBig  = rawFont
  fontEmojiHuge = rawFont
  fontUI      = love.graphics.newFont(18)
  fontUIBig   = love.graphics.newFont(28)
  fontUISmall = love.graphics.newFont(12)
end

local hudButtons = {}
local cropViewport = { x = 0, y = 0, w = 0, h = 0 }
local cropScrollMax = 0
local robotViewport = { x = 0, y = 0, w = 0, h = 0 }
local robotScrollMax = 0
local gameCanvas

local held = nil  -- { onClick, x, y, w, h, nextFire, delay }
local HOLD_INITIAL_DELAY = 0.30
local HOLD_MIN_DELAY = 0.04
local HOLD_DECAY = 0.85

local function hudBtn(id, x, y, w, h, label, onClick, opts)
  hudButtons[#hudButtons + 1] = {
    id = id, x = x, y = y, w = w, h = h,
    label = label, onClick = onClick, opts = opts or {},
  }
end

local BTN_PAD = 12
local BTN_EMOJI_LEAD = 38
local BTN_H = 40
local BTN_GAP = 6

local function btnW(label, opts)
  opts = opts or {}
  local textW = fontUI and fontUI:getWidth(label or "") or 60
  if opts.cropBuy or opts.robotBuy or opts.stickLabel or opts.stickBuy
    or opts.fertApply or opts.fertBuy or opts.stickApply then
    return BTN_EMOJI_LEAD + textW + BTN_PAD
  end
  return textW + BTN_PAD * 2
end

local function rebuildHudButtons()
  hudButtons = {}
  local hx = C.HUD_X
  local hw = C.HUD_W

  hudBtn("mute", hx + hw - BTN_H, C.HUD_OY, BTN_H, BTN_H, "",
    function() Sounds.muted = not Sounds.muted end,
    { muteIcon = true, active = Sounds.muted })

  hudBtn("reset", hx + hw - BTN_H * 2 - 6, C.HUD_OY, BTN_H, BTN_H, "",
    function() State.openModal = "resetConfirm" end,
    { resetIcon = true })

  local saveBx = hx + hw - BTN_H * 3 - 12
  hudBtn("save", saveBx, C.HUD_OY, BTN_H, BTN_H, "",
    function()
      Save.save()
      State.addPopup(saveBx + BTN_H * 0.5, C.HUD_OY + BTN_H + 8, "Saved!")
    end,
    { saveIcon = true, sound = "buy" })

  hudBtn("bestiary", hx + hw - BTN_H * 4 - 18, C.HUD_OY, BTN_H, BTN_H, "",
    function()
      if State.openModal == "bestiary" then State.openModal = nil
      else State.openModal = "bestiary" end
    end,
    { bestiaryIcon = true, active = State.openModal == "bestiary" })

  if State.debugPanel then
    hudBtn("dbg_money", hx + hw - BTN_H * 5 - 32, C.HUD_OY, BTN_H, BTN_H, "",
      function()
        State.money = State.money + 1000
        State.addPopup(C.HUD_X + 50, C.HUD_OY + 30, "+$1000")
      end,
      { debugMoneyIcon = true })

    hudBtn("dbg_reveal", hx + hw - BTN_H * 6 - 38, C.HUD_OY, BTN_H, BTN_H, "",
      function() State.debugRevealAll = not State.debugRevealAll end,
      { debugRevealIcon = true, active = State.debugRevealAll })
  end

  local actionBarY = C.HUD_OY + 80
  local actionCursor = hx
  local function actionBtn(id, emoji, onClick, opts)
    opts = opts or {}
    opts.actionToggle = emoji
    hudBtn(id, actionCursor, actionBarY, C.ACTION_BTN_W, C.ACTION_BTN_H, "", onClick, opts)
    actionCursor = actionCursor + C.ACTION_BTN_W + C.ACTION_BTN_GAP
  end

  actionBtn("act_stick", C.STICK_EMOJI,
    function() if State.sticks > 0 then State.toggleStick() end end,
    { active = State.stickMode, disabled = State.sticks <= 0, count = State.sticks })

  for _, key in ipairs(C.FERT_KEYS) do
    local def = C.FERTILIZERS[key]
    local n = State.fertInventory[key] or 0
    actionBtn("act_" .. key, def.emoji,
      function() if n > 0 then State.toggleFert(key) end end,
      { active = (State.fertMode == key), disabled = n <= 0, count = n, tint = def.tint })
  end

  actionBtn("act_shovel", "🪏",
    function() State.toggleDig() end,
    { active = State.digToggle })

  actionBtn("act_restrict", "🚫",
    function() State.toggleRestrict() end,
    { active = State.restrictMode })

  local helpY = 1080 - 60
  local rowH56 = 56
  local fertRows = #C.FERT_KEYS
  local fertShopH = fertRows * rowH56
  local fertShopTop = helpY - 8 - fertShopH
  local cropsY = fertShopTop - rowH56
  local buyY = cropsY - rowH56

  local robotsTop = actionBarY + C.ACTION_BTN_H + 14
  local robotRowH = 50
  local availableH = (buyY - 14) - robotsTop
  local robotViewportH = math.max(60, math.floor((availableH - 14) / 2))
  robotViewport = { x = hx, y = robotsTop, w = hw, h = robotViewportH }
  local robotsContentH = #State.robots * robotRowH
  robotScrollMax = math.max(0, robotsContentH - robotViewportH)
  if State.robotScroll > robotScrollMax then State.robotScroll = robotScrollMax end
  if State.robotScroll < 0 then State.robotScroll = 0 end

  local pendingPopups = {}
  local nameMaxW = 0
  for _, n in ipairs(C.ROBOT_NAMES) do
    local w = btnW(n, { nameLabel = true })
    if w > nameMaxW then nameMaxW = w end
  end
  for i, r in ipairs(State.robots) do
    local rowY = robotsTop + (i - 1) * robotRowH - State.robotScroll
    if rowY + BTN_H > robotsTop and rowY < robotsTop + robotViewportH then
      local cursorX = hx

    hudBtn("robot_name_" .. i, cursorX, rowY, nameMaxW, BTN_H, r.name, function() end,
      { selected = true, nameLabel = true, rowClip = "robots" })
    cursorX = cursorX + nameMaxW + BTN_GAP

    local taskLabel = r.task or "Idle"
    local maxTaskW = 0
    for _, tn in ipairs(C.TASKS) do
      local w = btnW(tn)
      if w > maxTaskW then maxTaskW = w end
    end
    local noneW = btnW("None")
    local tkW = math.max(maxTaskW, btnW(taskLabel))
    local tk2W = math.max(maxTaskW, noneW, btnW(r.task2 or "None"))
    local ddKey = "task_" .. i
    hudBtn("robot_task_" .. i, cursorX, rowY, tkW, BTN_H, taskLabel,
      function()
        if State.openDropdown == ddKey then State.openDropdown = nil
        else State.openDropdown = ddKey end
      end,
      { active = (State.openDropdown == ddKey), dropdownTrigger = ddKey, rowClip = "robots" })
    if State.openDropdown == ddKey then
      pendingPopups[#pendingPopups + 1] = {
        robotIdx = i, robotRef = r, x = cursorX, y = rowY + BTN_H + 4, w = tkW,
        taskList = C.TASKS,
        kind = "primary",
      }
    end
    cursorX = cursorX + tkW + BTN_GAP

    local task2Label = r.task2 or "None"
    local ddKey2 = "task2_" .. i
    hudBtn("robot_task2_" .. i, cursorX, rowY, tk2W, BTN_H, task2Label,
      function()
        if State.openDropdown == ddKey2 then State.openDropdown = nil
        else State.openDropdown = ddKey2 end
      end,
      { active = (State.openDropdown == ddKey2), dropdownTrigger = ddKey2, dim = r.task2 == nil, rowClip = "robots" })
    if State.openDropdown == ddKey2 then
      pendingPopups[#pendingPopups + 1] = {
        robotIdx = i, robotRef = r, x = cursorX, y = rowY + BTN_H + 4, w = tk2W,
        taskList = { "None", "Till", "Water", "Weed", "Replant" },
        kind = "fallback",
      }
    end
    cursorX = cursorX + tk2W + BTN_GAP

    local upCost = State.robotUpgradeCost(r)
    local speedLabel = "Lv" .. (r.level or 1) .. " $" .. upCost
    local spW = btnW(speedLabel)
    hudBtn("robot_speed_" .. i, cursorX, rowY, spW, BTN_H, speedLabel,
      function() State.upgradeRobot(r) end,
      { disabled = State.money < upCost, sound = "buy", tooltip = { kind = "robotUp", robot = r }, rowClip = "robots" })
    cursorX = cursorX + spW + BTN_GAP

    local qCount = r.queue and #r.queue or 0
    hudBtn("robot_clear_" .. i, cursorX, rowY, BTN_H, BTN_H, "",
      function()
        r.queue = {}
        if r.activeTask then
          r.activeTask = nil
          r.workTile = nil
          r.workTimer = 0
          r.state = "idle"
          r.idleTimer = 0
        end
      end,
      { disabled = qCount <= 0, clearIcon = true, rowClip = "robots" })
    end
  end

  local invTop = robotsTop + robotViewportH + 14
  local invBottomLimit = buyY - 14
  local viewportH = math.max(60, invBottomLimit - invTop)
  cropViewport = { x = hx, y = invTop, w = hw, h = viewportH }
  local rowH = 42
  local rows = {}
  for cropIdx = 1, #C.CROPS do
    local byTier = State.crops[cropIdx]
    if byTier then
      for tier = #C.TIER_NAMES, 1, -1 do
        local n = byTier[tier]
        if n and n > 0 then
          rows[#rows + 1] = { crop = cropIdx, tier = tier, count = n }
        end
      end
    end
  end
  local contentH = #rows * rowH
  local scrollMax = math.max(0, contentH - viewportH)
  if State.cropScroll > scrollMax then State.cropScroll = scrollMax end
  if State.cropScroll < 0 then State.cropScroll = 0 end
  cropScrollMax = scrollMax
  local sellBtnW = 90
  local infoBtnW = hw - sellBtnW - 4
  for i, row in ipairs(rows) do
    local rowY = invTop + (i - 1) * rowH - State.cropScroll
    if rowY + 32 > invTop and rowY < invTop + viewportH then
      local cropInfo = C.CROPS[row.crop]
      local price = math.floor(C.YIELD_TIER_VALUES[row.tier] * (cropInfo.yieldMult or 1))
      local idCrop = row.crop .. "_" .. row.tier
      local selected = (State.selectedCropIdx == row.crop and State.selectedCropTier == row.tier)
      hudBtn("invc_" .. idCrop, hx, rowY, infoBtnW, 32,
        "",
        function() State.toggleCrop(row.crop, row.tier) end,
        { cropRow = row, selected = selected, rowClip = "crops" })
      hudBtn("invc_sell_" .. idCrop, hx + infoBtnW + 4, rowY, sellBtnW, 32,
        "Sell $" .. price,
        function() State.sellOne(row.crop, row.tier) end,
        { sellLabel = true, sound = "sell", holdRepeat = true, centerLabel = true, rowClip = "crops" })
    end
  end

  do
    local rcost = State.nextRobotCost()
    local canBuyRobot = State.money >= rcost and #State.robots < C.ROBOT_CAP
    local rLabel = "Buy $" .. rcost
    local rW = btnW(rLabel, { robotBuy = true })
    hudBtn("buy_robot", hx, buyY, rW, BTN_H, rLabel,
      function()
        if canBuyRobot then
          State.money = State.money - rcost
          State.robots[#State.robots + 1] = State.newRobot(C.GRID_W * 0.5, 1, "Till")
        end
      end,
      { disabled = not canBuyRobot, robotBuy = true, sound = "buy" })
  end

  do
    local cursorX = hx
    local canBuyStick = State.money >= C.STICK_COST
    local sBuyLabel = "Buy $" .. C.STICK_COST
    local sBuyW = btnW(sBuyLabel, { stickBuy = true })
    hudBtn("buy_stick", cursorX, cropsY, sBuyW, BTN_H, sBuyLabel,
      function()
        if canBuyStick then
          State.money = State.money - C.STICK_COST
          State.sticks = State.sticks + 1
        end
      end,
      { disabled = not canBuyStick, stickBuy = true, sound = "buy" })
    cursorX = cursorX + sBuyW + BTN_GAP

    local tCost = C.CROPS[1].buyCost
    local canBuyTomato = State.money >= tCost
    local tLabel = "Buy $" .. tCost
    local tW = btnW(tLabel, { cropBuy = 1 })
    hudBtn("buy_tomato", cursorX, cropsY, tW, BTN_H, tLabel,
      function()
        if canBuyTomato then
          State.money = State.money - tCost
          State.addCrop(1, 1)
        end
      end,
      { disabled = not canBuyTomato, cropBuy = 1, sound = "buy" })
    cursorX = cursorX + tW + BTN_GAP

    local cCost = C.CROPS[2].buyCost
    local canBuyCarrot = State.money >= cCost
    local cLabel = "Buy $" .. cCost
    local cW = btnW(cLabel, { cropBuy = 2 })
    hudBtn("buy_carrot", cursorX, cropsY, cW, BTN_H, cLabel,
      function()
        if canBuyCarrot then
          State.money = State.money - cCost
          State.addCrop(2, 1)
        end
      end,
      { disabled = not canBuyCarrot, cropBuy = 2, sound = "buy" })
  end

  for i, key in ipairs(C.FERT_KEYS) do
    local def = C.FERTILIZERS[key]
    local rowY = fertShopTop + (i - 1) * rowH56
    local cur = hx

    local bcost = State.fertBuyCost(key)
    local buyLabel = "Buy $" .. bcost
    local buyW = btnW(buyLabel, { fertBuy = key })
    hudBtn("fert_buy_" .. key, cur, rowY, buyW, BTN_H, buyLabel,
      function() State.buyFert(key) end,
      { fertBuy = key, disabled = State.money < bcost, sound = "buy" })
    cur = cur + buyW + BTN_GAP

    local upCost = State.fertUpgradeCost(key)
    local lvl = State.fertLevel[key] or 1
    local upLabel = "Lv" .. lvl .. " $" .. upCost
    local upW = btnW(upLabel)
    hudBtn("fert_up_" .. key, cur, rowY, upW, BTN_H, upLabel,
      function() State.upgradeFert(key) end,
      { disabled = State.money < upCost, sound = "buy", tooltip = { kind = "fertUp", key = key } })
  end

  for _, pop in ipairs(pendingPopups) do
    local popY = pop.y
    for ti, taskName in ipairs(pop.taskList) do
      local current
      if pop.kind == "fallback" then
        current = pop.robotRef.task2 or "None"
      else
        current = pop.robotRef.task
      end
      local idPrefix = (pop.kind == "fallback") and "task2_pop_" or "task_pop_"
      hudBtn(idPrefix .. pop.robotIdx .. "_" .. ti, pop.x, popY, pop.w, BTN_H, taskName,
        function()
          if pop.kind == "fallback" then
            pop.robotRef.task2 = (taskName == "None") and nil or taskName
          else
            pop.robotRef.task = taskName
            pop.robotRef.state = "idle"
            pop.robotRef.idleTimer = 0
          end
          State.openDropdown = nil
        end,
        { active = (current == taskName), popupItem = true })
      popY = popY + BTN_H + 2
    end
  end

end

local autoSaveAccum = 0

function Farm.start()
  loadFonts()
  Sounds.init()
  State.init()
  Save.load()
  Modals.setFonts({
    ui = fontUI, uiBig = fontUIBig, uiSmall = fontUISmall,
    emoji = fontEmoji, emojiBig = fontEmojiBig,
    emojiNative = EMOJI_NATIVE,
  })
  gameCanvas = love.graphics.newCanvas(1920, 1080)
  State.recomputeViewport()
end

function Farm.resize()
  State.recomputeViewport()
end

function Farm.shutdown()
  Save.save()
end

function Farm.update(dt)
  Sim.update(dt)
  State.tickPopups()
  rebuildHudButtons()
  if held then
    local mx, my = State.getMousePosition()
    if not love.mouse.isDown(1)
      or mx < held.x or mx > held.x + held.w
      or my < held.y or my > held.y + held.h then
      held = nil
    else
      held.nextFire = held.nextFire - dt
      if held.nextFire <= 0 then
        held.onClick()
        held.delay = math.max(HOLD_MIN_DELAY, held.delay * HOLD_DECAY)
        held.nextFire = held.delay
      end
    end
  end
  autoSaveAccum = autoSaveAccum + dt
  if autoSaveAccum >= C.SAVE_INTERVAL then
    autoSaveAccum = 0
    Save.save()
  end
end

local function drawEmoji(font, glyph, x, y, scale)
  scale = scale or 1
  love.graphics.setFont(font)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print(glyph, x, y, 0, scale, scale)
end

local function drawCenteredEmoji(font, glyph, cx, cy, scale)
  scale = scale or 1
  love.graphics.setFont(font)
  love.graphics.setColor(1, 1, 1, 1)
  local w = font:getWidth(glyph) * scale
  local h = font:getHeight() * scale
  love.graphics.print(glyph, cx - w * 0.5, cy - h * 0.5, 0, scale, scale)
end

local function drawCenteredEmojiTinted(font, glyph, cx, cy, scale, tint)
  scale = scale or 1
  love.graphics.setFont(font)
  local c = tint or { 1, 1, 1 }
  love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
  local w = font:getWidth(glyph) * scale
  local h = font:getHeight() * scale
  love.graphics.print(glyph, cx - w * 0.5, cy - h * 0.5, 0, scale, scale)
end

local function drawPopups()
  for _, p in ipairs(State.popups) do
    local elapsed = State.time - p.startTime
    local t = elapsed / p.life
    if t < 1 then
      local y = p.y - 60 * t
      local alpha = 1 - t
      if p.kind == "crop" then
        local emojiScale = 28 / EMOJI_NATIVE
        local emojiW = fontEmojiBig:getWidth(p.emoji) * emojiScale
        local gap = 8
        love.graphics.setFont(fontUIBig)
        local tierW = fontUIBig:getWidth(p.tierLabel)
        local totalW = emojiW + gap + tierW
        local x0 = p.x - totalW * 0.5
        local ty = y + (fontEmojiBig:getHeight() * emojiScale - fontUIBig:getHeight()) * 0.5
        drawCenteredEmojiTinted(fontEmojiBig, p.emoji, x0 + emojiW * 0.5, y + fontEmojiBig:getHeight() * emojiScale * 0.5, emojiScale, { p.emojiTint[1], p.emojiTint[2], p.emojiTint[3], alpha })
        love.graphics.setFont(fontUIBig)
        love.graphics.setColor(0, 0, 0, 0.6 * alpha)
        love.graphics.print(p.tierLabel, x0 + emojiW + gap + 2, ty + 2)
        local tc = p.tierColor or { 1, 1, 1 }
        love.graphics.setColor(tc[1], tc[2], tc[3], alpha)
        love.graphics.print(p.tierLabel, x0 + emojiW + gap, ty)
      else
        love.graphics.setFont(fontUIBig)
        local w = fontUIBig:getWidth(p.text)
        love.graphics.setColor(0, 0, 0, 0.6 * alpha)
        love.graphics.print(p.text, p.x - w * 0.5 + 2, y + 2)
        love.graphics.setColor(1, 0.95, 0.4, alpha)
        love.graphics.print(p.text, p.x - w * 0.5, y)
      end
    end
  end
end

local function tileFill(t)
  if t.state == "wild"   then return 0.30, 0.22, 0.16 end
  if t.state == "tilled" then return 0.45, 0.30, 0.18 end
  if t.state == "growing" or t.state == "ripe" then return 0.38, 0.27, 0.17 end
  if t.state == "stick"  then return 0.42, 0.28, 0.18 end
  return 0.2, 0.2, 0.2
end

local function drawGrid()
  for y = 1, C.GRID_H do
    for x = 1, C.GRID_W do
      local t = State.tiles[y][x]
      local sx, sy = State.tileToScreen(x, y)
      if y > State.unlockedRows then
        love.graphics.setColor(0.45, 0.40, 0.30, 0.6)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", sx + 2, sy + 2, C.TILE - 4, C.TILE - 4, 6, 6)
      else
      local r, g, b = tileFill(t)
      love.graphics.setColor(r, g, b, 1)
      love.graphics.rectangle("fill", sx + 2, sy + 2, C.TILE - 4, C.TILE - 4, 6, 6)

      if t.weed then
        drawCenteredEmojiTinted(fontEmojiHuge, C.WEED_EMOJI, sx + C.TILE * 0.5, sy + C.TILE * 0.5, C.TILE * 0.8 / EMOJI_NATIVE, C.WEED_TINT)
      end

      if t.crop then
        local cx, cy = sx + C.TILE * 0.5, sy + C.TILE * 0.5
        local growthScale = 0.4 + 0.6 * t.crop.growth

        if t.state == "ripe" then
          local pulse = 0.5 + 0.5 * math.sin(State.time * 4)
          love.graphics.setColor(1, 0.95, 0.3, 0.25 + 0.35 * pulse)
          love.graphics.rectangle("fill", sx + 2, sy + 2, C.TILE - 4, C.TILE - 4, 6, 6)
          love.graphics.setColor(1, 0.9, 0.2, 0.7 + 0.3 * pulse)
          love.graphics.setLineWidth(3)
          love.graphics.rectangle("line", sx + 2, sy + 2, C.TILE - 4, C.TILE - 4, 6, 6)
          love.graphics.setLineWidth(1)
        end

        drawCenteredEmojiTinted(fontEmojiHuge, t.crop.pheno.emoji, cx, cy, (C.TILE * 0.6 / EMOJI_NATIVE) * growthScale, t.crop.pheno.tint)

        if t.state == "ripe" then
          local bob = math.sin(State.time * 6) * 4
          drawCenteredEmojiTinted(fontEmoji, C.RIPE_GLYPH, sx + C.TILE - 18, sy + 18 + bob, 28 / EMOJI_NATIVE, C.RIPE_TINT)
        end

        love.graphics.setColor(0, 0, 0, 0.35)
        love.graphics.rectangle("fill", sx + 6, sy + C.TILE - 12, C.TILE - 12, 6, 2, 2)
        if t.state == "ripe" then
          love.graphics.setColor(1, 0.85, 0.2, 1)
        else
          love.graphics.setColor(0.5, 0.9, 0.4, 1)
        end
        love.graphics.rectangle("fill", sx + 6, sy + C.TILE - 12, (C.TILE - 12) * t.crop.growth, 6, 2, 2)

        love.graphics.setColor(0.2, 0.6, 1.0, 0.9)
        love.graphics.rectangle("fill", sx + 6, sy + C.TILE - 22, (C.TILE - 12) * t.crop.water, 4, 2, 2)

        if t.crop.hybrid then
          love.graphics.setColor(1, 0.3, 0.9, 1)
          love.graphics.circle("fill", sx + C.TILE - 10, sy + C.TILE - 9, 4)
        end
      end

      if t.restrict then
        love.graphics.setColor(1, 0.5, 0.5, 0.85)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", sx + 2, sy + 2, C.TILE - 4, C.TILE - 4, 6, 6)
        love.graphics.setLineWidth(1)
      end

      if t.ferts then
        local active = {}
        for _, key in ipairs(C.FERT_KEYS) do
          local e = t.ferts[key]
          if e and e > State.time then active[#active + 1] = key end
        end
        local n = #active
        if n > 0 then
          local spacing = 22
          local iconR = 10
          local startX = sx + C.TILE * 0.5 - (n - 1) * spacing * 0.5
          local iconY = sy + 14
          for i, key in ipairs(active) do
            local def = C.FERTILIZERS[key]
            local cx = startX + (i - 1) * spacing
            love.graphics.setColor(0, 0, 0, 0.65)
            love.graphics.circle("fill", cx, iconY, iconR)
            drawCenteredEmojiTinted(fontEmoji, def.emoji, cx, iconY, 16 / EMOJI_NATIVE, def.tint)
            local remaining = t.ferts[key] - State.time
            local total = State.fertDuration(key)
            local progress = math.max(0, math.min(1, remaining / total))
            love.graphics.setColor(def.tint[1], def.tint[2], def.tint[3], 0.95)
            love.graphics.setLineWidth(2)
            love.graphics.arc("line", "open", cx, iconY, iconR + 2, -math.pi/2, -math.pi/2 + 2*math.pi*progress)
            love.graphics.setLineWidth(1)
          end
        end
      end
      end
    end
  end

  for y = State.unlockedRows + 1, C.GRID_H do
    local centerX = C.GRID_OX + C.GRID_W * C.TILE * 0.5
    local centerY = C.GRID_OY + (y - 0.5) * C.TILE
    drawCenteredEmojiTinted(fontEmojiBig, C.LOCK_EMOJI, C.GRID_OX + 22, centerY, 36 / EMOJI_NATIVE, C.LOCK_TINT)

    love.graphics.setFont(fontUIBig)
    local cost = State.rowUnlockCost(y) or 0
    local moneyOk = State.money >= cost
    local nextRow = y == State.unlockedRows + 1
    local costTxt = "$" .. cost
    if moneyOk and nextRow then
      love.graphics.setColor(1, 0.95, 0.45, 1)
    elseif moneyOk then
      love.graphics.setColor(0.9, 0.85, 0.55, 1)
    else
      love.graphics.setColor(0.95, 0.45, 0.45, 1)
    end
    local reqs = State.rowUnlockReqs(y)
    local emojiScale = 28 / EMOJI_NATIVE
    local cellGap = 16
    local costW = fontUIBig:getWidth(costTxt)
    local cells = {}
    local totalW = costW + cellGap
    love.graphics.setFont(fontUI)
    if reqs then
      for i, r in ipairs(reqs) do
        local have = State.cropCountAtTier(r.crop, r.tier)
        local crop = C.CROPS[r.crop]
        local tierName = C.TIER_NAMES[r.tier]
        local countTxt = string.format(" %d/%d ", have, r.count)
        local tierTxt = tierName .. "+"
        local emojiW = fontEmoji:getWidth(crop.emoji) * emojiScale
        local countW = fontUI:getWidth(countTxt)
        local tierW = fontUI:getWidth(tierTxt)
        local cw = emojiW + countW + tierW
        cells[i] = {
          w = cw, emojiW = emojiW, countW = countW, countTxt = countTxt,
          tierW = tierW, tierTxt = tierTxt, tier = r.tier,
          have = have, need = r.count, crop = crop,
        }
        totalW = totalW + cw
        if i < #reqs then totalW = totalW + cellGap end
      end
    end
    local cx = centerX - totalW * 0.5
    local lineY = centerY - fontUIBig:getHeight() * 0.5
    love.graphics.setFont(fontUIBig)
    love.graphics.print(costTxt, cx, lineY)
    cx = cx + costW + cellGap
    love.graphics.setFont(fontUI)
    local cellTextY = centerY - fontUI:getHeight() * 0.5
    for _, cell in ipairs(cells) do
      drawCenteredEmojiTinted(fontEmoji, cell.crop.emoji, cx + cell.emojiW * 0.5, centerY, emojiScale, cell.crop.color)
      local satisfied = cell.have >= cell.need
      if satisfied then
        love.graphics.setColor(0.55, 0.95, 0.55, 1)
      else
        love.graphics.setColor(0.95, 0.55, 0.55, 1)
      end
      love.graphics.setFont(fontUI)
      love.graphics.print(cell.countTxt, cx + cell.emojiW, cellTextY)
      local tc = C.TIER_COLORS[cell.tier] or { 1, 1, 1 }
      love.graphics.setColor(tc[1], tc[2], tc[3], 1)
      love.graphics.print(cell.tierTxt, cx + cell.emojiW + cell.countW, cellTextY)
      cx = cx + cell.w + cellGap
    end
  end

  for y = 1, State.unlockedRows do
    for x = 1, C.GRID_W do
      local t = State.tiles[y][x]
      if t.state == "stick" then
        local sx, sy = State.tileToScreen(x, y)
        local cx, cy = sx + C.TILE * 0.5, sy + C.TILE * 0.5
        local sw, sh = 9, 62
        local spacing = 20
        -- dark outline for contrast
        love.graphics.setColor(0.10, 0.06, 0.02, 1)
        love.graphics.rectangle("fill", cx - spacing - sw * 0.5 - 1, cy - sh * 0.5 - 1, sw + 2, sh + 2, 3, 3)
        love.graphics.rectangle("fill", cx + spacing - sw * 0.5 - 1, cy - sh * 0.5 - 1, sw + 2, sh + 2, 3, 3)
        -- bright tan vertical sticks
        love.graphics.setColor(0.95, 0.75, 0.40, 1)
        love.graphics.rectangle("fill", cx - spacing - sw * 0.5, cy - sh * 0.5, sw, sh, 2, 2)
        love.graphics.rectangle("fill", cx + spacing - sw * 0.5, cy - sh * 0.5, sw, sh, 2, 2)
        -- crossbar
        local cw = spacing * 2 + sw
        love.graphics.setColor(0.10, 0.06, 0.02, 1)
        love.graphics.rectangle("fill", cx - cw * 0.5 - 1, cy - 5, cw + 2, 8, 3, 3)
        love.graphics.setColor(1.00, 0.85, 0.45, 1)
        love.graphics.rectangle("fill", cx - cw * 0.5, cy - 4, cw, 6, 2, 2)
      end
    end
  end

  if State.hoverTile then
    local t = State.hoverTile
    local sx, sy = State.tileToScreen(t.x, t.y)
    local cr, cg, cb, ca
    if t.y > State.unlockedRows then
      local cost = State.rowUnlockCost(t.y) or 0
      if t.y == State.unlockedRows + 1 and State.money >= cost then
        cr, cg, cb, ca = 0.9, 0.8, 0.3, 0.25
      else
        cr, cg, cb, ca = 0.6, 0.3, 0.3, 0.20
      end
    elseif State.restrictMode then
      cr, cg, cb, ca = 1, 0.4, 0.4, 0.3
    elseif State.stickMode then
      if t.state == "tilled" then
        cr, cg, cb, ca = 0.95, 0.75, 0.40, 0.35
      else
        cr, cg, cb, ca = 0.7, 0.3, 0.3, 0.3
      end
    elseif State.fertMode then
      if t.state == "tilled" or t.state == "growing" or t.state == "ripe" or t.state == "stick" then
        local tt = C.FERTILIZERS[State.fertMode].tint
        cr, cg, cb, ca = tt[1], tt[2], tt[3], 0.35
      else
        cr, cg, cb, ca = 0.7, 0.3, 0.3, 0.3
      end
    elseif State.digToggle then
      cr, cg, cb, ca = 1, 0.3, 0.3, 0.4
    elseif t.weed then
      cr, cg, cb, ca = 0.4, 0.9, 0.4, 0.35
    elseif t.state == "ripe" then
      cr, cg, cb, ca = 0.4, 0.9, 0.4, 0.4
    elseif t.state == "tilled" and State.selectedCropIdx then
      cr, cg, cb, ca = 0.4, 0.9, 0.4, 0.3
    else
      cr, cg, cb, ca = 0.5, 0.5, 0.5, 0.12
    end
    love.graphics.setColor(cr, cg, cb, ca)
    love.graphics.rectangle("fill", sx + 2, sy + 2, C.TILE - 4, C.TILE - 4, 6, 6)
  end

  for y = 1, C.GRID_H do
    for x = 1, C.GRID_W do
      local t = State.tiles[y][x]
      if t._flashUntil and State.time < t._flashUntil then
        local sx, sy = State.tileToScreen(x, y)
        local p = (t._flashUntil - State.time) / 0.3
        local fc = t._flashColor or { 1, 0.2, 0.2 }
        love.graphics.setColor(fc[1], fc[2], fc[3], 0.5 * p)
        love.graphics.rectangle("fill", sx + 2, sy + 2, C.TILE - 4, C.TILE - 4, 6, 6)
      end
    end
  end

end

local function drawCropTooltip()
  if not (State.hoverTile and State.hoverTile.crop) then return end
  local t = State.hoverTile
  local ph = t.crop.pheno
  local sx, sy = State.tileToScreen(t.x, t.y)
  local panelW, panelH = 180, 106
  local px = sx + C.TILE * 0.5 - panelW * 0.5
  local py = sy - panelH - 8
  if py < 4 then py = sy + C.TILE + 8 end
  if px < 4 then px = 4 end
  if px + panelW > C.HUD_X - 16 then px = C.HUD_X - 16 - panelW end

  love.graphics.setColor(0.05, 0.05, 0.08, 0.92)
  love.graphics.rectangle("fill", px, py, panelW, panelH, 6, 6)
  love.graphics.setColor(0.5, 0.5, 0.65, 1)
  love.graphics.rectangle("line", px, py, panelW, panelH, 6, 6)

  drawCenteredEmojiTinted(fontEmojiBig, ph.emoji, px + 22, py + 22, 28 / EMOJI_NATIVE, ph.tint)
  love.graphics.setFont(fontUI)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print(ph.name, px + 46, py + 12)

  local lineY = py + 42
  love.graphics.setColor(0.85, 0.85, 0.9, 1)
  love.graphics.print("Tier: ", px + 10, lineY)
  local tc = C.TIER_COLORS[ph.tier] or { 1, 1, 1 }
  love.graphics.setColor(tc[1], tc[2], tc[3], 1)
  love.graphics.print(ph.tierLabel, px + 10 + fontUI:getWidth("Tier: "), lineY)

  lineY = lineY + 20
  love.graphics.setColor(0.85, 0.85, 0.9, 1)
  love.graphics.print(string.format("Price: %d$", ph.yield), px + 10, lineY)
  lineY = lineY + 20
  love.graphics.print(string.format("Grow: %dsec", ph.growTime), px + 10, lineY)

  if t.crop.hybrid then
    love.graphics.setColor(1, 0.4, 0.95, 1)
    love.graphics.circle("fill", px + panelW - 14, py + 14, 5)
  end
end

local function drawRobots()
  for _, r in ipairs(State.robots) do
    local cx = C.GRID_OX + (r.px - 0.5) * C.TILE
    local cy = C.GRID_OY + (r.py - 0.5) * C.TILE
    local rc = r.color or { 1, 1, 1 }
    local scale = C.TILE * 0.55 / EMOJI_NATIVE

    if r.pingUntil and State.time < r.pingUntil then
      local p = (r.pingUntil - State.time) / 0.5
      local radius = C.TILE * (0.35 + 0.35 * (1 - p))
      love.graphics.setColor(0.3, 0.8, 1, 0.7 * p)
      love.graphics.setLineWidth(3)
      love.graphics.circle("line", cx, cy, radius)
      love.graphics.setLineWidth(1)
    end
    love.graphics.setFont(fontEmojiBig)
    love.graphics.setColor(rc[1], rc[2], rc[3], 1)
    local rw = fontEmojiBig:getWidth(C.ROBOT_EMOJI) * scale
    local rh = fontEmojiBig:getHeight() * scale
    love.graphics.print(C.ROBOT_EMOJI, cx - rw * 0.5, cy - rh * 0.5, 0, scale, scale)
    drawCenteredEmojiTinted(fontEmoji, C.TASK_GLYPH[r.task] or "", cx + 24, cy + 22, 24 / EMOJI_NATIVE, C.TASK_TINT[r.task])

    love.graphics.setFont(fontUI)
    local nameW = fontUI:getWidth(r.name)
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", cx - nameW * 0.5 - 4, cy - C.TILE * 0.5 + 2, nameW + 8, 20, 4, 4)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(r.name, cx - nameW * 0.5, cy - C.TILE * 0.5 + 3)

    if r.state == "working" and r.workTimer > 0 then
      local workMult = 1 + ((r.level or 1) - 1) * C.ROBOT_WORK_MULT_PER_LEVEL
      local total = (C.WORK_TIME[r.activeTask or r.task] or 1) / workMult
      local p = 1 - (r.workTimer / total)
      love.graphics.setColor(0, 0, 0, 0.4)
      love.graphics.rectangle("fill", cx - (C.TILE - 24) * 0.5, cy + C.TILE * 0.5 - 10, C.TILE - 24, 5, 2, 2)
      love.graphics.setColor(0.4, 0.9, 1, 1)
      love.graphics.rectangle("fill", cx - (C.TILE - 24) * 0.5, cy + C.TILE * 0.5 - 10, (C.TILE - 24) * p, 5, 2, 2)
    end

    if r.queue and #r.queue > 0 then
      local badge = "+" .. #r.queue
      love.graphics.setFont(fontUI)
      local bw = fontUI:getWidth(badge)
      love.graphics.setColor(0.1, 0.4, 0.6, 0.85)
      love.graphics.rectangle("fill", cx + C.TILE * 0.3, cy - C.TILE * 0.5 + 2, bw + 10, 22, 4, 4)
      love.graphics.setColor(0.7, 0.95, 1, 1)
      love.graphics.print(badge, cx + C.TILE * 0.3 + 5, cy - C.TILE * 0.5 + 3)
    end
  end
end

local function drawHud()
  love.graphics.setColor(0.08, 0.08, 0.12, 1)
  love.graphics.rectangle("fill", C.HUD_X - 16, 0, C.HUD_W + 32, 1080)

  love.graphics.setFont(fontUIBig)
  love.graphics.setColor(1, 1, 0.6, 1)
  love.graphics.print(string.format("$%d", State.money), C.HUD_X, C.HUD_OY)
  love.graphics.setFont(fontUI)
  love.graphics.setColor(0.7, 0.7, 0.8, 1)
  local cropTotal = 0
  for _, byTier in pairs(State.crops) do
    for _, n in pairs(byTier) do cropTotal = cropTotal + n end
  end
  love.graphics.print(string.format("t=%.1fs  crops=%d  robots=%d/%d  weeds_in=%.0fs",
    State.time, cropTotal, #State.robots, C.ROBOT_CAP, State.weedTimer),
    C.HUD_X, C.HUD_OY + 44)

  local mxh, myh = State.getMousePosition()
  for _, b in ipairs(hudButtons) do
    local clipVp
    if b.opts.rowClip == "robots" then clipVp = robotViewport
    elseif b.opts.rowClip == "crops" then clipVp = cropViewport end
    if clipVp then
      love.graphics.setScissor(clipVp.x, clipVp.y, clipVp.w, clipVp.h)
    end
    local hover = (not b.opts.disabled) and (not b.opts.nameLabel)
      and mxh >= b.x and mxh <= b.x + b.w
      and myh >= b.y and myh <= b.y + b.h
      and (not clipVp or (myh >= clipVp.y and myh <= clipVp.y + clipVp.h))
    local br, bg, bb
    if b.opts.selected then
      br, bg, bb = 0.35, 0.55, 0.35
    elseif b.opts.active then
      br, bg, bb = 0.4, 0.4, 0.6
    elseif b.opts.disabled then
      br, bg, bb = 0.2, 0.2, 0.2
    elseif b.opts.sellLabel then
      br, bg, bb = 0.45, 0.38, 0.18
    elseif b.opts.popupItem then
      br, bg, bb = 0.18, 0.20, 0.30
    else
      br, bg, bb = 0.22, 0.22, 0.28
    end
    if hover then
      br = math.min(1, br + 0.12)
      bg = math.min(1, bg + 0.12)
      bb = math.min(1, bb + 0.12)
    end
    love.graphics.setColor(br, bg, bb, 1)
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 6, 6)
    if hover then
      love.graphics.setColor(0.95, 0.95, 1, 1)
    else
      love.graphics.setColor(0.5, 0.5, 0.6, 1)
    end
    love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 6, 6)

    love.graphics.setFont(fontUI)
    love.graphics.setColor(1, 1, 1, 1)
    if b.opts.cropRow then
      local row = b.opts.cropRow
      local cropInfo = C.CROPS[row.crop]
      love.graphics.setFont(fontUI)
      local emojiScale = 28 / EMOJI_NATIVE
      local emojiW = fontEmojiBig:getWidth(cropInfo.emoji) * emojiScale
      local nameW = fontUI:getWidth(cropInfo.name)
      local tierStr = C.TIER_NAMES[row.tier]
      local tierW = fontUI:getWidth(tierStr)
      local countStr = "x" .. row.count
      local countW = fontUI:getWidth(countStr)
      local gap0, gap1, gap2 = 8, 8, 12
      local totalW = emojiW + gap0 + nameW + gap1 + tierW + gap2 + countW
      local tx = b.x + (b.w - totalW) * 0.5
      local ty = b.y + (b.h - fontUI:getHeight()) * 0.5
      drawCenteredEmojiTinted(fontEmojiBig, cropInfo.emoji, tx + emojiW * 0.5, b.y + b.h * 0.5, emojiScale, cropInfo.color)
      tx = tx + emojiW + gap0
      love.graphics.setFont(fontUI)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.print(cropInfo.name, tx, ty)
      tx = tx + nameW + gap1
      local tc = C.TIER_COLORS[row.tier] or { 1, 1, 1 }
      love.graphics.setColor(tc[1], tc[2], tc[3], 1)
      love.graphics.print(tierStr, tx, ty)
      tx = tx + tierW + gap2
      love.graphics.setColor(0.9, 0.9, 0.95, 1)
      love.graphics.print(countStr, tx, ty)
    elseif b.opts.stickLabel then
      drawCenteredEmoji(fontEmojiBig, C.STICK_EMOJI, b.x + 18, b.y + b.h * 0.5, 28 / EMOJI_NATIVE)
      love.graphics.setFont(fontUI)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.print(b.label, b.x + 44, b.y + 10)
    elseif b.opts.cropBuy then
      local crop = C.CROPS[b.opts.cropBuy]
      drawCenteredEmojiTinted(fontEmojiBig, crop.emoji, b.x + 20, b.y + b.h * 0.5, 28 / EMOJI_NATIVE, crop.color)
      love.graphics.setFont(fontUI)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.print("Buy $" .. (crop.buyCost or 0), b.x + 44, b.y + 10)
    elseif b.opts.robotBuy then
      drawCenteredEmoji(fontEmojiBig, C.ROBOT_EMOJI, b.x + 20, b.y + b.h * 0.5, 28 / EMOJI_NATIVE)
      love.graphics.setFont(fontUI)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.print(b.label, b.x + 44, b.y + 10)
    elseif b.opts.stickBuy then
      drawCenteredEmoji(fontEmojiBig, C.STICK_EMOJI, b.x + 20, b.y + b.h * 0.5, 28 / EMOJI_NATIVE)
      love.graphics.setFont(fontUI)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.print(b.label, b.x + 44, b.y + 10)
    elseif b.opts.fertApply or b.opts.fertBuy then
      local key = b.opts.fertApply or b.opts.fertBuy
      local def = C.FERTILIZERS[key]
      drawCenteredEmojiTinted(fontEmojiBig, def.emoji, b.x + 20, b.y + b.h * 0.5, 28 / EMOJI_NATIVE, def.tint)
      love.graphics.setFont(fontUI)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.print(b.label, b.x + 44, b.y + 10)
    elseif b.opts.stickApply then
      drawCenteredEmoji(fontEmojiBig, C.STICK_EMOJI, b.x + 20, b.y + b.h * 0.5, 28 / EMOJI_NATIVE)
      love.graphics.setFont(fontUI)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.print(b.label, b.x + 44, b.y + 10)
    elseif b.opts.muteIcon then
      drawCenteredEmoji(fontEmojiBig, Sounds.muted and "🔇" or "🔊", b.x + b.w * 0.5, b.y + b.h * 0.5, 28 / EMOJI_NATIVE)
    elseif b.opts.resetIcon then
      drawCenteredEmoji(fontEmojiBig, "🗑", b.x + b.w * 0.5, b.y + b.h * 0.5, 28 / EMOJI_NATIVE)
    elseif b.opts.saveIcon then
      drawCenteredEmoji(fontEmojiBig, "💾", b.x + b.w * 0.5, b.y + b.h * 0.5, 28 / EMOJI_NATIVE)
    elseif b.opts.bestiaryIcon then
      drawCenteredEmoji(fontEmojiBig, C.BESTIARY_EMOJI, b.x + b.w * 0.5, b.y + b.h * 0.5, 28 / EMOJI_NATIVE)
    elseif b.opts.debugMoneyIcon then
      drawCenteredEmoji(fontEmojiBig, "💰", b.x + b.w * 0.5, b.y + b.h * 0.5, 28 / EMOJI_NATIVE)
    elseif b.opts.debugRevealIcon then
      drawCenteredEmoji(fontEmojiBig, "👁", b.x + b.w * 0.5, b.y + b.h * 0.5, 28 / EMOJI_NATIVE)
    elseif b.opts.clearIcon then
      drawCenteredEmoji(fontEmojiBig, "🔄", b.x + b.w * 0.5, b.y + b.h * 0.5, 28 / EMOJI_NATIVE)
    elseif b.opts.actionToggle then
      if b.opts.tint then
        drawCenteredEmojiTinted(fontEmojiBig, b.opts.actionToggle, b.x + b.w * 0.5, b.y + b.h * 0.5, 32 / EMOJI_NATIVE, b.opts.tint)
      else
        drawCenteredEmoji(fontEmojiBig, b.opts.actionToggle, b.x + b.w * 0.5, b.y + b.h * 0.5, 32 / EMOJI_NATIVE)
      end
      if b.opts.count then
        love.graphics.setFont(fontUISmall)
        local txt = "x" .. b.opts.count
        local tw = fontUISmall:getWidth(txt)
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", b.x + b.w - tw - 8, b.y + b.h - 16, tw + 6, 14, 3, 3)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(txt, b.x + b.w - tw - 5, b.y + b.h - 16)
      end
    elseif b.opts.digIcon then
      drawCenteredEmoji(fontEmojiBig, "🪏", b.x + b.w * 0.5, b.y + b.h * 0.5, 28 / EMOJI_NATIVE)
    elseif b.opts.centerLabel then
      local lw = fontUI:getWidth(b.label)
      local lh = fontUI:getHeight()
      love.graphics.print(b.label, b.x + (b.w - lw) * 0.5, b.y + (b.h - lh) * 0.5)
    else
      love.graphics.print(b.label, b.x + 10, b.y + 10)
    end
    if clipVp then love.graphics.setScissor() end
  end

  local lineX = C.HUD_X - 8
  local lineW = C.HUD_W + 16
  local topY = robotViewport.y - 7
  local midY = math.floor((robotViewport.y + robotViewport.h + cropViewport.y) * 0.5)
  local botY = cropViewport.y + cropViewport.h + 7
  love.graphics.setColor(0.7, 0.7, 0.8, 1)
  love.graphics.rectangle("fill", lineX, topY - 1, lineW, 2)
  love.graphics.rectangle("fill", lineX, midY - 1, lineW, 2)
  love.graphics.rectangle("fill", lineX, botY - 1, lineW, 2)

  local barX = C.HUD_X + C.HUD_W + 2
  if cropScrollMax > 0 then
    local barY = cropViewport.y + 2
    local barH = cropViewport.h - 4
    love.graphics.setColor(0.15, 0.15, 0.18, 1)
    love.graphics.rectangle("fill", barX, barY, 5, barH, 2, 2)
    local thumbH = math.max(20, barH * (barH / (barH + cropScrollMax)))
    local thumbY = barY + (State.cropScroll / cropScrollMax) * (barH - thumbH)
    love.graphics.setColor(0.55, 0.55, 0.65, 1)
    love.graphics.rectangle("fill", barX, thumbY, 5, thumbH, 2, 2)
  end

  if robotScrollMax > 0 then
    local barY = robotViewport.y + 2
    local barH = robotViewport.h - 4
    love.graphics.setColor(0.15, 0.15, 0.18, 1)
    love.graphics.rectangle("fill", barX, barY, 5, barH, 2, 2)
    local thumbH = math.max(20, barH * (barH / (barH + robotScrollMax)))
    local thumbY = barY + (State.robotScroll / robotScrollMax) * (barH - thumbH)
    love.graphics.setColor(0.55, 0.55, 0.65, 1)
    love.graphics.rectangle("fill", barX, thumbY, 5, thumbH, 2, 2)
  end

  local helpY = 1080 - 60
  love.graphics.setFont(fontUISmall)
  love.graphics.setColor(0.55, 0.55, 0.65, 1)
  love.graphics.print("LMB: harvest, plant selected crop, or use active action.", C.HUD_X, helpY)
  love.graphics.print("RMB/MMB: cancel mode, else queue nearest robot for tile.", C.HUD_X, helpY + 16)
  love.graphics.print("Action bar: stick / fert / shovel / restrict. Sticks breed adj ripe.", C.HUD_X, helpY + 32)

end

local function drawHudTooltip()
  local mx, my = State.getMousePosition()
  local hovered
  for i = #hudButtons, 1, -1 do
    local b = hudButtons[i]
    if b.opts.tooltip and mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
      hovered = b
      break
    end
  end
  if not hovered then return end
  local tt = hovered.opts.tooltip
  local lines = {}
  if tt.kind == "fertUp" then
    local def = C.FERTILIZERS[tt.key]
    local lvl = State.fertLevel[tt.key] or 1
    local curDur = State.fertDuration(tt.key, lvl)
    local nextDur = State.fertDuration(tt.key, lvl + 1)
    local cost = State.fertUpgradeCost(tt.key)
    table.insert(lines, { c = {1,1,1}, t = def.name .. " upgrade" })
    table.insert(lines, { c = {0.8,0.85,0.9}, t = string.format("Duration: %ds -> %ds", curDur, nextDur) })
    if def.baseMagnitude then
      local curMag = State.fertMagnitude(tt.key, lvl)
      local nextMag = State.fertMagnitude(tt.key, lvl + 1)
      table.insert(lines, { c = {0.8,0.85,0.9}, t = string.format("Effect: x%.2f -> x%.2f", curMag, nextMag) })
    end
    local curBuy = State.fertBuyCost(tt.key)
    local nextBuy = math.floor(def.buyCost * (C.FERT_BUY_COST_EXP ^ lvl))
    table.insert(lines, { c = {0.85,0.75,0.5}, t = string.format("Buy cost: $%d -> $%d", curBuy, nextBuy) })
    table.insert(lines, { c = {1,0.9,0.4}, t = "Cost: $" .. cost })
  elseif tt.kind == "robotUp" then
    local r = tt.robot
    local lvl = r.level or 1
    local curSp = C.ROBOT_SPEED + (lvl - 1) * C.ROBOT_SPEED_PER_LEVEL
    local nextSp = C.ROBOT_SPEED + lvl * C.ROBOT_SPEED_PER_LEVEL
    local curWk = 1 + (lvl - 1) * C.ROBOT_WORK_MULT_PER_LEVEL
    local nextWk = 1 + lvl * C.ROBOT_WORK_MULT_PER_LEVEL
    local cost = State.robotUpgradeCost(r)
    table.insert(lines, { c = {1,1,1}, t = r.name .. " upgrade" })
    table.insert(lines, { c = {0.8,0.85,0.9}, t = string.format("Speed: %.2f -> %.2f", curSp, nextSp) })
    table.insert(lines, { c = {0.8,0.85,0.9}, t = string.format("Work rate: x%.3f -> x%.3f", curWk, nextWk) })
    table.insert(lines, { c = {1,0.9,0.4}, t = "Cost: $" .. cost })
  end

  if #lines == 0 then return end
  love.graphics.setFont(fontUI)
  local maxW = 0
  for _, ln in ipairs(lines) do
    local w = fontUI:getWidth(ln.t)
    if w > maxW then maxW = w end
  end
  local pad = 10
  local lineH = 20
  local panelW = maxW + pad * 2
  local panelH = #lines * lineH + pad * 2
  local px = hovered.x - panelW - 8
  if px < 4 then px = hovered.x + hovered.w + 8 end
  local py = hovered.y + hovered.h - panelH
  if py < 4 then py = 4 end
  love.graphics.setColor(0.05, 0.05, 0.08, 0.94)
  love.graphics.rectangle("fill", px, py, panelW, panelH, 6, 6)
  love.graphics.setColor(0.5, 0.5, 0.65, 1)
  love.graphics.rectangle("line", px, py, panelW, panelH, 6, 6)
  for i, ln in ipairs(lines) do
    love.graphics.setColor(ln.c[1], ln.c[2], ln.c[3], 1)
    love.graphics.print(ln.t, px + pad, py + pad + (i - 1) * lineH)
  end
end

function Farm.draw()
  love.graphics.setCanvas(gameCanvas)
  love.graphics.clear(0.08, 0.10, 0.08, 1)
  drawGrid()
  drawRobots()
  drawHud()
  drawPopups()
  drawCropTooltip()
  drawHudTooltip()
  Modals.draw()
  love.graphics.setCanvas()

  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(gameCanvas, State.gameOffsetX, State.gameOffsetY, 0, State.gameScale, State.gameScale)
end

local function pickHover(sx, sy)
  State.hoverTile = nil

  if sx < C.GRID_OX or sx > C.GRID_OX + C.GRID_W * C.TILE then return end
  if sy < C.GRID_OY or sy > C.GRID_OY + C.GRID_H * C.TILE then return end

  local tx, ty = State.screenToTile(sx, sy)
  if not tx then return end
  State.hoverTile = State.tileAt(tx, ty)
end

function Farm.mousemoved(x, y)
  local gx, gy = State.windowToGame(x, y)
  pickHover(gx, gy)
end

local function flashTile(tile, color)
  if tile then
    tile._flashUntil = State.time + 0.3
    tile._flashColor = color or { 1, 0.2, 0.2 }
    if not color then Sounds.play("error") end
  end
end

local function handleLMB(tile)
  if State.restrictMode then
    tile.restrict = not tile.restrict
    Sounds.play("click")
    return
  end
  if State.stickMode then
    if tile.state == "tilled" and State.sticks > 0 then
      State.sticks = State.sticks - 1
      tile.state = "stick"
      tile.crop = nil
      Sounds.play("plant")
      if State.sticks <= 0 then State.stickMode = false end
    else
      flashTile(tile)
    end
    return
  end
  if State.fertMode then
    local applyOK = (tile.state == "tilled" or tile.state == "growing" or tile.state == "ripe" or tile.state == "stick")
    if applyOK and (State.fertInventory[State.fertMode] or 0) > 0 then
      State.applyFert(tile, State.fertMode)
      Sounds.play("fert")
      if (State.fertInventory[State.fertMode] or 0) <= 0 then
        State.fertMode = nil
      end
    else
      flashTile(tile)
    end
    return
  end
  if State.digToggle then
    if tile.crop then
      State.addCrop(tile.crop.pheno.cropIndex, tile.crop.pheno.tier)
      tile.crop = nil
      tile.state = "tilled"
      Sounds.play("click")
      return
    end
    if tile.state == "stick" then
      State.sticks = State.sticks + 1
      tile.state = "tilled"
      Sounds.play("click")
      return
    end
    flashTile(tile)
    return
  end
  if tile.state == "ripe" then
    if require("farm.harvest").harvestTile(tile) then
      Sounds.play("harvest")
    end
    return
  end
  if tile.state == "tilled" then
    local cropIdx = State.selectedCropIdx
    local tier = State.selectedCropTier
    if cropIdx and tier and State.takeCrop(cropIdx, tier) then
      local genome = Genetics.baseGenome(cropIdx, tier)
      tile.crop = {
        genome = genome,
        pheno  = Genetics.phenotype(genome),
        growth = 0,
        water  = 1.0,
      }
      tile.state = "growing"
      if State.cropCount(cropIdx, tier) <= 0 then
        State.selectedCropIdx = nil
        State.selectedCropTier = nil
      end
      Sounds.play("plant")
      return
    end
  end
  flashTile(tile)
end

local function handleMMB(tile)
  local needed
  if tile.weed then
    needed = "Weed"
  elseif tile.state == "wild" then
    needed = "Till"
  elseif tile.state == "growing" and tile.crop and tile.crop.water < C.WATER_REFILL_GATE then
    needed = "Water"
  end
  if not needed then
    flashTile(tile); return
  end
  local best, bestDist
  for _, r in ipairs(State.robots) do
    local dx, dy = tile.x - r.px, tile.y - r.py
    local d = dx*dx + dy*dy
    if not bestDist or d < bestDist then
      bestDist = d; best = r
    end
  end
  if not best then
    flashTile(tile); return
  end
  for _, q in ipairs(best.queue) do
    if q == tile then
      flashTile(tile, { 0.3, 0.8, 1 })
      return
    end
  end
  best.queue[#best.queue + 1] = tile
  best.pingUntil = State.time + 0.5
  flashTile(tile, { 0.3, 0.8, 1 })
  Sounds.play("queue")
  if best.state ~= "idle" and not best.activeTask then
    best.state = "idle"
    best.idleTimer = 0
    best.workTile = nil
    best.workTimer = 0
  end
end

local function handleRMB(tile)
  if State.stickMode or State.fertMode or State.digToggle or State.restrictMode or State.selectedCropIdx then
    State.clearModes()
    return
  end
  handleMMB(tile)
end

function Farm.mousepressed(x, y, btn)
  x, y = State.windowToGame(x, y)
  if State.openModal then
    Modals.mousepressed(x, y, btn)
    return
  end

  if btn == 1 then
    for i = #hudButtons, 1, -1 do
      local b = hudButtons[i]
      local clipVp
      if b.opts.rowClip == "robots" then clipVp = robotViewport
      elseif b.opts.rowClip == "crops" then clipVp = cropViewport end
      if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h
         and (not clipVp or (y >= clipVp.y and y <= clipVp.y + clipVp.h)) then
        if not b.opts.disabled then
          Sounds.play(b.opts.sound or "click")
          b.onClick()
          if b.opts.holdRepeat then
            held = {
              onClick = b.onClick, x = b.x, y = b.y, w = b.w, h = b.h,
              nextFire = HOLD_INITIAL_DELAY, delay = HOLD_INITIAL_DELAY,
            }
          end
        end
        if State.openDropdown and not b.opts.popupItem and not b.opts.dropdownTrigger then
          State.openDropdown = nil
        end
        return
      end
    end
    if State.openDropdown then State.openDropdown = nil end
  end

  if x < C.GRID_OX or x > C.GRID_OX + C.GRID_W * C.TILE then return end
  if y < C.GRID_OY or y > C.GRID_OY + C.GRID_H * C.TILE then return end

  local tx, ty = State.screenToTile(x, y)
  if not tx then return end
  local tile = State.tileAt(tx, ty)
  if not tile then return end

  if tile.y > State.unlockedRows then
    if btn == 1 then
      if State.tryUnlockRow(tile.y) then
        Sounds.play("unlock")
      else
        flashTile(tile)
      end
    end
    return
  end

  if btn == 1 then
    handleLMB(tile)
  elseif btn == 2 then
    handleRMB(tile)
  elseif btn == 3 then
    handleMMB(tile)
  end
end

function Farm.wheelmoved(dx, dy)
  if State.openModal then
    Modals.wheelmoved(dx, dy)
    return
  end
  local mx, my = State.getMousePosition()
  local hudRight = C.HUD_X + C.HUD_W + 16
  if mx >= robotViewport.x and mx <= hudRight
     and my >= robotViewport.y and my <= robotViewport.y + robotViewport.h then
    State.robotScroll = math.max(0, math.min(robotScrollMax, State.robotScroll - dy * 50))
  elseif mx >= cropViewport.x and mx <= hudRight
     and my >= cropViewport.y and my <= cropViewport.y + cropViewport.h then
    State.cropScroll = math.max(0, math.min(cropScrollMax, State.cropScroll - dy * 42))
  end
end

function Farm.mousereleased(x, y, btn)
  if btn == 1 then held = nil end
end

function Farm.keypressed(k, s, r)
  if k == "escape" then
    if State.openModal then
      State.openModal = nil
    else
      love.event.quit()
    end
    return
  end
  if k == "b" then
    if State.openModal == "bestiary" then State.openModal = nil
    elseif not State.openModal then State.openModal = "bestiary" end
    return
  end
  if k == "f3" then
    State.debugPanel = not State.debugPanel
    return
  end
end

function Farm.keyreleased() end

return Farm
