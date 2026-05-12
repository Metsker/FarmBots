# Custom Preloader with Progress Bar

Гайд по созданию собственного прогресс-бара для загрузки сцен. Покрывает три варианта сложности — от «полосочки на `love.graphics.rectangle`» до полноценного прелоадер-экрана с плавной анимацией и логотипом.

Основа — `SESceneLoader:preload()` или `SESceneManager:setLoadingDraw()`. И там, и там работаем с **handle**-объектом, у которого есть `:step()`, `:progress()`, `:done()`, `:build()`.

---

## Оглавление

1. [Как работает отложенная загрузка](#1-как-работает-отложенная-загрузка)
2. [Вариант 1: прогресс-бар без менеджера (`:preload()`)](#2-вариант-1-прогресс-бар-без-менеджера-preload)
3. [Вариант 2: прогресс-бар с менеджером (`setLoadingDraw`)](#3-вариант-2-прогресс-бар-с-менеджером-setloadingdraw)
4. [Вариант 3: отдельная «сцена-прелоадер» с анимацией](#4-вариант-3-отдельная-сцена-прелоадер-с-анимацией)
5. [Сглаживание прогресса](#5-сглаживание-прогресса)
6. [Общие ассеты для прогресс-бара](#6-общие-ассеты-для-прогресс-бара)
7. [Сколько ассетов грузить за кадр](#7-сколько-ассетов-грузить-за-кадр)
8. [Частые ошибки](#8-частые-ошибки)

---

## 1. Как работает отложенная загрузка

`SESceneLoader:load()` — блокирующий: читает манифест, грузит всё подряд через `SLoader:loadAll()`, строит дерево. Во время вызова Love-окно зависает.

`SESceneLoader:preload()` разбивает этот пайплайн на две фазы:

1. **Preload-фаза** (вызов `:preload()`): манифест прочитан, `components`/`handlers` зарегистрированы, ресурсы **поставлены в очередь** в `SLoader`. Ничего не загружено, дерево не построено.
2. **Step-фаза** (вы вызываете `handle:step()` по одному в кадр): загрузка ассетов по одному. Между шагами кадр отрисовывается — в этот момент и рисуете прогресс-бар.
3. **Build-фаза** (`handle:build()` когда `:done()`): дозагрузка остатков + регистрация в `SEEnvironment` + сборка дерева + `onEnter`. Идемпотентно.

```
preload()  →  { manifest, assets(queued), ... }
                 │
                 ├─ step()  \
                 ├─ step()   │  вы сами выбираете
                 ├─ step()   │  сколько шагов за кадр
                 ├─ ...     /
                 │
                 └─ done() == true
                      │
                      └─ build() → scene
```

**API handle-объекта:**

| Метод | Возвращает | Комментарий |
|-------|-----------|-------------|
| `handle:step()` | `bool` | загружает один ассет; `true` когда очередь пуста |
| `handle:progress()` | `0..1` | доля загруженного; `1` если ассетов нет |
| `handle:done()` | `bool` | `true` когда очередь пуста |
| `handle:build()` | `scene` | финализация; idempotent — повторно вернёт тот же `scene` |
| `handle.manifest` | `table` | распарсенный манифест (доступен сразу) |
| `handle.assets` | `SLoader` \| `nil` | `SLoader` с ресурсами в очереди |

---

## 2. Вариант 1: прогресс-бар без менеджера (`:preload()`)

Полностью ручной режим. Годится когда в проекте одна сцена или вы не хотите заводить менеджер.

```lua
-- main.lua
require("se3")

local state = "loading"       -- "loading" | "ready"
local preload, scene

function love.load()
  preload = SESceneLoader.new():preload("scenes.main")
end

function love.update(dt)
  if state == "loading" then
    -- 4 шага за кадр — компромисс скорости и плавности
    for _ = 1, 4 do
      if preload:step() then break end
    end
    if preload:done() then
      scene   = preload:build()
      preload = nil
      state   = "ready"
    end
    return
  end

  scene:__update(dt)
end

function love.draw()
  if state == "loading" then
    drawProgressBar(preload:progress())
    return
  end
  scene:__draw()
end

-- Простой прогресс-бар: рамка + заливка + процент
function drawProgressBar(p)
  local w, h  = love.graphics.getWidth(), love.graphics.getHeight()
  local bw, bh = 500, 20
  local x, y  = (w - bw) / 2, h / 2 - bh / 2

  love.graphics.setColor(0.1, 0.1, 0.12, 1)
  love.graphics.rectangle("fill", 0, 0, w, h)

  love.graphics.setColor(0.3, 0.3, 0.35, 1)
  love.graphics.rectangle("line", x, y, bw, bh)
  love.graphics.setColor(0.4, 0.8, 1.0, 1)
  love.graphics.rectangle("fill", x, y, bw * p, bh)

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(("%d%%"):format(math.floor(p * 100 + 0.5)),
                       0, y - 24, w, "center")
end

-- Прокидывание Love2D-событий только когда сцена готова:
local function gate(fn)
  return function(...)
    if state == "ready" then fn(...) end
  end
end

love.mousemoved    = gate(function(...) scene:__mousemoved(...)    end)
love.mousepressed  = gate(function(...) scene:__mousepressed(...)  end)
love.mousereleased = gate(function(...) scene:__mousereleased(...) end)
love.keypressed    = gate(function(...) scene:__keypressed(...)    end)
love.keyreleased   = gate(function(...) scene:__keyreleased(...)   end)
```

**Почему 4 шага за кадр.** `SLoader:step()` выполняет одну I/O-операцию — один `love.graphics.newImage`, один `love.audio.newSource` и т.д. Тяжёлые — atlas-texture (большие PNG). Если делать 1 шаг на кадр, сцена с 30 ассетами будет грузиться полсекунды на 60 FPS. 4 шага на кадр сокращает это до ~125 мс, но может вызвать единичный джиттер. Подберите опытным путём.

---

## 3. Вариант 2: прогресс-бар с менеджером (`setLoadingDraw`)

Если вы уже используете `SESceneManager` — он сам управляет циклом загрузки, а вам остаётся только перерисовать бар. Переопределите `draw`-функцию через `:setLoadingDraw(fn)`:

```lua
manager:setLoadingDraw(function(progress, manager)
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()

  love.graphics.setColor(0.05, 0.05, 0.08, 1)
  love.graphics.rectangle("fill", 0, 0, w, h)

  local bw, bh = 600, 14
  local bx, by = (w - bw) / 2, h - 120

  -- рамка
  love.graphics.setColor(1, 1, 1, 0.3)
  love.graphics.rectangle("line", bx - 2, by - 2, bw + 4, bh + 4)

  -- заливка
  love.graphics.setColor(1, 0.8, 0.2, 1)
  love.graphics.rectangle("fill", bx, by, bw * progress, bh)

  -- проценты
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(
    ("Loading %s... %d%%"):format(manager._pendingName or "", math.floor(progress*100+0.5)),
    0, by - 32, w, "center"
  )
end)
```

По умолчанию менеджер рисует центрированное «NN%». `manager:progress()` всегда доступен, возвращает 1 если загрузки нет. `manager:setStepsPerFrame(n)` — управление скоростью загрузки.

---

## 4. Вариант 3: отдельная «сцена-прелоадер» с анимацией

Хочется, чтобы прелоадер сам был сценой — со спрайтами, анимированным логотипом, бэкграундом. Идея: сделать `"loading"` отдельной лёгкой сценой с минимумом ресурсов (чтобы она сама загружалась мгновенно), а реальную сцену грузить «вручную» через `:preload()`, пока прелоадер-сцена живёт.

### Структура

```
mygame/
├── main.lua
├── scenes/
│   ├── loader.lua           -- сцена-прелоадер (лёгкая, быстрая)
│   ├── loader_ctrl.lua      -- контроллер: знает про preload-handle
│   ├── game.lua
│   └── menu.lua
├── prefabs/
│   └── progress_bar.lua
└── assets/
    ├── common/              -- общий атлас (логотип, шрифт, полоса)
    ├── game_heavy.png
    └── menu_bg.png
```

### Общие ассеты — один раз

```lua
-- main.lua
require("se3")

function love.load()
  -- Общий атлас (лого, шрифт, текстура полосы) — грузится синхронно до всего
  local common = SLoader.new()
  common:addAtlas("atlases.common", "assets/common/")
  common:addFont ("main", "assets/font.ttf", 24)
  common:loadAll()
  SEEnvironment:setLoader(common, "common")

  -- Прелоадер-цепочка: кого грузить, куда переходить
  _G.LoadNext = { target = nil, params = nil }

  manager = SESceneManager.new()

  local L = manager:loader()
  L:registerHandler("nav.menu", function()
    _G.LoadNext.target = "menu"; manager:change("loader")
  end)
  L:registerHandler("nav.game", function()
    _G.LoadNext.target = "game"; manager:change("loader")
  end)

  manager:register("loader", "scenes.loader")
  manager:register("menu",   "scenes.menu")
  manager:register("game",   "scenes.game")

  manager:change("loader")   -- стартуем с прелоадера
end
```

### Сцена-прелоадер: `scenes/loader.lua`

```lua
return {
  controller = "scenes.loader_ctrl",
  -- Никаких resources: всё, что нужно, берём из слота "common"
  scene = {
    type = "SGroup", x = 960, y = 540,

    { type = "SSprite", img = "logo", y = -120, id = "logo" },

    -- фон полосы
    { type = "SStretchedSprite", img = "bar_bg", w = 600, h = 16, y = 200 },

    -- заливка полосы — контроллер меняет её sx в update
    { type = "SStretchedSprite", img = "bar_fill", w = 600, h = 16,
      pivot = {0, 0.5}, x = -300, y = 200, id = "fill", sx = 0 },

    { type = "SText", font = "main", text = "", y = 240, id = "percent" },
  },
}
```

### Контроллер: `scenes/loader_ctrl.lua`

```lua
local Loader = Class{ init = function(self) self.progress = 0 end }

function Loader:onEnter(scene, params)
  self.scene   = scene
  self.fill    = scene:byId("fill")
  self.percent = scene:byId("percent")
  self.logo    = scene:byId("logo")
  self.elapsed = 0
  self.displayed = 0           -- сглаженный прогресс

  -- Стартуем preload целевой сцены
  local target = _G.LoadNext.target
  local path   = manager:_scenes and manager._scenes[target]
                 or error("loader: unknown target '" .. tostring(target) .. "'")
  local reqPrefix  = path:match("^(.*%.)[^.]+$") or ""   -- greedy: до последней точки
  local pathPrefix = reqPrefix:gsub("%.", "/")

  self.preload = manager:loader():preload(path, {
    params        = _G.LoadNext.params,
    requirePrefix = reqPrefix,
    pathPrefix    = pathPrefix,
  })
  self.targetName = target
end

function Loader:update(dt)
  self.elapsed = self.elapsed + dt

  -- Step загрузки — 4 ассета за кадр
  for _ = 1, 4 do
    if self.preload:step() then break end
  end

  -- Смужённый прогресс: догоняем реальный с экспоненциальным замедлением
  local real = self.preload:progress()
  self.displayed = self.displayed + (real - self.displayed) * math.min(1, dt * 5)

  self.fill.sx = self.displayed
  self.percent:setText(("%d%%"):format(math.floor(self.displayed * 100 + 0.5)))

  -- Покачивание лого
  self.logo.r = math.sin(self.elapsed * 2) * 0.05

  -- Готово? Строим сцену и переключаемся
  if self.preload:done() and self.displayed >= 0.995 then
    local scene = self.preload:build()
    -- build() уже прогнал setLoader в слот "scene";
    -- чтобы не поломать менеджер, «продадим» ему состояние напрямую:
    manager._preload         = nil
    manager._state           = "active"
    manager._current         = scene
    manager._currentManifest = self.preload.manifest
    manager._currentController = self.preload.controller
    manager._currentName     = self.targetName

    self.preload = nil
  end
end

return Loader
```

> **Предупреждение.** Последний шаг этого варианта (`manager._preload = nil` и так далее) опирается на внутренние поля `SESceneManager`. Это работает, но хрупко: изменение менеджера поломает его.
>
> Чище — оставить `SESceneManager` заниматься своей обычной работой (через `:change()`), а «декоративный» экран вынести в слой выше. Следующий раздел показывает более консервативный паттерн: использовать **встроенный** `setLoadingDraw`, но **нарисовать в нём полноценную сцену**, а не прямоугольники.

### Альтернатива: `setLoadingDraw` + мини-сцена

Соберите сцену-оверлей один раз на старте, а в `setLoadingDraw` обновляйте её и рисуйте:

```lua
-- main.lua
function love.load()
  require("se3")

  -- Общий слот
  local common = SLoader.new()
  common:addAtlas("atlases.common", "assets/common/")
  common:addFont ("main", "assets/font.ttf", 24)
  common:loadAll()
  SEEnvironment:setLoader(common, "common")

  manager = SESceneManager.new()
  manager:register("menu", "scenes.menu")
  manager:register("game", "scenes.game")

  -- Строим лоадер-оверлей императивно один раз — он сам не является "сценой"
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  loadingOverlay = SGroup{ x = w/2, y = h/2,
    SSprite{ img = "logo", y = -120, id = "logo" },
    SStretchedSprite{ img = "bar_bg",   w = 600, h = 16, y = 200 },
    SStretchedSprite{ img = "bar_fill", w = 600, h = 16, y = 200,
                      pivot = {0, 0.5}, x = -300, sx = 0 },
    SText{ font = "main", text = "", y = 240 },
  }
  loadingOverlay._fill    = loadingOverlay.childs[3]
  loadingOverlay._percent = loadingOverlay.childs[4]
  loadingOverlay._logo    = loadingOverlay.childs[1]
  loadingOverlay._elapsed = 0
  loadingOverlay._display = 0

  manager:setLoadingDraw(function(progress)
    local dt = love.timer.getDelta()
    local o  = loadingOverlay
    o._elapsed = o._elapsed + dt
    o._display = o._display + (progress - o._display) * math.min(1, dt * 5)

    o._fill.sx   = o._display
    o._percent:setText(("%d%%"):format(math.floor(o._display * 100 + 0.5)))
    o._logo.r    = math.sin(o._elapsed * 2) * 0.05

    love.graphics.setColor(0.05, 0.05, 0.08, 1)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    love.graphics.setColor(1, 1, 1, 1)
    o:__draw()
  end)

  manager:change("menu")
end
```

Этот паттерн:

- Не трогает внутренности менеджера.
- Использует всю мощь SE3-сцены для отрисовки оверлея (анимации, pivot, child-ы).
- Хранит «прелоадер-сцену» отдельно от `_current`, поэтому не ломает состояние.

Единственная тонкость — оверлей **должен** опираться только на ресурсы из слота `"common"` (или собранные императивно Love-объекты), потому что слот `"scene"` в момент отрисовки может быть уже заменён или пуст.

---

## 5. Сглаживание прогресса

Реальный `progress()` скачет рывками (каждый `step()` — +1/total). Полоса выглядит некрасиво: стоит — рывок — стоит. Классический трюк — отдельно держать `displayed` и догонять им настоящее значение:

```lua
local real = handle:progress()
-- экспоненциальное сглаживание: скорость ~ 5 единиц в секунду
displayed = displayed + (real - displayed) * math.min(1, dt * 5)
```

Выше `5` → быстрее догоняет, меньше сглаживания. `2–3` — «тягучая» полоса, хорошо выглядит на быстрых загрузках. `10+` — почти мгновенная реакция.

Обычно завершают переход не по `progress == 1`, а по `displayed >= 0.995`, чтобы финальный рывок полосы не обрезался.

---

## 6. Общие ассеты для прогресс-бара

Главная ловушка прогресс-бара: **сам прогресс-бар нужно чем-то рисовать.**

Варианты:

- **love.graphics.rectangle + стандартный шрифт**. Ноль ассетов, работает всегда. Скучно.
- **Слот `"common"`**, загруженный синхронно на старте `love.load()` до первого `change()`. 1-2 маленьких картинки и шрифт — загружается за 10-20 мс, после чего можно показать красивый прогресс-бар для всех последующих сцен.
- **Отдельная микро-сцена «loader»** с минимальным `resources` (логотип + текстура полосы), загружающаяся быстро. Усложняет навигацию — см. предостережения в §4.

Рекомендация: **слот `"common"`**. Кладите туда всё, что нужно прогресс-бару и другим UI-элементам, которые разделены между сценами.

---

## 7. Сколько ассетов грузить за кадр

Менеджер по умолчанию делает 4 шага за кадр. Подберите число в зависимости от размера ассетов:

- Мелкие PNG (≤ 256×256), короткие OGG, атласы на одну текстуру — **8-16**.
- Крупные атласы (4k+), длинные streamed-звуки уже грузятся лениво — **4-8**.
- 8k атласы, несколько больших текстур за раз — **2-4**.

Критерий: если во время загрузки прогресс-бар заметно дёргается (кадр просаживается до 20 FPS), уменьшайте. Если загрузка тянется «секундами пустой полосы» — увеличивайте.

```lua
manager:setStepsPerFrame(8)
```

Для ручного режима (`:preload()` + свой цикл) — меняйте `for _ = 1, N` в `update`.

---

## 8. Частые ошибки

### 1. Забыли вызвать `build()`

`preload()` возвращает handle, но **не строит дерево**. Если в `update` проверять только `done()` и не вызывать `build()`, у вас никогда не будет сцены.

```lua
if handle:done() then
  scene = handle:build()    -- ОБЯЗАТЕЛЬНО
end
```

### 2. `build()` вызван, но `SEEnvironment` не синхронизирован

Это происходит, если прошли `opts.env = false` и забыли вручную зарегистрировать лоадер в `SEEnvironment`. Внутри конструктора `SSprite` дёргает `resource:get(name)` и получает `nil` — `w`/`h` нули, пивот схлопывается.

Правильно: оставить `opts.env` по умолчанию **или** сделать `SEEnvironment:setLoader(handle.assets, "scene")` до вызова `build(... { env = false })`.

### 3. События обрабатываются в `loading`

Если просто вызывать `scene:__mousepressed(...)` без проверки — во время загрузки `scene == nil` → краш, либо идёт форвардинг в старую сцену, которой уже нет. `SESceneManager` делает это проверкой внутри `proxy()`. В ручном режиме — gate-обёртка (см. §2).

### 4. Два `:change()` подряд

```lua
manager:change("game")
manager:change("shop")    -- возвращает false, игнорируется
```

Менеджер не поддерживает очередь переходов. Если нужно — сохраните намерение в поле и сделайте переход из `onEnter` следующей сцены, либо реализуйте очередь в своём коде.

### 5. Build вызывается повторно

`handle:build()` **идемпотентен**: повторные вызовы возвращают один и тот же `scene`, **не** пересобирают дерево и **не** вызывают `onEnter` второй раз. Это полезно как fallback («если очередь не пуста — дочерпай и построй»), но значит: если вы хотите «перезагрузить сцену», вы должны сделать новый `:preload()`, а не второй `:build()`.

### 6. Handle живёт дольше, чем надо

После `build()` объект `handle` больше не нужен — `handle.assets` уже передан `SEEnvironment`. Держать ссылку на `handle` — не ошибка, но мешает GC. В примерах я занулил `preload = nil`; так и делайте.

---

## См. также

- [SESceneLoader.md](./SESceneLoader.md) — полное описание лоадера и манифестов.
- [SESceneManager.md](./SESceneManager.md) — роутер между сценами.
- `seloader.lua` — исходник `SLoader` (100 строк, смотрится легко — понятно, что именно делает `step()`).
