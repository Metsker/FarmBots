local C = require("farm.constants")
local State = require("farm.state")
local Genetics = require("farm.genetics")

local Save = {}

local function serialize(v)
  local t = type(v)
  if t == "nil" then return "nil" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then return tostring(v) end
  if t == "string" then return string.format("%q", v) end
  if t == "table" then
    local parts = {}
    local arrayLike = true
    local idx = 1
    for k in pairs(v) do
      if k ~= idx then arrayLike = false; break end
      idx = idx + 1
    end
    if arrayLike then
      for _, val in ipairs(v) do
        parts[#parts + 1] = serialize(val)
      end
    else
      for k, val in pairs(v) do
        local keyStr
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then
          keyStr = k
        else
          keyStr = "[" .. serialize(k) .. "]"
        end
        parts[#parts + 1] = keyStr .. "=" .. serialize(val)
      end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "nil"
end

local function snapshotTiles()
  local out = {}
  for y = 1, C.GRID_H do
    out[y] = {}
    for x = 1, C.GRID_W do
      local t = State.tiles[y][x]
      local rec = { s = t.state }
      if t.weed then rec.w = true end
      if t.crop then
        rec.c = {
          g = t.crop.genome,
          gr = t.crop.growth,
          wa = t.crop.water,
          h = t.crop.hybrid and true or nil,
        }
      end
      if t.breederId then rec.b = t.breederId end
      if t.breederRole then rec.br = t.breederRole end
      if t.breederMiddle then rec.bm = true end
      if t.parentSlot then
        rec.ps = { crop = t.parentSlot.crop }
      end
      if t.ferts then
        local f = {}
        local any = false
        for k, e in pairs(t.ferts) do
          if e and e > State.time then
            f[k] = e - State.time
            any = true
          end
        end
        if any then rec.f = f end
      end
      out[y][x] = rec
    end
  end
  return out
end

local function snapshotBreeders()
  local out = {}
  for id, b in pairs(State.breeders or {}) do
    out[#out + 1] = {
      id = id,
      cost = b.cost or 0,
      leftX = b.leftX, leftY = b.leftY,
      midX = b.midX, midY = b.midY,
      rightX = b.rightX, rightY = b.rightY,
    }
  end
  return out
end

local function snapshotRobots()
  local out = {}
  for _, r in ipairs(State.robots) do
    local q = {}
    for _, qe in ipairs(r.queue or {}) do
      if qe.tile then
        q[#q + 1] = { x = qe.tile.x, y = qe.tile.y, task = qe.task, payload = qe.payload }
      end
    end
    out[#out + 1] = {
      name = r.name,
      px = r.px, py = r.py,
      task = r.task,
      task2 = r.task2,
      plantCrop = r.plantCrop,
      level = r.level or 1,
      speed = r.speed or C.ROBOT_SPEED,
      color = r.color,
      queue = q,
    }
  end
  return out
end

function Save.save()
  local data = {
    schema = C.SAVE_SCHEMA,
    money = State.money,
    time = State.time,
    weedTimer = State.weedTimer,
    unlockedRows = State.unlockedRows,
    _usedNames = State._usedNames,
    fertInventory = State.fertInventory,
    fertLevel = State.fertLevel,
    discovered = State.discovered,
    crops = State.crops,
    boughtCrops = State.boughtCrops,
    robots = snapshotRobots(),
    tiles = snapshotTiles(),
    breeders = snapshotBreeders(),
    nextBreederId = State.nextBreederId,
  }
  love.filesystem.write(C.SAVE_FILE, "return " .. serialize(data))
end

function Save.exists()
  return love.filesystem.getInfo(C.SAVE_FILE) ~= nil
end

function Save.load()
  if not Save.exists() then return false end
  local chunk, err = love.filesystem.load(C.SAVE_FILE)
  if not chunk then print("[save] load error: " .. tostring(err)); return false end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= "table" then print("[save] eval error"); return false end
  if data.schema ~= C.SAVE_SCHEMA then
    print(string.format("[save] schema mismatch (got %s, want %d) — starting fresh", tostring(data.schema), C.SAVE_SCHEMA))
    return false
  end

  State.money = data.money or 0
  State.time = data.time or 0
  State.weedTimer = data.weedTimer or C.WEED_SPAWN_MAX_INTERVAL
  State.unlockedRows = data.unlockedRows or C.STARTING_ROWS
  State._usedNames = data._usedNames or {}
  State.fertInventory = data.fertInventory or {}
  State.fertLevel = data.fertLevel or {}
  State.discovered = data.discovered or {}
  State.crops = data.crops or {}
  State.boughtCrops = data.boughtCrops or {}
  for _, k in ipairs(C.FERT_KEYS) do
    State.fertInventory[k] = State.fertInventory[k] or 0
    State.fertLevel[k] = State.fertLevel[k] or 1
  end

  for y = 1, C.GRID_H do
    for x = 1, C.GRID_W do
      local t = State.tiles[y][x]
      local rec = data.tiles and data.tiles[y] and data.tiles[y][x]
      if rec then
        t.state = rec.s or "wild"
        t.weed = rec.w == true
        if rec.c then
          t.crop = {
            genome = rec.c.g,
            pheno = Genetics.phenotype(rec.c.g),
            growth = rec.c.gr or 0,
            water = rec.c.wa or 1.0,
            hybrid = rec.c.h == true,
          }
        else
          t.crop = nil
        end
        if rec.b then t.breederId = rec.b end
        if rec.br then t.breederRole = rec.br end
        if rec.bm then t.breederMiddle = true end
        if rec.ps then
          t.parentSlot = { crop = rec.ps.crop }
        end
        if rec.f then
          local ferts = {}
          for k, remaining in pairs(rec.f) do
            ferts[k] = State.time + remaining
          end
          t.ferts = ferts
        else
          t.ferts = nil
        end
      end
    end
  end

  State.breeders = {}
  for _, b in ipairs(data.breeders or {}) do
    State.breeders[b.id] = {
      id = b.id,
      cost = b.cost or 0,
      leftX = b.leftX, leftY = b.leftY,
      midX = b.midX, midY = b.midY,
      rightX = b.rightX, rightY = b.rightY,
    }
  end
  State.nextBreederId = data.nextBreederId or 1

  State.robots = {}
  for _, rd in ipairs(data.robots or {}) do
    local r = State.newRobot(rd.px, rd.py, rd.task)
    r.name = rd.name or r.name
    r.px = rd.px
    r.py = rd.py
    r.targetTx = rd.px
    r.targetTy = rd.py
    r.task = rd.task or "Till"
    r.task2 = rd.task2
    r.plantCrop = rd.plantCrop
    r.level = rd.level or 1
    r.speed = rd.speed or C.ROBOT_SPEED
    r.color = rd.color or r.color
    r.queue = {}
    for _, qc in ipairs(rd.queue or {}) do
      local tile = State.tileAt(qc.x, qc.y)
      if tile and qc.task then
        r.queue[#r.queue + 1] = { tile = tile, task = qc.task, payload = qc.payload }
      end
    end
    r.state = "idle"
    r.idleTimer = 0
    r.activeTask = nil
    r.activeQE = nil
    r.workTile = nil
    r.workTimer = 0
    State.robots[#State.robots + 1] = r
  end

  State._usedNames = State._usedNames or {}
  for _, r in ipairs(State.robots) do
    State._usedNames[r.name] = true
  end

  return true
end

function Save.reset()
  if Save.exists() then love.filesystem.remove(C.SAVE_FILE) end
  State.init()
end

return Save
