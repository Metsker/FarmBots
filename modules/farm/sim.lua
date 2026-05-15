local C = require("farm.constants")
local State = require("farm.state")
local Genetics = require("farm.genetics")
local Sounds = require("farm.sounds")

local Sim = {}

local function plantCropForTile(robot, t)
  -- Returns the cropIdx to plant on this tile, or nil if this robot
  -- shouldn't service it. Parent slots dictate their own crop; a robot
  -- with no plantCrop is a generalist that fills any configured slot.
  local slotCrop = t.parentSlot and t.parentSlot.crop
  if slotCrop then
    if robot.plantCrop and robot.plantCrop ~= slotCrop then return nil end
    return slotCrop
  end
  return robot.plantCrop
end

local function tileMatchesAutonomousTask(robot, t, task)
  if task == "Till" then
    return t.state == "wild" and not t.weed
  elseif task == "Water" then
    return t.state == "growing" and t.crop and t.crop.water <= C.WATER_REFILL_GATE
  elseif task == "Weed" then
    return t.weed and true or false
  elseif task == "Harvest" then
    if t.state ~= "ripe" then return false end
    if t.parentSlot then return false end
    return true
  elseif task == "Plant" then
    if t.state ~= "tilled" or t.weed then return false end
    local cropIdx = plantCropForTile(robot, t)
    if not cropIdx then return false end
    return State.firstAvailableTier(cropIdx) ~= nil
  end
  return false
end

local function findJobForTask(robot, task, claimed)
  if not task or task == "Idle" or task == "None" then return nil end
  local best
  local bestRank
  for y = 1, State.unlockedRows do
    for x = 1, C.GRID_W do
      local t = State.tiles[y][x]
      if tileMatchesAutonomousTask(robot, t, task) and not claimed[t] then
        local dx, dy = x - robot.px, y - robot.py
        local rank = dx*dx + dy*dy
        if task == "Plant" and t.parentSlot then
          rank = rank - 1e6
        end
        if not bestRank or rank < bestRank then
          bestRank = rank
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

local tryBreedAtStructure  -- forward decl, defined below

local function harvestTile(tile)
  if tile.state ~= "ripe" or not tile.crop then return end
  local ph = tile.crop.pheno
  local qty = Genetics.rollHarvestQty(ph.cropIndex, ph.tier)
  for _ = 1, qty do
    State.addCrop(ph.cropIndex, ph.tier)
  end
  local cx, cy = State.tileCenter(tile.x, tile.y)
  State.addCropPopup(cx, cy, ph.cropIndex, ph.tier)
  if qty > 1 then
    State.addPopup(cx, cy - 28, "x" .. qty)
  end
  tile.crop = nil
  if tile.breederMiddle then
    tile.state = "breeder"
  else
    tile.state = "tilled"
  end
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
    if tile.breederId then tryBreedAtStructure(tile.breederId) end
  elseif task == "Harvest" then
    if tile.parentSlot then return end
    harvestTile(tile)
  elseif task == "Plant" then
    if tile.state == "tilled" and not tile.crop then
      if qe and qe.payload then
        plantPayloadOnTile(tile, qe.payload)
      else
        local cropIdx = plantCropForTile(robot, tile)
        if cropIdx then
          local tier = State.firstAvailableTier(cropIdx)
          if tier and State.takeCrop(cropIdx, tier) then
            local genome = Genetics.baseGenome(cropIdx, tier)
            plantPayloadOnTile(tile, { genome = genome })
          end
        end
      end
    end
  elseif task == "PlaceBreeder" then
    if qe and qe.payload then
      local left = State.tileAt(qe.payload.leftX, qe.payload.leftY)
      local mid  = State.tileAt(qe.payload.midX,  qe.payload.midY)
      local right= State.tileAt(qe.payload.rightX,qe.payload.rightY)
      if left and mid and right
        and left.state == "tilled" and not left.weed and not left.breederId
        and mid.state  == "tilled" and not mid.weed  and not mid.breederId
        and right.state== "tilled" and not right.weed and not right.breederId then
        State.registerBreeder(left, mid, right)
      else
        State.money = State.money + (qe.payload.cost or 0)
      end
    end
  elseif task == "Fertilize" then
    if qe and qe.payload and qe.payload.key then
      local key = qe.payload.key
      local applyOK = (tile.state == "tilled" or tile.state == "growing"
                       or tile.state == "ripe" or tile.state == "breeder")
      if applyOK then
        State.fertInventory[key] = (State.fertInventory[key] or 0) + 1
        State.applyFert(tile, key)
      else
        State.fertInventory[key] = (State.fertInventory[key] or 0) + 1
      end
    end
  elseif task == "Dig" then
    if tile.breederId then
      State.removeBreeder(tile.breederId)
    elseif tile.crop then
      State.addCrop(tile.crop.pheno.cropIndex, tile.crop.pheno.tier)
      tile.crop = nil
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

tryBreedAtStructure = function(id)
  if not id then return end
  local left, mid, right = State.breederTiles(id)
  if not (left and mid and right) then return end
  if mid.state ~= "breeder" or mid.weed then return end
  if left.state ~= "ripe" or not left.crop then return end
  if right.state ~= "ripe" or not right.crop then return end
  local genome = Genetics.cross(left.crop.genome, right.crop.genome)
  local pheno = Genetics.phenotype(genome)
  mid.crop = { genome = genome, pheno = pheno, growth = 0, water = 1.0, hybrid = true }
  mid.state = "growing"
  left.crop = nil
  left.state = "tilled"
  right.crop = nil
  right.state = "tilled"
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
            if t.breederId then tryBreedAtStructure(t.breederId) end
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
          and (t.state == "wild" or t.state == "tilled" or t.state == "breeder")
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
