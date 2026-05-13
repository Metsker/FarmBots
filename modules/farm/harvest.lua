local State = require("farm.state")
local Genetics = require("farm.genetics")

local Harvest = {}

function Harvest.harvestTile(tile)
  if not tile or tile.state ~= "ripe" or not tile.crop then return false end
  local gain = tile.crop.pheno.yield
  State.money = State.money + gain
  local cx, cy = State.tileCenter(tile.x, tile.y)
  State.addPopup(cx, cy, "+$" .. gain)
  State.addSeed(Genetics.cloneGenome(tile.crop.genome), tile.crop.pheno.name)
  tile.crop = nil
  tile.state = "tilled"
  return true
end

return Harvest
