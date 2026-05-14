local C = {
  GRID_W = 15,
  GRID_H = 11,
  TILE   = 92,
  GRID_OX = 32,
  GRID_OY = 12,

  ACTION_BTN_W = 56,
  ACTION_BTN_H = 56,
  ACTION_BTN_GAP = 6,

  STARTING_ROWS = 3,
  ROW_UNLOCK_COSTS = { 200, 500, 1200, 2800, 6000, 12000, 24000, 50000 },

  HUD_X = 1444,
  HUD_W = 460,
  HUD_OY = 32,

  TASKS = { "Till", "Water", "Weed", "Replant" },

  CROPS = {
    { name="Tomato",     emoji="🍅", color={1.00, 0.30, 0.22}, buyCost = 5,  yieldMult = 1 },
    { name="Carrot",     emoji="🥕", color={1.00, 0.55, 0.15}, buyCost = 10, yieldMult = 2 },
    { name="Cucumber",   emoji="🥒", color={0.45, 0.80, 0.35}, yieldMult = 3 },
    { name="Corn",       emoji="🌽", color={1.00, 0.85, 0.30}, yieldMult = 3 },
    { name="Chili",      emoji="🌶", color={0.95, 0.20, 0.20}, yieldMult = 3 },
    { name="Eggplant",   emoji="🍆", color={0.65, 0.35, 0.80}, yieldMult = 5 },
    { name="Broccoli",   emoji="🥦", color={0.30, 0.65, 0.35}, yieldMult = 4 },
    { name="Strawberry", emoji="🍓", color={1.00, 0.40, 0.50}, yieldMult = 3 },
    { name="Watermelon", emoji="🍉", color={0.55, 0.85, 0.55}, yieldMult = 5 },
    { name="Pineapple",  emoji="🍍", color={1.00, 0.85, 0.25}, yieldMult = 5 },
    { name="Avocado",    emoji="🥑", color={0.55, 0.75, 0.35}, yieldMult = 7 },
    { name="Coconut",    emoji="🥥", color={0.75, 0.55, 0.30}, yieldMult = 10 },
    { name="Onion",      emoji="🧅", color={0.95, 0.80, 0.55}, yieldMult = 2 },
    { name="Pepper",     emoji="🫑", color={0.35, 0.75, 0.40}, yieldMult = 3 },
    { name="Garlic",     emoji="🧄", color={0.95, 0.92, 0.85}, yieldMult = 3 },
    { name="Cherry",     emoji="🍒", color={0.85, 0.15, 0.25}, yieldMult = 3 },
    { name="Mushroom",   emoji="🍄", color={0.75, 0.30, 0.30}, yieldMult = 4 },
    { name="Grapes",     emoji="🍇", color={0.55, 0.35, 0.75}, yieldMult = 4 },
    { name="Lemon",      emoji="🍋", color={1.00, 0.95, 0.30}, yieldMult = 4 },
    { name="Pumpkin",    emoji="🎃", color={1.00, 0.55, 0.10}, yieldMult = 5 },
    { name="Banana",     emoji="🍌", color={1.00, 0.90, 0.40}, yieldMult = 6 },
    { name="Mango",      emoji="🥭", color={1.00, 0.70, 0.20}, yieldMult = 8 },
  },

  TIER_NAMES = { "E", "D", "C", "B", "A", "S" },
  TIER_COLORS = {
    { 0.90, 0.30, 0.30 },
    { 1.00, 0.55, 0.20 },
    { 1.00, 0.85, 0.30 },
    { 0.50, 0.85, 0.40 },
    { 0.30, 0.80, 0.95 },
    { 0.95, 0.45, 0.95 },
  },
  YIELD_TIER_VALUES    = { 10, 20, 36, 60, 100, 160 },
  GROWTIME_TIER_VALUES = { 40, 30, 22, 16, 12, 8 },

  CROP_RECIPES = {
    { a="Carrot",     b="Carrot",     result="Cucumber",   chance=0.25 },
    { a="Tomato",     b="Carrot",     result="Chili",      chance=0.30 },
    { a="Tomato",     b="Cucumber",   result="Strawberry", chance=0.30 },
    { a="Carrot",     b="Cucumber",   result="Corn",       chance=0.30 },
    { a="Cucumber",   b="Corn",       result="Broccoli",   chance=0.25 },
    { a="Carrot",     b="Corn",       result="Pineapple",  chance=0.25 },
    { a="Tomato",     b="Chili",      result="Eggplant",   chance=0.25 },
    { a="Cucumber",   b="Strawberry", result="Watermelon", chance=0.25 },
    { a="Corn",       b="Strawberry", result="Pineapple",  chance=0.25 },
    { a="Cucumber",   b="Eggplant",   result="Avocado",    chance=0.25 },
    { a="Watermelon", b="Pineapple",  result="Coconut",    chance=0.20 },
    { a="Broccoli",   b="Avocado",    result="Coconut",    chance=0.20 },
    { a="Tomato",     b="Corn",       result="Chili",      chance=0.20 },
    { a="Chili",      b="Eggplant",   result="Strawberry", chance=0.20 },
    { a="Tomato",     b="Tomato",     result="Onion",      chance=0.30 },
    { a="Carrot",     b="Onion",      result="Pepper",     chance=0.30 },
    { a="Carrot",     b="Chili",      result="Garlic",     chance=0.25 },
    { a="Strawberry", b="Chili",      result="Cherry",     chance=0.25 },
    { a="Strawberry", b="Strawberry", result="Grapes",     chance=0.25 },
    { a="Cucumber",   b="Broccoli",   result="Mushroom",   chance=0.25 },
    { a="Onion",      b="Garlic",     result="Mushroom",   chance=0.30 },
    { a="Pineapple",  b="Strawberry", result="Lemon",      chance=0.25 },
    { a="Corn",       b="Eggplant",   result="Pumpkin",    chance=0.25 },
    { a="Cherry",     b="Grapes",     result="Watermelon", chance=0.25 },
    { a="Pepper",     b="Pumpkin",    result="Banana",     chance=0.22 },
    { a="Pineapple",  b="Avocado",    result="Banana",     chance=0.20 },
    { a="Mushroom",   b="Pumpkin",    result="Eggplant",   chance=0.25 },
    { a="Coconut",    b="Pineapple",  result="Mango",      chance=0.20 },
    { a="Lemon",      b="Mango",      result="Coconut",    chance=0.18 },
  },

  WORK_TIME = { Till=2.0, Water=1.5, Weed=1.5, Replant=1.0 },

  ROBOT_SPEED       = 2,
  ROBOT_SPEED_UP    = 3,
  ROBOT_SPEED_PER_LEVEL = 0.25,
  ROBOT_WORK_MULT_PER_LEVEL = 0.125,
  ROBOT_UPGRADE_COST = 100,
  ROBOT_UPGRADE_BASE_COST = 100,
  ROBOT_UPGRADE_COST_EXP = 2.0,
  ROBOT_BASE_COST   = 50,
  ROBOT_COST_EXP    = 2.4,
  ROBOT_CAP         = 12,

  SEED_BASE_COST = 50,
  SEED_COST_EXP  = 1,
  STICK_COST     = 5,

  ROBOT_NAMES = {
    "Beep", "Bop", "Tin", "Rusty", "Cog", "Sprocket", "Bolt", "Whirr",
    "Click", "Zap", "Gear", "Buzz", "Rivet", "Pixel", "Chip", "Spark",
  },

  WEED_SPAWN_MIN_INTERVAL = 10,
  WEED_SPAWN_MAX_INTERVAL = 15,
  WEED_SPAWN_MIN = 1,
  WEED_SPAWN_MAX = 2,

  WATER_DRAIN_PER_SEC = 1 / 10,
  WATER_MAX           = 1.0,
  WATER_GROW_GATE     = 0.05,
  WATER_REFILL_GATE   = 0.5,

  MUTATION_RATE = 0.03,

  STICK_EMOJI = "🪵",
  WEED_EMOJI  = "🌿",
  ROBOT_EMOJI = "🤖",
  BESTIARY_EMOJI = "📖",

  TASK_GLYPH = {
    Idle    = "💤",
    Till    = "🚜",
    Water   = "💧",
    Weed    = "🪓",
    Replant = "🌾",
  },

  TASK_TINT = {
    Idle    = { 0.7, 0.7, 0.9 },
    Till    = { 1.00, 0.65, 0.15 },
    Water   = { 0.30, 0.65, 1.00 },
    Weed    = { 0.70, 0.50, 0.25 },
    Replant = { 1.00, 0.85, 0.30 },
  },

  WEED_TINT = { 0.90, 0.30, 0.70 },
  RIPE_TINT = { 1.00, 0.90, 0.30 },
  LOCK_TINT = { 0.95, 0.85, 0.40 },

  RIPE_GLYPH = "✨",
  LOCK_EMOJI = "🔒",

  FERT_KEYS = { "weedShield", "growBoost", "autoWater" },
  FERTILIZERS = {
    weedShield = {
      name  = "Shield",
      emoji = "🛡",
      tint  = { 0.6, 0.85, 1.0 },
      buyCost = 20,
      baseDuration = 60,
      baseMagnitude = nil,
      magStep = 0,
      magCap = nil,
    },
    growBoost = {
      name  = "Boost",
      emoji = "⚡",
      tint  = { 1.0, 0.95, 0.4 },
      buyCost = 40,
      baseDuration = 60,
      baseMagnitude = 1.5,
      magStep = 0.1,
      magCap = 5.0,
    },
    autoWater = {
      name  = "Water+",
      emoji = "💦",
      tint  = { 0.4, 0.7, 1.0 },
      buyCost = 30,
      baseDuration = 60,
      baseMagnitude = nil,
      magStep = 0,
      magCap = nil,
    },
  },
  FERT_DURATION_PER_LEVEL = 60,
  FERT_UPGRADE_BASE_COST = 100,
  FERT_UPGRADE_COST_EXP = 2.0,
  FERT_BUY_COST_EXP = 1.6,

  SAVE_FILE = "save.lua",
  SAVE_INTERVAL = 60,
  SAVE_SCHEMA = 3,
}

-- Derived lookups: name → index, and recipe lookup by sorted-index key.
-- Source of truth = CROP_RECIPES (names). Runtime uses indexes.
C.CROP_INDEX = {}
for i, crop in ipairs(C.CROPS) do
  C.CROP_INDEX[crop.name] = i
end

C.RECIPE_LOOKUP = {}
for ri, r in ipairs(C.CROP_RECIPES) do
  local ai = assert(C.CROP_INDEX[r.a], "unknown crop name in recipe.a: " .. tostring(r.a))
  local bi = assert(C.CROP_INDEX[r.b], "unknown crop name in recipe.b: " .. tostring(r.b))
  local resIdx = assert(C.CROP_INDEX[r.result], "unknown crop name in recipe.result: " .. tostring(r.result))
  local lo, hi = ai, bi
  if lo > hi then lo, hi = hi, lo end
  local key = lo .. "+" .. hi
  C.RECIPE_LOOKUP[key] = {
    result    = resIdx,
    chance    = r.chance,
    recipeIdx = ri,
    aName     = r.a,
    bName     = r.b,
    resultName= r.result,
  }
end

local TIER = {}
for i, name in ipairs(C.TIER_NAMES) do TIER[name] = i end

-- Row unlock crop requirements. Each entry corresponds to rows 4..11 (i.e. starting row + i).
-- { crop = "Name", tier = "E"-"S", count = N }
local UNLOCK_RAW = {
  -- Row 4
  { { crop="Tomato",     tier="E", count=3 } },
  -- Row 5
  { { crop="Carrot",     tier="D", count=5 } },
  -- Row 6
  { { crop="Cucumber",   tier="D", count=3 },
    { crop="Chili",      tier="D", count=3 },
    { crop="Onion",      tier="D", count=2 } },
  -- Row 7
  { { crop="Corn",       tier="D", count=2 },
    { crop="Strawberry", tier="D", count=2 },
    { crop="Pepper",     tier="D", count=2 },
    { crop="Garlic",     tier="D", count=2 } },
  -- Row 8
  { { crop="Broccoli",   tier="C", count=2 },
    { crop="Pineapple",  tier="C", count=2 },
    { crop="Eggplant",   tier="C", count=2 },
    { crop="Cherry",     tier="C", count=2 },
    { crop="Grapes",     tier="C", count=2 } },
  -- Row 9
  { { crop="Watermelon", tier="B", count=2 },
    { crop="Mushroom",   tier="B", count=2 },
    { crop="Pumpkin",    tier="B", count=2 },
    { crop="Lemon",      tier="B", count=2 } },
  -- Row 10
  { { crop="Avocado",    tier="B", count=2 },
    { crop="Banana",     tier="A", count=2 } },
  -- Row 11
  { { crop="Coconut",    tier="A", count=2 },
    { crop="Mango",      tier="A", count=2 },
    { crop="Banana",     tier="A", count=2 },
    { crop="Avocado",    tier="A", count=2 },
    { crop="Lemon",      tier="B", count=2 } },
}

C.ROW_UNLOCK_REQS = {}
for ri, reqs in ipairs(UNLOCK_RAW) do
  local out = {}
  for _, r in ipairs(reqs) do
    out[#out + 1] = {
      crop  = assert(C.CROP_INDEX[r.crop], "unknown crop in unlock req: " .. r.crop),
      tier  = assert(TIER[r.tier], "unknown tier in unlock req: " .. r.tier),
      count = r.count,
    }
  end
  C.ROW_UNLOCK_REQS[ri] = out
end

return C
