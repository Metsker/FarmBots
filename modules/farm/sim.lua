local C = require("farm.constants")
local State = require("farm.state")
local Genetics = require("farm.genetics")
local Sounds = require("farm.sounds")

local Sim = {}

local function tileMatchesTask(t, task)
  if task == "Till" then return t.state == "wild"
  elseif task == "Water" then return t.state == "growing" and t.crop and t.crop.water <= C.WATER_REFILL_GATE
  elseif task == "Weed" then return t.weed and true or false
  elseif task == "Replant" then return t.state == "ripe" and not t.restrict
  end
  return false
end

local function findJobForTask(robot, task, claimed)
  if not task or task == "Idle" or task == "None" then return nil end
  local best
  local bestDist
  for y = 1, State.unlockedRows do
    for x = 1, C.GRID_W do
      local t = State.tiles[y][x]
      if tileMatchesTask(t, task) and not claimed[t] then
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

local function findRobotJob(robot)
  local claimed = {}
  for _, r in ipairs(State.robots) do
    if r ~= robot and r.workTile and (r.state == "moving" or r.state == "working") then
      claimed[r.workTile] = true
    end
  end
  local tile = findJobForTask(robot, robot.task, claimed)
  if tile then return tile, robot.task end
  tile = findJobForTask(robot, robot.task2, claimed)
  if tile then return tile, robot.task2 end
  return nil, nil
end

local function pickClosestEmpty(robot)
  local best
  local bestDist
  for y = 1, State.unlockedRows do
    for x = 1, C.GRID_W do
      local t = State.tiles[y][x]
      if t.state == "wild" or t.state == "tilled" then
        local dx, dy = x - robot.px, y - robot.py
        local d = dx*dx + dy*dy
        if not bestDist or d < bestDist then
          bestDist = d
          best = t
        end
      end
    end
  end
  return best, bestDist
end

local function neededTaskFor(tile)
  if not tile then return nil end
  if tile.weed then return "Weed" end
  if tile.state == "wild" then return "Till" end
  if tile.state == "growing" and tile.crop then return "Water" end
  if tile.state == "ripe" and not tile.restrict then return "Replant" end
  return nil
end

local function performWork(robot, tile)
  local task = robot.activeTask or robot.task
  if task == "Till" then
    if tile.state == "wild" then
      tile.state = "tilled"
      tile.weed = false
    end
  elseif task == "Water" then
    if tile.state == "growing" and tile.crop then
      tile.crop.water = 1.0
    end
  elseif task == "Weed" then
    tile.weed = false
  elseif task == "Replant" then
    if tile.state == "ripe" and tile.crop then
      local clonedGenome = Genetics.cloneGenome(tile.crop.genome)
      local pheno = tile.crop.pheno
      State.money = State.money + pheno.yield
      local cx, cy = State.tileCenter(tile.x, tile.y)
      State.addPopup(cx, cy, "+$" .. pheno.yield)
      tile.crop = {
        genome = clonedGenome,
        pheno  = Genetics.phenotype(clonedGenome),
        growth = 0,
        water  = 1.0,
      }
      tile.state = "growing"
    end
  end
end

local function updateRobot(robot, dt)
  if robot.state == "idle" then
    robot.idleTimer = (robot.idleTimer or 0) - dt
    if robot.idleTimer > 0 then return end

    while robot.queue and #robot.queue > 0 do
      local target = robot.queue[1]
      local task = neededTaskFor(target)
      if task then
        robot.activeTask = task
        robot.workTile = target
        robot.targetTx = target.x
        robot.targetTy = target.y
        robot.state = "moving"
        return
      else
        table.remove(robot.queue, 1)
      end
    end

    local tile, matchedTask = findRobotJob(robot)
    if tile then
      robot.activeTask = matchedTask
      robot.workTile = tile
      robot.targetTx = tile.x
      robot.targetTy = tile.y
      robot.state = "moving"
    else
      local rest, restDist = pickClosestEmpty(robot)
      if rest and restDist and restDist > 0.01 then
        robot.activeTask = nil
        robot.workTile = nil
        robot.targetTx = rest.x
        robot.targetTy = rest.y
        robot.state = "moving"
      else
        robot.idleTimer = 1.0
      end
    end
  elseif robot.state == "moving" then
    local dx = robot.targetTx - robot.px
    local dy = robot.targetTy - robot.py
    local dist = math.sqrt(dx*dx + dy*dy)
    local step = robot.speed * dt
    if dist <= step then
      robot.px = robot.targetTx
      robot.py = robot.targetTy
      if robot.workTile then
        robot.state = "working"
        local workMult = 1 + ((robot.level or 1) - 1) * C.ROBOT_WORK_MULT_PER_LEVEL
        robot.workTimer = (C.WORK_TIME[robot.activeTask or robot.task] or 1.0) / workMult
      else
        robot.state = "idle"
        robot.idleTimer = 1.0
      end
    else
      robot.px = robot.px + dx / dist * step
      robot.py = robot.py + dy / dist * step
    end
  elseif robot.state == "working" then
    robot.workTimer = robot.workTimer - dt
    if robot.workTimer <= 0 then
      if robot.workTile then
        performWork(robot, robot.workTile)
        Sounds.play("work")
      end
      if robot.activeTask and robot.queue and robot.queue[1] == robot.workTile then
        table.remove(robot.queue, 1)
      end
      robot.activeTask = nil
      robot.workTile = nil
      robot.state = "idle"
      robot.idleTimer = 0.1
    end
  end
end

local NEIGHBOR_OFFSETS = { {1,0}, {-1,0}, {0,1}, {0,-1} }

local function tryBreedAtRipen(ripeTile)
  for _, off in ipairs(NEIGHBOR_OFFSETS) do
    local stick = State.tileAt(ripeTile.x + off[1], ripeTile.y + off[2])
    if stick and stick.state == "stick" and not stick.weed then
      local mates = {}
      for _, off2 in ipairs(NEIGHBOR_OFFSETS) do
        local m = State.tileAt(stick.x + off2[1], stick.y + off2[2])
        if m and m ~= ripeTile and m.state == "ripe" and m.crop then
          mates[#mates + 1] = m
        end
      end
      if #mates > 0 then
        local mate = mates[love.math.random(1, #mates)]
        local genome = Genetics.cross(ripeTile.crop.genome, mate.crop.genome)
        local pheno = Genetics.phenotype(genome)
        stick.crop = { genome = genome, pheno = pheno, growth = 0, water = 1.0, hybrid = true }
        stick.state = "growing"
      end
    end
  end
end

local function tickCrops(dt)
  for y = 1, State.unlockedRows do
    for x = 1, C.GRID_W do
      local t = State.tiles[y][x]
      if t.state == "growing" and t.crop then
        if not State.tileHasFert(t, "autoWater") then
          t.crop.water = math.max(0, t.crop.water - C.WATER_DRAIN_PER_SEC * dt)
        end
        if t.crop.water >= C.WATER_GROW_GATE then
          local boost = 1
          if State.tileHasFert(t, "growBoost") then
            boost = State.fertMagnitude("growBoost") or 1
          end
          t.crop.growth = t.crop.growth + (dt * boost) / t.crop.pheno.growTime
          if t.crop.growth >= 1 then
            t.crop.growth = 1
            t.state = "ripe"
            Sounds.play("ripen")
            tryBreedAtRipen(t)
          end
        end
      end
    end
  end
end

local function rollWeedInterval()
  return C.WEED_SPAWN_MIN_INTERVAL + love.math.random() * (C.WEED_SPAWN_MAX_INTERVAL - C.WEED_SPAWN_MIN_INTERVAL)
end

local function tickWeeds(dt)
  State.weedTimer = State.weedTimer - dt
  if State.weedTimer <= 0 then
    State.weedTimer = rollWeedInterval()
    local eligible = {}
    for y = 1, State.unlockedRows do
      for x = 1, C.GRID_W do
        local t = State.tiles[y][x]
        if not t.weed
          and (t.state == "wild" or t.state == "tilled" or t.state == "stick")
          and not State.tileHasFert(t, "weedShield") then
          eligible[#eligible + 1] = t
        end
      end
    end
    local count = love.math.random(C.WEED_SPAWN_MIN, C.WEED_SPAWN_MAX)
    for _ = 1, count do
      if #eligible == 0 then break end
      local idx = love.math.random(1, #eligible)
      local t = eligible[idx]
      if t.state == "tilled" then
        t.state = "wild"
      end
      t.weed = true
      table.remove(eligible, idx)
    end
  end
end

local SIM_SPEED = 1

function Sim.update(dt)
  dt = dt * SIM_SPEED
  State.time = State.time + dt
  for _, r in ipairs(State.robots) do updateRobot(r, dt) end
  tickCrops(dt)
  tickWeeds(dt)
end

return Sim
