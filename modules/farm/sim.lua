local C = require("farm.constants")
local State = require("farm.state")
local Genetics = require("farm.genetics")

local Sim = {}

local function findRobotJob(robot)
  local task = robot.task
  if task == "Idle" then return nil end

  local claimed = {}
  for _, r in ipairs(State.robots) do
    if r ~= robot and r.workTile and (r.state == "moving" or r.state == "working") then
      claimed[r.workTile] = true
    end
  end

  local best
  local bestDist
  for y = 1, C.GRID_H do
    for x = 1, C.GRID_W do
      local t = State.tiles[y][x]
      local match = false
      if task == "Till" then
        match = (t.state == "wild")
      elseif task == "Water" then
        match = (t.state == "growing" and t.crop and t.crop.water < C.WATER_REFILL_GATE)
      elseif task == "Weed" then
        match = (t.weed and t.state == "wild")
      end
      if match and not claimed[t] then
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

local function pickClosestEmpty(robot)
  local best
  local bestDist
  for y = 1, C.GRID_H do
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

local function performWork(robot, tile)
  local task = robot.task
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
  end
end

local function updateRobot(robot, dt)
  if robot.state == "idle" then
    robot.idleTimer = (robot.idleTimer or 0) - dt
    if robot.idleTimer > 0 then return end

    local tile = findRobotJob(robot)
    if tile then
      robot.workTile = tile
      robot.targetTx = tile.x
      robot.targetTy = tile.y
      robot.state = "moving"
    else
      local rest, restDist = pickClosestEmpty(robot)
      if rest and restDist and restDist > 0.01 then
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
        robot.workTimer = C.WORK_TIME[robot.task] or 1.0
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
      if robot.workTile then performWork(robot, robot.workTile) end
      robot.workTile = nil
      robot.state = "idle"
      robot.idleTimer = 0.1
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

local NEIGHBOR_OFFSETS = { {1,0}, {-1,0}, {0,1}, {0,-1} }

local function tickBreeding()
  for y = 1, C.GRID_H do
    for x = 1, C.GRID_W do
      local t = State.tiles[y][x]
      if t.state == "stick" then
        local ripeNeighbors = {}
        for _, off in ipairs(NEIGHBOR_OFFSETS) do
          local n = State.tileAt(x + off[1], y + off[2])
          if n and n.state == "ripe" and n.crop then
            ripeNeighbors[#ripeNeighbors + 1] = n
          end
        end
        if #ripeNeighbors >= 2 then
          local a = ripeNeighbors[love.math.random(1, #ripeNeighbors)]
          local b
          repeat
            b = ripeNeighbors[love.math.random(1, #ripeNeighbors)]
          until b ~= a
          local genome = Genetics.cross(a.crop.genome, b.crop.genome)
          local pheno = Genetics.phenotype(genome)
          t.crop = { genome = genome, pheno = pheno, growth = 0, water = 1.0 }
          t.state = "growing"
        end
      end
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
  tickBreeding()
end

return Sim
