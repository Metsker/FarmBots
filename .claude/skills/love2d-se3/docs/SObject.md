# SObject, SGroup, SCanvas, Mixins — Extended Guide

Корень всего scene-graph-а в SE3. Каждый видимый и интерактивный элемент — потомок `SObject`. Группы, z-сортировка, канвасы для пост-обработки и миксины обработки ввода — всё в файле `seobject.lua`.

---

## Оглавление

1. [Модель: дерево узлов, трансформы, пивот](#1-модель-дерево-узлов-трансформы-пивот)
2. [SObject](#2-sobject)
3. [SGroup — z-сортировка](#3-sgroup--z-сортировка)
4. [SCanvas — рендер в canvas](#4-scanvas--рендер-в-canvas)
5. [SMouseObject (миксин)](#5-smouseobject-миксин)
6. [SKeyboardObject (миксин)](#6-skeyboardobject-миксин)
7. [Собственный визуальный класс](#7-собственный-визуальный-класс)
8. [Собственный интерактивный класс](#8-собственный-интерактивный-класс)
9. [Каноны и edge cases](#9-каноны-и-edge-cases)

---

## 1. Модель: дерево узлов, трансформы, пивот

Каждый `SObject` хранит:

| Поле | Тип | Смысл |
|------|-----|-------|
| `x, y, z` | number | позиция в системе координат родителя; `z` — для сортировки внутри `SGroup` |
| `r` | number | угол поворота (радианы) |
| `sx, sy` | number | scale X/Y (по умолчанию `1`) |
| `w, h` | number | логический размер (обычно заполняется автоматически — например, по размеру картинки в `SSprite`) |
| `pivot` | `{px, py}` | точка отсчёта (0..1 по осям w/h); по умолчанию `{0.5, 0.5}` |
| `offsetx, offsety` | number | смещение, вытаскиваемое из атласа (sprite offset) |
| `color` | `{r,g,b,a}` \| nil | тинт (компоненты в 0..1); `nil` = чисто белый. Также принимает HEX-строку: `'#RRGGBB'` / `'#RRGGBBAA'` |
| `parent` | `SObject` \| nil | ссылка на родителя (ставится автоматически в `add`) |
| `childs` | `SObject[]` | список потомков в порядке добавления |

**Трансформы комбинируются родитель → ребёнок.** Когда вы ставите `SGroup{x=100, y=100, children={SSprite{x=10, y=0}}}`, спрайт рисуется в `(110, 100)` мировых координат. `transform(…)` в `seobject.lua` делает эту композицию.

**Пивот — точка, относительно которой считается `x`/`y` и вокруг которой происходит поворот/масштабирование.** По умолчанию `{0.5, 0.5}` — центр объекта. `{0, 0}` — левый верх, `{1, 1}` — правый низ. Можно передавать одним числом — `pivot = 0` означает `{0, 0}`.

### События

Все события пропагируются по дереву в два этапа:
- `__eventname(...)` — внутренний проход по дереву (добавляет трансформы, вызывает потомков).
- `eventname(...)` — пользовательский метод на инстансе, который получает «локальные» координаты мыши.

Разделение `__`-метод vs открытый метод — **намеренное**. При создании новых типов событий сохраняйте эту пару.

### Флаги видимости

| Флаг | Эффект |
|------|--------|
| `self.off = true` | полностью исключает узел и всё поддерево из отрисовки И событий |
| `self.eventoff = true` | исключает только из событий (рисуется, но не слышит) |
| `self.hidden = true` | большинство встроенных `draw` просто пропускают отрисовку (но дети рисуются) |

---

## 2. SObject

Базовый класс. Остальное почти всё — его потомки.

### Конструктор

```lua
local obj = SObject{
  x = 100, y = 200,
  sx = 1.5, sy = 1.5,
  r = math.pi / 4,
  w = 64, h = 64,
  pivot = {0, 0},
  color = {1, 0, 0, 1},
  alpha = 0.5,            -- перекрывает color[4]
  off = false,
  eventoff = false,
  hidden = false,

  -- дети — через массивную часть или явно:
  SSprite{ img = "icon" },
  SText{ font = "main", text = "hi" },

  children = {
    SSprite{ img = "another" },
  },
}
```

Массивная часть и `children = {...}` объединяются — оба варианта работают, можно даже мешать. Типичный стиль — короткие композиции писать через массивную часть, длинные/программно сгенерированные — через `children`.

### Фундаментальные методы

```lua
obj:add(child)                   -- добавить потомка, вернуть его
obj:getDimensions()              -- вернуть w, h (наследуется)
obj:setPivot(px, py)             -- установить пивот; число → {n, n}
obj:setX(x)  obj:setY(y)  obj:setZ(z)
obj:setR(r)  obj:setSX(v) obj:setSY(v)
obj:setW(w)  obj:setH(h)
obj:setSize(w, h)                -- подгоняет sx/sy так, чтобы визуальный размер = w×h
obj:setSizeW(w)  obj:setSizeH(h)
```

Все `setX/setY/...` делают `:refresh()`, который поднимается вверх по дереву, давая возможность родителям пересчитать что-то зависящее (например, z-порядок).

### Bounding box

```lua
local minX, minY, maxX, maxY = obj:getBoundingBox()
```

Рекурсивный AABB, включая всех потомков. Учитывает поворот (считает реальный экранный bounding-box после всех трансформов).

### Жизненный цикл

Стандартный порядок в корневом `love.update`/`love.draw`:

```lua
function love.update(dt)  scene:__update(dt) end
function love.draw()      scene:__draw()     end
```

Внутри `__update`:

```
if self.update then self:update(dt) end       -- собственный апдейт
for each child do child:__update(dt) end       -- дети
```

`__draw` делает то же самое, плюс композицию трансформов (`transform(…)` на каждом узле).

Для собственной логики — переопределяйте `update(dt)` (не `__update`).

```lua
local Spinner = Class{ __includes = SObject,
  init = function(self, p) SObject.init(self, p) end
}

function Spinner:update(dt) self.r = self.r + dt end
```

---

## 3. SGroup — z-сортировка

`SGroup` — наследник `SObject`, внутри которого дети сортируются по полю `z`.

```lua
local group = SGroup{
  SSprite{ img = "background", z = 0 },
  SSprite{ img = "midground",  z = 1 },
  SSprite{ img = "foreground", z = 2 },
}
```

Что происходит под капотом:

1. `SGroup.init` создаёт два списка: `childs` (порядок добавления, для событий) и `zchilds` (по убыванию `z`, для отрисовки).
2. `:add(child)` пушит в оба и перес-sortирует `zchilds`.
3. `__draw` делает двухфазный проход: сначала собирает трансформы в `cache` для каждого потомка, затем рисует в порядке `zchilds`.

Изменение `z` на лету через `setZ(n)`:

```lua
local sprite = SSprite{ img = "thing", z = 0 }
group:add(sprite)
sprite:setZ(10)    -- :zrefresh поднимается до SGroup, который пересортирует zchilds
```

**Nested groups.** Если вы вложите `SGroup` внутрь `SGroup`, внутренний сохранит свой собственный z-порядок независимо:

```lua
SGroup{
  SSprite{ img = "bg", z = 0 },
  SGroup{ z = 5, children = {
    SSprite{ img = "item_a", z = 10 },
    SSprite{ img = "item_b", z = 20 },
  }}
}
```

Внешняя группа видит внутреннюю как один узел с `z=5`. Внутри неё `item_b` над `item_a`.

### Почему `zchilds = {}` создаётся до `SObject.init`

```lua
local SGroup = Class{ __includes = SObject,
  init = function(self, p)
    self.zchilds = {}          -- обязательно до
    SObject.init(self, p)       -- здесь внутри идут :add для детей из p[]
  end
}
```

`SObject.init` вызывает `self:add(child)` для каждого ребёнка. `:add` вызывает `zrefresh`, который пушит в `self.zchilds`. Если поменять местами — `zchilds` ещё не существует и всё упадёт.

---

## 4. SCanvas — рендер в canvas

`SCanvas` рисует своих потомков в отдельный `love.graphics.Canvas`. Полезно когда:

- нужно применить шейдер ко всему поддереву сразу,
- поддерево не меняется и можно кэшировать рендер,
- нужно отрендерить что-то в off-screen-буфер для дальнейшего использования.

```lua
local canvas = SCanvas{
  canvasSize = {800, 600},
  children = {
    SSprite{ img = "bg" },
    SText{ font = "main", text = "overlay" },
  }
}
```

**Как работает кэш.** После первой отрисовки `canvas.canvas_notchanged = true` — последующие кадры просто рисуют готовый canvas. Любой `:refresh()` вверх по дереву сбрасывает флаг → канвас перерисовывается.

То есть если дети стационарны — рендер почти бесплатный. Если в детях есть анимация — переделывать канвас каждый кадр; смысл использования минимальный.

**Комбинация с `SShader`.** Чтобы применить шейдер к поддереву, оберните канвас в `SShader` (см. [SShader.md](./SShader.md)).

---

## 5. SMouseObject (миксин)

Миксин, добавляющий тест «курсор в зоне» и обработку мыши:

```lua
local MyButton = Class{ __includes = { SObject, SMouseObject },
  init = function(self, p)
    SObject.init(self, p)
    -- SMouseObject не требует init
  end
}

function MyButton:click() print("clicked") end
function MyButton:over()  self.color = {1, 1, 0, 1} end
function MyButton:release() self.color = nil end
function MyButton:press()   self.color = {1, 0.5, 0, 1} end
```

Какие хуки можно переопределить:

| Метод | Когда вызывается |
|-------|------------------|
| `over(x, y)` | курсор вошёл в `inBox` |
| `press(x, y)` | `mousepressed` поверх кнопки |
| `release(x, y)` | курсор ушёл из зоны (или `mousereleased` за пределами) |
| `click()` | клик (по умолчанию — в `mousereleased` внутри зоны) |
| `longpress()` | срабатывает из `SButtonEngine` по таймеру `timeout` |

### `inBox` и `setCollider`

По умолчанию collider — прямоугольник `{0, 0, w, h}`, скорректированный по пивоту. Если нужна другая зона клика (например, кнопка меньше своей графической области):

```lua
btn:setCollider({-50, -30, 100, 60})   -- {x, y, w, h}
```

Также `getBox()` возвращает готовый `{xmin, ymin, xmax, ymax}` для точки пивота.

### Флаги состояния (внутренние)

```
self.__over       -- true если курсор в зоне (без учёта pressed)
self.__pressed    -- true если кнопка мыши нажата поверх этого объекта
self.__longfired  -- true если уже сработал longpress (см. SButtonEngine)
```

Можно читать из своего кода, писать — не стоит.

### `triggerOn`

```lua
MyButton{ triggerOn = "press", … }
```

По умолчанию `click` вызывается на `mousereleased`. С `triggerOn = "press"` — сразу на `mousepressed`. Используется, например, для кнопок «огонь» в геймпейях, где нужен низкий latency.

---

## 6. SKeyboardObject (миксин)

Тот же паттерн, но для клавиш:

```lua
local KeyButton = Class{ __includes = { SObject, SKeyboardObject },
  init = function(self, p)
    SObject.init(self, p)
    self.keys = p.keys or {"space", "return"}
  end
}

function KeyButton:click()  print("activated") end
function KeyButton:press()  end
function KeyButton:release() end
function KeyButton:down(key, scancode) end   -- при первом press
function KeyButton:up(key)                end -- при release
```

По умолчанию `click` стреляет на `keyreleased`. Опции:

- `clickByDown = true` — `click` на первом `keypressed` (не ждать release).
- `triggerOn = "press"` — то же самое, но через ту же опцию, что у `SMouseObject` — полезно в кнопках, которые слышат и клавиатуру, и мышь (`SButton`, `SSpriteButton`).

Поле `self.keys` — массив строк (Love2D key names: `"space"`, `"escape"`, `"a"`, `"return"` и т.д.).

---

## 7. Собственный визуальный класс

Минимальный шаблон — нарисовать произвольный примитив:

```lua
local GradientRect = Class{ __includes = SObject,
  init = function(self, p)
    SObject.init(self, p)
    self.colorA = p.colorA or {0.2, 0.2, 0.39, 1}
    self.colorB = p.colorB or {0.78, 0.39, 0.2, 1}
  end
}

function GradientRect:draw(x, y, r, sx, sy, tx, ty)
  if self.hidden then return end
  love.graphics.push()
  love.graphics.translate(x - tx, y - ty)
  love.graphics.rotate(r)
  love.graphics.scale(sx, sy)

  local mesh = self._mesh
  if not mesh then
    mesh = love.graphics.newMesh({
      {0,      0,      0, 0, self.colorA[1], self.colorA[2], self.colorA[3], self.colorA[4]},
      {self.w, 0,      0, 0, self.colorA[1], self.colorA[2], self.colorA[3], self.colorA[4]},
      {self.w, self.h, 0, 0, self.colorB[1], self.colorB[2], self.colorB[3], self.colorB[4]},
      {0,      self.h, 0, 0, self.colorB[1], self.colorB[2], self.colorB[3], self.colorB[4]},
    }, "fan", "static")
    self._mesh = mesh
  end
  love.graphics.draw(mesh)
  love.graphics.pop()
end
```

Важные замечания:

- Аргументы `draw` — **уже с учётом трансформов родителей**. Движок их пропускает через `love.graphics.draw`, если вы используете обычный путь. Здесь я показал вариант с `push/pop` — он проще для шейдеров/мешей, но не единственный.
- `tx, ty` — смещения от пивота (`w * pivotX - offsetx` и `h * pivotY - offsety`). `love.graphics.draw` ожидает их с отрицательным знаком, так что часто используют `love.graphics.draw(img, x, y, r, sx, sy, tx, ty)` напрямую.
- Для участия в z-сортировке нужно реализовать `cacheCoords(x, y, r, sx, sy, tx, ty)` — см. [§9](#9-каноны-и-edge-cases).

### Рекомендуемый паттерн — использовать Love-спрайт примитивы

Если ваш класс — это всё же картинка, наследуйте `SSprite`, а не городите `love.graphics.draw` руками. См. [SSprite.md](./SSprite.md).

---

## 8. Собственный интерактивный класс

Хотите свою кнопку с нестандартной геометрией (круг, hex, пиксель-точный хит-тест)?

```lua
local CircleButton = Class{ __includes = { SObject, SMouseObject },
  init = function(self, p)
    SObject.init(self, p)
    self.radius = p.radius or 50
    self.event  = p.event
  end
}

function CircleButton:inBox(x, y)
  return (x * x + y * y) <= self.radius * self.radius
end

function CircleButton:click()
  if self.event then Signal.emit("click", self.event) end
end

function CircleButton:over()    self.color = {1, 1, 0.39, 1} end
function CircleButton:release() self.color = nil              end
function CircleButton:press()   self.color = {1, 0.5, 0.39, 1} end

function CircleButton:draw(x, y, r, sx, sy, tx, ty)
  if self.color then love.graphics.setColor(self.color) end
  love.graphics.circle("fill", x, y, self.radius * sx)
  love.graphics.setColor(1, 1, 1, 1)
end
```

`SMouseObject:mousepressed/released/moved` получат локальные координаты (уже после поворота и масштаба родителей), и `self:inBox(x, y)` будет тестировать на нашу круглую геометрию.

---

## 9. Каноны и edge cases

### `__draw` / `cacheCoords` / `drawCached`

Два пути рендера внутри движка:

1. **Прямой (`__draw`)** — рекурсивный вызов `draw` на себе и детях. Используется по умолчанию.
2. **Кешированный (`cacheCoords` → `drawCached`)** — двухфазный. `SGroup` сначала обходит детей, вызывая `__cacheCoords` (каждый сохраняет готовый трансформ), затем сортирует по `z` и вызывает `drawCached` в отсортированном порядке.

Дефолтный `SObject:drawCached` рисует `self` по кешированному трансформу, затем рекурсивно вызывает `drawCached` для детей в естественном порядке. `SGroup:drawCached` переопределяет рекурсию на `zchilds` (свой z-сортированный список), поэтому вложенные группы сохраняют независимую z-сортировку.

**Вам не нужно трогать `drawCached`**, если ваш класс — просто прямой контейнер. Если внутри класса лежит собственное поддерево и вы хотите своим правилам z-сортировки — переопределите `drawCached`.

**Чтобы класс участвовал в z-сортировке родительского `SGroup`**, он должен реализовать `cacheCoords(x, y, r, sx, sy, tx, ty)` — сохранить готовый трансформ. Дефолтный `SObject.cacheCoords` уже это делает (пишет в `self.cache`), но если вы переопределили `__draw` напрямую без вызова базы — `cacheCoords` не сработает.

### Флаг `hidden` vs `off`

- `hidden = true` — свой `draw` обычно ничего не рисует, но дети **продолжают** рисоваться. Используется в кнопках (сами графические состояния скрываются/показываются через `hidden`, чтобы не чистить `childs`).
- `off = true` — весь узел и всё поддерево пропущены и в отрисовке, и в событиях.
- `eventoff = true` — узел рисуется, но события не получает.

### `color` — диапазон 0..1 и HEX

SE3 и Love2D 11+ используют общий формат: компоненты цвета — числа в `0..1` (`{1, 0.5, 0.25, 0.78}`). Движок передаёт `self.color` прямо в `love.graphics.setColor` без нормализации.

Дополнительно `color`/`alpha` и `:setColor()` принимают **HEX-строку**: `"#RRGGBB"`, `"#RRGGBBAA"`, короткие формы `"#RGB"` / `"#RGBA"`. Под капотом разбор делается через `SEColor.parse` — он возвращает `{r,g,b,a}` в 0..1. Например, `color = "#ff8040cc"` эквивалентно `{1, 0.5, 0.25, 0.8}`.

### `:refresh()` — обход до корня

Любой `setX/setY/setW/...` делает `:refresh()`, который рекурсивно поднимается по `parent`-ам и вызывает их `refresh`. Это даёт возможность родителям пересчитать что-то при изменении потомков. Используется в `SCanvas` (сбрасывает флаг кэша) и в `SGroup` (через `zrefresh`).

Если ваш класс хочет отреагировать на «ребёнок изменился» — переопределите `refresh()` и не забудьте вызвать базу.

### `alpha` перекрывает `color[4]`

```lua
SSprite{ img = "foo", color = {1, 0, 0, 0.78}, alpha = 0.5 }
```

Здесь `color` станет `{1, 0, 0, 0.5}` — `alpha` перекрывает четвёртый канал. Это удобно в анимациях: задали базовый тинт и меняете только alpha через `self.color[4] = new`.

### `pivot` как число

```lua
SSprite{ img = "foo", pivot = 0 }   -- == pivot = {0, 0}
SSprite{ img = "foo", pivot = 0.5 } -- == pivot = {0.5, 0.5}
```

Для непропорциональных пивотов — только таблица.

### Установка детей после конструктора

```lua
local group = SGroup{ x = 100, y = 100 }
group:add(SSprite{ img = "foo" })
group:add(SSprite{ img = "bar", z = 5 })   -- z-sort пересчитается
```

`:add` работает в любой момент — не только в конструкторе. Полезно для динамических сцен (добавлять объекты на уровень по ходу игры).

---

## См. также

- [SSprite.md](./SSprite.md) — спрайты и анимации.
- [SButton.md](./SButton.md) — кнопки, построенные на миксинах `SMouseObject` + `SKeyboardObject`.
- [SEInputController.md](./SEInputController.md) — named-action input, дополняющий прямые `keypressed/keyreleased`.
- [SAnimatedObject.md](./SAnimatedObject.md) — stateful-объекты с анимацией, скриптами и easing-ами.
