local State = require("farm.state")
local Genetics = require("farm.genetics")

local Harvest = {}

function Harvest.harvestTile(tile)
  if not tile or tile.state ~= "ripe" or not tile.crop then return false end
  State.money = State.money + tile.crop.pheno.yield
  local drops = love.math.random(1, 2)
  for _ = 1, drops do
    State.addSeed(Genetics.cloneGenome(tile.crop.genome), tile.crop.pheno.name)
  end
  tile.crop = nil
  tile.state = "tilled"
  return true
end

return Harvest
