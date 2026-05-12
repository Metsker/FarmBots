local modulePath = (...):match("(.-)[^%.]+$")
local utils = require(modulePath .. "utils")
local enums = utils.enums

local Positioning = enums.Positioning
local AlignItems = enums.AlignItems

--- Simple grid layout calculations
local Grid = {}

--- Parse one track entry into { kind = "px"|"fr"|"%", value = n }.
--- Accepts: number → px; string "44", "44px", "0.4fr", "50%".
---@param entry number|string
---@return table
local function parseTrack(entry)
  if type(entry) == "number" then
    return { kind = "px", value = entry }
  end
  if type(entry) == "string" then
    local numStr, unit = entry:match("^%s*([%-]?[%d%.]+)%s*(.-)%s*$")
    local n = tonumber(numStr)
    if not n then
      return { kind = "px", value = 0 }
    end
    if unit == "" or unit == "px" then
      return { kind = "px", value = n }
    elseif unit == "fr" then
      return { kind = "fr", value = n }
    elseif unit == "%" then
      return { kind = "%", value = n }
    end
  end
  return { kind = "px", value = 0 }
end

--- Resolve an array of track entries into concrete pixel sizes.
--- Algorithm: subtract gaps + fixed (px) + percentage from `available`,
--- distribute the remainder across `fr` tracks proportional to their values.
---@param tracks table Array of number|string entries
---@param available number Container content-axis size in px
---@param gap number Gap between adjacent tracks
---@return table Array of resolved sizes (px), same length as `tracks`
local function resolveTracks(tracks, available, gap)
  local n = #tracks
  if n == 0 then
    return {}
  end
  local fixed, frUnits = 0, 0
  local parsed = {}
  for i, t in ipairs(tracks) do
    local pt = parseTrack(t)
    parsed[i] = pt
    if pt.kind == "px" then
      fixed = fixed + pt.value
    elseif pt.kind == "%" then
      fixed = fixed + (pt.value / 100) * available
    elseif pt.kind == "fr" then
      frUnits = frUnits + pt.value
    end
  end
  local frSpace = math.max(0, available - (n - 1) * gap - fixed)
  local perFr = (frUnits > 0) and (frSpace / frUnits) or 0
  local sizes = {}
  for i, pt in ipairs(parsed) do
    if pt.kind == "fr" then
      sizes[i] = pt.value * perFr
    elseif pt.kind == "%" then
      sizes[i] = (pt.value / 100) * available
    else
      sizes[i] = pt.value
    end
  end
  return sizes
end

--- Layout grid items within a grid container.
--- Track sizing: if `gridTemplateColumns`/`gridTemplateRows` arrays are set,
--- each entry resolves via fr/px/% (see resolveTracks). Otherwise falls back
--- to equal distribution driven by `gridColumns`/`gridRows`.
---@param element Element -- Grid container element
function Grid.layoutGridItems(element)
  local hasColTemplate = type(element.gridTemplateColumns) == "table" and #element.gridTemplateColumns > 0
  local hasRowTemplate = type(element.gridTemplateRows) == "table" and #element.gridTemplateRows > 0

  local columns = hasColTemplate and #element.gridTemplateColumns
    or (element.gridColumns and element.gridColumns > 0 and element.gridColumns or 1)
  local rows = hasRowTemplate and #element.gridTemplateRows
    or (element.gridRows and element.gridRows > 0 and element.gridRows or 1)

  -- Calculate space reserved by absolutely positioned siblings
  local reservedLeft = 0
  local reservedRight = 0
  local reservedTop = 0
  local reservedBottom = 0

  for _, child in ipairs(element.children) do
    if child.positioning == Positioning.ABSOLUTE and child._explicitlyAbsolute then
      local childBorderBoxWidth = child:getBorderBoxWidth()
      local childBorderBoxHeight = child:getBorderBoxHeight()

      if child.left then
        reservedLeft = math.max(reservedLeft, child.left + childBorderBoxWidth)
      end
      if child.right then
        reservedRight = math.max(reservedRight, child.right + childBorderBoxWidth)
      end
      if child.top then
        reservedTop = math.max(reservedTop, child.top + childBorderBoxHeight)
      end
      if child.bottom then
        reservedBottom = math.max(reservedBottom, child.bottom + childBorderBoxHeight)
      end
    end
  end

  -- BORDER-BOX MODEL: element.width and element.height are content dimensions
  local availableWidth = element.width - reservedLeft - reservedRight
  local availableHeight = element.height - reservedTop - reservedBottom

  local columnGap = element.columnGap or 0
  local rowGap = element.rowGap or 0

  -- Resolve track sizes (templated or equal distribution)
  local columnSizes, rowSizes
  if hasColTemplate then
    columnSizes = resolveTracks(element.gridTemplateColumns, availableWidth, columnGap)
  else
    local cellW = (availableWidth - (columns - 1) * columnGap) / columns
    columnSizes = {}
    for i = 1, columns do
      columnSizes[i] = cellW
    end
  end
  if hasRowTemplate then
    rowSizes = resolveTracks(element.gridTemplateRows, availableHeight, rowGap)
  else
    local cellH = (availableHeight - (rows - 1) * rowGap) / rows
    rowSizes = {}
    for i = 1, rows do
      rowSizes[i] = cellH
    end
  end

  -- Cumulative offsets for each track (origin = content area start)
  local columnOffsets = { [1] = 0 }
  for i = 2, columns do
    columnOffsets[i] = columnOffsets[i - 1] + columnSizes[i - 1] + columnGap
  end
  local rowOffsets = { [1] = 0 }
  for i = 2, rows do
    rowOffsets[i] = rowOffsets[i - 1] + rowSizes[i - 1] + rowGap
  end

  local gridChildren = {}
  for _, child in ipairs(element.children) do
    if not (child.positioning == Positioning.ABSOLUTE and child._explicitlyAbsolute) then
      table.insert(gridChildren, child)
    end
  end

  for i, child in ipairs(gridChildren) do
    local index = i - 1
    local col = index % columns
    local row = math.floor(index / columns)

    if row >= rows then
      break
    end

    local cellWidth = columnSizes[col + 1]
    local cellHeight = rowSizes[row + 1]
    local cellX = element.x + element.padding.left + reservedLeft + columnOffsets[col + 1]
    local cellY = element.y + element.padding.top + reservedTop + rowOffsets[row + 1]

    local effectiveAlignItems = element.alignItems or AlignItems.STRETCH

    if effectiveAlignItems == AlignItems.STRETCH or effectiveAlignItems == "stretch" then
      child.x = cellX
      child.y = cellY
      child._borderBoxWidth = cellWidth
      child._borderBoxHeight = cellHeight
      child.width = math.max(0, cellWidth - child.padding.left - child.padding.right)
      child.height = math.max(0, cellHeight - child.padding.top - child.padding.bottom)
      child.autosizing.width = false
      child.autosizing.height = false
    elseif effectiveAlignItems == AlignItems.CENTER or effectiveAlignItems == "center" then
      local childBorderBoxWidth = child:getBorderBoxWidth()
      local childBorderBoxHeight = child:getBorderBoxHeight()
      child.x = cellX + (cellWidth - childBorderBoxWidth) / 2
      child.y = cellY + (cellHeight - childBorderBoxHeight) / 2
    elseif
      effectiveAlignItems == AlignItems.FLEX_START
      or effectiveAlignItems == "flex-start"
      or effectiveAlignItems == "start"
    then
      child.x = cellX
      child.y = cellY
    elseif
      effectiveAlignItems == AlignItems.FLEX_END
      or effectiveAlignItems == "flex-end"
      or effectiveAlignItems == "end"
    then
      local childBorderBoxWidth = child:getBorderBoxWidth()
      local childBorderBoxHeight = child:getBorderBoxHeight()
      child.x = cellX + cellWidth - childBorderBoxWidth
      child.y = cellY + cellHeight - childBorderBoxHeight
    else
      child.x = cellX
      child.y = cellY
      child._borderBoxWidth = cellWidth
      child._borderBoxHeight = cellHeight
      child.width = math.max(0, cellWidth - child.padding.left - child.padding.right)
      child.height = math.max(0, cellHeight - child.padding.top - child.padding.bottom)
      child.autosizing.width = false
      child.autosizing.height = false
    end

    if #child.children > 0 then
      child:layoutChildren()
    end
  end
end

return Grid
