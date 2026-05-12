# Event Propagation — Extended Guide

Детальный разбор того, как события (`mouse*`, `key*`, `update`) ходят по дереву сцены, что делает флаг `used`, чем различаются `off` и `eventoff`, когда событие «съедается», и как писать свои объекты, которые правильно участвуют в этом потоке.

Источник: `seobject.lua` (функции `__mousemoved`, `__mousepressed`, `__mousereleased`, `__keypressed`, `__keyreleased`, `__update`, `__draw`, `__cacheCoords`).

---

## Оглавление

1. [Пара `__event` / `event`](#1-пара-__event--event)
2. [Маршрут события по дереву](#2-маршрут-события-по-дереву)
3. [Флаг `used`](#3-флаг-used)
4. [Порядок обхода детей](#4-порядок-обхода-детей)
5. [`off` vs `eventoff` vs `hidden`](#5-off-vs-eventoff-vs-hidden)
6. [Трансформация координат мыши](#6-трансформация-координат-мыши)
7. [Мышь поверх кнопок — кто победит](#7-мышь-поверх-кнопок--кто-победит)
8. [Клавиатура — глобальный характер](#8-клавиатура--глобальный-характер)
9. [Пишем свой event-тип](#9-пишем-свой-event-тип)
10. [Паттерны и антипаттерны](#10-паттерны-и-антипаттерны)

---

## 1. Пара `__event` / `event`

SE3 делит каждое событие на **два** метода:

| Метод | Роль |
|-------|------|
| `self:__eventname(...)` | **Внутренний** обход дерева. Добавляет трансформы, рекурсивно вызывает детей. Обычно не переопределяется. |
| `self:eventname(...)` | **Пользовательский** хук — реагируете на событие, получаете уже-трансформированные координаты. Переопределяется. |

Пример:

```lua
function SObject:__mousepressed(mx, my, button, istouch, x, y, r, sx, sy, used)
  local x,y,r,sx,sy, mx1, my1 = self:transformMouse(mx, my, x, y, r, sx, sy)
  if self.mousepressed then used = self:mousepressed(mx1, my1, button, istouch, used) end
  -- ... рекурсия в детей ...
end
```

`mx1, my1` — координаты мыши, трансформированные в **локальную** систему координат этого узла. Это то, что получает ваш `mousepressed` — тестируете на `inBox(mx1, my1)`, не надо вручную вычитать родительские смещения.

**Правило**: при создании своего класса переопределяйте `mousepressed` (`click`, `press`, `release`, `over`), **не** `__mousepressed`. Если переопределите внутренний — пропадёт рекурсия в детей, и вложенные кнопки перестанут работать.

---

## 2. Маршрут события по дереву

Любое событие проходит по одному шаблону (mousepressed в качестве примера):

```
love.mousepressed(x, y, button)
   │
   ▼
 scene:__mousepressed(x, y, button)           (корневой SObject)
   │
   ├─ transformMouse(…) → локальные координаты
   │
   ├─ if self.mousepressed → self:mousepressed(mx, my, button, istouch, used)
   │    (если нам самим интересно — отработали здесь)
   │
   └─ for each child in self.childs:
        if not child.off and not child.eventoff:
          used = child:__mousepressed(x, y, button, istouch, parentX, parentY, …, used)
```

Ключевые наблюдения:

- **Сначала обрабатывается сам узел**, потом дети. В отличие от «pre-order», где корни обрабатывались бы после листьев.
- **Дети получают тот же `used` и возвращают обновлённый.** Если child поставил `used = true`, следующие дети его видят.
- **Родитель не может отменить решение ребёнка.** Если ребёнок вернул `used = true`, родитель это не узнаёт до конца рекурсии (потому что `self:mousepressed` уже отработал).

Это отличается от многих DOM-фреймворков с capture/bubble фазами — у SE3 только одна фаза, pre-order.

---

## 3. Флаг `used`

`used` — булево значение, которое «путешествует» по дереву:

- **Начинается как `false` или `nil`** (разные события стартуют по-разному; обычно `nil`).
- **Любой обработчик может вернуть `true`**, сигнализируя «я съел это событие».
- **Следующие обработчики видят `used = true`** и обычно ничего не делают.

### Что делают встроенные классы

**SMouseObject** — уважает `used`:

```lua
function SMouseObject:mousepressed(x, y, button, istouch, used)
  if self.__over and not self.__pressed and not used then
    -- срабатывает только если used == false
    self.__pressed = true
    ...
    used = true
  end
  return used
end
```

То есть кнопка **не** регистрирует press, если выше по дереву что-то уже обработало это событие. И если сработала — **помечает** событие как использованное, чтобы нижестоящие кнопки не сработали тоже.

**SKeyboardObject** — тоже уважает:

```lua
if (self.clickByDown or self.triggerOn == "press") and not used and self.click then
  self:click()
end
```

### Когда возвращать `used = true`

- Кликнули на кнопку — дальше пусть никто не срабатывает.
- Модальное окно съедает все клики вне себя.
- Drag-handler перехватил движение — остальные mouse-слушатели не нужны.

### Когда **не** возвращать `used = true`

- Панель-контейнер, которая сама ни на что не реагирует — просто пропускает детям.
- Отладочный overlay, который хочет знать про события, но не мешать.
- Логгер: «запиши, что кликнули, но дай кнопке тоже сработать».

---

## 4. Порядок обхода детей

Дети обходятся **в порядке добавления** (`self.childs[1..N]`). Это значит:

```lua
SGroup{
  SSpriteButton{ states = "btn_a", event = "a" },   -- childs[1]
  SSpriteButton{ states = "btn_b", event = "b" },   -- childs[2]
}
```

Event приходит сначала `btn_a`, потом `btn_b`. Если `btn_a` «съел» событие (выставил `used = true`), `btn_b` не отреагирует.

### Но при **отрисовке** порядок — `z`!

```lua
SGroup{
  SSpriteButton{ states = "btn_a", event = "a", z = 0 },
  SSpriteButton{ states = "btn_b", event = "b", z = 10 },  -- рисуется поверх
}
```

Рендер — сверху вниз по `z` (z=10 рисуется позже → он визуально сверху). Но **события** идут по `childs[]`, не по `zchilds[]`. Это значит: даже если `btn_b` нарисован сверху, `btn_a` услышит клик раньше него.

**Это баг?** Нет, это сознательное решение — но проблема иногда вылезает. Если у вас перекрывающиеся кнопки с разным `z`, добавляйте их в нужном порядке:

```lua
-- Правильный вариант — сначала добавить то, что визуально снизу:
SGroup{
  SSpriteButton{ states = "btn_a", event = "a", z = 0 },
  SSpriteButton{ states = "btn_b", event = "b", z = 10 },
}
-- event обходит [a, b] → a получает первым.
-- Если b съедает (потому что курсор над ним), a не сработает.
```

Работает потому что `SMouseObject:mousepressed` проверяет `self.__over` — то есть «курсор внутри **этого** узла». И для `a`, и для `b` может быть `__over = true`, но `a` попробует первым.

Если кнопки не перекрываются физически — проблема не возникает.

Если перекрываются, и вы хотите «верхняя по `z` получает первой» — надо руками менять порядок в `childs` при добавлении (например, в `add` пересортировать childs тоже, как и `zchilds`). Из коробки этого нет.

---

## 5. `off` vs `eventoff` vs `hidden`

Три флага, три семантики:

### `off = true`

**Полностью отключает** узел и поддерево:

- `__draw` пропускает узел (и всех детей).
- `__mouse*` / `__key*` / `__update` пропускают узел (и всех детей).
- Не участвует в bounding box.

Используйте для:
- Скрытых UI-элементов, которые могут включиться.
- Выключение всей панели за один флаг.
- Состояний кнопки внутри `SButton` (каждое состояние — отдельный ребёнок, активен только `release.off = false`).

### `eventoff = true`

**Только события**: узел рисуется, но не получает mouse/key/update.

```lua
local decoration = SSprite{ img = "decorative_icon", eventoff = true }
```

Используйте для:
- Декоративных элементов — чтобы они не мешали клику на кнопке снизу.
- Overlay-ов, которые рисуются поверх игры, но не перехватывают события.
- Текстовых лейблов поверх интерактивных элементов.

### `hidden = true`

**Только отрисовка этого конкретного узла** — дети всё ещё рисуются.

```lua
-- Конкретно этот SSprite не рисуется, но дети его — да.
SSprite{ img = "bg", hidden = true, children = {
  SSprite{ img = "icon" }    -- всё равно нарисуется
}}
```

Используется редко — обычно для узлов, которые сами ничего не рисуют, но играют роль «контейнера» с трансформами.

### Сводная таблица

| Флаг | `draw` | `events` | `update` | `children draw` | `children events` |
|------|:------:|:--------:|:--------:|:---------------:|:-----------------:|
| none | ✓ | ✓ | ✓ | ✓ | ✓ |
| `off` | ✗ | ✗ | ✗ | ✗ | ✗ |
| `eventoff` | ✓ | ✗ | ✓ | ✓ | ✗ |
| `hidden` | ✗ | ✓ | ✓ | ✓ | ✓ |

(`update` под `eventoff` — интересная деталь: узел продолжает обновляться, даже если не получает событий. Но дети под `eventoff` **не** получают событий — потому что проверка в `__mousepressed` идёт `if not c.off and not c.eventoff`.)

---

## 6. Трансформация координат мыши

`transformMouse(mx, my, x, y, r, sx, sy)` — обратный трансформ. Принимает мир→экран параметры родителя и возвращает локальные координаты мыши:

```
global mouse (mx, my)
       │
       │ parent transform (x, y, r, sx, sy)
       ▼
local mouse (mx1, my1)   — готово для :inBox проверки
```

Что происходит:

1. Сначала идёт `self:transform(x, y, r, sx, sy)` — композиция с собственными `self.x/y/r`. Получаем мировой трансформ **этого** узла.
2. Затем `(mx - x) / sx, (my - y) / sy` — переводим в систему координат узла.
3. Через `toPolar / fromPolar` с обратным поворотом `-r` — убираем поворот.

Результат `mx1, my1` — координаты мыши в локальной системе координат узла, где `(0, 0)` = центр узла (если `pivot = {0.5, 0.5}`) или угол (если `pivot = {0, 0}`).

### Практика

Вы почти никогда не вызываете `transformMouse` сами. Когда пишете `mousepressed(mx, my, button, istouch, used)`, `mx, my` — **уже** локальные. Тестируйте на `inBox` и не думайте о трансформациях родителей:

```lua
function MyButton:mousepressed(mx, my, button, istouch, used)
  if used then return used end
  if self:inBox(mx, my) then
    self:click()
    return true
  end
  return used
end
```

### `inBox` на нетривиальной геометрии

По умолчанию `inBox` — AABB-тест. Если нужен круг, многоугольник, маска пикселей — переопределите:

```lua
function CircleButton:inBox(x, y)
  return x * x + y * y <= self.radius * self.radius
end
```

`x, y` здесь — локальные координаты, относительно пивота. Без хлопот с трансформациями.

---

## 7. Мышь поверх кнопок — кто победит

Классическая ситуация: две кнопки частично перекрываются.

```lua
SGroup{
  SSpriteButton{ x = 0, states = "btn_a", event = "a" },      -- ширина 100
  SSpriteButton{ x = 50, states = "btn_b", event = "b" },      -- частично над btn_a
}
```

Курсор при `(75, 0)` находится внутри обеих. Обе получат `mousepressed`. Кто сработает?

- `btn_a` — первый в `childs[]`. Видит `used = false`, кликает, возвращает `true`.
- `btn_b` — следующий. Видит `used = true`, не реагирует.

**Первый по порядку добавления выиграет.**

Если хотите «верхняя визуально» — поменяйте порядок добавления:

```lua
SGroup{
  SSpriteButton{ x = 0,  states = "btn_a", event = "a" },
  SSpriteButton{ x = 50, states = "btn_b", event = "b" },
}
-- btn_a впереди в childs. Если x = 50 — btn_b (вторая) перекрывает btn_a визуально,
-- но получает клики второй. Не здорово.
```

Решение — поменять порядок **добавления** так, чтобы верхняя визуально была первой в `childs[]`:

```lua
local a = SSpriteButton{...}
local b = SSpriteButton{...}
group:add(b)    -- сначала визуально верхняя
group:add(a)
```

Или просто не перекрывать кликабельные кнопки. Это самое чистое решение.

### Модалки

Классическая цель — заблокировать клики ниже себя:

```lua
local modal = SGroup{
  SStretchedSprite{ img = "black", w = 1920, h = 1080, color = {0, 0, 0, 0.59} },
  SSpriteButton{ states = "btn_ok", event = "modal.ok", y = 100 },
}

-- Добавляем модалку последней — значит она в childs[] последней.
scene:add(modal)
```

Но это не помогает — модалка-то в childs последняя, значит события получает последней, и кнопки **под** ней получат свои клики первыми.

Правильный паттерн — **добавить полный-экранный блокер внутрь модалки с `used = true` на любом клике**:

```lua
local Blocker = Class{ __includes = { SObject, SMouseObject },
  init = function(self, p)
    SObject.init(self, p)
    self.w, self.h = p.w, p.h
  end
}
function Blocker:mousepressed(mx, my, button, istouch, used) return true end
function Blocker:inBox() return true end   -- съедает всё
```

И поместить его **первым** в modal:

```lua
local modal = SGroup{
  Blocker{ w = 1920, h = 1080 },   -- съедает все клики
  SStretchedSprite{ img = "black" },
  SSpriteButton{ states = "btn_ok", event = "modal.ok" },
}
```

Но и тут hitch — blocker первый в childs **внутри** modal, но сама modal последняя в родительском childs. События идут: родитель → childs[1] (какая-то кнопка) → childs[2] (modal) → modal.childs[1] (blocker, съедает) → modal.childs[3] (кнопка ОК).

Блокатор внутри modal не остановит клики, которые уже обработаны кнопками **до** modal.

### Правильное решение — modal должна быть first-child

Добавляйте модалку **в начало** childs[], не в конец:

```lua
-- В SObject нет add-first, так что делайте вручную:
table.insert(scene.childs, 1, modal)
modal.parent = scene
```

Теперь `modal` — childs[1]. Событие сначала идёт в неё. Внутри `modal` первый — blocker, съедает. Кнопки ОК внутри modal идут после blocker-а, но получают события (потому что внутри modal blocker съел только — точнее, blocker съел и возвратил `used = true`, но это **внутри** modal-вселенной, дочерние кнопки ОК увидят `used = true`).

Чтобы и кнопка ОК внутри модалки всё ещё работала, blocker надо сделать **последним** ребёнком модалки:

```lua
local modal = SGroup{
  SStretchedSprite{ img = "black" },              -- childs[1]
  SSpriteButton{ states = "btn_ok", event = "modal.ok" },   -- childs[2]
  Blocker{ w = 1920, h = 1080 },                  -- childs[3] — съедает всё, что не попало в кнопку
}
```

Тогда поток: `modal:__mousepressed` → `black` (нет реакции) → `btn_ok` (если курсор на ней — клик, возвращает true) → `Blocker` (съедает оставшееся).

Если `modal` — childs[1] в родительском дереве, клики вне её до остальных кнопок не дойдут.

Это нетривиально — в фреймворках с capture/bubble модалки проще. В SE3 стратегия: `modal` первым в childs, blocker последним в modal.

---

## 8. Клавиатура — глобальный характер

Клавиатурные события **не** привязаны к геометрии. Любой `SKeyboardObject` (или `SEInputController`) в дереве получит событие, если его `keys` содержат нажатую клавишу.

```lua
SGroup{
  SEInputController{ bindings = { fire = { keys = {"space"} } } },
  SEInputController{ bindings = { jump = { keys = {"space"} } } },
}
-- Обе услышат space. Флаг used не блокирует их — они оба делают обработку.
```

`SEInputController` **не** возвращает `used = true` явно (возвращает, что получил). Так что множественные input-контроллеры на одно действие = множественные вызовы.

Если это мешает — используйте **один** input-контроллер для каждой уникальной клавиши, и разносите логику по `onClick/onPress/...`.

### `SKeyboardObject` и `used`

```lua
if (self.clickByDown or self.triggerOn == "press") and not used and self.click then
  self:click()
  used = true
end
```

Кнопки с `clickByDown` уважают `used` — если выше что-то уже обработало, не дублируют click. Это защита от ситуации «два SpaceButton случайно в одной сцене».

---

## 9. Пишем свой event-тип

Добавить новый тип события (например, `mousewheel` — в SE3 из коробки нет) — это написать пару `__eventname` / `eventname` по шаблону:

```lua
function SObject:__mousewheel(dx, dy, used)
  if self.mousewheel then used = self:mousewheel(dx, dy, used) end
  for i = 1, #self.childs do
    local c = self.childs[i]
    if not c.off and c.__mousewheel and not c.eventoff then
      used = c:__mousewheel(dx, dy, used)
    end
  end
  return used
end
```

Размещение: лучше всего в вашем `init.lua`/bootstrap, **после** `require("se3")`, чтобы дополнить существующий `SObject`. Не надо форкать `seobject.lua`.

И прокинуть в main:

```lua
function love.wheelmoved(dx, dy)
  scene:__mousewheel(dx, dy)
end
```

Теперь любой класс, определяющий `self:mousewheel(dx, dy, used)`, будет ловить прокрутку.

### Транс-координаты для mousewheel

У wheelmoved **нет позиции** — только `dx, dy`. Но обычно хочется знать, **над каким** элементом прокрутили. Паттерн — сохранять последнюю позицию мыши:

```lua
local lastMouseX, lastMouseY = 0, 0
function love.mousemoved(x, y, ...) lastMouseX, lastMouseY = x, y; scene:__mousemoved(x,y,...) end
function love.wheelmoved(dx, dy) scene:__mousewheel(lastMouseX, lastMouseY, dx, dy) end

function SObject:__mousewheel(mx, my, dx, dy, x, y, r, sx, sy, used)
  local x,y,r,sx,sy, mx1, my1 = self:transformMouse(mx, my, x, y, r, sx, sy)
  if self.mousewheel then used = self:mousewheel(mx1, my1, dx, dy, used) end
  for i = 1, #self.childs do
    local c = self.childs[i]
    if not c.off and c.__mousewheel and not c.eventoff then
      used = c:__mousewheel(mx, my, dx, dy, x, y, r, sx, sy, used)
    end
  end
  return used
end
```

Дальше в своём классе:

```lua
function Scroller:mousewheel(mx, my, dx, dy, used)
  if used or not self:inBox(mx, my) then return used end
  self:scroll(dy * -20)
  return true
end
```

---

## 10. Паттерны и антипаттерны

### ✓ Уважать `used`

```lua
function MyButton:mousepressed(mx, my, button, istouch, used)
  if used then return used end
  if self:inBox(mx, my) then
    self:click()
    return true
  end
  return used
end
```

Не перезаписывайте `used = false`, не игнорируйте его — и вы будете жить в гармонии с остальной сценой.

### ✗ Одноразовая консумация в обе стороны

```lua
-- НЕПРАВИЛЬНО
function BadButton:mousepressed(mx, my, button)
  self:click()
  return true   -- всегда «съедает» — даже если курсор не над кнопкой!
end
```

Это сделает кнопку «поглощающей все клики в мире». Проверяйте `inBox` прежде чем возвращать `true`.

### ✓ Event-bubble замена через `parent`

SE3 не делает bubble-фазу, но можно самому:

```lua
function MyContainer:onChildClicked(child)
  -- кастомный метод, вызываемый ребёнком
  print("Child " .. child.id .. " clicked")
end

function MyChildButton:click()
  if self.parent and self.parent.onChildClicked then
    self.parent:onChildClicked(self)
  end
end
```

Удобно для списков: `ListItemButton` уведомляет родительский `List` без знания его типа.

### ✗ Игнорирование `off`/`eventoff`

```lua
-- НЕПРАВИЛЬНО
function MyGroup:__draw(x, y, r, sx, sy)
  for i, c in ipairs(self.childs) do
    c:__draw(x, y, r, sx, sy)    -- обходит off!
  end
end
```

Если переопределяете `__draw`, обязательно проверяйте `if not c.off and c.__draw then ...` — иначе сломаются флаги. То же для `__eventname`.

### ✓ Consume только свой event

```lua
function ScrollPanel:mousepressed(mx, my, button, istouch, used)
  if used then return used end
  if not self:inBox(mx, my) then return used end
  self._dragging = true
  return true
end

function ScrollPanel:mousereleased(mx, my, button, istouch, used)
  if self._dragging then
    self._dragging = false
    return true    -- съедаем только если МЫ драгали
  end
  return used
end
```

Не консумите press **и** release подряд если press не ваш — сломаются другие кнопки.

### ✗ Забыть отписаться в onLeave

См. [Signals.md §3](./Signals.md#3-регистрация-и-отписка).

### ✓ Использовать `eventoff` вместо ручного `inBox`

Если у вас декоративный overlay, который не должен мешать событиям:

```lua
scene = SGroup{
  SSprite{ img = "bg" },
  SSpriteButton{ ... },
  SSprite{ img = "decorative_frame", eventoff = true, z = 100 },   -- не перехватывает
}
```

Намного чище, чем писать пустой `mousepressed` и возвращать `used`.

---

## См. также

- [SObject.md §9](./SObject.md#9-каноны-и-edge-cases) — базовые правила рендера/событий.
- [SEInputController.md](./SEInputController.md) — готовый named-action input поверх key events.
- [Signals.md](./Signals.md) — шина между точкой эмита и подписчиком.
- [Inheritance.md §15](./Inheritance.md#15-рекомендации-и-edge-cases) — edge cases при переопределении `__draw` и прочих внутренних методов.
