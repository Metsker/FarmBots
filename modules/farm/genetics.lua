local C = require("farm.constants")

local Genetics = {}

local function pickAllele(pair)
  return pair[love.math.random(1, 2)]
end

local function mutate(value, kind)
  if kind == "yield" then
    return math.max(1, math.floor(value * (0.8 + love.math.random() * 0.4)))
  elseif kind == "growTime" then
    return math.max(8, math.floor(value * (0.8 + love.math.random() * 0.4)))
  elseif kind == "color" then
    return love.math.random(1, #C.CROPS)
  end
  return value
end

function Genetics.baseGenome(cropIndex, yield, growTime)
  return {
    yield    = { yield, yield },
    growTime = { growTime, growTime },
    color    = { cropIndex, cropIndex },
  }
end

function Genetics.phenotype(g)
  local y = (g.yield[1]    + g.yield[2])    * 0.5
  local t = (g.growTime[1] + g.growTime[2]) * 0.5
  local c = math.min(g.color[1], g.color[2])
  return {
    yield     = math.floor(y),
    growTime  = t,
    cropIndex = c,
    name      = C.CROPS[c].name,
    emoji     = C.CROPS[c].emoji,
  }
end

function Genetics.cross(parentA, parentB)
  local child = {
    yield    = { pickAllele(parentA.yield),    pickAllele(parentB.yield) },
    growTime = { pickAllele(parentA.growTime), pickAllele(parentB.growTime) },
    color    = { pickAllele(parentA.color),    pickAllele(parentB.color) },
  }
  if love.math.random() < C.MUTATION_RATE then
    local slot = love.math.random(1, 2)
    child.yield[slot] = mutate(child.yield[slot], "yield")
  end
  if love.math.random() < C.MUTATION_RATE then
    local slot = love.math.random(1, 2)
    child.growTime[slot] = mutate(child.growTime[slot], "growTime")
  end
  if love.math.random() < C.MUTATION_RATE then
    local slot = love.math.random(1, 2)
    child.color[slot] = mutate(child.color[slot], "color")
  end
  return child
end

return Genetics
