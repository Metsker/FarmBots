# Architecture — Extended Guide

Как расставлять код, где хранить состояние, как сцены общаются. Документ не про синтаксис SE3, а про **практики** — как проект перестаёт быть кучей файлов и становится поддерживаемой структурой.

Все рекомендации — из опыта. Не «единственно правильные». Это набор ориентиров; отступайте, когда у вашего случая своя специфика.

---

## Оглавление

1. [Слои проекта](#1-слои-проекта)
2. [Рекомендуемое дерево каталогов](#2-рекомендуемое-дерево-каталогов)
3. [main.lua — что и когда](#3-mainlua--что-и-когда)
4. [Где живёт состояние](#4-где-живёт-состояние)
5. [Коммуникация между сценами](#5-коммуникация-между-сценами)
6. [Signal vs handler vs контроллер vs прямой вызов](#6-signal-vs-handler-vs-контроллер-vs-прямой-вызов)
7. [Глобалы и синглтоны](#7-глобалы-и-синглтоны)
8. [Модели данных (game state, save data, settings)](#8-модели-данных-game-state-save-data-settings)
9. [Локализация](#9-локализация)
10. [Тестируемость](#10-тестируемость)
11. [Антипаттерны](#11-антипаттерны)

---

## 1. Слои проекта

В SE3-проекте естественно выделяются пять слоёв:

```
┌───────────────────────────────────────────────┐
│ main.lua    — bootstrap, love.load, callbacks  │
├───────────────────────────────────────────────┤
│ manager     — SESceneManager + nav handlers    │
├───────────────────────────────────────────────┤
│ scenes/     — манифесты + controllers          │
├───────────────────────────────────────────────┤
│ widgets/    — переиспользуемые классы          │
│ prefabs/    — переиспользуемые поддеревья      │
├───────────────────────────────────────────────┤
│ model/      — игровая логика, data, I/O        │
└───────────────────────────────────────────────┘
        ↓ каждый слой знает только о слоях под собой
```

- **main.lua** знает про менеджер, глобальные ассеты, навигацию.
- **manager** знает про сцены по именам и их пути. Не знает, что внутри.
- **scenes** — каждая сцена сама по себе: манифест + контроллер + свои локальные handler-ы.
- **widgets / prefabs** — переиспользуемые строительные блоки. Ничего не знают о сценах, в которых живут.
- **model** — чистая логика игры. Не знает ни о сценах, ни о виджетах, ни о Love.

Ломать слои («виджет дёргает менеджер напрямую», «сцена читает глобаль model-я») — ОК в прототипах, проблема в больших проектах.

---

## 2. Рекомендуемое дерево каталогов

```
mygame/
├── main.lua
├── conf.lua
│
├── se3/                      -- симлинк или clone движка
│
├── scenes/
│   ├── loader.lua            -- экран загрузки (опц.)
│   ├── menu.lua
│   ├── menu_ctrl.lua
│   ├── game.lua
│   ├── game_ctrl.lua
│   ├── settings.lua
│   └── settings_ctrl.lua
│
├── widgets/                  -- классы, регистрируемые через components
│   ├── health_bar.lua
│   ├── hero_card.lua
│   └── all.lua               -- агрегатор для удобства
│
├── prefabs/                  -- чистые поддеревья (без методов)
│   ├── button.lua
│   ├── dialog.lua
│   └── toggle.lua
│
├── handlers/                 -- именованные функции для @name
│   ├── nav.lua
│   ├── audio.lua
│   └── dev.lua
│
├── model/                    -- данные и игровая логика
│   ├── game_state.lua        -- GameState синглтон
│   ├── save.lua              -- save/load в love.filesystem
│   ├── settings.lua          -- user settings
│   └── rules/
│       ├── combat.lua
│       └── economy.lua
│
├── assets/
│   ├── common/               -- общий атлас (кнопки, шрифт, UI)
│   ├── menu/
│   ├── game/
│   └── fonts/
│
└── shaders/
    ├── bloom.glsl
    └── vignette.glsl
```

Что важно:

- **Сцены и их контроллеры рядом** — легче править один и другой вместе.
- **widgets и prefabs разделены** — это разные концепции ([Inheritance §14](./Inheritance.md#14-регистрация-кастомных-классов-в-sesceneloader)).
- **handlers — отдельная папка** — потому что они используются из разных сцен.
- **model — отдельный слой** — чтобы в будущем можно было вынести его на сервер или в отдельный процесс без рефакторинга UI.
- **assets по сценам** — легче отслеживать, где что лежит, и удалять неиспользуемые ассеты.

### Standalone-сцена

Если делаете портативную сцену, которую можно запустить и как микроапп, и из родительского проекта:

```
modules/scenes/slot_1/
├── main.lua            -- микроапп-запуск
├── conf.lua
├── scene_description.lua
├── scene.lua           -- контроллер
├── shared/
│   └── se3 → /path/to/se3
└── assets/
```

Запуск: `love modules/scenes/slot_1`. Из родителя: `manager:register("slot_1", "modules.scenes.slot_1.scene_description")`.

Подробнее — [SESceneManager §11](./SESceneManager.md#11-standalone-microapp-pattern).

---

## 3. main.lua — что и когда

Типичный `main.lua` для небольшого проекта:

```lua
require("se3")

function love.load()
  -- 1. Bootstrap: общие ассеты
  local common = SLoader.new()
  common:addAtlas("atlases.common", "assets/common/")
  common:addFont ("main", "assets/fonts/main.ttf", 32)
  common:loadAll()
  SEEnvironment:setLoader(common, "common")

  -- 2. Глобальные singleton-ы
  Sound      = SSoundManager()
  GameState  = require("model.game_state")
  Settings   = require("model.settings").load()

  -- 3. Менеджер и навигация
  manager = SESceneManager.new()
  require("handlers.nav")(manager)        -- регистрирует @nav.* handler-ы
  require("handlers.audio")(manager)

  -- 4. Регистрация сцен
  manager:register("menu",     "scenes.menu")
  manager:register("game",     "scenes.game")
  manager:register("settings", "scenes.settings")

  -- 5. Кастомный loading-экран (опц.)
  manager:setLoadingDraw(require("model.loading_draw"))

  -- 6. Запуск
  manager:change("menu")
end

function love.update(dt)              manager:update(dt)              end
function love.draw()                  manager:draw()                  end
function love.mousemoved(x,y,dx,dy,t) manager:mousemoved(x,y,dx,dy,t) end
function love.mousepressed(x,y,b,t)   manager:mousepressed(x,y,b,t)   end
function love.mousereleased(x,y,b,t)  manager:mousereleased(x,y,b,t)  end
function love.keypressed(k,s,r)       manager:keypressed(k,s,r)       end
function love.keyreleased(k)          manager:keyreleased(k)          end

function love.quit()
  Settings:save()
  GameState:save()
  SEEnvironment:unloadAll()
end
```

**Шесть блоков** — каждый хорошо виден. Одно правило: `main.lua` никогда не решает «как работает меню» или «как игрок прыгает». Только bootstrap.

### Handler-модуль

```lua
-- handlers/nav.lua
return function(manager)
  local L = manager:loader()
  L:registerHandler("nav.menu",     function() manager:change("menu")     end)
  L:registerHandler("nav.game",     function() manager:change("game")     end)
  L:registerHandler("nav.settings", function() manager:change("settings") end)
  L:registerHandler("nav.quit",     function() love.event.quit()          end)
end
```

Это модуль-функция, принимающая менеджер. Вызов `require("handlers.nav")(manager)` — паттерн «init». Так код навигации изолирован в одном файле.

Альтернатива — `nav.lua` читает `_G.manager`. Менее чисто, но проще для маленьких проектов.

---

## 4. Где живёт состояние

Важнейший вопрос в проекте любого размера. Три уровня:

### Уровень 1: сцена (контроллер)

Состояние, **зависящее только от конкретной сцены** — в её контроллере:

```lua
-- scenes/game_ctrl.lua
local Game = Class{ init = function(self)
  self.score = 0
  self.time  = 0
  self.enemies = {}
end }

function Game:onEnter(scene, params) ... end
function Game:update(dt) ... end
```

Когда сцена уходит — контроллер уходит с ней. Score забывается. Это **правильно** для внутриигрового состояния, которое не должно переживать выход в меню.

### Уровень 2: глобальный синглтон (GameState)

Состояние, **переживающее смену сцены, но живущее в памяти**:

```lua
-- model/game_state.lua
local GameState = {
  currentLevel = 1,
  gold         = 0,
  hp           = 100,
  maxHp        = 100,
  inventory    = {},
}

function GameState:addGold(n)
  self.gold = self.gold + n
  Signal.emit("gamestate.goldChanged", self.gold)
end

function GameState:reset()
  self.currentLevel = 1
  self.gold = 0
  ...
end

return GameState
```

Используется из любой сцены: `GameState:addGold(50)`. Переход между сценами его не трогает.

### Уровень 3: персистентное (Save)

Состояние, **переживающее перезапуск игры**:

```lua
-- model/save.lua
local Save = {}

function Save.load()
  if not love.filesystem.getInfo("save.lua") then return end
  local data = love.filesystem.load("save.lua")()
  GameState.currentLevel = data.level
  GameState.gold         = data.gold
  ...
end

function Save.save()
  local data = {
    level = GameState.currentLevel,
    gold  = GameState.gold,
    ...
  }
  love.filesystem.write("save.lua",
    "return " .. require("inspect")(data))
end

return Save
```

Save — **не** держит state. State в `GameState`. Save — это I/O.

### Решение: что куда

| Что | Где |
|-----|-----|
| Кадр анимации на сцене | **сцена.контроллер** |
| Текущий игрок hover-идёт над кнопкой | **виджет (кнопка сама)** |
| Положение камеры | **сцена.контроллер** |
| Очки в текущем матче | **сцена.контроллер** |
| Общее золото игрока между матчами | **GameState** |
| Список отпертых уровней | **GameState** (потом в Save) |
| Громкость звука | **Settings** (в Save) |
| FPS или другая статистика рендера | **main.lua / singleton** |

Если непонятно, куда — **начните с контроллера**. Поднимать состояние в более верхний слой легче, чем спускать.

---

## 5. Коммуникация между сценами

Три способа:

### A. `params` при `change`

```lua
-- A эмитит клик "go to game":
manager:change("game", { difficulty = "hard", fromMenu = true })

-- B получает в onEnter:
function Game:onEnter(scene, params)
  self.difficulty = params.difficulty
  self.fromMenu   = params.fromMenu
end
```

Идёт «вниз по потоку» — A → B. Типично для передачи конфигурации новой сцены.

### B. GameState

Сцена A записывает что-то в `GameState`, B читает при входе:

```lua
function Menu:startGame(level)
  GameState.currentLevel = level
  manager:change("game")
end

function Game:onEnter(scene)
  self.level = GameState.currentLevel
end
```

Работает и в обе стороны: `Game:onLeave` записывает score в `GameState.lastScore`, потом `Menu` его читает и показывает.

### C. Signal

Только для **живых** подписчиков:

```lua
Signal.emit("game.completed", { score = 100 })

-- где-то подписчик (должен быть зарегистрирован ДО emit):
Signal.register("game.completed", function(result)
  achievement:check(result)
end)
```

Не годится для межсценной передачи, если подписчик ещё не создан. **Не используйте Signal для «сцена A → сцена B».**

---

## 6. Signal vs handler vs контроллер vs прямой вызов

Четыре механизма для «кто-то что-то сделал — что-то должно произойти». Выбор зависит от:

1. **Есть ли состояние?** Если да — контроллер.
2. **Знает ли источник получателя?** Если нет — Signal.
3. **Переживает ли сцену?** Если да — handler менеджера.
4. **Локальная ли логика кнопки?** Если да — функциональный event.

### Таблица выбора

| Ситуация | Механизм |
|----------|----------|
| Кнопка PLAY переключает сцену | **handler** `@nav.play` |
| Внутренний клик мутирует state сцены | **контроллер** `@self:method` |
| Аналитика / звук / логгер слушает много событий | **Signal** |
| Одноразовый callback локально | **функциональный event** |
| Модуль аудио подменяет стандартный Sound | **прямой вызов** `Sound:play()` |

### Пример: клик по «PLAY»

```lua
-- Вариант 1: handler (хорошо, если кнопка из разных сцен ведёт в game)
{ type = "SSpriteButton", event = "@nav.play", ... }

-- Вариант 2: локальная функция (хорошо для prototype, не масштабируется)
{ type = "SSpriteButton", event = function() manager:change("game") end, ... }

-- Вариант 3: контроллер (хорошо, если «play» мутирует state этой сцены)
{ type = "SSpriteButton", event = "@self:play", ... }
-- ...
function Menu:play()
  self.clicks = self.clicks + 1
  manager:change("game", { menuClicks = self.clicks })
end

-- Вариант 4: Signal (хорошо, если PLAY услышит логгер, аналитика, звук)
{ type = "SSpriteButton", event = "menu.play", ... }   -- Signal.emit("click", "menu.play")
-- ... слушатели зарегистрированы где-то ещё
```

Все четыре работают. Выбор — о читаемости и переиспользуемости.

### Привычный паттерн для средних проектов

```
Signal "click" → handlers (через @)    — стандартная UI-навигация
"@self:method" → controller            — локальное state-related поведение
Signal для analytics / audio           — cross-cutting concerns
Direct calls                            — model / core logic
```

---

## 7. Глобалы и синглтоны

SE3-шка и Love вынуждают иметь **некоторые** глобали:

| Глобаль | Откуда | Зачем |
|---------|--------|-------|
| `resource` | `SEEnvironment` в `init.lua` | доступ к ассетам изнутри классов |
| `Signal` | `hump/signal.lua` | шина событий |
| `Class` | `hump/class.lua` | `__includes` |
| `lume` | `lume.lua` | functional helpers |
| Классы движка (`SObject`, `SSprite`…) | `se3.lua` | регистрируются как глобали |

Это — **инфраструктурные** глобали. SE3 их ставит без вашего участия.

### Добавление своих

Для маленького проекта можно добавить свои глобали:

```lua
-- main.lua
GameState = require("model.game_state")
Sound     = SSoundManager()
Settings  = require("model.settings").load()
```

Это **удобно** — из любого контроллера `GameState.gold` работает. Минус — их не видно из кода (нет `require`), что затрудняет grep «где используется?» и может удивить нового разработчика.

Для бОльших проектов:

- Импортируйте через `require`:

```lua
-- scenes/game_ctrl.lua
local GameState = require("model.game_state")

function Game:addGold(n)
  GameState:addGold(n)
end
```

- Избегайте «скрытых» глобалей. Глобалями оставляйте только **движковые** вещи.

---

## 8. Модели данных (game state, save data, settings)

### GameState как plain Lua-таблица

Самый простой вариант:

```lua
-- model/game_state.lua
local M = {
  gold         = 0,
  hp           = 100,
  currentLevel = 1,
}

function M:addGold(n)
  self.gold = self.gold + n
end

function M:spendGold(n)
  if self.gold < n then return false end
  self.gold = self.gold - n
  return true
end

function M:reset()
  self.gold, self.hp, self.currentLevel = 0, 100, 1
end

return M
```

- Возвращает таблицу — `require`-кэш сделает её синглтоном.
- Методы через `:` — понятно, что это объект, а не просто набор констант.

### Settings как таблица с сериализацией

```lua
-- model/settings.lua
local M = {
  soundVolume = 1.0,
  musicVolume = 0.5,
  fullscreen  = false,
  language    = "en",
}

function M:load()
  if not love.filesystem.getInfo("settings.lua") then return self end
  local fn = love.filesystem.load("settings.lua")
  local data = fn()
  for k, v in pairs(data) do self[k] = v end
  return self
end

function M:save()
  local lines = { "return {" }
  for k, v in pairs(self) do
    if type(v) ~= "function" then
      lines[#lines+1] = ("  %s = %s,"):format(k, require("inspect")(v))
    end
  end
  lines[#lines+1] = "}"
  love.filesystem.write("settings.lua", table.concat(lines, "\n"))
end

return M
```

Простая сериализация через `return {...}`-модуль. Для сложных структур — `love.data.pack` или JSON через библиотеку.

### Reactivity — уведомление при изменении

Если нужно, чтобы HUD сам обновился при изменении gold:

```lua
function GameState:addGold(n)
  self.gold = self.gold + n
  Signal.emit("gamestate.changed", "gold", self.gold)
end

-- HUD-контроллер:
function HUD:onEnter(scene)
  self._onChanged = function(field, value)
    if field == "gold" then scene:byId("gold_label"):setText(tostring(value)) end
  end
  Signal.register("gamestate.changed", self._onChanged)
end

function HUD:onLeave()
  Signal.remove("gamestate.changed", self._onChanged)
end
```

Простейшая reactive-система: mutator эмитит, слушатели обновляются. Не перебор для SE3-проекта.

---

## 9. Локализация

SE3 не имеет встроенного i18n — но делать его самостоятельно просто.

```lua
-- model/i18n.lua
local M = { _lang = "en", _strings = {} }

function M:setLanguage(lang)
  self._lang = lang
  self._strings = love.filesystem.load("i18n/" .. lang .. ".lua")()
  Signal.emit("i18n.changed", lang)
end

function M:t(key, params)
  local s = self._strings[key] or key
  if params then
    for k, v in pairs(params) do
      s = s:gsub("{" .. k .. "}", tostring(v))
    end
  end
  return s
end

return M
```

Файл `i18n/en.lua`:

```lua
return {
  ["menu.play"]  = "PLAY",
  ["menu.quit"]  = "QUIT",
  ["game.score"] = "Score: {value}",
}
```

Использование:

```lua
local I18n = require("model.i18n")
I18n:setLanguage(Settings.language)

-- В сцене:
{ type = "SText", font = "main", text = I18n:t("menu.play") }

-- С параметрами:
SText{ text = I18n:t("game.score", {value = GameState.score}) }
```

Реактивность: на `"i18n.changed"` контроллеры сцен перезаполняют текстовые узлы.

---

## 10. Тестируемость

SE3-проект средней сложности тестируется с трудом (Love-графика жёстко привязана к игровому циклу). Но **модели** тестируются тривиально:

```lua
-- tests/game_state_test.lua
local GameState = require("model.game_state")

local function test_addGold()
  GameState:reset()
  GameState:addGold(100)
  assert(GameState.gold == 100)
end

local function test_spendGold_insufficient()
  GameState:reset()
  local ok = GameState:spendGold(50)
  assert(ok == false)
  assert(GameState.gold == 0)
end

test_addGold()
test_spendGold_insufficient()
print("OK")
```

Запускать — вне Love, через обычный `lua`:

```bash
lua tests/game_state_test.lua
```

Но это работает только для модулей, которые не зависят от Love. Как только модуль импортирует `love.graphics`, тест упадёт.

### Граница

Держите `model/` **полностью** free от Love. Чистый Lua. Это единственная часть проекта, которую можно тестировать без Love-раннера.

UI (сцены, виджеты) — не тестируется автоматически. Проверяется запуском игры.

---

## 11. Антипаттерны

### `_G.scene` и `_G.manager` везде

```lua
-- widgets/foo.lua
function Foo:click()
  _G.manager:change("bar")
end
```

Виджет теперь зависит от глобали. Нельзя переиспользовать в контексте без менеджера (тесты, standalone-превью).

**Лучше**: виджет эмитит `event` или `Signal`, а менеджер (снаружи) подписывается.

### Логика игры в контроллере

```lua
-- scenes/game_ctrl.lua
function Game:attackEnemy(enemy)
  enemy.hp = enemy.hp - 10
  if enemy.hp <= 0 then
    self.score = self.score + 100
    self:removeEnemy(enemy)
  end
end
```

«Атака врага» — это **model**, не scene. Контроллер должен вызвать `Combat.attack(self.player, enemy)`, а `Combat` — чистый модуль, который потом легко переиспользовать и тестировать.

**Правило**: в контроллере — UI-логика (что показать, куда перейти). В model — правила игры (сколько урона, как считается лут).

### Все классы в одном файле

```lua
-- widgets/all.lua
local HealthBar = Class{ __includes = SObject, ... }
local HeroCard  = Class{ __includes = SObject, ... }
local MiniMap   = Class{ __includes = SGroup,  ... }
-- 500 строк
```

Для 2-3 мелких классов — ОК. Для серьёзных виджетов — разносите по файлам (`widgets/health_bar.lua`, `widgets/hero_card.lua`). Агрегатор `widgets/all.lua` пусть только re-exports:

```lua
return { components = {
  HealthBar = require("widgets.health_bar"),
  HeroCard  = require("widgets.hero_card"),
  MiniMap   = require("widgets.mini_map"),
}}
```

### Слишком много сцен

```
scenes/
├── main_menu.lua
├── main_menu_settings.lua
├── main_menu_credits.lua
├── game_pause.lua
├── game_gameover.lua
├── game_levelselect.lua
└── ... (30 сцен)
```

Каждая «сцена» перезагружает всё. Settings и pause — это **оверлеи**, а не сцены. Делайте их поддеревьями внутри одной сцены:

```lua
-- scenes/game.lua
{
  scene = {
    type = "SGroup", children = {
      { type = "SGroup", id = "gameplay", ... },
      { type = "SGroup", id = "pause_overlay", off = true, ... },     -- показывается on pause
      { type = "SGroup", id = "gameover_overlay", off = true, ... },
    }
  }
}
```

Контроллер переключает `off` для нужного оверлея. Без перезагрузки ассетов, без полной смены сцены.

**Критерий «что — сцена, что — оверлей»**:
- Сцена = новый набор тяжёлых ассетов.
- Оверлей = использует те же ассеты + немного своих.

### Сцена читает глобали контроллера другой сцены

```lua
-- scenes/menu_ctrl.lua
function Menu:onEnter()
  if GameController and GameController.lastScore then
    self:showBadge("Last: " .. GameController.lastScore)
  end
end
```

`GameController` — контроллер другой сцены. Он мог быть выгружен; его state уже не валиден. Вы обратились к зомби-объекту.

**Лучше**: `GameController:onLeave` пишет `GameState.lastScore = self.score`. `Menu:onEnter` читает `GameState.lastScore`.

---

## См. также

- [SESceneLoader.md](./SESceneLoader.md) — манифесты и контроллеры.
- [SESceneManager.md](./SESceneManager.md) — переходы между сценами.
- [Signals.md](./Signals.md) — когда и зачем использовать шину.
- [Inheritance.md](./Inheritance.md) — где уместно делать класс, а где — префаб.
- [Performance.md](./Performance.md) — что делать, если состояние большое/многочисленное.
