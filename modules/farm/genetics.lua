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
    tier = g.tier,
  }
end

function Genetics.baseGenome(cropIndex, tier)
  return {
    color = cropIndex,
    tier = tier or 1,
  }
end

function Genetics.phenotype(g)
  local cropInfo = C.CROPS[g.color]
  local mult = cropInfo.yieldMult or 1
  local tier = g.tier
  return {
    tier         = tier,
    yield        = math.floor(C.YIELD_TIER_VALUES[tier] * mult),
    growTime     = C.GROWTIME_TIER_VALUES[tier],
    cropIndex    = g.color,
    name         = cropInfo.name,
    emoji        = cropInfo.emoji,
    tint         = cropInfo.color or { 1, 1, 1 },
    tierLabel    = C.TIER_NAMES[tier],
  }
end

function Genetics.cross(parentA, parentB)
  return {
    tier  = rollImprove(math.max(parentA.tier, parentB.tier)),
    color = pickColor(parentA.color, parentB.color),
  }
end

return Genetics
