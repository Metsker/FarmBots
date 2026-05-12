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
  State.money = 0
  State.time  = 0
  State.weedTimer = C.WEED_SPAWN_INTERVAL
  State.mode = "plant"
  State.hoverEdge = nil
  State.hoverTile = nil
  State.selectedSeedId = 1

  State.tiles = {}
  for y = 1, C.GRID_H do
    State.tiles[y] = {}
    for x = 1, C.GRID_W do
      State.tiles[y][x] = newTile(x, y)
    end
  end

  State.seeds = {}
  for _ = 1, 6 do
    local g = Genetics.baseGenome(1, 10, 30)
    State._nextSeedId = State._nextSeedId + 1
    State.seeds[#State.seeds + 1] = {
      id = State._nextSeedId, genome = g, pheno = Genetics.phenotype(g),
      label = "Tomato",
    }
  end

  State._usedNames = {}
  State.robots = {
    State.newRobot(C.GRID_W * 0.5,     C.GRID_H * 0.5, "Till"),
    State.newRobot(C.GRID_W * 0.5 + 1, C.GRID_H * 0.5, "Water"),
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

function State.newRobot(tx, ty, task)
  return {
    name = pickName(),
    px = tx, py = ty,
    targetTx = tx, targetTy = ty,
    task = task or "Idle",
    state = "idle",
    workTimer = 0,
    workTile = nil,
    speed = C.ROBOT_SPEED,
    upgraded = false,
  }
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

function State.selectedSeed()
  if #State.seeds == 0 then return nil end
  for _, s in ipairs(State.seeds) do
    if s.id == State.selectedSeedId then return s end
  end
  State.selectedSeedId = State.seeds[1].id
  return State.seeds[1]
end

function State.nextRobotCost()
  local n = #State.robots
  return math.floor(C.ROBOT_BASE_COST * (C.ROBOT_COST_EXP ^ (n - 1)))
end

return State
