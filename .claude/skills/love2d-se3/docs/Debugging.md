# Debugging — Extended Guide

Как понять, что происходит в сцене, когда что-то идёт не так. Набор простых инструментов — код, который вы добавляете в проект для ускорения цикла «проблема → решение».

SE3 не имеет встроенного debug-overlay или инспектора. Но дерево сцены — это обычная Lua-структура, легко обходимая и визуализируемая.

---

## Оглавление

1. [Печать дерева сцены](#1-печать-дерева-сцены)
2. [Визуализация bounding-box-ов](#2-визуализация-bounding-box-ов)
3. [Overlay с FPS, stats, tree size](#3-overlay-с-fps-stats-tree-size)
4. [Live-reload манифеста](#4-live-reload-манифеста)
5. [Пошаговая инспекция узла](#5-пошаговая-инспекция-узла)
6. [Отладка событий](#6-отладка-событий)
7. [Поиск утечек подписок](#7-поиск-утечек-подписок)
8. [Отладка трансформов](#8-отладка-трансформов)
9. [Flip-flop между состояниями](#9-flip-flop-между-состояниями)
10. [Хоткеи для dev-режима](#10-хоткеи-для-dev-режима)

---

## 1. Печать дерева сцены

Быстрая функция «покажи всё, что в сцене»:

```lua
-- debug/tree.lua
local function printTree(node, depth)
  depth = depth or 0
  local prefix = string.rep("  ", depth)
  local cls = "SObject"
  -- хампа класса в экземпляре не видно, но можно проверить через getmetatable.
  -- Проще — по характерным полям:
  if node.img then cls = "SSprite"
  elseif node.text then cls = "SText"
  elseif node.states then cls = "SButton"
  elseif node.zchilds then cls = "SGroup"
  end
  local info = string.format("%s[%s] id=%s pos=(%.0f,%.0f) size=(%.0f,%.0f)%s%s",
    prefix, cls, tostring(node.id or "-"),
    node.x, node.y, node.w, node.h,
    node.off and " OFF" or "",
    node.eventoff and " EVOFF" or "")
  print(info)
  for _, c in ipairs(node.childs or {}) do
    printTree(c, depth + 1)
  end
end

return printTree
```

Использование:

```lua
local printTree = require("debug.tree")
printTree(scene)
```

Вывод:

```
[SGroup] id=- pos=(960,540) size=(0,0)
  [SSprite] id=- pos=(0,0) size=(1920,1080)
  [SGroup] id=hud pos=(0,-420) size=(0,0)
    [SSprite] id=hp_icon pos=(0,0) size=(40,40)
    [SText] id=hp_label pos=(50,0) size=(120,32)
  [SButton] id=btn_play pos=(0,100) size=(200,80)
    [SSprite] id=- pos=(0,0) size=(200,80)
    [SSprite] id=- pos=(0,0) size=(200,80) OFF
```

### Расширенная версия с фильтром

```lua
local function printTree(node, depth, filter)
  depth = depth or 0
  if filter and not filter(node) then return end
  -- ... остальное
  for _, c in ipairs(node.childs or {}) do
    printTree(c, depth + 1, filter)
  end
end

-- Показать только узлы с id:
printTree(scene, 0, function(n) return n.id ~= nil end)
```

---

## 2. Визуализация bounding-box-ов

Добавить debug-отрисовку рамок после нормального рендера:

```lua
-- debug/drawBoxes.lua
local function drawBoxes(node, depth, color)
  if node.off or node.hidden then return end
  local minX, minY, maxX, maxY = node:getBoundingBox()
  love.graphics.setColor(unpack(color or {0, 1, 0, 0.4}))
  love.graphics.rectangle("line", minX, minY, maxX - minX, maxY - minY)
  love.graphics.setColor(1, 1, 1, 1)
  for _, c in ipairs(node.childs or {}) do
    drawBoxes(c, (depth or 0) + 1, color)
  end
end

return drawBoxes
```

В main:

```lua
function love.draw()
  manager:draw()
  if DEBUG then
    require("debug.drawBoxes")(manager:current())
  end
end
```

### Цветной boxes по типу

```lua
local function drawBoxesTyped(node)
  if node.off then return end
  local color
  if node.states then color = {1, 1, 0, 0.5}          -- кнопка — жёлтый
  elseif node.img then color = {0, 1, 0, 0.3}         -- спрайт — зелёный
  elseif node.text then color = {0, 0.5, 1, 0.5}      -- текст — синий
  else color = {1, 1, 1, 0.2}                          -- группа — серый
  end
  local minX, minY, maxX, maxY = node:getBoundingBox()
  love.graphics.setColor(color)
  love.graphics.rectangle("line", minX, minY, maxX - minX, maxY - minY)
  love.graphics.setColor(1, 1, 1, 1)
  for _, c in ipairs(node.childs or {}) do drawBoxesTyped(c) end
end
```

---

## 3. Overlay с FPS, stats, tree size

```lua
-- debug/overlay.lua
local function countNodes(node)
  local n = 1
  for _, c in ipairs(node.childs or {}) do n = n + countNodes(c) end
  return n
end

local Overlay = {}

function Overlay.draw(sceneRoot)
  local stats = love.graphics.getStats()
  local fps   = love.timer.getFPS()
  local dt    = love.timer.getAverageDelta() * 1000
  local nodes = sceneRoot and countNodes(sceneRoot) or 0
  local mem   = collectgarbage("count")   -- KB

  local lines = {
    string.format("FPS: %d (%.2f ms)", fps, dt),
    string.format("Draws: %d  Switches: %d", stats.drawcalls, stats.canvasswitches),
    string.format("Images: %d  Canvas: %d  Fonts: %d", stats.images, stats.canvases, stats.fonts),
    string.format("VRAM: %.1f MB", stats.texturememory / 1024 / 1024),
    string.format("Lua:  %.1f MB", mem / 1024),
    string.format("Nodes: %d", nodes),
  }

  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.rectangle("fill", 0, 0, 280, #lines * 18 + 10)
  love.graphics.setColor(1, 1, 0.5, 1)
  for i, line in ipairs(lines) do
    love.graphics.print(line, 6, (i - 1) * 18 + 4)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Overlay
```

Использование:

```lua
local Overlay = require("debug.overlay")

function love.draw()
  manager:draw()
  if DEBUG then Overlay.draw(manager:current()) end
end
```

---

## 4. Live-reload манифеста

Во время разработки удобно менять `scene_description.lua` и сразу видеть результат, не перезапуская игру.

```lua
-- В main.lua:
function love.keypressed(key, ...)
  manager:keypressed(key, ...)
  if DEBUG and key == "f5" then reloadCurrent() end
end

function reloadCurrent()
  local name = manager:currentName()
  if not name then return end
  local path = manager._scenes[name]   -- приватное поле, но для dev-режима OK
  package.loaded[path] = nil

  -- сбросить также компоненты и префабы, если они менялись:
  for k in pairs(package.loaded) do
    if k:match("^scenes%.")   or
       k:match("^widgets%.")  or
       k:match("^prefabs%.")  or
       k:match("^handlers%.") then
      package.loaded[k] = nil
    end
  end

  manager:change(name, { reloaded = true })
end
```

Теперь F5 перезагружает текущую сцену. Минус — теряется in-memory state (score, позиции). Если важно сохранить — выгружайте state в `onLeave`, загружайте в `onEnter`.

### Reload без смены сцены (только манифест)

`SESceneLoader:read(path, reload)` с `reload=true` обойдёт кэш. Но всё остальное (components, handlers) останется cached. Для «полного» перезагрузочного цикла — см. код выше.

---

## 5. Пошаговая инспекция узла

Когда нужно понять «почему этот узел ведёт себя странно»:

```lua
-- debug/inspect.lua
local function inspect(node, indent)
  indent = indent or "  "
  for _, key in ipairs({"x", "y", "z", "r", "sx", "sy", "w", "h",
                        "off", "eventoff", "hidden", "color", "alpha",
                        "__over", "__pressed", "disable",
                        "img", "text", "id"}) do
    local v = node[key]
    if v ~= nil then
      if type(v) == "table" then
        print(indent .. key .. " = {" ..
              table.concat({tostring(v[1]), tostring(v[2]),
                            tostring(v[3]), tostring(v[4])}, ", ") .. "}")
      else
        print(indent .. key .. " = " .. tostring(v))
      end
    end
  end
  print(indent .. "childs = " .. #(node.childs or {}))
  print(indent .. "parent = " .. tostring(node.parent and node.parent.id or "nil"))
end

return inspect
```

Использование:

```lua
local inspect = require("debug.inspect")
inspect(scene:byId("hud.hp"))
-- или
inspect(manager:current().childs[1])
```

### Инспектор с hot-key: печатаем узел под курсором

```lua
function love.keypressed(key)
  manager:keypressed(key)
  if DEBUG and key == "f12" then
    local mx, my = love.mouse.getPosition()
    local node = findNodeAtPoint(manager:current(), mx, my)
    if node then inspect(node) end
  end
end

function findNodeAtPoint(node, mx, my, depth)
  -- грубая версия: проверяем bounding box
  for i = #(node.childs or {}), 1, -1 do
    local c = node.childs[i]
    if not c.off then
      local minX, minY, maxX, maxY = c:getBoundingBox()
      if mx >= minX and my >= minY and mx < maxX and my < maxY then
        return findNodeAtPoint(c, mx, my, (depth or 0) + 1) or c
      end
    end
  end
end
```

F12 в точке курсора → напечатает узел под ним.

---

## 6. Отладка событий

Простой logger, подписанный на Signal:

```lua
if DEBUG then
  Signal.register("click", function(name)
    print("[click]", name)
  end)
  Signal.register("input", function(handler, action, phase)
    print(string.format("[input] %s (%s/%s)", handler, action, phase))
  end)
  Signal.register("animation.stop", function(sp)
    print("[anim.stop]", tostring(sp.id or sp))
  end)
end
```

Это покажет все UI-клики, input-actions и завершённые анимации. В console-е моментально видно, что произошло.

### Трассировка mousepressed по дереву

Если подозреваете, что событие «съедается» не тем узлом:

```lua
-- один раз в dev-режиме:
local original = SObject.__mousepressed
function SObject:__mousepressed(mx, my, button, istouch, x, y, r, sx, sy, used)
  local was = used
  local result = original(self, mx, my, button, istouch, x, y, r, sx, sy, used)
  if result ~= was then
    print(string.format("mousepressed consumed by: %s (id=%s)",
      tostring(self), tostring(self.id or "-")))
  end
  return result
end
```

Каждый узел, изменивший `used` с false на true, будет напечатан. Хак, но эффективный.

---

## 7. Поиск утечек подписок

После нескольких переходов между сценами клики стреляют по 2, 3, 5 раз — значит, `Signal.register` вызывался без `Signal.remove`.

```lua
-- debug/signals.lua
local function countSubs(signal)
  local n = 0
  for _ in pairs(Signal[signal] or {}) do n = n + 1 end
  return n
end

local function printAllSubs()
  for signal, fns in pairs(Signal) do
    if type(fns) == "table" then
      local n = 0
      for _ in pairs(fns) do n = n + 1 end
      if n > 0 then
        print(string.format("%-30s %d", signal, n))
      end
    end
  end
end

return { countSubs = countSubs, printAllSubs = printAllSubs }
```

Использование:

```lua
local dbg = require("debug.signals")
print("before change:")
dbg.printAllSubs()

manager:change("other")
-- ... подождать загрузки ...

print("after change:")
dbg.printAllSubs()
```

Если число подписчиков растёт — есть утечка. Найдите, кто регистрирует без парного `remove`.

---

## 8. Отладка трансформов

Пивоты, scale, rotation — самый частый источник «спрайт не там, где должен».

### Проверка точки-пивота

Нарисуйте маленький крестик в точке `(x, y)` узла:

```lua
local function drawPivots(node)
  if node.off then return end
  -- узел не имеет cached.x/y до render-а, но после первого кадра — есть
  if node.cache then
    love.graphics.setColor(1, 0, 1, 1)
    love.graphics.line(node.cache.x - 5, node.cache.y, node.cache.x + 5, node.cache.y)
    love.graphics.line(node.cache.x, node.cache.y - 5, node.cache.x, node.cache.y + 5)
    love.graphics.setColor(1, 1, 1, 1)
  end
  for _, c in ipairs(node.childs or {}) do drawPivots(c) end
end
```

`node.cache` появляется после `cacheCoords` — то есть после того, как узел был хотя бы раз рендерен через `SGroup.__draw`. Для узлов, рендеренных напрямую через `__draw`, кэша не будет.

Для гарантированной точки — вычисляйте трансформ вручную:

```lua
local function worldPos(node)
  local x, y = 0, 0
  local cur = node
  while cur do
    x = x + cur.x
    y = y + cur.y
    cur = cur.parent
  end
  return x, y
end
```

Приближённо: без учёта поворотов и масштабов (для этого есть `transform`), но для быстрого sanity check — сойдёт.

### Поиск невидимых спрайтов

Спрайт есть, но не виден. Частые причины и способы проверить:

```lua
local function diagnose(node)
  if node.off then print("off = true"); return end
  if node.hidden then print("hidden = true"); return end
  local minX, minY, maxX, maxY = node:getBoundingBox()
  if maxX == minX or maxY == minY then
    print("zero-sized bounding box")
    print("w, h =", node.w, node.h)
  end
  local w, h = love.graphics.getWidth(), love.graphics.getHeight()
  if maxX < 0 or maxY < 0 or minX > w or minY > h then
    print("outside screen")
    print("box:", minX, minY, maxX, maxY)
  end
  if node.color and node.color[4] == 0 then print("alpha = 0") end
end

diagnose(scene:byId("missing_sprite"))
```

---

## 9. Flip-flop между состояниями

Если `SAnimatedObject` зависает в странном состоянии или состояния переключаются не так, как вы ожидаете:

```lua
-- внедряем логгинг
local original = SAnimatedObject.setState
function SAnimatedObject:setState(name, opts)
  print(string.format("[setState] %s → %s", tostring(self._currentState), tostring(name)))
  return original(self, name, opts)
end
```

Это запишет каждый переход в лог. Уберите в продакшне.

---

## 10. Хоткеи для dev-режима

```lua
-- main.lua
function love.keypressed(key, scancode, isrepeat)
  manager:keypressed(key, scancode, isrepeat)
  if not DEBUG then return end

  if     key == "f1"  then printTree(manager:current())
  elseif key == "f2"  then require("debug.signals").printAllSubs()
  elseif key == "f3"  then DEBUG_BOXES = not DEBUG_BOXES
  elseif key == "f5"  then reloadCurrent()
  elseif key == "f12" then inspectAtCursor()
  end
end

function love.draw()
  manager:draw()
  if DEBUG_BOXES then require("debug.drawBoxes")(manager:current()) end
  if DEBUG       then require("debug.overlay").draw(manager:current()) end
end
```

| Хоткей | Действие |
|--------|---------|
| F1 | печать дерева |
| F2 | печать подписок Signal |
| F3 | toggle bounding boxes |
| F5 | reload текущей сцены |
| F12 | inspect узла под курсором |

### Флаг `DEBUG`

```lua
-- main.lua или conf.lua
DEBUG = love.filesystem.getInfo("dev.flag") ~= nil
```

Если в папке проекта есть файл `dev.flag` (любой пустой файл), DEBUG = true. В production-билде файла нет, DEBUG = false. Или:

```lua
DEBUG = arg and lume.any(arg, function(a) return a == "--dev" end)
-- запуск: love . --dev
```

---

## Типовые проблемы и чем их выявить

| Проблема | Как выявить |
|----------|-------------|
| Спрайт не виден | `diagnose(node)` — проверка off/hidden/alpha/размеров |
| Клик не срабатывает | logger на mousepressed, проверка `self.__over`, позиции `inBox` |
| Несколько кликов на один | `printAllSubs()` — утечка Signal-подписок |
| Плохой FPS | Overlay с drawcalls, количеством узлов |
| Неправильный цвет | Inspect `color` — убедитесь, что компоненты в 0..1 (или HEX-строка); старые значения 0..255 больше не поддерживаются |
| Кнопка не меняет состояние | Проверка `self.states` — есть ли нужный state, или fallback на release |
| Память растёт | `collectgarbage("count")` до/после смены сцены |
| Странное поведение анимации | Log в `setState`, проверка длительностей scripts |

---

## Дисциплина debug-кода

Debug-код в репозитории — отдельная папка `debug/` (не путать с lua built-in `debug`). Импортируется **только** в dev-режиме. В релиз-билде либо удалять папку при сборке, либо условно требовать:

```lua
-- main.lua
if DEBUG then
  require("debug.setup")    -- устанавливает хоткеи, подписывает логгеры
end
```

И `debug/setup.lua` настраивает всё остальное. Так ни один debug-вызов не оказывается в проде случайно.

---

## См. также

- [Performance.md](./Performance.md) — метрики и способы их собрать.
- [Architecture.md](./Architecture.md) — где размещать debug-код.
- [Signals.md §3](./Signals.md#3-регистрация-и-отписка) — первопричины утечек подписок.
- [EventPropagation.md §3](./EventPropagation.md#3-флаг-used) — что съедает события.
