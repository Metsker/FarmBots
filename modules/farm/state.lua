local C = require("farm.constants")
local Genetics = require("farm.genetics")

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

local function newSeed(genome, label)
  return {
    id = State and State._nextSeedId or 1,
    genome = genome,
    pheno = Genetics.phenotype(genome),
    label = label,
  }
end

function State.init()
  State._nextSeedId = 1
  State.money = 100
  State.sticks = 2
  State.digToggle = false
  State.time  = 0
  State.weedTimer = C.WEED_SPAWN_MAX_INTERVAL
  State.hoverEdge = nil
  State.hoverTile = nil
  State.selectedSeedId = nil
  State.popups = {}
  State.unlockedRows = C.STARTING_ROWS
  State.seedScroll = 0
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

  State.tiles = {}
  for y = 1, C.GRID_H do
    State.tiles[y] = {}
    for x = 1, C.GRID_W do
      State.tiles[y][x] = newTile(x, y)
    end
  end

  State.seeds = {}

  State._usedNames = {}
  State.robots = {
    State.newRobot(C.GRID_W * 0.5, C.GRID_H * 0.5, "Till"),
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
    state = "idle",
    workTimer = 0,
    workTile = nil,
    speed = C.ROBOT_SPEED,
    level = 1,
    color = { cr, cg, cb },
    queue = {},
    activeTask = nil,
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

function State.nextSeedCost()
  return math.floor(C.SEED_BASE_COST * (C.SEED_COST_EXP ^ (#State.seeds)))
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

function State.addSeed(genome, label)
  State._nextSeedId = State._nextSeedId + 1
  State.seeds[#State.seeds + 1] = {
    id = State._nextSeedId,
    genome = genome,
    pheno = Genetics.phenotype(genome),
    label = label,
  }
end

function State.removeSeed(id)
  for i, s in ipairs(State.seeds) do
    if s.id == id then table.remove(State.seeds, i) return s end
  end
  return nil
end

function State.sellSeed(id)
  for i, s in ipairs(State.seeds) do
    if s.id == id then
      local sellVal = math.max(1, math.floor(s.pheno.yield * 0.1))
      State.money = State.money + sellVal
      State.addPopup(C.HUD_X + 50, C.HUD_OY + 30, "+$" .. sellVal)
      table.remove(State.seeds, i)
      return sellVal
    end
  end
  return 0
end

function State.selectedSeed()
  if not State.selectedSeedId then return nil end
  for _, s in ipairs(State.seeds) do
    if s.id == State.selectedSeedId then return s end
  end
  return nil
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
  State.selectedSeedId = nil
end

function State.toggleRestrict()
  if State.restrictMode then State.restrictMode = false
  else State.clearModes(); State.restrictMode = true end
end

function State.toggleSeed(id)
  if State.selectedSeedId == id then State.selectedSeedId = nil
  else State.clearModes(); State.selectedSeedId = id end
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

function State.tryUnlockRow(y)
  if y <= State.unlockedRows then return false end
  if y ~= State.unlockedRows + 1 then return false end
  local cost = State.rowUnlockCost(y)
  if not cost or State.money < cost then return false end
  State.money = State.money - cost
  State.unlockedRows = y
  return true
end

return State
