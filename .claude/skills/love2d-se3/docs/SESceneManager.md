# SESceneManager — Extended Guide

`SESceneManager` — тонкий роутер поверх `SESceneLoader` и `SEEnvironment`. Он нужен, когда в проекте **больше одной сцены** и надо уметь переключаться между ними с асинхронной загрузкой ассетов и прогресс-баром.

Файл с реализацией: `sescenemanager.lua`.

---

## Оглавление

1. [Зачем менеджер](#1-зачем-менеджер)
2. [Минимальный пример](#2-минимальный-пример)
3. [Состояния и переходы](#3-состояния-и-переходы)
4. [Регистрация и переключение сцен](#4-регистрация-и-переключение-сцен)
5. [Параметры и `onEnter(scene, params)`](#5-параметры-и-onenterscene-params)
6. [Форвардинг Love2D-событий](#6-форвардинг-love2d-событий)
7. [Контроллер сцены и менеджер](#7-контроллер-сцены-и-менеджер)
8. [Общие ресурсы через `"common"` слот](#8-общие-ресурсы-через-common-слот)
9. [Handler-ы, которые переживают переключение](#9-handler-ы-которые-переживают-переключение)
10. [Кастомный прогресс-бар](#10-кастомный-прогресс-бар)
11. [Standalone microapp pattern](#11-standalone-microapp-pattern)
12. [Полный пример: лобби ↔ игра ↔ магазин](#12-полный-пример-лобби--игра--магазин)
13. [API Reference](#13-api-reference)

---

## 1. Зачем менеджер

`SESceneLoader:load()` отлично работает, когда сцена в проекте одна. Как только сцен становится две и больше, поднимаются вопросы:

- Кто отвечает за выгрузку ассетов предыдущей сцены?
- Как показать прогресс-бар во время переключения?
- Как не получить двойную обработку событий в момент, когда старой сцены уже нет, а новой ещё нет?
- Как сделать кнопку «старт игры» и отдельный вход для «обратно в лобби»?

`SESceneManager` решает всё это одним объектом. Он хранит:

- Один общий `SESceneLoader`.
- Реестр `name → manifest path`.
- Одну активную сцену, её манифест и контроллер.
- Конечный автомат переходов.

---

## 2. Минимальный пример

```lua
-- main.lua
require("se3")

function love.load()
  manager = SESceneManager.new()

  -- навигационные handler-ы живут на лоадере менеджера и переживают сцены
  manager:loader():registerHandler("nav.play",  function() manager:change("game")  end)
  manager:loader():registerHandler("nav.lobby", function() manager:change("lobby") end)

  manager:register("lobby", "scenes.lobby")
  manager:register("game",  "scenes.game")

  manager:change("lobby")
end

function love.update(dt)              manager:update(dt)              end
function love.draw()                  manager:draw()                  end
function love.mousemoved(x,y,dx,dy,t) manager:mousemoved(x,y,dx,dy,t) end
function love.mousepressed(x,y,b,t)   manager:mousepressed(x,y,b,t)   end
function love.mousereleased(x,y,b,t)  manager:mousereleased(x,y,b,t)  end
function love.keypressed(k,s,r)       manager:keypressed(k,s,r)       end
function love.keyreleased(k)          manager:keyreleased(k)          end
```

Любая кнопка или keyboard-action внутри любой сцены может вызвать `@nav.play`, и менеджер переведёт игру в сцену `game`.

---

## 3. Состояния и переходы

```
           change(name)
  idle ─────────────────────▶ loading
                                  │
                                  │ preload done
                                  ▼
                              active
                                  │
                                  │ change(other)
                                  ▼
                              loading
```

| Состояние | Что происходит |
|-----------|----------------|
| `idle` | нет активной сцены (до первого `:change`) |
| `loading` | идёт preload новой сцены; события **игнорируются**, вызовы `change()` тоже |
| `active` | сцена работает, события форвардятся нормально |

Пока менеджер в `loading`:

- Повторный `change()` возвращает `false` и никуда не ведёт — один переход за раз.
- Все входные события (`mouse*`, `key*`) отбрасываются. Старой сцены уже нет, новая не построена — отправлять события некуда.
- Каждый `update(dt)` делает до `stepsPerFrame` шагов `preload:step()`. По умолчанию — 4 шага на кадр; настраивается через `opts.stepsPerFrame` в конструкторе или `:setStepsPerFrame(n)`.
- `draw()` рисует прогресс-бар: по умолчанию — центрированный текст `"NN%"`. Переопределяется через `:setLoadingDraw(fn)`.

---

## 4. Регистрация и переключение сцен

```lua
manager:register("lobby", "scenes.lobby")
manager:register("game",  "modules.scenes.game.scene_description")
manager:register("shop",  "modules.scenes.shop.scene_description")

manager:change("game", { level = 3, difficulty = "hard" })
```

Что происходит внутри `change(name, params)`:

1. Если `state == "loading"` — возврат `false` (игнорируется).
2. Находит путь в реестре (`error`, если имя не зарегистрировано).
3. Если есть активная сцена:
   - Вызывает `manifest.onLeave(currentScene, manager)`.
   - Вызывает `controller:onLeave(currentScene, manager)`.
   - Сбрасывает все ссылки на текущую сцену/манифест/контроллер.
4. Выводит `requirePrefix` и `pathPrefix` из зарегистрированного пути.
5. Делает `loader:preload(path, { params, requirePrefix, pathPrefix })`.
6. Переходит в `loading`.

При завершении загрузки (`preload:done()` в `update`):

1. Вызывает `preload:build()`:
   - `loadAll()` дотягивает всё, что не докачано.
   - `SEEnvironment:setLoader(newAssets, "scene")` — предыдущий слот выгружается автоматически.
   - Строит дерево.
   - `controller:onEnter(scene, params)`.
   - `manifest.onEnter(scene, params)`.
2. Переходит в `active`.

Порядок `onEnter`/`onLeave` зеркальный — контроллер первым «поднимается» и последним «ложится»:

| Фаза | Порядок |
|------|---------|
| Enter | `controller:onEnter` → `manifest.onEnter` |
| Leave | `manifest.onLeave` → `controller:onLeave` |

---

## 5. Параметры и `onEnter(scene, params)`

Второй аргумент `:change(name, params)` попадает в оба хука:

```lua
-- scenes/game.lua
return {
  controller = "scenes.game_ctrl",
  resources = { ... },
  scene = { ... },

  onEnter = function(scene, params)
    print("start level", params.level, "difficulty", params.difficulty)
  end,
}
```

```lua
-- scenes/game_ctrl.lua
local Game = Class{ init = function(self) self.level = 1 end }

function Game:onEnter(scene, params)
  self.level      = params.level or 1
  self.difficulty = params.difficulty or "normal"
  self.scoreLabel = scene:byId("hud.score")
end

return Game
```

Используйте `params` для передачи ID уровня, имени предыдущей сцены (для условной анимации входа), сложности — любого контекста, который нельзя/не хочется хранить в глобалях.

---

## 6. Форвардинг Love2D-событий

Методы менеджера форвардят события в активную сцену **только когда `state == "active"`**:

```lua
-- псевдокод изнутри манифеста менеджера
manager.mousepressed = function(self, x, y, b, t)
  if self._state == "loading" then return end
  if self._current then self._current:__mousepressed(x, y, b, t) end
  if self._currentController and self._currentController.mousepressed then
    self._currentController:mousepressed(x, y, b, t)
  end
end
```

Порядок для событий:

| Хук | Порядок |
|-----|---------|
| `update(dt)` | `controller:update` → `scene:__update` |
| `draw()` | `scene:__draw` → `controller:draw` |
| `mouse*/key*` | `scene:__<event>` → `controller:<event>` |

Зачем такой порядок:

- `update` — контроллер может готовить состояние перед обновлением дерева (таймеры, AI).
- `draw` — контроллер рисует **поверх** сцены (оверлеи, дебаг-инфа).
- `input` — кнопки и `SEInputController` внутри дерева поглощают событие первыми; контроллер получает «сырое» событие как catch-all, если оно не было поглощено.

Все методы контроллера опциональны. Если не объявлены — просто не вызываются.

---

## 7. Контроллер сцены и менеджер

Контроллер — основной способ хранить состояние, которое живёт столько, сколько сцена. Менеджер даёт к нему удобный доступ:

```lua
-- внешний код
manager:currentController()          --> instance | nil
manager:currentName()                --> "game"   | nil
manager:current()                    --> root scene | nil
```

Пример: главный игровой цикл обращается к контроллеру для паузы.

```lua
function love.keypressed(k, scancode, isrepeat)
  manager:keypressed(k, scancode, isrepeat)  -- прокидываем в сцену
  if k == "escape" then
    local ctrl = manager:currentController()
    if ctrl and ctrl.togglePause then ctrl:togglePause() end
  end
end
```

Внутри сцены на методы контроллера ссылаются через `@self:method`:

```lua
{ type = "SSpriteButton", event = "@self:restart", states = "btn_restart" }
```

См. разделы [SESceneLoader.md §11 «Контроллер сцены»](./SESceneLoader.md#11-контроллер-сцены) для детального описания контроллеров.

---

## 8. Общие ресурсы через `"common"` слот

Менеджер трогает только слот `"scene"` внутри `SEEnvironment`. Всё, что пушнули в `"common"`, живёт всё время работы приложения:

```lua
function love.load()
  require("se3")

  -- один раз на старте
  local common = SLoader.new()
  common:addAtlas("atlases.common", "assets/common/")
  common:addFont ("main", "assets/font.ttf", 32)
  common:loadAll()
  SEEnvironment:setLoader(common, "common")

  -- готовый love.Font (например, дефолтный):
  local default = SLoader.new()
  default:putFont("default", love.graphics.newFont(14))
  SEEnvironment:setLoader(default, "default")

  manager = SESceneManager.new()
  manager:register("menu", "scenes.menu")
  manager:register("game", "scenes.game")
  manager:change("menu")
end
```

Любая сцена, у которой в манифесте нет своего шрифта `"main"`, возьмёт его из `"common"` — `SEEnvironment` ищет по слотам сверху вниз.

Сцены без `resources` **очищают** слот `"scene"` (это важное поведение: переход с «тяжёлой» сцены на «голую» иначе лик залипал бы старый лоадер). Слоты кроме `"scene"` не трогаются вообще.

---

## 9. Handler-ы, которые переживают переключение

`manager:loader()` — это общий для всех сцен `SESceneLoader`. Handler-ы, зарегистрированные на нём, видны всем манифестам:

```lua
-- main.lua, один раз
manager:loader():registerHandler("nav.play",  function() manager:change("game")  end)
manager:loader():registerHandler("nav.lobby", function() manager:change("lobby") end)
manager:loader():registerHandler("nav.shop",  function() manager:change("shop")  end)
```

В манифесте:

```lua
-- любая сцена
{ include = "prefabs.button",
  params = { label = "PLAY", event = "@nav.play" } }
```

Handler-ы, которые нужны **только** внутри одной сцены, всё равно подключайте через `handlers = { "..." }` в её манифесте или положите их методами на контроллер и дёргайте через `@self:method`.

---

## 10. Кастомный прогресс-бар

Дефолтный «NN%» в центре — нормальное начало, но часто хочется картинку с логотипом и анимированной полосой. Передайте функцию отрисовки:

```lua
manager:setLoadingDraw(function(progress, manager)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()

  -- фон
  love.graphics.setColor(0.08, 0.08, 0.12, 1)
  love.graphics.rectangle("fill", 0, 0, w, h)

  -- полоса
  local barW, barH = 400, 20
  local bx, by = (w - barW) / 2, h - 80
  love.graphics.setColor(0.2, 0.2, 0.25, 1)
  love.graphics.rectangle("fill", bx, by, barW, barH)
  love.graphics.setColor(0.4, 0.8, 1.0, 1)
  love.graphics.rectangle("fill", bx, by, barW * progress, barH)

  -- процент
  love.graphics.setColor(1, 1, 1, 1)
  local text = ("Loading %d%%"):format(math.floor(progress * 100 + 0.5))
  love.graphics.print(text, bx, by - 22)

  -- название следующей сцены можно вытянуть так:
  -- manager._pendingName  (внутреннее поле, не гарантируется стабильным)
end)
```

Для более сложного прогресс-бара с анимированным логотипом, smoothing-ом и переходами см. отдельный гайд:

→ [CustomPreloader.md](./CustomPreloader.md)

Настройка количества шагов в кадре:

```lua
manager:setStepsPerFrame(8)   -- по умолчанию 4
```

Больше шагов → быстрее загрузка, но дольше один кадр (возможны фризы). Меньше → плавнее, но загрузка тянется дольше.

---

## 11. Standalone microapp pattern

Сцена, у которой есть свой `scene_description.lua` **и** свой `main.lua`, запускается независимо:

```
modules/scenes/foo/
├── main.lua                  -- входная точка микроприложения
├── conf.lua                  -- window config
├── scene_description.lua     -- манифест
├── scene.lua                 -- контроллер
├── shared/
│   └── se3 → /path/to/se3    -- симлинк на движок
└── assets/
    ├── bg.png
    └── ui/...
```

`main.lua` такой сцены:

```lua
-- modules/scenes/foo/main.lua
package.path = "shared/?/init.lua;shared/?.lua;" .. package.path
require("se3")

function love.load()
  manager = SESceneManager.new()
  manager:register("scene", "scene_description")   -- путь без точек → пустой префикс
  manager:change("scene")
end

function love.update(dt)              manager:update(dt)              end
function love.draw()                  manager:draw()                  end
function love.mousemoved(x,y,dx,dy,t) manager:mousemoved(x,y,dx,dy,t) end
function love.mousepressed(x,y,b,t)   manager:mousepressed(x,y,b,t)   end
function love.mousereleased(x,y,b,t)  manager:mousereleased(x,y,b,t)  end
function love.keypressed(k,s,r)       manager:keypressed(k,s,r)       end
function love.keyreleased(k)          manager:keyreleased(k)          end
```

Запуск: `love modules/scenes/foo`. Каталог сцены становится корнем Love-проекта; пути в манифесте (`controller = "scene"`, `path = "assets/bg.png"`) резолвятся верно.

Тот же `scene_description.lua`, вмонтированный в родительский проект:

```lua
-- project-root/main.lua
manager:register("foo", "modules.scenes.foo.scene_description")
manager:change("foo")
```

Менеджер видит точки в пути и автоматически префиксует все `require` и fs-пути внутри манифеста. Одна сцена — два режима запуска, без изменений.

---

## 12. Полный пример: лобби ↔ игра ↔ магазин

### Структура проекта

```
mygame/
├── main.lua
├── scenes/
│   ├── lobby.lua
│   ├── game.lua
│   ├── game_ctrl.lua
│   └── shop.lua
├── prefabs/
│   └── nav_button.lua
├── handlers/
│   └── audio.lua
└── assets/
    ├── common/         -- общий атлас
    ├── lobby.png
    ├── game.png
    └── shop.png
```

### `main.lua`

```lua
require("se3")

function love.load()
  -- Общие ассеты (живут весь процесс)
  local common = SLoader.new()
  common:addAtlas("atlases.common", "assets/common/")
  common:addFont ("main", "assets/font.ttf", 32)
  common:loadAll()
  SEEnvironment:setLoader(common, "common")

  manager = SESceneManager.new()

  -- Навигационные handler-ы — один раз, доступны везде
  local L = manager:loader()
  L:registerHandler("nav.lobby", function() manager:change("lobby") end)
  L:registerHandler("nav.game",  function() manager:change("game", { level = 1 }) end)
  L:registerHandler("nav.shop",  function() manager:change("shop") end)
  L:registerHandler("nav.quit",  function() love.event.quit() end)

  -- Симпатичный прогресс-бар
  manager:setLoadingDraw(function(p)
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1, 1)
    local bw, bh = 500, 16
    love.graphics.rectangle("line", (w-bw)/2, h/2 - bh/2, bw, bh)
    love.graphics.rectangle("fill", (w-bw)/2, h/2 - bh/2, bw * p, bh)
    love.graphics.printf(("%d%%"):format(math.floor(p*100+0.5)),
                         0, h/2 + 14, w, "center")
  end)

  manager:register("lobby", "scenes.lobby")
  manager:register("game",  "scenes.game")
  manager:register("shop",  "scenes.shop")

  manager:change("lobby")
end

function love.update(dt)              manager:update(dt)              end
function love.draw()                  manager:draw()                  end
function love.mousemoved(x,y,dx,dy,t) manager:mousemoved(x,y,dx,dy,t) end
function love.mousepressed(x,y,b,t)   manager:mousepressed(x,y,b,t)   end
function love.mousereleased(x,y,b,t)  manager:mousereleased(x,y,b,t)  end
function love.keypressed(k,s,r)       manager:keypressed(k,s,r)       end
function love.keyreleased(k)          manager:keyreleased(k)          end
```

### `prefabs/nav_button.lua`

```lua
return function(p)
  return {
    type   = "SSpriteButton",
    x      = p.x or 0,
    y      = p.y or 0,
    states = p.states or "btn_main",
    font   = "main",
    text   = p.label or "",
    event  = p.event,
  }
end
```

### `scenes/lobby.lua`

```lua
return {
  resources = {
    images = { { name = "bg_lobby", path = "assets/lobby.png" } },
  },

  scene = {
    type = "SGroup", x = 960, y = 540,
    { type = "SSprite", img = "bg_lobby" },
    { type = "SText", font = "main", text = "LOBBY", y = -360 },

    { include = "prefabs.nav_button",
      params = { label = "PLAY",  event = "@nav.game", y = -60 }, id = "btn_play" },
    { include = "prefabs.nav_button",
      params = { label = "SHOP",  event = "@nav.shop", y =  20 }, id = "btn_shop" },
    { include = "prefabs.nav_button",
      params = { label = "QUIT",  event = "@nav.quit", y = 100 }, id = "btn_quit" },
  },
}
```

### `scenes/game.lua` + `scenes/game_ctrl.lua`

```lua
-- scenes/game.lua
return {
  controller = "scenes.game_ctrl",

  resources = {
    images = { { name = "bg_game", path = "assets/game.png" } },
  },

  scene = {
    type = "SGroup", x = 960, y = 540,
    { type = "SSprite", img = "bg_game" },
    { type = "SText", id = "level_label", font = "main", text = "", y = -400 },
    { type = "SText", id = "score",       font = "main", text = "score: 0", y = -340 },

    { include = "prefabs.nav_button",
      params = { label = "BACK", event = "@nav.lobby", y = 400 } },

    { type = "SSpriteButton",
      states = "btn_main", font = "main", text = "+1", y = 200,
      event = "@self:addScore" },
  },

  onLeave = function(scene, manager)
    print("leaving game, final score:", manager:currentController().score)
  end,
}
```

```lua
-- scenes/game_ctrl.lua
local Game = Class{ init = function(self) self.score = 0 end }

function Game:onEnter(scene, params)
  self.level     = params.level or 1
  self.score     = 0
  self.labelLbl  = scene:byId("level_label")
  self.scoreLbl  = scene:byId("score")
  self.labelLbl:setText("LEVEL " .. self.level)
end

function Game:addScore()
  self.score = self.score + 1
  self.scoreLbl:setText("score: " .. self.score)
end

function Game:update(dt)  -- love-style hook, форвардится менеджером
  self.elapsed = (self.elapsed or 0) + dt
end

function Game:keypressed(key)
  if key == "space" then self:addScore() end
end

return Game
```

### `scenes/shop.lua`

```lua
return {
  resources = {
    images = { { name = "bg_shop", path = "assets/shop.png" } },
  },

  scene = {
    type = "SGroup", x = 960, y = 540,
    { type = "SSprite", img = "bg_shop" },
    { type = "SText", font = "main", text = "SHOP", y = -360 },
    { include = "prefabs.nav_button",
      params = { label = "BACK", event = "@nav.lobby", y = 400 } },
  },
}
```

Любая кнопка в любой сцене переключает сцены через общий handler `@nav.*`. Ресурсы каждой сцены живут только пока сцена активна, а общий атлас — весь процесс. Между сценами поддерживается состояние (score) через контроллер; хук `onLeave` может записать его в сохранялку перед выходом.

---

## 13. API Reference

### Конструкция

```lua
SESceneManager.new(opts)
```

| Ключ | Умолчание | Что делает |
|------|-----------|-----------|
| `opts.loader` | `SESceneLoader.new()` | использовать готовый лоадер вместо создания нового |
| `opts.stepsPerFrame` | `4` | сколько ассетов обрабатывать за один `update` во время загрузки |
| `opts.loadingDraw` | — | функция `function(progress, manager)` для отрисовки прогресса |

### Регистрация

```lua
manager:register(name, path)   --> self   -- name → require-путь манифеста
manager:loader()               --> SESceneLoader  -- общий лоадер
```

### Переключение

```lua
manager:change(name, params)   --> bool   -- true если переход стартовал
```

Возвращает `false`, если:
- Менеджер уже в `loading` (текущий переход не завершён).

Бросает `error`, если:
- Имя сцены не зарегистрировано.

### Состояние

```lua
manager:current()              --> SObject | nil   -- корень активной сцены
manager:currentName()          --> string | nil    -- имя из реестра
manager:currentController()    --> instance | nil  -- контроллер активной сцены
manager:isLoading()            --> bool            -- true пока идёт загрузка
manager:progress()             --> number          -- 0..1 во время загрузки, 1 иначе
```

### Настройка загрузки

```lua
manager:setLoadingDraw(fn)     --> self   -- fn(progress, manager)
manager:setStepsPerFrame(n)    --> self
```

### Love2D callbacks

```lua
manager:update(dt)
manager:draw()
manager:mousemoved(x, y, dx, dy, istouch)
manager:mousepressed(x, y, button, istouch)
manager:mousereleased(x, y, button, istouch)
manager:keypressed(key, scancode, isrepeat)
manager:keyreleased(key)
```

Все они безопасны в любом состоянии — события, прилетевшие во время `loading`, просто игнорируются; во время `idle` — тоже (`self._current == nil`).

---

## См. также

- [SESceneLoader.md](./SESceneLoader.md) — подробно про манифесты, контроллеры и `@`-ссылки.
- [CustomPreloader.md](./CustomPreloader.md) — как сделать красивый прогресс-бар с анимацией.
- `sescenemanager.lua` — исходник (250 строк, читается быстро).
