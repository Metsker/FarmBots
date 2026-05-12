# SESceneLoader — Extended Guide

`SESceneLoader` превращает декларативный Lua-**манифест** (обычную Lua-таблицу) в живое дерево `SObject`-ов. Это основная точка входа в проектах SE3, где интерфейс и логика сцены разбиты на несколько файлов, а не собираются императивно в одном месте.

Файл с реализацией: `sescene.lua`.

---

## Оглавление

1. [Чем лоадер отличается от императивной сборки](#1-чем-лоадер-отличается-от-императивной-сборки)
2. [Минимальный пример](#2-минимальный-пример)
3. [Структура манифеста](#3-структура-манифеста)
4. [Ресурсы](#4-ресурсы)
5. [Типы узлов и дерево](#5-типы-узлов-и-дерево)
6. [Prefab-ы через `include`](#6-prefab-ы-через-include)
7. [Идентификаторы, пути и `byId`/`byPath`](#7-идентификаторы-пути-и-byidbypath)
8. [`@`-ссылки — декларативные колбэки](#8--ссылки--декларативные-колбэки)
9. [Кастомные компоненты](#9-кастомные-компоненты)
10. [Handler-ы](#10-handler-ы)
11. [Контроллер сцены](#11-контроллер-сцены)
12. [Хуки `onEnter` / `onLeave`](#12-хуки-onenter--onleave)
13. [Префиксы путей — переносимые сцены](#13-префиксы-путей--переносимые-сцены)
14. [Отложенная загрузка — `preload()`](#14-отложенная-загрузка--preload)
15. [API Reference](#15-api-reference)
16. [Порядок разрешения и тонкости](#16-порядок-разрешения-и-тонкости)

---

## 1. Чем лоадер отличается от императивной сборки

Императивный стиль:

```lua
local scene = SGroup{ x = 960, y = 540,
  SSprite{ img = "bg" },
  SSpriteButton{ states = "play", event = "start" },
}
```

Это работает отлично для маленьких сцен. Но как только появляется:

- Десяток кнопок по одному шаблону с разными подписями.
- UI, который хочется редактировать отдельно от логики.
- Несколько сцен с общими виджетами.
- Загрузка ресурсов «на сцену», а не «на игру».

императивный стиль начинает разъезжаться. Лоадер даёт:

- **Одну точку входа для всей сцены** (имя модуля).
- **Отдельную секцию ресурсов** — они подгружаются вместе со сценой и выгружаются при переходе.
- **Prefab-ы** — переиспользуемые поддеревья, параметризованные таблицей `params`.
- **Декларативные `@`-ссылки** — события привязываются к методам узлов без Lua-замыканий.
- **`byId`/`byPath`** — именованный доступ к узлам.
- **Контроллер сцены** — класс с состоянием и хуками жизненного цикла.

---

## 2. Минимальный пример

Структура проекта:

```
mygame/
├── main.lua
├── scenes/
│   └── main.lua              -- манифест
└── assets/
    ├── bg.png
    └── main.ttf
```

Манифест:

```lua
-- scenes/main.lua
return {
  resources = {
    images = { { name = "bg", path = "assets/bg.png" } },
    fonts  = { { name = "main", path = "assets/main.ttf", size = 32 } },
  },

  scene = {
    type = "SGroup", x = 960, y = 540,
    children = {
      { type = "SSprite", img = "bg" },
      { type = "SText",   font = "main", text = "Hello, SE3" },
    },
  },
}
```

Точка входа:

```lua
-- main.lua
require("se3")

function love.load()
  _G.scene = SESceneLoader.new():load("scenes.main")
end

function love.update(dt)              scene:__update(dt)              end
function love.draw()                  scene:__draw()                  end
function love.mousemoved(x,y,dx,dy,t) scene:__mousemoved(x,y,dx,dy,t) end
function love.mousepressed(x,y,b,t)   scene:__mousepressed(x,y,b,t)   end
function love.mousereleased(x,y,b,t)  scene:__mousereleased(x,y,b,t)  end
function love.keypressed(k,s,r)       scene:__keypressed(k,s,r)       end
function love.keyreleased(k)          scene:__keyreleased(k)          end
```

`:load()` делает всю работу: читает манифест, ставит ресурсы в `SLoader`, прогоняет `loadAll()`, регистрирует лоадер в `SEEnvironment` (чтобы `resource:get` работал во время сборки дерева), и строит дерево.

---

## 3. Структура манифеста

Манифест — это Lua-модуль, возвращающий одну таблицу. Все поля, кроме `scene`, опциональны.

```lua
return {
  name       = "main_menu",      -- cosmetic, только для сообщений об ошибках
  controller = "scenes.main",    -- путь к модулю контроллера (optional)
  components = { ... },          -- пользовательские классы
  handlers   = { ... },          -- именованные функции
  resources  = { ... },          -- атласы / картинки / шрифты / звуки
  scene      = { ... },          -- корень дерева (обязательно)

  onEnter = function(scene, params) end,
  onLeave = function(scene, manager) end,
}
```

Разделы обрабатываются в порядке: `components` → `handlers` → `resources` → `build`. Причина важна — см. [§16](#16-порядок-разрешения-и-тонкости).

---

## 4. Ресурсы

Каждая категория — список; лоадер проталкивает записи в `SLoader`.

```lua
resources = {
  atlases = {
    { require = "atlases.ui",  path = "assets/ui/"  },
    { require = "atlases.sym", path = "assets/sym/" },
  },
  spineAtlases = {
    { path = "assets/spine/sym_cherry_win.atlas" },
  },
  spineSkeletons = {
    { name = "mega_win",
      skeleton = "assets/mega_win.json",
      atlas    = "assets/popups_fire.atlas",
      scale    = 0.6 },
  },
  images = {
    { name = "bg",  path = "assets/bg.png"  },
    { name = "log", path = "assets/logo.png" },
  },
  fonts = {
    { name = "main",  path = "assets/main.ttf", size = 32 },
    { name = "small", path = "assets/main.ttf", size = 18 },
  },
  sounds = {
    { name = "click", path = "assets/click.ogg" },
    { name = "bgm",   path = "assets/bgm.ogg", stream = true },  -- streamed
  },
}
```

**Что важно:**

- `atlases[].require` — Lua `require`-путь к файлу TexturePacker-атласа.
- `atlases[].path` — каталог, из которого атлас грузит свои текстуры.
- `spineSkeletons` — скелеты Spine 4.2 под логическими именами; плеер ссылается на имя через `{ type = "SESpinePlayer", spine = "mega_win" }`. Подробно — в [SESpinePlayer.md](./SESpinePlayer.md).
- `sounds[].stream = true` → источник типа `"stream"` (для музыки), иначе `"static"`.
- Все пути префиксуются `pathPrefix`/`requirePrefix` сцены (либо пусты для standalone-запуска). Префикс обходится символом `!` в начале пути.
- `:load()` автоматически регистрирует получившийся `SLoader` в слот `"scene"` `SEEnvironment`. Это обязательно, иначе `resource:get(name)` при конструкции спрайтов вернёт `nil`, и расчёт размеров/пивота сломается.

---

## 5. Типы узлов и дерево

Каждый узел — таблица, где `type` выбирает класс из реестра лоадера, а остальные поля становятся props-таблицей.

```lua
scene = {
  type = "SGroup", x = 960, y = 540,
  children = {
    { type = "SSprite", img = "bg" },
    { type = "SText",   font = "main", text = "Hello" },
    { type = "SGroup",  x = 100, y = 100, children = {
        { type = "SSprite", img = "icon" },
    }},
  }
}
```

Детей можно объявлять либо через `children = {…}`, либо как массивную часть таблицы:

```lua
scene = {
  type = "SGroup", x = 960, y = 540,
  { type = "SSprite", img = "bg" },
  { type = "SText",   font = "main", text = "Hello" },
}
```

Оба варианта работают одинаково и соответствуют props-таблицам движка.

**Вложенные узлы в нестандартных полях.** Лоадер рекурсивно обходит props-таблицы и собирает любое поддерево, где встречает `{type=…}`. Это позволяет декларативно описывать состояния кнопки:

```lua
{ type = "SSpriteButton", x = 0, y = 0,
  states = {
    release = { type = "SSprite", img = "btn_release" },
    over    = { type = "SSprite", img = "btn_over"    },
    press   = { type = "SSprite", img = "btn_press"   },
  },
}
```

Таблицы с метатаблицей (то есть уже построенные инстансы, которые вы вручную вставили в манифест) пропускаются как есть; таблицы без `type` (`color = {1, 0, 0, 1}`, `pivot = {0.5, 0.5}`) копируются без изменений.

### Декларативные spine followers — `followers = {...}`

Поле `followers` на любой ноде, у которой есть метод `:player()` (то есть `SAnimatedSpine`), привязывает SObject-ы к bone'ам/slot'ам скелета **через манифест** — без ручных `replaceSlot`/`attachToBone` в `scene.lua:onEnter`.

```lua
{ type = "SAnimatedSpine", id = "popup",
  spine = "you_win",
  states = { ... },
  followers = {
    -- replaceSlot вариант (slot field): прячет native attachment + пришивает SObject
    { slot = "_numbers", id = "popup_amount",
      inheritAlpha = true,    -- skeleton.a × slot.color.a → text.color[4] на draw
      offsetX = 0, offsetY = -10,
      type = "SText", font = "popup_amount",
      text = "$amountText",   -- $-bind как у обычной ноды
      pivot = {0.5, 0.5}, color = "#ffffff",
    },
    -- attachToBone вариант (bone field): без подмены slot'а, просто follow bone
    { bone = "head", offsetY = -8,
      type = "SSprite", img = "crown" },

    -- replaceSlot + bone override: скрыть baked attachment слота "$",
    -- но следовать за совсем другим bone (например, "popup_all" с scale-
    -- таймлайном на всю плашку). Используется, когда родная кость слота-
    -- источника root-parented и не имеет нужной scale/translate анимации.
    { slot = "$", bone = "popup_all",
      type = "SText", text = "$amountText", y = 122 },
  },
}
```

Каждая запись в `followers[]`:
1. Должна содержать **хотя бы одно** из `slot = "..."` (→ `replaceSlot` — прячет attachment слота и follows bone слота) или `bone = "..."` (→ `attachToBone` — просто follows bone, ничего не скрывает). **Можно указать оба** одновременно: `slot` + `bone` означает «скрыть attachment слота `slot`, но following-кость взять из `bone`» (override slot.bone). Loader выбросит ошибку, только если ни одного не указано.
2. **Meta-поля** (опционально): `offsetX/offsetY`, `keepRotation/keepScale`, `inheritAlpha`. Лоадер вынимает их и кладёт в opts для `replaceSlot`/`attachToBone` (см. `SESpinePlayer.md`).
3. **Остальные поля** (`type`, `id`, `font`, `text`, `color`, `pivot`, `x`, `y`, …) — обычный node-descriptor: лоадер билдит follower через `_buildNode`, регистрирует id в `byId` (если есть), резолвит `$key`-биндинги, добавляет ноду как ребёнка spine'ы.
4. `off = true` ставится **автоматически** на follower'е — без этого нода рисовалась бы и через scene-graph child-iter, и через follower-путь (двойная отрисовка).

**Imperative API (`replaceSlot`/`attachToBone` в scene.lua) сохраняется** — обе формы взаимозаменяемы, можно смешивать в одной сцене.

---

## 6. Prefab-ы через `include`

Prefab — Lua-модуль, возвращающий **функцию** `params → node table`. Всё переиспользуемое (кнопки, диалоги, HUD-элементы) выносится в отдельные файлы.

```lua
-- prefabs/button.lua
return function(p)
  return {
    type   = "SSpriteButton",
    x      = p.x or 0,  y = p.y or 0,
    states = p.states or "btn_main",
    font   = "main",
    text   = p.label or "",
    event  = p.event,
  }
end
```

Использование:

```lua
children = {
  { include = "prefabs.button",
    params = { label = "PLAY", event = "start_game", y = -40 },
    id = "btn_play" },
  { include = "prefabs.button",
    params = { label = "QUIT", event = "quit", y = 40 },
    id = "btn_quit" },
}
```

**Поля на `include`-узле перекрывают вывод префаба.** Всё, что лежит рядом с `include` кроме `include` и `params` (например, `id`, `x`, `y`, `z`, разовый `color`), дописывается в таблицу, которую вернул prefab. Это позволяет давать id и позицию без прокидывания через `params`.

**Композиция префабов.** Prefab может содержать `include` внутри себя, а также принимать поддеревья через `params`:

```lua
-- prefabs/dialog.lua
return function(p)
  return {
    type = "SGroup", x = p.x or 0, y = p.y or 0,
    children = {
      { type = "SStretchedSprite", img = "dialog_bg", w = p.w, h = p.h },
      { type = "SText", font = "main", text = p.title, y = -p.h/2 + 30 },
      p.body,                                              -- слот
      { type = "SGroup", y = p.h/2 - 60, children = p.actions or {} },
    },
  }
end
```

Использование:

```lua
{ include = "prefabs.dialog", params = {
    w = 600, h = 400, title = "Выйти?",
    body = { type = "SText", text = "Прогресс сохранится", font = "small" },
    actions = {
      { include = "prefabs.button", params = { label = "ДА",  event = "quit",   x = -100 } },
      { include = "prefabs.button", params = { label = "НЕТ", event = "cancel", x =  100 } },
    },
}},
```

---

## 7. Идентификаторы, пути и `byId`/`byPath`

Любой узел может объявить `id`. Именованные предки образуют **скоупы**: вложенные id адресуются через точку, безымянные узлы прозрачны для пути.

```lua
scene = { type = "SGroup", id = "root",
  children = {
    { type = "SGroup", id = "hud",
      children = {
        { type = "SSprite", img = "hp_icon", id = "hp" },
        { type = "SGroup",                                 -- anonymous
          children = {
            { type = "SSprite", img = "mana_icon", id = "mana" },
          }},
      }},
  }}

scene:byPath("root.hud.hp")     --> SSprite
scene:byPath("root.hud.mana")   --> SSprite (промежуточный SGroup без id)
scene:byId  ("root.hud.hp")     -- то же
```

**Короткий синтаксис — `#name`.** Если строка начинается с `#`, остаток трактуется как простой id без точек и ищется по плоскому индексу, собранному на этапе `build`. Возвращается **самый верхний** (root-most) узел с таким id — с минимальной глубиной скоупа:

```lua
scene:byId("#hp")               -- то же, что scene:byPath("root.hud.hp")
scene:byId("#mana")             -- то же, что scene:byPath("root.hud.mana")
```

Идея — не прошивать в скриптах и контроллерах всю цепочку предков: переименование или перенос промежуточного скоупа (`hud`→`topbar`) не ломает потребителей. При равной глубине двух совпадений результат неопределён — если нужен конкретный узел из ветки, используйте полный `byPath("branch.label")`.

`#name` работает и внутри `@`-ссылок: `"@#hero:setState('hit')"` эквивалентно `scene:byId("#hero"):setState("hit")` при вызове. Правила те же: после `#` только простое имя, без точек; побеждает root-most.

`id` уникален **внутри своего скоупа** — коллизия падает ошибкой на этапе сборки.

Корень обычно оставляют без `id`, чтобы узлы верхнего уровня адресовались короткими путями (`"hero"` вместо `"root.hero"`).

`byId` / `byPath` доступны только на корне. Если нужна та же карта глубже в дереве — сохраняйте ссылку на корень или идите через `self.parent`.

---

## 8. `@`-ссылки — декларативные колбэки

Любая строка в дереве, начинающаяся с `@`, превращается в callable при сборке.

| Форма | Что делает |
|-------|-----------|
| `"@path.to.node:method"` | `node:method()` |
| `"@path.to.node:method()"` | то же |
| `"@path.to.node:method(1, 'hi')"` | `node:method(1, "hi")` — аргументы парсятся как Lua-литералы через `load()` |
| `"@#simple_id:method"` | `scene:byId("#simple_id"):method()` — root-most по простому id |
| `"@self:method"` | `controller:method()` — метод контроллера этой сцены |
| `"@handler.name"` | вызов зарегистрированного handler-а (без двоеточия) |

Ссылки резолвятся **лениво**, уже после сборки дерева — forward-references работают нормально. Пример:

```lua
-- кнопка объявлена раньше, чем hero, но ссылка разрешится
{ include = "prefabs.button",
  params = { label = "HIT", event = "@hero:setState('hit')" } },

-- ...

{ type = "SAnimatedObject", id = "hero", states = {...} },
```

**Ограничение.** Аргументы подставляются из литералов спецификации; varargs, которые пришли бы от вызывающей стороны, отбрасываются. Если нужны динамические аргументы — используйте handler.

---

## 9. Кастомные компоненты

Классы пользователя (наследники `SObject`) надо зарегистрировать, иначе `type = "MyClass"` упадёт с ошибкой. Это делается либо через `loader:register(name, class)`, либо декларативно в секции `components` манифеста.

```lua
-- game/widgets/health_bar.lua
local HealthBar = Class{ __includes = SObject,
  init = function(self, p)
    SObject.init(self, p)
    self.max   = p.max   or 100
    self.value = p.value or self.max
  end,
}

function HealthBar:setValue(v) self.value = v; self:refresh() end
function HealthBar:flash()     -- ...
end

return { name = "HealthBar", class = HealthBar }
```

Подключение в манифесте:

```lua
components = { "game.widgets.health_bar" },

scene = {
  type = "SGroup", children = {
    { type = "HealthBar", id = "hp", x = 100, max = 200 },
  },
}
```

Несколько классов из одного файла:

```lua
-- game/widgets/all.lua
return { components = {
  HealthBar = HealthBar,
  ManaBar   = ManaBar,
  MiniMap   = MiniMap,
}}
```

Регистрация «руками» (полезно для одноразовых виджетов):

```lua
loader:register("HealthBar", HealthBar)
```

---

## 10. Handler-ы

Handler — именованная функция, доступная из любого callback-поля через `"@name"`. Ставится отдельно от дерева сцены, чтобы Lua-логика не тянулась в файл манифеста.

```lua
-- game/handlers/menu.lua
return {
  name = "menu",
  handlers = {
    quit    = function() love.event.quit() end,
    restart = function() game.start() end,
  }
}
```

Поле `name` — префикс: модуль зарегистрирует `menu.quit` и `menu.restart`.

Использование:

```lua
handlers = { "game.handlers.menu" },

scene = {
  type = "SGroup", children = {
    { include = "prefabs.button",
      params = { label = "Quit", event = "@menu.quit" } },
  }
}
```

Альтернативные формы модуля (все три валидны):

```lua
-- 1. namespaced → "menu.quit"
return { name = "menu", handlers = { quit = fn, restart = fn } }

-- 2. flat → "quit"
return { handlers = { quit = fn, restart = fn } }

-- 3. плоская карта функций → "quit"
return { quit = fn, restart = fn }
```

Регистрация «руками»:

```lua
loader:registerHandler("menu.quit", function() love.event.quit() end)
```

---

## 11. Контроллер сцены

Когда handler-ов становится много и им нужно делить состояние между вызовами, переходите на **контроллер** — класс с собственными полями и методами, привязанный к сцене.

```lua
-- modules/scenes/slot_1/scene_description.lua
return {
  controller = "modules.scenes.slot_1.scene",
  resources = { ... },
  scene = {
    type = "SGroup",
    children = {
      { type = "SText",   id = "counter", font = "main", text = "clicks: 0" },
      { type = "SButton", event = "@self:tap",
        states = { release = { type = "SText", font = "main", text = "TAP" } } },
    },
  },
}
```

```lua
-- modules/scenes/slot_1/scene.lua
local Scene = Class{ init = function(self) self.clicks = 0 end }

function Scene:onEnter(root, params)
  self.counter = root:byId("counter")
  self.clicks  = 0
end

function Scene:onLeave(root, manager)  -- опционально
end

function Scene:tap()
  self.clicks = self.clicks + 1
  self.counter:setText("clicks: " .. self.clicks)
end

return Scene
```

Контроллер создаётся один раз при входе в сцену и живёт до выхода. Всё, что должно пережить сцену — в отдельный синглтон.

**Порядок хуков** — см. [§12](#12-хуки-onenter--onleave).

**Форматы модуля контроллера:**

- `Class{ init = ... }` (hump.class — таблица с `__call`) → `mod()` инстанциирует.
- Обычная функция → `mod()` как фабрика.
- Обычная таблица без метатаблицы → используется как есть (singleton-style).

**Контроллер как love-скрипт.** `SESceneManager` форвардит в контроллер методы `update(dt)`, `draw()`, `mousemoved`, `mousepressed`, `mousereleased`, `keypressed`, `keyreleased` — если они определены. Порядок:

| Метод | Порядок |
|-------|---------|
| `update(dt)` | контроллер → сцена (контроллер готовит состояние перед обновлением дерева) |
| `draw()` | сцена → контроллер (контроллер рисует оверлеи поверх) |
| `mouse*/key*` | сцена → контроллер (кнопки поглощают первыми, контроллер — catch-all) |

```lua
function Scene:update(dt) self.elapsed = (self.elapsed or 0) + dt end

function Scene:draw()
  love.graphics.print(("t = %.2fs"):format(self.elapsed), 12, 12)
end

function Scene:keypressed(key)
  if key == "space" then self:tap() end
end
```

---

## 12. Хуки `onEnter` / `onLeave`

Два опциональных хука, которые можно объявить как на уровне манифеста, так и на уровне контроллера.

```lua
return {
  onEnter = function(scene, params)
    -- вызовется сразу после сборки
  end,

  onLeave = function(scene, manager)
    -- вызовется перед выходом, только если переключает SESceneManager
  end,

  scene = { ... },
}
```

**Порядок (при работе с `SESceneManager`):**

- Вход: `controller:onEnter` → `manifest.onEnter`.
- Выход: `manifest.onLeave` → `controller:onLeave`.

Логика разделения: контроллер первым поднимает состояние, потом манифест может его прочитать. На выходе — наоборот, манифест ещё видит живой контроллер.

Если вы работаете напрямую через `:load()` (без менеджера), `onEnter` всё равно отработает — `:preload():build()` его вызывает. А вот `onLeave` вам придётся дёрнуть вручную при тирдауне.

---

## 13. Префиксы путей — переносимые сцены

Сцена, лежащая в подкаталоге большого проекта, обычно хочет ссылаться на свои же ассеты (`"assets/bg.png"`). Но эти имена резолвятся от корня проекта — если записать полный путь (`"modules/scenes/slot_1/assets/bg.png"`), сцена привязывается к своему местоположению и её нельзя запустить как standalone.

`SESceneLoader:preload(path, opts)` принимает два опционных префикса:

| Опция | Префиксуется к чему |
|-------|---------------------|
| `opts.requirePrefix` | `manifest.controller`, все `components`/`handlers`, все `include`-пути, `atlas.require` |
| `opts.pathPrefix`    | все фс-пути: `atlas.path`, `image.path`, `font.path`, `sound.path` |

`SESceneManager:change()` выводит оба префикса **автоматически** из зарегистрированного пути сцены:

```
"modules.scenes.slot_1.scene_description"
        ↓
requirePrefix = "modules.scenes.slot_1."
pathPrefix    = "modules/scenes/slot_1/"
```

Благодаря этому один и тот же `scene_description.lua` запускается и из родительского проекта, и как standalone-микроприложение:

```lua
-- Mounted в родительский проект:
manager:register("game", "modules.scenes.slot_1.scene_description")
manager:change("game")

-- Standalone (запуск `love modules/scenes/slot_1`):
manager:register("scene", "scene_description")   -- без точек → пустой префикс
manager:change("scene")
```

Подробнее см. [SESceneManager.md](./SESceneManager.md#standalone-microapp-pattern).

---

## 14. Отложенная загрузка — `preload()`

`:load()` — блокирующий пайплайн. Для прогресс-бара и прелоадеров используется `:preload()`, который возвращает **handle**:

```lua
local handle = loader:preload("scenes.main")

handle.manifest     -- распарсенный манифест
handle.assets       -- SLoader с ресурсами в очереди (или nil)
handle:step()       -- загрузить один ассет, вернёт true если очередь пуста
handle:progress()   -- 0..1
handle:done()       -- true если очередь пуста
handle:build()      -- собрать дерево; idempotent (повторный вызов — тот же scene)
```

См. отдельный гайд: [CustomPreloader.md](./CustomPreloader.md).

---

## 15. API Reference

### Конструкция и регистрация

```lua
SESceneLoader.new()                -- новый лоадер с преднабором классов SE3
loader:register(name, class)       -- зарегистрировать класс для type = "name"
loader:registerHandler(name, fn)   -- зарегистрировать handler для "@name"
loader:getClass(name)              -- поиск в реестре
loader:getHandler(name)            -- поиск handler-а
```

### Чтение манифеста

```lua
loader:read(path [, reload])       -- require(path); reload=true обходит package.loaded
```

### Ресурсы

```lua
loader:loadResources(manifest, slowLoader [, prefixes])
-- проталкивает manifest.resources в существующий SLoader;
-- вы сами вызываете :loadAll() или степпинг.
-- prefixes = { require = "...", path = "..." } (опц.)
```

### Сборка

```lua
loader:build(data [, controller [, prefixes]])
-- Построить дерево из уже готовой data-таблицы.
-- Без загрузки ресурсов и регистрации в SEEnvironment.
-- Возвращает root с прикрученными byId/byPath.
```

### Высокоуровневый пайплайн

```lua
local scene, manifest, assets, controller = loader:load(path [, opts])
```

Делает последовательно:
1. `require` манифеста (с `opts.reload` — обойти кэш).
2. Регистрирует `components`.
3. Регистрирует `handlers`.
4. Создаёт `SLoader` (или использует `opts.loader`), проталкивает `resources`, `:loadAll()`.
5. Регистрирует полученный `SLoader` в `SEEnvironment` (слот `opts.envName` или `"scene"`).
6. Строит дерево.
7. Вызывает `controller:onEnter` → `manifest.onEnter`.

**Опции:**

| Ключ | Умолчание | Что делает |
|------|-----------|-----------|
| `opts.loader`  | — | внешний `SLoader` для ресурсов (иначе создаётся автоматически если есть `resources`) |
| `opts.reload`  | `false` | обойти `package.loaded` для манифеста (hot-reload в dev-режиме) |
| `opts.env`     | `SEEnvironment` | куда регистрировать собранный `SLoader`; `false` — пропустить регистрацию |
| `opts.envName` | `"scene"` | имя слота в `env` |
| `opts.params`  | — | передаётся в `onEnter` (и manifest, и controller) |
| `opts.requirePrefix` | `""` | префикс к require-путям (controller, components, handlers, include, atlas.require) |
| `opts.pathPrefix`    | `""` | префикс к fs-путям (атласы, image/font/sound) |

Возвращает `(scene, manifest, assets, controller)`. `assets` — `nil` если в манифесте нет `resources`; `controller` — `nil` если нет `manifest.controller`.

### Отложенный пайплайн

```lua
local handle = loader:preload(path [, opts])
handle:step()      -- load one asset; true if queue empty
handle:progress()  -- 0..1
handle:done()      -- true if queue empty
handle:build()     -- finalise: loadAll + env register + build tree; idempotent
```

Опции те же, что у `:load()`. `handle:build()` — идемпотентный; повторные вызовы вернут тот же `scene`.

---

## 16. Порядок разрешения и тонкости

Последовательность проходов внутри `:load()`:

1. **Прочитать манифест** (`require(path)`).
2. **Зарегистрировать components** — реестр классов пополнен.
3. **Зарегистрировать handlers** — реестр handler-ов пополнен.
4. **Загрузить resources** в `SLoader`, опционально дёрнуть `:loadAll()`.
5. **Зарегистрировать `SLoader` в `SEEnvironment`** (если `opts.env` ≠ `false`) — чтобы `resource:get` работал во время сборки.
6. **Обойти дерево сцены** рекурсивно:
   - Развернуть `{include=...}` через вызов prefab-функции с `params`, смержить поля с include-сайта.
   - Для каждого `{type=...}` — найти класс, глубоко трансформировать props, собрать детей, инстанциировать.
   - Записать id-узлы в `byId` под полным скоупом.
   - Заменить `"@..."` строки на замыкания.
7. **Прошить `byId`-карту в замыкания** — ссылки теперь разрешаются.
8. **Вызвать `controller:onEnter` → `manifest.onEnter`.**

**Почему регистрация в `SEEnvironment` важна до шага 6.** Спрайты дергают `resource:get(name)` внутри своего `setImg`, а `setImg` вызывается из конструктора — то есть прямо во время сборки. Если лоадер не виден `resource` в этот момент, `w`/`h` читаются как `0`, смещения остаются дефолтными, а расчёт пивота схлопывается в `(0, 0)`: каждый спрайт рисуется из левого верхнего угла независимо от заданного `pivot`. Автоматическая регистрация это решает; `opts.env = false` ставьте только если сами подключаете другой `resource`.

**Два следствия порядка:**

- Prefab может ссылаться на класс из `components` — реестр заполнен до сборки.
- `"@node:method"` может форвард-референсить узел, объявленный ниже в дереве — замыкания резолвятся лениво.

**`:preload()` разрывает пайплайн:** шаги 1–3 плюс постановка в очередь (часть шага 4) происходят внутри `:preload()`; дренаж очереди, регистрация в env и сборка (шаги 4b, 5, 6–7) — внутри `handle:build()`. Всё между ними — в ваших руках.

### Guardrails внутри `_transformValue`

Защита, которую **не надо** убирать:

```lua
if getmetatable(v) then return v end
```

Это защита от глубокого обхода уже собранных `SObject`-инстансов, которые вы могли вручную вставить в манифест или в `params`. У plain-data таблиц метатаблицы нет; у инстансов — есть. Уберёте — лоадер пойдёт разбирать живой узел как data-таблицу и либо упадёт, либо пересоберёт его неправильно.

### Горячая перезагрузка

`opts.reload = true` сбрасывает `package.loaded[path]` только для манифеста. Подключённые им модули (`components`, `handlers`, prefab-ы) остаются закэшированы. Если хотите перезагрузить всю сцену целиком — вычистите их вручную:

```lua
for _, m in ipairs({ "prefabs.button", "game.widgets.health_bar" }) do
  package.loaded[m] = nil
end
scene = SESceneLoader.new():load("scenes.main", { reload = true })
```

---

## См. также

- [SESceneManager.md](./SESceneManager.md) — роутер между сценами.
- [CustomPreloader.md](./CustomPreloader.md) — кастомный прогресс-бар.
- Основной `README.md` — справочник по остальным классам движка.
