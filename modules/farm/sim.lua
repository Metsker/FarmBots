local C = require("farm.constants")
local State = require("farm.state")
local Genetics = require("farm.genetics")

local Sim = {}

local function findRobotJob(robot)
  local task = robot.task
  if task == "Idle" then return nil end

  local best
  local bestDist
  for y = 1, C.GRID_H do
    for x = 1, C.GRID_W do
      local t = State.tiles[y][x]
      local match = false
      if task == "Till" then
        match = (t.state == "wild")
      elseif task == "Plant" then
        match = (t.state == "tilled" and State.selectedSeed() ~= nil)
      elseif task == "Water" then
        match = (t.state == "growing" and t.crop and t.crop.water < C.WATER_REFILL_GATE)
      elseif task == "Harvest" then
        match = (t.state == "ripe")
      elseif task == "Weed" then
        match = (t.weed and t.state == "wild")
      end
      if match then
        local dx, dy = x - robot.px, y - robot.py
        local d = dx*dx + dy*dy
        if not bestDist or d < bestDist then
          bestDist = d
          best = t
        end
      end
    end
  end
  return best
end

local function performWork(robot, tile)
  local task = robot.task
  if task == "Till" then
    if tile.state == "wild" then
      tile.state = "tilled"
      tile.weed = false
    end
  elseif task == "Plant" then
    if tile.state == "tilled" then
      local seed = State.selectedSeed()
      if seed then
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
  elseif task == "Water" then
    if tile.state == "growing" and tile.crop then
      tile.crop.water = 1.0
    end
  elseif task == "Harvest" then
    if tile.state == "ripe" and tile.crop then
      State.money = State.money + tile.crop.pheno.yield
      tile.crop.growth = 0
      tile.crop.water  = 1.0
      tile.state = "growing"
    end
  elseif task == "Weed" then
    tile.weed = false
  end
end

local function updateRobot(robot, dt)
  if robot.state == "idle" then
    local tile = findRobotJob(robot)
    if tile then
      robot.workTile = tile
      robot.targetTx = tile.x
      robot.targetTy = tile.y
      robot.state = "moving"
    end
  elseif robot.state == "moving" then
    local dx = robot.targetTx - robot.px
    local dy = robot.targetTy - robot.py
    local dist = math.sqrt(dx*dx + dy*dy)
    local step = robot.speed * dt
    if dist <= step then
      robot.px = robot.targetTx
      robot.py = robot.targetTy
      robot.state = "working"
      robot.workTimer = C.WORK_TIME[robot.task] or 1.0
    else
      robot.px = robot.px + dx / dist * step
      robot.py = robot.py + dy / dist * step
    end
  elseif robot.state == "working" then
    robot.workTimer = robot.workTimer - dt
    if robot.workTimer <= 0 then
      if robot.workTile then performWork(robot, robot.workTile) end
      robot.workTile = nil
      robot.state = "idle"
    end
  end
end

local function tickCrops(dt)
  for y = 1, C.GRID_H do
    for x = 1, C.GRID_W do
      local t = State.tiles[y][x]
      if t.state == "growing" and t.crop then
        t.crop.water = math.max(0, t.crop.water - C.WATER_DRAIN_PER_SEC * dt)
        if t.crop.water >= C.WATER_GROW_GATE then
          t.crop.growth = t.crop.growth + dt / t.crop.pheno.growTime
          if t.crop.growth >= 1 then
            t.crop.growth = 1
            t.state = "ripe"
          end
        end
      end
    end
  end
end

local function tickWeeds(dt)
  State.weedTimer = State.weedTimer - dt
  if State.weedTimer <= 0 then
    State.weedTimer = C.WEED_SPAWN_INTERVAL
    local wild = {}
    for y = 1, C.GRID_H do
      for x = 1, C.GRID_W do
        local t = State.tiles[y][x]
        if t.state == "wild" and not t.weed then
          wild[#wild + 1] = t
        end
      end
    end
    if #wild > 0 then
      local t = wild[love.math.random(1, #wild)]
      t.weed = true
    end
  end
end

local function tickBreeding()
  for y = 1, C.GRID_H do
    for x = 1, C.GRID_W do
      local t = State.tiles[y][x]
      if t.stickE then
        local r = State.tileAt(x + 1, y)
        if t.state == "ripe" and r and r.state == "ripe" and t.crop and r.crop then
          local genome = Genetics.cross(t.crop.genome, r.crop.genome)
          local pheno = Genetics.phenotype(genome)
          State.addSeed(genome, pheno.name .. "×" .. (r.crop.pheno.name or ""))
          t.stickE = false
        end
      end
      if t.stickS then
        local b = State.tileAt(x, y + 1)
        if t.state == "ripe" and b and b.state == "ripe" and t.crop and b.crop then
          local genome = Genetics.cross(t.crop.genome, b.crop.genome)
          local pheno = Genetics.phenotype(genome)
          State.addSeed(genome, pheno.name .. "×" .. (b.crop.pheno.name or ""))
          t.stickS = false
        end
      end
    end
  end
end

local SIM_SPEED = 2

function Sim.update(dt)
  dt = dt * SIM_SPEED
  State.time = State.time + dt
  for _, r in ipairs(State.robots) do updateRobot(r, dt) end
  tickCrops(dt)
  tickWeeds(dt)
  tickBreeding()
end

return Sim
