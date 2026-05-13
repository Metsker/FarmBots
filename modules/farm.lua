local C = require("farm.constants")
local State = require("farm.state")
local Sim = require("farm.sim")
local Genetics = require("farm.genetics")
local Sounds = require("farm.sounds")

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
  local hy = C.HUD_OY + 90

  hudBtn("mute", hx + hw - BTN_H, C.HUD_OY, BTN_H, BTN_H, "",
    function() Sounds.muted = not Sounds.muted end,
    { muteIcon = true, active = Sounds.muted })

  local robotRowH = 50
  for i, r in ipairs(State.robots) do
    local rowY = hy + (i - 1) * robotRowH
    local cursorX = hx

    local nameW = btnW(r.name, { nameLabel = true })
    hudBtn("robot_name_" .. i, cursorX, rowY, nameW, BTN_H, r.name, function() end,
      { selected = true, nameLabel = true })
    cursorX = cursorX + nameW + BTN_GAP

    for ti, taskName in ipairs(C.TASKS) do
      local cw = btnW(taskName)
      hudBtn("robot_t_" .. i .. "_" .. ti, cursorX, rowY, cw, BTN_H,
        taskName,
        function()
          r.task = taskName
          r.state = "idle"
          r.idleTimer = 0
        end,
        { active = (r.task == taskName) })
      cursorX = cursorX + cw + BTN_GAP
    end

    local speedLabel = r.upgraded and "Fast" or ("Speed $" .. C.ROBOT_UPGRADE_COST)
    local spW = btnW(speedLabel)
    hudBtn("robot_speed_" .. i, cursorX, rowY, spW, BTN_H, speedLabel,
      function()
        if not r.upgraded and State.money >= C.ROBOT_UPGRADE_COST then
          State.money = State.money - C.ROBOT_UPGRADE_COST
          r.speed = C.ROBOT_SPEED_UP
          r.upgraded = true
        end
      end,
      { disabled = r.upgraded, sound = "buy" })
  end

  local buyY = hy + (#State.robots) * 50 + 12
  local cursorX = hx

  local rcost = State.nextRobotCost()
  local canBuyRobot = State.money >= rcost and #State.robots < C.ROBOT_CAP
  local rLabel = "Buy $" .. rcost
  local rW = btnW(rLabel, { robotBuy = true })
  hudBtn("buy_robot", cursorX, buyY, rW, BTN_H, rLabel,
    function()
      if canBuyRobot then
        State.money = State.money - rcost
        State.robots[#State.robots + 1] = State.newRobot(C.GRID_W * 0.5, C.GRID_H * 0.5, "Till")
      end
    end,
    { disabled = not canBuyRobot, robotBuy = true, sound = "buy" })
  cursorX = cursorX + rW + BTN_GAP

  local tCost = C.CROPS[1].buyCost
  local canBuyTomato = State.money >= tCost
  local tLabel = "Buy $" .. tCost
  local tW = btnW(tLabel, { seedBuy = 1 })
  hudBtn("buy_tomato", cursorX, buyY, tW, BTN_H, tLabel,
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
  hudBtn("buy_carrot", cursorX, buyY, cW, BTN_H, cLabel,
    function()
      if canBuyCarrot then
        State.money = State.money - cCost
        local g = require("farm.genetics").baseGenome(2, 1, 1)
        State.addSeed(g, "Carrot")
      end
    end,
    { disabled = not canBuyCarrot, seedBuy = 2, sound = "buy" })

  local stickRowY = buyY + 56
  cursorX = hx
  local stickApplyLabel = "x" .. State.sticks
  local saW = btnW(stickApplyLabel, { stickApply = true })
  hudBtn("stick_apply", cursorX, stickRowY, saW, BTN_H, stickApplyLabel,
    function()
      if State.sticks > 0 then State.toggleStick() end
    end,
    { stickApply = true, active = State.stickMode, disabled = State.sticks <= 0 })
  cursorX = cursorX + saW + BTN_GAP

  local canBuyStick = State.money >= C.STICK_COST
  local sBuyLabel = "Buy $" .. C.STICK_COST
  local sBuyW = btnW(sBuyLabel, { stickBuy = true })
  hudBtn("buy_stick", cursorX, stickRowY, sBuyW, BTN_H, sBuyLabel,
    function()
      if canBuyStick then
        State.money = State.money - C.STICK_COST
        State.sticks = State.sticks + 1
      end
    end,
    { disabled = not canBuyStick, stickBuy = true, sound = "buy" })

  local fertRowsStartY = stickRowY + 56
  for i, key in ipairs(C.FERT_KEYS) do
    local def = C.FERTILIZERS[key]
    local rowY = fertRowsStartY + (i - 1) * 56
    local cur = hx
    local count = State.fertInventory[key] or 0

    local applyLabel = "x" .. count
    local applyW = btnW(applyLabel, { fertApply = key })
    hudBtn("fert_apply_" .. key, cur, rowY, applyW, BTN_H, applyLabel,
      function()
        if count > 0 then State.toggleFert(key) end
      end,
      { fertApply = key, active = (State.fertMode == key), disabled = count <= 0 })
    cur = cur + applyW + BTN_GAP

    local buyLabel = "Buy $" .. def.buyCost
    local buyW = btnW(buyLabel, { fertBuy = key })
    hudBtn("fert_buy_" .. key, cur, rowY, buyW, BTN_H, buyLabel,
      function() State.buyFert(key) end,
      { fertBuy = key, disabled = State.money < def.buyCost, sound = "buy" })
    cur = cur + buyW + BTN_GAP

    local upCost = State.fertUpgradeCost(key)
    local lvl = State.fertLevel[key] or 1
    local upLabel = "Lv" .. lvl .. " $" .. upCost
    local upW = btnW(upLabel)
    hudBtn("fert_up_" .. key, cur, rowY, upW, BTN_H, upLabel,
      function() State.upgradeFert(key) end,
      { disabled = State.money < upCost, sound = "buy" })
  end

  local digRowY = fertRowsStartY + #C.FERT_KEYS * 56
  local digW = BTN_H + 4
  hudBtn("mode_dig", hx, digRowY, digW, BTN_H, "",
    function() State.toggleDig() end,
    { active = State.digToggle, digIcon = true })

  local seedHeaderY = digRowY + 56
  local seedY = seedHeaderY + 30
  local viewportH = math.max(36, 1080 - 70 - seedY)
  seedViewport = { x = hx, y = seedY, w = hw - 60, h = viewportH }
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
    local rowY = seedY + (i - 1) * rowH - State.seedScroll
    if rowY >= seedY and rowY + 32 <= seedY + viewportH then
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
end

function Farm.start()
  loadFonts()
  Sounds.init()
  State.init()
end

function Farm.update(dt)
  Sim.update(dt)
  State.tickPopups()
  rebuildHudButtons()
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
        love.graphics.setColor(0.08, 0.07, 0.05, 1)
        love.graphics.rectangle("fill", sx + 2, sy + 2, C.TILE - 4, C.TILE - 4, 6, 6)
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
    elseif State.stickMode then
      if t.state == "tilled" then
        cr, cg, cb, ca = 0.95, 0.75, 0.40, 0.35
      else
        cr, cg, cb, ca = 0.7, 0.3, 0.3, 0.3
      end
    elseif State.fertMode then
      if t.state == "tilled" or t.state == "growing" or t.state == "ripe" then
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
      local total = C.WORK_TIME[r.activeTask or r.task] or 1
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
    local hover = (not b.opts.disabled)
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
      local def = C.FERTILIZERS[b.opts.fertApply or b.opts.fertBuy]
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

  local helpY = 1080 - 60
  love.graphics.setFont(fontUISmall)
  love.graphics.setColor(0.55, 0.55, 0.65, 1)
  love.graphics.print("LMB: plant seed / harvest ripe / pull weed.", C.HUD_X, helpY)
  love.graphics.print("RMB: place stick (tilled).  MMB: redirect nearest task-robot.", C.HUD_X, helpY + 16)
  love.graphics.print("Dig toggle: LMB digs, RMB cancels. Sticks breed when adj plant ripens.", C.HUD_X, helpY + 32)
end

function Farm.draw()
  love.graphics.clear(0.08, 0.10, 0.08, 1)
  drawGrid()
  drawRobots()
  drawPopups()
  drawHud()
  drawCropTooltip()
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
    local applyOK = (tile.state == "tilled" or tile.state == "growing" or tile.state == "ripe")
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
  if btn == 1 then
    for _, b in ipairs(hudButtons) do
      if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
        if not b.opts.disabled then
          Sounds.play(b.opts.sound or "click")
          b.onClick()
        end
        return
      end
    end
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

function Farm.wheelmoved(_, dy)
  local mx, my = love.mouse.getPosition()
  if mx >= seedViewport.x and mx <= seedViewport.x + seedViewport.w + 16
     and my >= seedViewport.y and my <= seedViewport.y + seedViewport.h then
    State.seedScroll = math.max(0, math.min(seedScrollMax, State.seedScroll - dy * 36))
  end
end

function Farm.mousereleased() end
function Farm.keypressed() end
function Farm.keyreleased() end

return Farm
