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
  local tier = g.tier
  local priceMult = cropInfo.priceMult or 1
  return {
    tier         = tier,
    price        = math.floor(C.BASE_PRICE * priceMult),
    growTime     = C.GROWTIME_TIER_VALUES[tier],
    cropIndex    = g.color,
    name         = cropInfo.name,
    emoji        = cropInfo.emoji,
    tint         = cropInfo.color or { 1, 1, 1 },
    tierLabel    = C.TIER_NAMES[tier],
  }
end

-- Roll the number of crops dropped on a harvest. Random per call.
-- `yieldMult` (per-crop scalar, default 1) multiplies the tier-rolled qty.
function Genetics.rollHarvestQty(cropIdx, tier)
  local dist = C.YIELD_TIER_DIST[tier]
  if not dist then return 1 end
  local roll = love.math.random()
  local base = 1
  for _, entry in ipairs(dist) do
    if roll <= entry[2] then
      base = entry[1]
      break
    end
  end
  local mult = (C.CROPS[cropIdx] and C.CROPS[cropIdx].yieldMult) or 1
  return base * mult
end

function Genetics.cross(parentA, parentB)
  local color = pickColor(parentA.color, parentB.color)
  local tier
  if color ~= parentA.color and color ~= parentB.color then
    tier = 1
  else
    tier = rollImprove(math.max(parentA.tier, parentB.tier))
  end
  return {
    tier  = tier,
    color = color,
  }
end

return Genetics
