local C = require("farm.constants")
local State = require("farm.state")
local Sim = require("farm.sim")
local Genetics = require("farm.genetics")

local Farm = {}

local fontEmoji
local fontEmojiBig
local fontEmojiHuge
local fontUI
local fontUIBig

-- NotoColorEmoji is a CBDT bitmap font: FreeType only supports its native
-- strike size (109px). We load it once at 109 and scale via draw transforms.
local EMOJI_NATIVE = 109
local function loadFonts()
  local rawFont = love.graphics.newFont("assets/fonts/NotoColorEmoji.ttf", EMOJI_NATIVE)
  fontEmoji     = rawFont
  fontEmojiBig  = rawFont
  fontEmojiHuge = rawFont
  fontUI    = love.graphics.newFont(18)
  fontUIBig = love.graphics.newFont(28)
end

local hudButtons = {}

local function hudBtn(id, x, y, w, h, label, onClick, opts)
  hudButtons[#hudButtons + 1] = {
    id = id, x = x, y = y, w = w, h = h,
    label = label, onClick = onClick, opts = opts or {},
  }
end

local function rebuildHudButtons()
  hudButtons = {}
  local hx = C.HUD_X
  local hw = C.HUD_W
  local hy = C.HUD_OY + 90

  local robotRowH = 50
  for i, r in ipairs(State.robots) do
    local rowY = hy + (i - 1) * robotRowH

    hudBtn("robot_name_" .. i, hx, rowY, 80, 40, r.name, function() end,
      { selected = true, nameLabel = true })

    local chipX = hx + 86
    for ti, taskName in ipairs(C.TASKS) do
      local chipW = 62
      hudBtn("robot_t_" .. i .. "_" .. ti, chipX, rowY, chipW, 40,
        taskName,
        function()
          r.task = taskName
          r.state = "idle"
          r.idleTimer = 0
        end,
        { active = (r.task == taskName) })
      chipX = chipX + chipW + 4
    end

    hudBtn("robot_speed_" .. i, chipX + 4, rowY, 100, 40,
      r.upgraded and "Fast" or ("Speed $" .. C.ROBOT_UPGRADE_COST),
      function()
        if not r.upgraded and State.money >= C.ROBOT_UPGRADE_COST then
          State.money = State.money - C.ROBOT_UPGRADE_COST
          r.speed = C.ROBOT_SPEED_UP
          r.upgraded = true
        end
      end,
      { disabled = r.upgraded })
  end

  local buyY = hy + (#State.robots) * 50 + 12
  local rcost = State.nextRobotCost()
  local canBuyRobot = State.money >= rcost and #State.robots < C.ROBOT_CAP
  hudBtn("buy_robot", hx, buyY, 200, 40,
    canBuyRobot and ("Buy robot $" .. rcost) or ("Buy robot $" .. rcost),
    function()
      if canBuyRobot then
        State.money = State.money - rcost
        State.robots[#State.robots + 1] = State.newRobot(C.GRID_W * 0.5, C.GRID_H * 0.5, "Idle")
      end
    end,
    { disabled = not canBuyRobot })

  local scost = State.nextSeedCost()
  local canBuySeed = State.money >= scost
  hudBtn("buy_seed", hx + 210, buyY, 200, 40,
    canBuySeed and ("Buy tomato seed $" .. scost) or ("Buy tomato seed $" .. scost),
    function()
      if canBuySeed then
        State.money = State.money - scost
        local g = require("farm.genetics").baseGenome(1, 10, 30)
        State.addSeed(g, "Tomato")
      end
    end,
    { disabled = not canBuySeed })

  local modeY = buyY + 56
  hudBtn("mode_plant",   hx,         modeY, 120, 40, "Plant",   function() State.mode = "plant" end,   {active = State.mode=="plant"})
  hudBtn("mode_harvest", hx + 126,   modeY, 120, 40, "Harvest", function() State.mode = "harvest" end, {active = State.mode=="harvest"})
  hudBtn("mode_stick",   hx + 252,   modeY, 140, 40, "Stick $" .. C.STICK_COST, function() State.mode = "stick" end, {active = State.mode=="stick"})
  hudBtn("mode_delete",  hx + 398,   modeY, 120, 40, "Dig up",  function() State.mode = "delete" end,  {active = State.mode=="delete"})

  local seedHeaderY = modeY + 60
  local seedY = seedHeaderY + 30
  local visible = math.min(#State.seeds, 10)
  for i = 1, visible do
    local s = State.seeds[i]
    local rowY = seedY + (i - 1) * 36
    hudBtn("seed_" .. s.id, hx, rowY, hw - 60, 32,
      string.format("[%s]  y=%d  t=%.0fs  %s",
        s.pheno.emoji, s.pheno.yield, s.pheno.growTime, s.label or s.pheno.name),
      function() State.selectedSeedId = s.id end,
      { selected = (State.selectedSeedId == s.id), emojiIndex = 2 })
  end
end

function Farm.start()
  loadFonts()
  State.init()
end

function Farm.update(dt)
  Sim.update(dt)
  rebuildHudButtons()
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

local function drawGrid()
  for y = 1, C.GRID_H do
    for x = 1, C.GRID_W do
      local t = State.tiles[y][x]
      local sx, sy = State.tileToScreen(x, y)
      local r, g, b = tileFill(t)
      love.graphics.setColor(r, g, b, 1)
      love.graphics.rectangle("fill", sx + 2, sy + 2, C.TILE - 4, C.TILE - 4, 6, 6)

      if t.weed then
        drawCenteredEmoji(fontEmoji, C.WEED_EMOJI, sx + 24, sy + C.TILE - 24, 24 / EMOJI_NATIVE)
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

        drawCenteredEmoji(fontEmojiHuge, t.crop.pheno.emoji, cx, cy, (C.TILE * 0.6 / EMOJI_NATIVE) * growthScale)

        if t.state == "ripe" then
          local bob = math.sin(State.time * 6) * 4
          drawCenteredEmoji(fontEmoji, C.RIPE_GLYPH, sx + C.TILE - 18, sy + 18 + bob, 28 / EMOJI_NATIVE)
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
      end
    end
  end

  for y = 1, C.GRID_H do
    for x = 1, C.GRID_W do
      local t = State.tiles[y][x]
      if t.state == "stick" then
        local sx, sy = State.tileToScreen(x, y)
        local cx, cy = sx + C.TILE * 0.5, sy + C.TILE * 0.5
        drawCenteredEmoji(fontEmojiHuge, C.STICK_EMOJI, cx, cy, C.TILE * 0.75 / EMOJI_NATIVE)
      end
    end
  end

  if State.mode == "stick" and State.hoverTile then
    local sx, sy = State.tileToScreen(State.hoverTile.x, State.hoverTile.y)
    if State.hoverTile.state == "tilled" and State.money >= C.STICK_COST then
      love.graphics.setColor(0.85, 0.7, 0.3, 0.4)
    else
      love.graphics.setColor(0.7, 0.3, 0.3, 0.35)
    end
    love.graphics.rectangle("fill", sx + 2, sy + 2, C.TILE - 4, C.TILE - 4, 6, 6)
  elseif State.mode == "plant" and State.hoverTile then
    local sx, sy = State.tileToScreen(State.hoverTile.x, State.hoverTile.y)
    if State.hoverTile.state == "tilled" then
      love.graphics.setColor(0.4, 0.9, 0.4, 0.35)
    else
      love.graphics.setColor(0.7, 0.3, 0.3, 0.3)
    end
    love.graphics.rectangle("fill", sx + 2, sy + 2, C.TILE - 4, C.TILE - 4, 6, 6)
  elseif State.mode == "harvest" and State.hoverTile then
    local sx, sy = State.tileToScreen(State.hoverTile.x, State.hoverTile.y)
    if State.hoverTile.state == "ripe" then
      love.graphics.setColor(0.4, 0.9, 0.4, 0.4)
    else
      love.graphics.setColor(0.7, 0.3, 0.3, 0.3)
    end
    love.graphics.rectangle("fill", sx + 2, sy + 2, C.TILE - 4, C.TILE - 4, 6, 6)
  elseif State.mode == "delete" and State.hoverTile then
    local sx, sy = State.tileToScreen(State.hoverTile.x, State.hoverTile.y)
    love.graphics.setColor(1, 0.3, 0.3, 0.4)
    love.graphics.rectangle("fill", sx + 2, sy + 2, C.TILE - 4, C.TILE - 4, 6, 6)
  end
end

local function drawRobots()
  for _, r in ipairs(State.robots) do
    local cx = C.GRID_OX + (r.px - 0.5) * C.TILE
    local cy = C.GRID_OY + (r.py - 0.5) * C.TILE
    drawCenteredEmoji(fontEmojiBig, C.ROBOT_EMOJI, cx, cy, C.TILE * 0.55 / EMOJI_NATIVE)
    drawCenteredEmoji(fontEmoji, C.TASK_GLYPH[r.task] or "", cx + 24, cy + 22, 24 / EMOJI_NATIVE)

    love.graphics.setFont(fontUI)
    local nameW = fontUI:getWidth(r.name)
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", cx - nameW * 0.5 - 4, cy - C.TILE * 0.5 + 2, nameW + 8, 20, 4, 4)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(r.name, cx - nameW * 0.5, cy - C.TILE * 0.5 + 3)

    if r.state == "working" and r.workTimer > 0 then
      local total = C.WORK_TIME[r.task] or 1
      local p = 1 - (r.workTimer / total)
      love.graphics.setColor(0, 0, 0, 0.4)
      love.graphics.rectangle("fill", cx - (C.TILE - 24) * 0.5, cy + C.TILE * 0.5 - 10, C.TILE - 24, 5, 2, 2)
      love.graphics.setColor(0.4, 0.9, 1, 1)
      love.graphics.rectangle("fill", cx - (C.TILE - 24) * 0.5, cy + C.TILE * 0.5 - 10, (C.TILE - 24) * p, 5, 2, 2)
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

  for _, b in ipairs(hudButtons) do
    if b.opts.selected then
      love.graphics.setColor(0.35, 0.55, 0.35, 1)
    elseif b.opts.active then
      love.graphics.setColor(0.4, 0.4, 0.6, 1)
    elseif b.opts.disabled then
      love.graphics.setColor(0.2, 0.2, 0.2, 1)
    else
      love.graphics.setColor(0.22, 0.22, 0.28, 1)
    end
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 6, 6)
    love.graphics.setColor(0.5, 0.5, 0.6, 1)
    love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 6, 6)

    love.graphics.setFont(fontUI)
    love.graphics.setColor(1, 1, 1, 1)
    if b.opts.emojiIndex then
      local seedId = tonumber((b.id:gsub("seed_", "")))
      local seed
      for _, s in ipairs(State.seeds) do if s.id == seedId then seed = s break end end
      if seed then
        drawCenteredEmoji(fontEmojiBig, seed.pheno.emoji, b.x + 18, b.y + b.h * 0.5, 28 / EMOJI_NATIVE)
        love.graphics.setFont(fontUI)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(string.format("y=%d  t=%.0fs  %s",
          seed.pheno.yield, seed.pheno.growTime, seed.label or seed.pheno.name),
          b.x + 44, b.y + 8)
      end
    else
      love.graphics.print(b.label, b.x + 10, b.y + 10)
    end
  end

  local helpY = 1080 - 90
  love.graphics.setFont(fontUI)
  love.graphics.setColor(0.6, 0.6, 0.7, 1)
  love.graphics.print("Plant mode: click tilled tile to plant selected seed.", C.HUD_X, helpY)
  love.graphics.print("Stick mode: click tilled tile; 2+ ripe neighbors -> hybrid grows here.", C.HUD_X, helpY + 22)
  love.graphics.print("Dig mode: click any tile -> back to wild. Esc quits.",   C.HUD_X, helpY + 44)
end

function Farm.draw()
  love.graphics.clear(0.08, 0.10, 0.08, 1)
  drawGrid()
  drawRobots()
  drawHud()
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

function Farm.mousepressed(x, y, btn)
  if btn ~= 1 then return end
  for _, b in ipairs(hudButtons) do
    if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
      if not b.opts.disabled then b.onClick() end
      return
    end
  end

  if x < C.GRID_OX or x > C.GRID_OX + C.GRID_W * C.TILE then return end
  if y < C.GRID_OY or y > C.GRID_OY + C.GRID_H * C.TILE then return end

  local tx, ty = State.screenToTile(x, y)
  if not tx then return end
  local tile = State.tileAt(tx, ty)
  if State.mode == "stick" and tile then
    if tile.state == "tilled" and State.money >= C.STICK_COST then
      State.money = State.money - C.STICK_COST
      tile.state = "stick"
      tile.crop = nil
    end
  elseif State.mode == "delete" and tile then
    if tile.state ~= "wild" then
      tile.state = "wild"
      tile.crop = nil
    end
  elseif State.mode == "plant" and tile then
    if tile.state == "tilled" then
      local seed = State.selectedSeed()
      if seed then
        local Genetics = require("farm.genetics")
        tile.crop = {
          genome = seed.genome,
          pheno  = Genetics.phenotype(seed.genome),
          growth = 0,
          water  = 1.0,
        }
        tile.state = "growing"
        State.removeSeed(seed.id)
      end
    end
  elseif State.mode == "harvest" and tile then
    require("farm.harvest").harvestTile(tile)
  end
end

function Farm.mousereleased() end
function Farm.keypressed() end
function Farm.keyreleased() end

return Farm
