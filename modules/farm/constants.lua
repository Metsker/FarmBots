return {
  GRID_W = 12,
  GRID_H = 8,
  TILE   = 96,
  GRID_OX = 32,
  GRID_OY = 32,

  HUD_X = 1240,
  HUD_W = 660,
  HUD_OY = 32,

  TASKS = { "Idle", "Till", "Plant", "Water", "Harvest", "Weed" },

  CROPS = {
    { name="Tomato",     emoji="🍅" },
    { name="Carrot",     emoji="🥕" },
    { name="Cucumber",   emoji="🥒" },
    { name="Corn",       emoji="🌽" },
    { name="Chili",      emoji="🌶" },
    { name="Eggplant",   emoji="🍆" },
    { name="Broccoli",   emoji="🥦" },
    { name="Strawberry", emoji="🍓" },
    { name="Watermelon", emoji="🍉" },
    { name="Pineapple",  emoji="🍍" },
    { name="Avocado",    emoji="🥑" },
    { name="Coconut",    emoji="🥥" },
  },

  WORK_TIME = { Till=2.0, Plant=1.0, Water=1.5, Harvest=1.0, Weed=1.5 },

  ROBOT_SPEED       = 2,
  ROBOT_SPEED_UP    = 3,
  ROBOT_UPGRADE_COST = 100,
  ROBOT_BASE_COST   = 25,
  ROBOT_COST_EXP    = 1.9,
  ROBOT_CAP         = 12,

  SEED_BASE_COST = 15,
  SEED_COST_EXP  = 1.35,

  ROBOT_NAMES = {
    "Beep", "Bop", "Tin", "Rusty", "Cog", "Sprocket", "Bolt", "Whirr",
    "Click", "Zap", "Gear", "Buzz", "Rivet", "Pixel", "Chip", "Spark",
  },

  WEED_SPAWN_INTERVAL = 12,

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
    Plant   = "🌱",
    Water   = "💧",
    Harvest = "🧺",
    Weed    = "🪓",
  },
}
