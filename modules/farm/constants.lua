return {
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
    ["2+2"]  = { result = 3,  chance = 0.25 },
    ["1+2"]  = { result = 5,  chance = 0.30 },
    ["1+3"]  = { result = 8,  chance = 0.30 },
    ["2+3"]  = { result = 4,  chance = 0.30 },
    ["3+4"]  = { result = 7,  chance = 0.25 },
    ["2+4"]  = { result = 10, chance = 0.25 },
    ["1+5"]  = { result = 6,  chance = 0.25 },
    ["3+8"]  = { result = 9,  chance = 0.25 },
    ["4+8"]  = { result = 10, chance = 0.25 },
    ["3+6"]  = { result = 11, chance = 0.25 },
    ["9+10"] = { result = 12, chance = 0.20 },
    ["7+11"] = { result = 12, chance = 0.20 },
    ["1+4"]  = { result = 5,  chance = 0.20 },
    ["5+6"]  = { result = 8,  chance = 0.20 },
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
  WATER_REFILL_GATE   = 0.35,

  MUTATION_RATE = 0.03,

  STICK_EMOJI = "🪵",
  WEED_EMOJI  = "🌿",
  ROBOT_EMOJI = "🤖",

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

  WEED_TINT = { 0.40, 0.85, 0.35 },
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
}
