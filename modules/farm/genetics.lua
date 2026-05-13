local C = require("farm.constants")

local Genetics = {}

local TIER_MAX = #C.TIER_NAMES

local function pairKey(a, b)
  if a <= b then return a .. "+" .. b end
  return b .. "+" .. a
end

local function pickColor(a, b)
  local recipe = C.RECIPE_LOOKUP[pairKey(a, b)]
  if recipe and love.math.random() < recipe.chance then
    local State = require("farm.state")
    State.recordDiscovery(recipe.recipeIdx)
    return recipe.result
  end
  if love.math.random() < 0.5 then return a end
  return b
end

local function rollImprove(currentTier)
  if love.math.random() < 0.5 then
    return math.min(TIER_MAX, currentTier + 1)
  end
  return currentTier
end

function Genetics.cloneGenome(g)
  return {
    color = g.color,
    yieldTier = g.yieldTier,
    growTimeTier = g.growTimeTier,
  }
end

function Genetics.baseGenome(cropIndex, yieldTier, growTimeTier)
  return {
    color = cropIndex,
    yieldTier = yieldTier or 1,
    growTimeTier = growTimeTier or 1,
  }
end

function Genetics.phenotype(g)
  local cropInfo = C.CROPS[g.color]
  local mult = cropInfo.yieldMult or 1
  return {
    yieldTier    = g.yieldTier,
    growTimeTier = g.growTimeTier,
    yield        = math.floor(C.YIELD_TIER_VALUES[g.yieldTier] * mult),
    growTime     = C.GROWTIME_TIER_VALUES[g.growTimeTier],
    cropIndex    = g.color,
    name         = cropInfo.name,
    emoji        = cropInfo.emoji,
    tint         = cropInfo.color or { 1, 1, 1 },
    yieldLabel   = C.TIER_NAMES[g.yieldTier],
    growLabel    = C.TIER_NAMES[g.growTimeTier],
  }
end

function Genetics.cross(parentA, parentB)
  return {
    yieldTier    = rollImprove(math.max(parentA.yieldTier,    parentB.yieldTier)),
    growTimeTier = rollImprove(math.max(parentA.growTimeTier, parentB.growTimeTier)),
    color        = pickColor(parentA.color, parentB.color),
  }
end

return Genetics
