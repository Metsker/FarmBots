local C = require("farm.constants")
local State = require("farm.state")
local Genetics = require("farm.genetics")
local Sounds = require("farm.sounds")

local Sim = {}

local function tileMatchesAutonomousTask(robot, t, task)
  if task == "Till" then
    return t.state == "wild" and not t.weed
  elseif task == "Water" then
    return t.state == "growing" and t.crop and t.crop.water <= C.WATER_REFILL_GATE
  elseif task == "Weed" then
    return t.weed and true or false
  elseif task == "Harvest" then
    return t.state == "ripe"
  elseif task == "Plant" then
    if t.state ~= "tilled" or t.restrict or t.weed then return false end
    if not robot.plantCrop then return false end
    return State.firstAvailableTier(robot.plantCrop) ~= nil
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
      if tileMatchesAutonomousTask(robot, t, task) and not claimed[t] then
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

local function plantPayloadOnTile(tile, payload)
  tile.crop = {
    genome = payload.genome,
    pheno  = Genetics.phenotype(payload.genome),
    growth = 0,
    water  = 1.0,
  }
  tile.state = "growing"
end

local function performWork(robot, tile, qe)
  local task = (qe and qe.task) or robot.activeTask or robot.task
  if task == "Till" then
    if tile.state == "wild" and not tile.weed then
      tile.state = "tilled"
    end
  elseif task == "Water" then
    if tile.state == "growing" and tile.crop then
      tile.crop.water = 1.0
    end
  elseif task == "Weed" then
    tile.weed = false
  elseif task == "Harvest" then
    if tile.state == "ripe" and tile.crop then
      local ph = tile.crop.pheno
      State.addCrop(ph.cropIndex, ph.tier)
      local cx, cy = State.tileCenter(tile.x, tile.y)
      State.addCropPopup(cx, cy, ph.cropIndex, ph.tier)
      tile.crop = nil
      tile.state = "tilled"
    end
  elseif task == "Plant" then
    if tile.state == "tilled" and not tile.crop then
      if qe and qe.payload then
        plantPayloadOnTile(tile, qe.payload)
      elseif robot.plantCrop then
        local tier = State.firstAvailableTier(robot.plantCrop)
        if tier and State.takeCrop(robot.plantCrop, tier) then
          local genome = Genetics.baseGenome(robot.plantCrop, tier)
          plantPayloadOnTile(tile, { genome = genome })
        end
      end
    end
  elseif task == "PlaceStick" then
    if tile.state == "tilled" then
      tile.state = "stick"
      tile.crop = nil
    else
      State.sticks = State.sticks + 1
    end
  elseif task == "Fertilize" then
    if qe and qe.payload and qe.payload.key then
      local key = qe.payload.key
      local applyOK = (tile.state == "tilled" or tile.state == "growing"
                       or tile.state == "ripe" or tile.state == "stick")
      if applyOK then
        State.fertInventory[key] = (State.fertInventory[key] or 0) + 1
        State.applyFert(tile, key)
      else
        State.fertInventory[key] = (State.fertInventory[key] or 0) + 1
      end
    end
  elseif task == "Dig" then
    if tile.crop then
      State.addCrop(tile.crop.pheno.cropIndex, tile.crop.pheno.tier)
      tile.crop = nil
      tile.state = "tilled"
    elseif tile.state == "stick" then
      State.sticks = State.sticks + 1
      tile.state = "tilled"
    end
  elseif task == "Unlock" then
    if qe and qe.payload then
      State.unlockedRows = math.max(State.unlockedRows, tile.y)
    end
  elseif task == "Summon" then
    -- no-op; arrival is the payload
  end
end

local function startQueueEntry(robot, qe)
  robot.activeQE = qe
  robot.activeTask = qe.task
  robot.workTile = qe.tile
  robot.targetTx = qe.tile.x
  robot.targetTy = qe.tile.y
  robot.state = "moving"
end

local function updateRobot(robot, dt)
  if robot.state == "idle" then
    robot.idleTimer = (robot.idleTimer or 0) - dt
    if robot.idleTimer > 0 then return end

    while robot.queue and #robot.queue > 0 do
      local qe = robot.queue[1]
      if qe and qe.tile then
        startQueueEntry(robot, qe)
        return
      else
        table.remove(robot.queue, 1)
      end
    end

    local tile, matchedTask = findRobotJob(robot)
    if tile then
      robot.activeQE = nil
      robot.activeTask = matchedTask
      robot.workTile = tile
      robot.targetTx = tile.x
      robot.targetTy = tile.y
      robot.state = "moving"
    else
      local rest, restDist = pickClosestEmpty(robot)
      if rest and restDist and restDist > 0.01 then
        robot.activeQE = nil
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
        if robot.activeTask == "Summon" then
          robot.activeTask = nil
          robot.workTile = nil
          if robot.activeQE then
            robot.queue = robot.queue or {}
            for i, qe in ipairs(robot.queue) do
              if qe == robot.activeQE then table.remove(robot.queue, i); break end
            end
            robot.activeQE = nil
          end
          robot.state = "idle"
          robot.idleTimer = 0.05
        else
          robot.state = "working"
          local workMult = 1 + ((robot.level or 1) - 1) * C.ROBOT_WORK_MULT_PER_LEVEL
          robot.workTimer = (C.WORK_TIME[robot.activeTask or robot.task] or 1.0) / workMult
        end
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
        performWork(robot, robot.workTile, robot.activeQE)
        Sounds.play("work")
      end
      if robot.activeQE and robot.queue then
        for i, qe in ipairs(robot.queue) do
          if qe == robot.activeQE then table.remove(robot.queue, i); break end
        end
      end
      robot.activeQE = nil
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
