local State = require("farm.state")

local Harvest = {}

function Harvest.harvestTile(tile)
  if not tile or tile.state ~= "ripe" or not tile.crop then return false end
  local ph = tile.crop.pheno
  State.addCrop(ph.cropIndex, ph.tier)
  local cx, cy = State.tileCenter(tile.x, tile.y)
  State.addCropPopup(cx, cy, ph.cropIndex, ph.tier)
  tile.crop = nil
  tile.state = "tilled"
  return true
end

return Harvest
