local C = require("farm.constants")
local State = require("farm.state")
local Sim = require("farm.sim")
local Genetics = require("farm.genetics")
local Sounds = require("farm.sounds")
local Save = require("farm.save")
local FlexLove = require("flexlove.FlexLove")
local Modals = require("farm.modals")

local Farm = {}

local fontEmoji
local fontEmojiBig
local fontEmojiHuge
local fontUI
local fontUIBig
local fontUISmall

-- NotoColorEmoji is a CBDT bitmap font: FreeType only supports its native
-- strike size (109px). We load it once at 109 and scale via draw transforms.
local EMOJI_NATIVE = 109
local function loadFonts()
  local rawFont = love.graphics.newFont("assets/fonts/NotoColorEmoji.ttf", EMOJI_NATIVE)
  fontEmoji     = rawFont
  fontEmojiBig  = rawFont
  fontEmojiHuge = rawFont
  fontUI      = love.graphics.newFont(18)
  fontUIBig   = love.graphics.newFont(28)
  fontUISmall = love.graphics.newFont(12)
end

local hudButtons = {}
local seedViewport = { x = 0, y = 0, w = 0, h = 0 }
local seedScrollMax = 0
local robotViewport = { x = 0, y = 0, w = 0, h = 0 }
local robotScrollMax = 0

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
  if opts.seedBuy or opts.robotBuy or opts.stickLabel or opts.stickBuy
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

  hudBtn("save", hx + hw - BTN_H * 3 - 12, C.HUD_OY, BTN_H, BTN_H, "",
    function() Save.save() end,
    { saveIcon = true, sound = "buy" })

  hudBtn("bestiary", hx + hw - BTN_H * 4 - 18, C.HUD_OY, BTN_H, BTN_H, "",
    function()
      if State.openModal == "bestiary" then State.openModal = nil
      else State.openModal = "bestiary" end
    end,
    { bestiaryIcon = true, active = State.openModal == "bestiary" })

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
  robotViewport = { x = hx, y = robotsTop, w = hw - 60, h = robotViewportH }
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
    if rowY < robotsTop or rowY + BTN_H > robotsTop + robotViewportH then
      goto continue_robot
    end
    do
    local cursorX = hx

    hudBtn("robot_name_" .. i, cursorX, rowY, nameMaxW, BTN_H, r.name, function() end,
      { selected = true, nameLabel = true })
    cursorX = cursorX + nameMaxW + BTN_GAP

    local taskLabel = r.task or "Idle"
    local maxTaskW = 0
    for _, tn in ipairs(C.TASKS) do
      local w = btnW(tn)
      if w > maxTaskW then maxTaskW = w end
    end
    local tkW = math.max(maxTaskW, btnW(taskLabel))
    local ddKey = "task_" .. i
    hudBtn("robot_task_" .. i, cursorX, rowY, tkW, BTN_H, taskLabel,
      function()
        if State.openDropdown == ddKey then State.openDropdown = nil
        else State.openDropdown = ddKey end
      end,
      { active = (State.openDropdown == ddKey), dropdownTrigger = ddKey })
    if State.openDropdown == ddKey then
      pendingPopups[#pendingPopups + 1] = { robotIdx = i, robotRef = r, x = cursorX, y = rowY + BTN_H + 4, w = tkW }
    end
    cursorX = cursorX + tkW + BTN_GAP

    local upCost = State.robotUpgradeCost(r)
    local speedLabel = "Lv" .. (r.level or 1) .. " $" .. upCost
    local spW = btnW(speedLabel)
    hudBtn("robot_speed_" .. i, cursorX, rowY, spW, BTN_H, speedLabel,
      function() State.upgradeRobot(r) end,
      { disabled = State.money < upCost, sound = "buy", tooltip = { kind = "robotUp", robot = r } })
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
      { disabled = qCount <= 0, clearIcon = true })
    end
    ::continue_robot::
  end

  local seedTop = robotsTop + robotViewportH + 14
  local seedBottomLimit = buyY - 14
  local viewportH = math.max(60, seedBottomLimit - seedTop)
  seedViewport = { x = hx, y = seedTop, w = hw - 60, h = viewportH }
  local rowH = 36
  local contentH = #State.seeds * rowH
  local scrollMax = math.max(0, contentH - viewportH)
  if State.seedScroll > scrollMax then State.seedScroll = scrollMax end
  if State.seedScroll < 0 then State.seedScroll = 0 end
  seedScrollMax = scrollMax
  local sellBtnW = 76
  local selBtnW = (hw - 60) - sellBtnW - 4
  for i = 1, #State.seeds do
    local s = State.seeds[i]
    local rowY = seedTop + (i - 1) * rowH - State.seedScroll
    if rowY >= seedTop and rowY + 32 <= seedTop + viewportH then
      hudBtn("seed_" .. s.id, hx, rowY, selBtnW, 32,
        string.format("Yield=%s   Time=%s",
          s.pheno.yieldLabel, s.pheno.growLabel),
        function() State.toggleSeed(s.id) end,
        { selected = (State.selectedSeedId == s.id), emojiIndex = 2 })
      local sellVal = math.max(1, math.floor(s.pheno.yield * 0.1))
      hudBtn("sell_" .. s.id, hx + selBtnW + 4, rowY, sellBtnW, 32,
        "Sell $" .. sellVal,
        function() State.sellSeed(s.id) end,
        { sellLabel = true, sound = "sell" })
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
    local tW = btnW(tLabel, { seedBuy = 1 })
    hudBtn("buy_tomato", cursorX, cropsY, tW, BTN_H, tLabel,
      function()
        if canBuyTomato then
          State.money = State.money - tCost
          local g = require("farm.genetics").baseGenome(1, 1, 1)
          State.addSeed(g, "Tomato")
        end
      end,
      { disabled = not canBuyTomato, seedBuy = 1, sound = "buy" })
    cursorX = cursorX + tW + BTN_GAP

    local cCost = C.CROPS[2].buyCost
    local canBuyCarrot = State.money >= cCost
    local cLabel = "Buy $" .. cCost
    local cW = btnW(cLabel, { seedBuy = 2 })
    hudBtn("buy_carrot", cursorX, cropsY, cW, BTN_H, cLabel,
      function()
        if canBuyCarrot then
          State.money = State.money - cCost
          local g = require("farm.genetics").baseGenome(2, 1, 1)
          State.addSeed(g, "Carrot")
        end
      end,
      { disabled = not canBuyCarrot, seedBuy = 2, sound = "buy" })
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
    for ti, taskName in ipairs(C.TASKS) do
      hudBtn("task_pop_" .. pop.robotIdx .. "_" .. ti, pop.x, popY, pop.w, BTN_H, taskName,
        function()
          pop.robotRef.task = taskName
          pop.robotRef.state = "idle"
          pop.robotRef.idleTimer = 0
          State.openDropdown = nil
        end,
        { active = (pop.robotRef.task == taskName), popupItem = true })
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
  FlexLove.init({ baseScale = { width = 1920, height = 1080 } })
end

function Farm.shutdown()
  Save.save()
end

function Farm.update(dt)
  Sim.update(dt)
  State.tickPopups()
  rebuildHudButtons()
  Modals.syncTo(State.openModal)
  FlexLove.update(dt)
  autoSaveAccum = autoSaveAccum + dt
  if autoSaveAccum >= C.SAVE_INTERVAL then
    autoSaveAccum = 0
    Save.save()
  end
end

local function drawPopups()
  love.graphics.setFont(fontUIBig)
  for _, p in ipairs(State.popups) do
    local elapsed = State.time - p.startTime
    local t = elapsed / p.life
    if t < 1 then
      local y = p.y - 60 * t
      local alpha = 1 - t
      local w = fontUIBig:getWidth(p.text)
      love.graphics.setColor(0, 0, 0, 0.6 * alpha)
      love.graphics.print(p.text, p.x - w * 0.5 + 2, y + 2)
      love.graphics.setColor(1, 0.95, 0.4, alpha)
      love.graphics.print(p.text, p.x - w * 0.5, y)
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
  love.graphics.setColor(c[1], c[2], c[3], 1)
  local w = font:getWidth(glyph) * scale
  local h = font:getHeight() * scale
  love.graphics.print(glyph, cx - w * 0.5, cy - h * 0.5, 0, scale, scale)
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
    drawCenteredEmojiTinted(fontEmojiBig, C.LOCK_EMOJI, centerX, centerY - 14, 48 / EMOJI_NATIVE, C.LOCK_TINT)
    love.graphics.setFont(fontUIBig)
    local cost = State.rowUnlockCost(y) or 0
    local txt = "Unlock $" .. cost
    local affordable = State.money >= cost and y == State.unlockedRows + 1
    if affordable then
      love.graphics.setColor(1, 0.95, 0.45, 1)
    else
      love.graphics.setColor(0.6, 0.5, 0.3, 1)
    end
    local w = fontUIBig:getWidth(txt)
    love.graphics.print(txt, centerX - w * 0.5, centerY + 18)
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
    elseif t.state == "tilled" and State.selectedSeed() then
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
  local panelW, panelH = 180, 86
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
  love.graphics.print("Yield: ", px + 10, lineY)
  local yc = C.TIER_COLORS[ph.yieldTier] or { 1, 1, 1 }
  love.graphics.setColor(yc[1], yc[2], yc[3], 1)
  love.graphics.print(ph.yieldLabel .. " (" .. ph.yield .. ")", px + 10 + fontUI:getWidth("Yield: "), lineY)

  lineY = lineY + 20
  love.graphics.setColor(0.85, 0.85, 0.9, 1)
  love.graphics.print("Time: ", px + 10, lineY)
  local gc = C.TIER_COLORS[ph.growTimeTier] or { 1, 1, 1 }
  love.graphics.setColor(gc[1], gc[2], gc[3], 1)
  love.graphics.print(ph.growLabel .. " (" .. ph.growTime .. "s)", px + 10 + fontUI:getWidth("Time: "), lineY)

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
    local tUnder = State.tileAt(math.floor(r.px + 0.5), math.floor(r.py + 0.5))
    if tUnder then
      local br, bgc, bb = tileFill(tUnder)
      love.graphics.setColor(br, bgc, bb, 1)
      love.graphics.circle("fill", cx, cy, C.TILE * 0.30)
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
  love.graphics.print(string.format("t=%.1fs  seeds=%d  robots=%d/%d  weeds_in=%.0fs",
    State.time, #State.seeds, #State.robots, C.ROBOT_CAP, State.weedTimer),
    C.HUD_X, C.HUD_OY + 44)

  local mxh, myh = love.mouse.getPosition()
  for _, b in ipairs(hudButtons) do
    local hover = (not b.opts.disabled) and (not b.opts.nameLabel)
      and mxh >= b.x and mxh <= b.x + b.w
      and myh >= b.y and myh <= b.y + b.h
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
    if b.opts.emojiIndex then
      local seedId = tonumber((b.id:gsub("seed_", "")))
      local seed
      for _, s in ipairs(State.seeds) do if s.id == seedId then seed = s break end end
      if seed then
        drawCenteredEmojiTinted(fontEmojiBig, seed.pheno.emoji, b.x + 18, b.y + b.h * 0.5, 28 / EMOJI_NATIVE, seed.pheno.tint)
        love.graphics.setFont(fontUI)
        local tx = b.x + 44
        local ty = b.y + 8
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Yield=", tx, ty)
        tx = tx + fontUI:getWidth("Yield=")
        local yc = C.TIER_COLORS[seed.pheno.yieldTier] or { 1, 1, 1 }
        love.graphics.setColor(yc[1], yc[2], yc[3], 1)
        love.graphics.print(seed.pheno.yieldLabel, tx, ty)
        tx = tx + fontUI:getWidth(seed.pheno.yieldLabel)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("   Time=", tx, ty)
        tx = tx + fontUI:getWidth("   Time=")
        local gc = C.TIER_COLORS[seed.pheno.growTimeTier] or { 1, 1, 1 }
        love.graphics.setColor(gc[1], gc[2], gc[3], 1)
        love.graphics.print(seed.pheno.growLabel, tx, ty)
      end
    elseif b.opts.stickLabel then
      drawCenteredEmoji(fontEmojiBig, C.STICK_EMOJI, b.x + 18, b.y + b.h * 0.5, 28 / EMOJI_NATIVE)
      love.graphics.setFont(fontUI)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.print(b.label, b.x + 44, b.y + 10)
    elseif b.opts.seedBuy then
      local crop = C.CROPS[b.opts.seedBuy]
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
    else
      love.graphics.print(b.label, b.x + 10, b.y + 10)
    end
  end

  if seedScrollMax > 0 then
    local barX = seedViewport.x + seedViewport.w + 8
    local barY = seedViewport.y
    local barH = seedViewport.h
    love.graphics.setColor(0.15, 0.15, 0.18, 1)
    love.graphics.rectangle("fill", barX, barY, 5, barH, 2, 2)
    local thumbH = math.max(20, barH * (barH / (barH + seedScrollMax)))
    local thumbY = barY + (State.seedScroll / seedScrollMax) * (barH - thumbH)
    love.graphics.setColor(0.55, 0.55, 0.65, 1)
    love.graphics.rectangle("fill", barX, thumbY, 5, thumbH, 2, 2)
  end

  if robotScrollMax > 0 then
    local barX = robotViewport.x + robotViewport.w + 8
    local barY = robotViewport.y
    local barH = robotViewport.h
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
  love.graphics.print("LMB: harvest, plant selected seed, or use active action.", C.HUD_X, helpY)
  love.graphics.print("RMB: cancel mode.   MMB: queue nearest robot for tile.", C.HUD_X, helpY + 16)
  love.graphics.print("Action bar: stick / fert / shovel / restrict. Sticks breed adj ripe.", C.HUD_X, helpY + 32)

end

local function drawHudTooltip()
  local mx, my = love.mouse.getPosition()
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
  love.graphics.clear(0.08, 0.10, 0.08, 1)
  drawGrid()
  drawRobots()
  drawPopups()
  drawHud()
  drawCropTooltip()
  drawHudTooltip()
  FlexLove.draw()
  Modals.drawEmojiOverlay(fontEmoji, EMOJI_NATIVE)
end

local function pickHover(sx, sy)
  State.hoverTile = nil

  if sx < C.GRID_OX or sx > C.GRID_OX + C.GRID_W * C.TILE then return end
  if sy < C.GRID_OY or sy > C.GRID_OY + C.GRID_H * C.TILE then return end

  local tx, ty = State.screenToTile(sx, sy)
  if not tx then return end
  State.hoverTile = State.tileAt(tx, ty)
end

function Farm.mousemoved(x, y) pickHover(x, y) end

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
      State.addSeed(Genetics.cloneGenome(tile.crop.genome), tile.crop.pheno.name)
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
    local seed = State.selectedSeed()
    if seed then
      local idx
      for i, s in ipairs(State.seeds) do
        if s.id == seed.id then idx = i; break end
      end
      tile.crop = {
        genome = seed.genome,
        pheno  = Genetics.phenotype(seed.genome),
        growth = 0,
        water  = 1.0,
      }
      tile.state = "growing"
      State.removeSeed(seed.id)
      if idx and #State.seeds > 0 then
        local nextIdx = math.min(idx, #State.seeds)
        State.selectedSeedId = State.seeds[nextIdx].id
      else
        State.selectedSeedId = nil
      end
      Sounds.play("plant")
      return
    end
  end
  flashTile(tile)
end

local function handleRMB(tile)
  if State.stickMode or State.fertMode or State.digToggle then
    State.clearModes()
    return
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

function Farm.mousepressed(x, y, btn)
  if State.openModal then return end

  if btn == 1 then
    for i = #hudButtons, 1, -1 do
      local b = hudButtons[i]
      if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
        if not b.opts.disabled then
          Sounds.play(b.opts.sound or "click")
          b.onClick()
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
    FlexLove.wheelmoved(dx, dy)
    return
  end
  local mx, my = love.mouse.getPosition()
  if mx >= robotViewport.x and mx <= robotViewport.x + robotViewport.w + 16
     and my >= robotViewport.y and my <= robotViewport.y + robotViewport.h then
    State.robotScroll = math.max(0, math.min(robotScrollMax, State.robotScroll - dy * 50))
  elseif mx >= seedViewport.x and mx <= seedViewport.x + seedViewport.w + 16
     and my >= seedViewport.y and my <= seedViewport.y + seedViewport.h then
    State.seedScroll = math.max(0, math.min(seedScrollMax, State.seedScroll - dy * 36))
  end
end

function Farm.mousereleased() end

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
  FlexLove.keypressed(k, s, r)
end

function Farm.keyreleased() end

return Farm
