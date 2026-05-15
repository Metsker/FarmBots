local C = require("farm.constants")

local State = {}

local function newTile(x, y)
  return {
    x = x, y = y,
    state = "wild",
    crop = nil,
    weed = false,
    growth = 0,
    water = 0,
  }
end

function State.init()
  State.money = 100
  State.sticks = 2
  State.digToggle = false
  State.time  = 0
  State.weedTimer = C.WEED_SPAWN_MAX_INTERVAL
  State.hoverEdge = nil
  State.hoverTile = nil
  State.selectedCropIdx = nil
  State.selectedCropTier = nil
  State.popups = {}
  State.unlockedRows = C.STARTING_ROWS
  State.cropScroll = 0
  State.robotScroll = 0
  State.fertInventory = {}
  State.fertLevel = {}
  for _, k in ipairs(C.FERT_KEYS) do
    State.fertInventory[k] = 0
    State.fertLevel[k] = 1
  end
  State.fertMode = nil
  State.stickMode = false
  State.restrictMode = false
  State.openDropdown = nil
  State.openModal = nil
  State.discovered = {}
  State.debugPanel = false
  State.debugRevealAll = false

  State.tiles = {}
  for y = 1, C.GRID_H do
    State.tiles[y] = {}
    for x = 1, C.GRID_W do
      State.tiles[y][x] = newTile(x, y)
    end
  end

  State.crops = {}
  State.boughtCrops = {}

  State._usedNames = {}
  State.robots = {
    State.newRobot(C.GRID_W * 0.5, 1, "Till"),
  }
end

local function pickName()
  local used = State._usedNames or {}
  local pool = {}
  for _, n in ipairs(C.ROBOT_NAMES) do
    if not used[n] then pool[#pool + 1] = n end
  end
  local pick
  if #pool > 0 then
    pick = pool[love.math.random(1, #pool)]
  else
    pick = C.ROBOT_NAMES[love.math.random(1, #C.ROBOT_NAMES)] .. tostring(love.math.random(2, 99))
  end
  used[pick] = true
  State._usedNames = used
  return pick
end

local function hsvToRgb(h, s, v)
  local i = math.floor(h * 6)
  local f = h * 6 - i
  local p = v * (1 - s)
  local q = v * (1 - f * s)
  local tt = v * (1 - (1 - f) * s)
  i = i % 6
  if i == 0 then return v, tt, p end
  if i == 1 then return q, v, p end
  if i == 2 then return p, v, tt end
  if i == 3 then return p, q, v end
  if i == 4 then return tt, p, v end
  return v, p, q
end

function State.newRobot(tx, ty, task)
  local cr, cg, cb = hsvToRgb(love.math.random(), 0.85 + love.math.random() * 0.15, 0.95)
  return {
    name = pickName(),
    px = tx, py = ty,
    targetTx = tx, targetTy = ty,
    task = task or "Till",
    task2 = nil,
    plantCrop = nil,
    state = "idle",
    workTimer = 0,
    workTile = nil,
    speed = C.ROBOT_SPEED,
    level = 1,
    color = { cr, cg, cb },
    queue = {},
    activeTask = nil,
    activeQE = nil,
  }
end

function State.robotUpgradeCost(robot)
  local lvl = robot.level or 1
  return math.floor(C.ROBOT_UPGRADE_BASE_COST * (C.ROBOT_UPGRADE_COST_EXP ^ (lvl - 1)))
end

function State.upgradeRobot(robot)
  local cost = State.robotUpgradeCost(robot)
  if State.money < cost then return false end
  State.money = State.money - cost
  robot.level = (robot.level or 1) + 1
  robot.speed = C.ROBOT_SPEED + (robot.level - 1) * C.ROBOT_SPEED_PER_LEVEL
  return true
end

function State.addPopup(x, y, text)
  State.popups[#State.popups + 1] = {
    x = x, y = y, text = text, startTime = State.time, life = 1.0,
  }
end

function State.addCropPopup(x, y, cropIdx, tier)
  local cropInfo = C.CROPS[cropIdx]
  State.popups[#State.popups + 1] = {
    kind = "crop",
    x = x, y = y,
    emoji = cropInfo.emoji,
    emojiTint = cropInfo.color,
    tier = tier,
    tierLabel = C.TIER_NAMES[tier],
    tierColor = C.TIER_COLORS[tier],
    startTime = State.time,
    life = 1.0,
  }
end

function State.tickPopups()
  local i = 1
  while i <= #State.popups do
    local p = State.popups[i]
    if State.time - p.startTime >= p.life then
      table.remove(State.popups, i)
    else
      i = i + 1
    end
  end
end

function State.tileAt(tx, ty)
  if tx < 1 or tx > C.GRID_W or ty < 1 or ty > C.GRID_H then return nil end
  return State.tiles[ty][tx]
end

function State.tileToScreen(tx, ty)
  return C.GRID_OX + (tx - 1) * C.TILE,
         C.GRID_OY + (ty - 1) * C.TILE
end

function State.tileCenter(tx, ty)
  local x, y = State.tileToScreen(tx, ty)
  return x + C.TILE * 0.5, y + C.TILE * 0.5
end

function State.screenToTile(sx, sy)
  local tx = math.floor((sx - C.GRID_OX) / C.TILE) + 1
  local ty = math.floor((sy - C.GRID_OY) / C.TILE) + 1
  if tx < 1 or tx > C.GRID_W or ty < 1 or ty > C.GRID_H then return nil end
  return tx, ty
end

State.gameScale, State.gameOffsetX, State.gameOffsetY = 1, 0, 0

function State.recomputeViewport()
  local sw, sh = love.graphics.getDimensions()
  State.gameScale = math.min(sw / 1920, sh / 1080)
  State.gameOffsetX = math.floor((sw - 1920 * State.gameScale) * 0.5)
  State.gameOffsetY = math.floor((sh - 1080 * State.gameScale) * 0.5)
end

function State.windowToGame(x, y)
  return (x - State.gameOffsetX) / State.gameScale,
         (y - State.gameOffsetY) / State.gameScale
end

function State.getMousePosition()
  return State.windowToGame(love.mouse.getPosition())
end

function State.nextRobotCost()
  local n = #State.robots
  return math.floor(C.ROBOT_BASE_COST * (C.ROBOT_COST_EXP ^ (n - 1)))
end

function State.rowUnlockCost(y)
  return C.ROW_UNLOCK_COSTS[y - C.STARTING_ROWS]
end

function State.fertDuration(key, level)
  local def = C.FERTILIZERS[key]
  level = level or State.fertLevel[key] or 1
  return def.baseDuration + (level - 1) * C.FERT_DURATION_PER_LEVEL
end

function State.fertMagnitude(key, level)
  local def = C.FERTILIZERS[key]
  if not def.baseMagnitude then return nil end
  level = level or State.fertLevel[key] or 1
  local mag = def.baseMagnitude + (level - 1) * def.magStep
  if def.magCap and mag > def.magCap then mag = def.magCap end
  return mag
end

function State.fertUpgradeCost(key)
  local lvl = State.fertLevel[key] or 1
  return math.floor(C.FERT_UPGRADE_BASE_COST * (C.FERT_UPGRADE_COST_EXP ^ (lvl - 1)))
end

function State.fertBuyCost(key)
  local def = C.FERTILIZERS[key]
  local lvl = State.fertLevel[key] or 1
  return math.floor(def.buyCost * (C.FERT_BUY_COST_EXP ^ (lvl - 1)))
end

function State.buyFert(key)
  local def = C.FERTILIZERS[key]
  if not def then return false end
  local cost = State.fertBuyCost(key)
  if State.money < cost then return false end
  State.money = State.money - cost
  State.fertInventory[key] = (State.fertInventory[key] or 0) + 1
  return true
end

function State.upgradeFert(key)
  local cost = State.fertUpgradeCost(key)
  if State.money < cost then return false end
  State.money = State.money - cost
  State.fertLevel[key] = (State.fertLevel[key] or 1) + 1
  return true
end

function State.applyFert(tile, key)
  if not tile or not key then return false end
  if (State.fertInventory[key] or 0) <= 0 then return false end
  local dur = State.fertDuration(key)
  tile.ferts = tile.ferts or {}
  local now = State.time
  local prev = tile.ferts[key]
  local base = (prev and prev > now) and prev or now
  tile.ferts[key] = base + dur
  State.fertInventory[key] = State.fertInventory[key] - 1
  return true
end

function State.tileHasFert(tile, key)
  if not tile or not tile.ferts then return false end
  local e = tile.ferts[key]
  return e and e > State.time
end

function State.clearModes()
  State.digToggle = false
  State.fertMode = nil
  State.stickMode = false
  State.restrictMode = false
  State.selectedCropIdx = nil
  State.selectedCropTier = nil
end

function State.toggleRestrict()
  if State.restrictMode then State.restrictMode = false
  else State.clearModes(); State.restrictMode = true end
end

function State.toggleCrop(cropIdx, tier)
  if State.selectedCropIdx == cropIdx and State.selectedCropTier == tier then
    State.selectedCropIdx = nil
    State.selectedCropTier = nil
  else
    State.clearModes()
    State.selectedCropIdx = cropIdx
    State.selectedCropTier = tier
  end
end

function State.advanceSelectionFrom(cropIdx, tier)
  local function stocked(c, t)
    local byTier = State.crops[c]
    return byTier and byTier[t] and byTier[t] > 0
  end
  local order = {}
  for c = 1, #C.CROPS do
    for t = #C.TIER_NAMES, 1, -1 do
      order[#order + 1] = { c, t }
    end
  end
  local pos
  for i, entry in ipairs(order) do
    if entry[1] == cropIdx and entry[2] == tier then pos = i; break end
  end
  if not pos then
    State.selectedCropIdx = nil
    State.selectedCropTier = nil
    return
  end
  for i = pos + 1, #order do
    if stocked(order[i][1], order[i][2]) then
      State.selectedCropIdx, State.selectedCropTier = order[i][1], order[i][2]
      return
    end
  end
  for i = pos - 1, 1, -1 do
    if stocked(order[i][1], order[i][2]) then
      State.selectedCropIdx, State.selectedCropTier = order[i][1], order[i][2]
      return
    end
  end
  State.selectedCropIdx = nil
  State.selectedCropTier = nil
end

function State.toggleDig()
  if State.digToggle then State.digToggle = false
  else State.clearModes(); State.digToggle = true end
end

function State.toggleFert(key)
  if State.fertMode == key then State.fertMode = nil
  else State.clearModes(); State.fertMode = key end
end

function State.toggleStick()
  if State.stickMode then State.stickMode = false
  else State.clearModes(); State.stickMode = true end
end

function State.recordDiscovery(recipeIdx)
  if not recipeIdx then return end
  State.discovered = State.discovered or {}
  State.discovered[recipeIdx] = (State.discovered[recipeIdx] or 0) + 1
end

function State.addCrop(cropIdx, tier)
  local byCrop = State.crops[cropIdx]
  if not byCrop then
    byCrop = {}
    State.crops[cropIdx] = byCrop
  end
  byCrop[tier] = (byCrop[tier] or 0) + 1
end

function State.addBoughtCrop(cropIdx, tier)
  State.addCrop(cropIdx, tier)
  local bought = State.boughtCrops[cropIdx]
  if not bought then
    bought = {}
    State.boughtCrops[cropIdx] = bought
  end
  bought[tier] = (bought[tier] or 0) + 1
end

function State.boughtCount(cropIdx, tier)
  local byCrop = State.boughtCrops[cropIdx]
  if not byCrop then return 0 end
  return byCrop[tier] or 0
end

function State.sellableCount(cropIdx, tier)
  return State.cropCount(cropIdx, tier) - State.boughtCount(cropIdx, tier)
end

local function decBought(cropIdx, tier)
  local bought = State.boughtCrops[cropIdx]
  if not bought or (bought[tier] or 0) <= 0 then return end
  bought[tier] = bought[tier] - 1
  if bought[tier] <= 0 then bought[tier] = nil end
end

function State.cropCount(cropIdx, tier)
  local byCrop = State.crops[cropIdx]
  if not byCrop then return 0 end
  return byCrop[tier] or 0
end

function State.cropCountAtTier(cropIdx, minTier)
  local byCrop = State.crops[cropIdx]
  if not byCrop then return 0 end
  local total = 0
  for t, n in pairs(byCrop) do
    if t >= minTier then total = total + n end
  end
  return total
end

local function takeOneFrom(cropIdx, minTier)
  local byCrop = State.crops[cropIdx]
  if not byCrop then return false end
  local bestT
  for t, n in pairs(byCrop) do
    if t >= minTier and n > 0 then
      if not bestT or t < bestT then bestT = t end
    end
  end
  if not bestT then return false end
  byCrop[bestT] = byCrop[bestT] - 1
  if byCrop[bestT] <= 0 then byCrop[bestT] = nil end
  decBought(cropIdx, bestT)
  return true
end

function State.takeCrop(cropIdx, tier)
  local byCrop = State.crops[cropIdx]
  if not byCrop or (byCrop[tier] or 0) <= 0 then return false end
  byCrop[tier] = byCrop[tier] - 1
  if byCrop[tier] <= 0 then byCrop[tier] = nil end
  decBought(cropIdx, tier)
  return true
end

function State.sellOne(cropIdx, tier)
  if State.sellableCount(cropIdx, tier) <= 0 then return 0 end
  local byCrop = State.crops[cropIdx]
  local cropInfo = C.CROPS[cropIdx]
  local mult = cropInfo.yieldMult or 1
  local price = math.floor(C.YIELD_TIER_VALUES[tier] * mult)
  byCrop[tier] = byCrop[tier] - 1
  if byCrop[tier] <= 0 then byCrop[tier] = nil end
  State.money = State.money + price
  State.addPopup(C.HUD_X + 50, C.HUD_OY + 30, "+$" .. price)
  return price
end

function State.rowUnlockReqs(y)
  return C.ROW_UNLOCK_REQS and C.ROW_UNLOCK_REQS[y - C.STARTING_ROWS]
end

function State.canUnlockRow(y)
  if y <= State.unlockedRows then return false end
  if y ~= State.unlockedRows + 1 then return false end
  local cost = State.rowUnlockCost(y)
  if not cost or State.money < cost then return false end
  local reqs = State.rowUnlockReqs(y)
  if reqs then
    for _, r in ipairs(reqs) do
      if State.cropCountAtTier(r.crop, r.tier) < r.count then return false end
    end
  end
  return true
end

function State.tryUnlockRow(y)
  if not State.canUnlockRow(y) then return false end
  local cost = State.rowUnlockCost(y)
  State.money = State.money - cost
  local reqs = State.rowUnlockReqs(y)
  if reqs then
    for _, r in ipairs(reqs) do
      for _ = 1, r.count do takeOneFrom(r.crop, r.tier) end
    end
  end
  State.unlockedRows = y
  return true
end

local function takeLowestTierAtOrAbove(cropIdx, minTier)
  local byCrop = State.crops[cropIdx]
  if not byCrop then return nil end
  local bestT
  for t, n in pairs(byCrop) do
    if t >= minTier and n > 0 then
      if not bestT or t < bestT then bestT = t end
    end
  end
  if not bestT then return nil end
  byCrop[bestT] = byCrop[bestT] - 1
  if byCrop[bestT] <= 0 then byCrop[bestT] = nil end
  return bestT
end

function State.firstAvailableTier(cropIdx)
  local byCrop = State.crops[cropIdx]
  if not byCrop then return nil end
  local bestT
  for t, n in pairs(byCrop) do
    if n > 0 then
      if not bestT or t < bestT then bestT = t end
    end
  end
  return bestT
end

function State.reserveUnlock(y)
  local cost = State.rowUnlockCost(y) or 0
  if State.money < cost then return nil end
  local reqs = State.rowUnlockReqs(y)
  local taken = {}
  if reqs then
    for _, r in ipairs(reqs) do
      for _ = 1, r.count do
        local t = takeLowestTierAtOrAbove(r.crop, r.tier)
        if not t then
          for _, item in ipairs(taken) do
            State.addCrop(item.cropIdx, item.tier)
          end
          return nil
        end
        taken[#taken + 1] = { cropIdx = r.crop, tier = t }
      end
    end
  end
  State.money = State.money - cost
  return { cost = cost, taken = taken }
end

function State.findNearestRobot(tile)
  local best, bestDist
  for _, r in ipairs(State.robots) do
    local dx, dy = tile.x - r.px, tile.y - r.py
    local d = dx * dx + dy * dy
    if not bestDist or d < bestDist then
      bestDist = d
      best = r
    end
  end
  return best
end

function State.tileQueueRef(tile)
  if not tile then return nil end
  for _, r in ipairs(State.robots) do
    if r.activeQE and r.activeQE.tile == tile then
      return r, r.activeQE, true
    end
    if r.queue then
      for i, qe in ipairs(r.queue) do
        if qe.tile == tile then return r, qe, false end
      end
    end
  end
  return nil
end

local function refundQE(qe)
  if not qe then return end
  local task = qe.task
  local p = qe.payload
  if task == "Plant" and p then
    State.addCrop(p.cropIdx, p.tier)
  elseif task == "PlaceStick" then
    State.sticks = State.sticks + 1
  elseif task == "Fertilize" and p then
    State.fertInventory[p.key] = (State.fertInventory[p.key] or 0) + 1
  elseif task == "Unlock" and p then
    State.money = State.money + (p.cost or 0)
    if p.taken then
      for _, item in ipairs(p.taken) do
        State.addCrop(item.cropIdx, item.tier)
      end
    end
  end
end

function State.queueTask(tile, task, payload)
  local existingRobot, existingQE, isActive = State.tileQueueRef(tile)
  if existingRobot then
    if not isActive then
      for i, qe in ipairs(existingRobot.queue) do
        if qe == existingQE then
          table.remove(existingRobot.queue, i)
          table.insert(existingRobot.queue, 1, qe)
          if existingRobot.activeQE == nil
            and (existingRobot.state ~= "moving" and existingRobot.state ~= "working") then
            existingRobot.state = "idle"
            existingRobot.idleTimer = 0
          end
          return existingRobot, qe, "bumped"
        end
      end
    end
    return existingRobot, existingQE, "exists"
  end

  local robot = State.findNearestRobot(tile)
  if not robot then return nil end
  local qe = { tile = tile, task = task, payload = payload }
  robot.queue = robot.queue or {}
  if robot.activeQE == nil and (robot.state == "moving" or robot.state == "working") then
    robot.activeTask = nil
    robot.workTile = nil
    robot.workTimer = 0
    robot.state = "idle"
    robot.idleTimer = 0
    table.insert(robot.queue, 1, qe)
  else
    robot.queue[#robot.queue + 1] = qe
    if robot.state == "idle" then
      robot.idleTimer = 0
    end
  end
  robot.pingUntil = State.time + 0.5
  return robot, qe, "queued"
end

function State.clearRobotQueue(robot)
  if not robot then return end
  if robot.activeQE then
    refundQE(robot.activeQE)
    robot.activeQE = nil
    robot.activeTask = nil
    robot.workTile = nil
    robot.workTimer = 0
    robot.state = "idle"
    robot.idleTimer = 0
  end
  if robot.queue then
    for _, qe in ipairs(robot.queue) do
      refundQE(qe)
    end
  end
  robot.queue = {}
end

function State.cancelTileTask(tile)
  local robot, qe, isActive = State.tileQueueRef(tile)
  if not robot then return false end
  refundQE(qe)
  if isActive then
    robot.activeQE = nil
    robot.activeTask = nil
    robot.workTile = nil
    robot.workTimer = 0
    robot.state = "idle"
    robot.idleTimer = 0
  end
  if robot.queue then
    for i, e in ipairs(robot.queue) do
      if e == qe then table.remove(robot.queue, i); break end
    end
  end
  return true
end

return State
