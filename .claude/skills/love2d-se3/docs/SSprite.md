# SSprite family — Extended Guide

Спрайты SE3. Файл `sesprite.lua`.

Все классы этой семьи:

| Класс | Что делает |
|-------|-----------|
| `SSprite` | одна статичная картинка |
| `SStretchedSprite` | картинка с собственными `scaleX`/`scaleY` (независимо от `sx`/`sy` узла) — удобно растягивать бэкграунды |
| `SAnimationSprite` | кадровая анимация |
| `SComplexAnimSprite` | анимация с intro-фазой (1..start-1 играется один раз) + loop-фазой (start..end повторяется) |
| `SAnimator` | миксин с логикой таймингов; сам `SAnimationSprite` его использует |

---

## Оглавление

1. [SSprite — статичный спрайт](#1-ssprite--статичный-спрайт)
2. [SStretchedSprite — растягивание](#2-sstretchedsprite--растягивание)
3. [SAnimator — логика кадров](#3-sanimator--логика-кадров)
4. [SAnimationSprite](#4-sanimationsprite)
5. [SComplexAnimSprite — intro + loop](#5-scomplexanimsprite--intro--loop)
6. [Работа с атласом и оффсетами](#6-работа-с-атласом-и-оффсетами)
7. [Полный пример — анимированный герой](#7-полный-пример--анимированный-герой)

---

## 1. SSprite — статичный спрайт

```lua
local bg = SSprite{ img = "background", x = 0, y = 0 }
```

Поле `img`:

- **Строка** — имя в `resource` (ищется через `resource:get(name)`). Может быть либо именем атласного спрайта, либо именем standalone-картинки.
- **`love.graphics.Image`** — готовый объект Love2D. Используйте, если хотите показать что-то, чего нет в `resource` (например, generated canvas).

```lua
-- имя из атласа
SSprite{ img = "icon_heart" }

-- прямо love.Image
SSprite{ img = love.graphics.newImage("assets/special.png") }
```

Размер (`w`/`h`) устанавливается автоматически в `setImg`:

- Если в `resource` возвращается кортеж с `offset` (как у атласного спрайта с поддержкой trim) — `w/h = offset[3], offset[4]` и заполняется `offsetx, offsety`.
- Если только `rect` — `w/h = rect[3], rect[4]`.
- Если plain image — `w/h = img:getDimensions()`.

### Методы

```lua
s:setImg(nameOrImage)       -- переустановить картинку; обновит w/h/offset
s:getImg()                  -- вернуть (img, quad) — полезно при ручной отрисовке
s:setColor({r, g, b, a})    -- тинт (компоненты в 0..1); также принимает HEX-строку: "#RRGGBB" / "#RRGGBBAA"
```

### Отрисовка и `color`

Внутри `draw` спрайт делает:

```lua
if self.color then love.graphics.setColor(self.color) end
love.graphics.draw(img, x, y, r, sx, sy, tx, ty)   -- или с quad
if self.color then love.graphics.setColor(1, 1, 1, 1) end
```

Так что установка `color = nil` возвращает к чисто-белому. Установка `alpha` через props-таблицу при конструкции изменяет 4-й канал `color` (см. [SObject §9](./SObject.md#9-каноны-и-edge-cases)).

---

## 2. SStretchedSprite — растягивание

Обычный `sx`/`sy` на `SSprite` работает от пивота, поэтому масштабирование «раздувает» спрайт и в позицию, и в угол поворота. Часто нужен просто «растянутый прямоугольник» (бэкграунд диалога, полоса прогресса, индикатор) — без влияния на дочерние трансформы.

`SStretchedSprite` даёт локальные `scaleX`/`scaleY`, применяющиеся только к отрисовке, не к композиции трансформов.

```lua
SStretchedSprite{
  img = "bar_bg",
  w   = 600,          -- логический размер
  h   = 16,
  -- На момент construction, scaleX/scaleY хранятся в _sx/_sy:
  -- по умолчанию 1, т.е. img рисуется в свой натуральный размер,
  -- но setSize() будет пересчитывать _sx/_sy по отношению к w/h картинки.
}
```

Методы растягивания:

```lua
s:setSize(w, h)         -- обновляет _sx, _sy так, чтобы рендер был w × h
s:setSizeW(w)           -- только ширина
s:setSizeH(h)           -- только высота
```

Типичный сценарий — прогресс-бар:

```lua
local fill = SStretchedSprite{
  img = "bar_fill",
  pivot = {0, 0.5},       -- растягиваем от левого края
  x = -300, y = 0,
}
-- в update:
fill._sx = progress       -- 0 → полоса схлопнулась, 1 → на всю ширину
```

---

## 3. SAnimator — логика кадров

`SAnimator` — миксин, не самостоятельный класс. Реализует тайминг кадров: очередь фреймов, таймер, play/stop/loop, callback при остановке.

Формат **sequence** (последовательности кадров):

```lua
-- 1. Одна строка — одиночный кадр
sequence = "idle_01"

-- 2. Массив строк — кадры по имени (атласные спрайты), общий delay
sequence = {"walk_01", "walk_02", "walk_03", "walk_04"}

-- 3. Массив таблиц — кадр + собственный delay
sequence = {
  { frame = "walk_01", delay = 0.1 },
  { frame = "walk_02", delay = 0.2 },    -- этот кадр подольше
  { frame = "walk_03", delay = 0.1 },
}

-- 4. Шаблон — {pattern, delay, from, to}
sequence = {"symbol_%05d", 0.1, 1, 10}
-- разворачивается в 10 кадров:
--   symbol_00001 ... symbol_00010
-- Направление: если from > to → кадры убывают.

-- 5. Смешанный список — шаблоны и отдельные кадры вперемешку
sequence = {
  "intro_01",
  {"walk_%02d", 0.1, 1, 8},
  "hit",
  {"recover_%02d", 0.2, 1, 4},
}
```

Детекция шаблонов — **по форме**: `string + 3 числа`. Не пересекается с другими форматами.

### API (на любом классе, включающем `SAnimator`)

```lua
s:setSequence(sequence)        -- задать новую последовательность, поставить на frame 1
s:setDelay(delay)              -- общая задержка между кадрами; перезаписывает
                               -- индивидуальные delays в sequence
s:play([startFrame])           -- play once
s:loop([startFrame])           -- loop forever
s:stop([frameToFreezeAt])      -- остановить; можно указать кадр-«стоп»
s:setCallback(fn)              -- callback при завершении play-once
s:setCurrentFrame(index)       -- принудительно перейти на кадр
```

В момент остановки вызывается `stopCallback` (если установлен) и эмитится `Signal.emit("animation.stop", self)`. Последнее — в `SComplexAnimSprite` (см. ниже).

---

## 4. SAnimationSprite

`SAnimationSprite` = `SSprite` + `SAnimator` + (внутренне) `STextObject`. Выдает кадровую анимацию из последовательности имен атласных спрайтов.

```lua
local hero = SAnimationSprite{
  sequence = {"hero_walk_%02d", 0.1, 1, 8},
  delay    = 0.1,
  x = 400, y = 500,
}
hero:loop()
```

По умолчанию создаётся на первом кадре но **не** в play-режиме (`animationStop = true`). Надо явно вызвать `:play()` или `:loop()`.

### Практика

```lua
-- idle зациклен
hero:setSequence({"idle_%02d", 0.15, 1, 4})
hero:loop()

-- атака — play-once с callback
hero:setSequence({"attack_%02d", 0.08, 1, 6})
hero:setCallback(function()
  hero:setSequence({"idle_%02d", 0.15, 1, 4})
  hero:loop()
end)
hero:play()
```

Когда таких переходов становится больше трёх-четырёх — пора переходить на [SAnimatedObject](./SAnimatedObject.md) с его декларативным state-machine.

### `stop(frame)` тонкость

`SAnimator:stop(frame)` сохраняет `index = frame`, обновляет `__curent_frame`, но **не** вызывает `setImg` — то есть визуально картинка не перерисуется до следующего `setImg`. Большинство вызывающих кода делает это вручную:

```lua
sp:stop(5)
sp:setImg(sp.__curent_frame.frame)
```

Это поведение используется, например, в `SAnimatedObject:setState(name, {saveFrame=true})` (см. его док).

---

## 5. SComplexAnimSprite — intro + loop

Спрайт, где часть последовательности играется один раз (intro), а часть — зацикливается.

```lua
local door = SComplexAnimSprite{
  sequence = {"door_%02d", 0.1, 1, 10},
  startLoopFrame = 6,           -- с 6-го начинается цикл
  finalLoopFrame = 10,          -- до 10-го
}
door:loop()
```

Кадры 1..5 проиграются один раз (intro), затем 6..10 будут повторяться бесконечно.

Методы:

```lua
door:setLoopFrames(6, 10)     -- поменять границы цикла на лету
door:stop()                    -- немедленно остановить; эмитится Signal "animation.stop"
```

Полезно для:
- Монстра с анимацией появления + idle-циклом.
- Кнопки с highlight-анимацией (intro + пульсация).
- Дверь/механизм с открытием + свечение вокруг.

---

## 6. Работа с атласом и оффсетами

Если спрайт загружен из атласа (TexturePacker), `resource:get(name)` возвращает:

```
texture, quad, rect, _, offset
```

где:

- `texture` — `love.graphics.Image` общей текстуры атласа.
- `quad` — `love.graphics.Quad` для конкретного спрайта.
- `rect` — `{x, y, w, h}` внутри текстуры (не нужен обычно).
- `offset` — `{offsetX, offsetY, originalW, originalH}` — для спрайтов с trim: размер **до** обрезки прозрачных пикселей и смещение, которое вернёт спрайт на его «исходное» место.

`SSprite:setImg` автоматически кладёт offset в `offsetx, offsety` и использует его при вычислении `tx, ty` в `draw`. Это значит, что даже trim-нутые спрайты рисуются на своей «правильной» позиции — пивот работает по исходному размеру, а не по обрезанному.

### Как это проверить

```lua
local s = SSprite{ img = "trimmed_icon" }
print(s.w, s.h)                    -- original W/H (если есть trim)
print(s.offsetx, s.offsety)        -- смещение от top-left оригинала
```

Если `offset == nil` (спрайт без trim) — `w/h` возьмутся из `rect`, `offsetx/offsety` останутся `0`.

---

## 7. Полный пример — анимированный герой

```lua
-- scenes/game.lua
return {
  resources = {
    atlases = { { require = "atlases.hero", path = "assets/hero/" } },
  },

  scene = {
    type = "SGroup", x = 960, y = 540,

    -- Фон — SSprite
    { type = "SSprite", img = "bg" },

    -- Растянутая полоса здоровья — SStretchedSprite
    { type = "SGroup", y = -400, children = {
        { type = "SStretchedSprite", img = "bar_bg",   w = 200, h = 12 },
        { type = "SStretchedSprite", img = "bar_fill", w = 200, h = 12,
          pivot = {0, 0.5}, x = -100, id = "hp_fill" },
    }},

    -- Hero — SComplexAnimSprite (intro + loop)
    { type = "SComplexAnimSprite",
      id = "hero",
      sequence = {
        "hero_spawn_01", "hero_spawn_02", "hero_spawn_03",  -- intro 1..3
        "hero_idle_01",  "hero_idle_02",  "hero_idle_03",   -- loop 4..6
      },
      delay = 0.1,
      startLoopFrame = 4,
      finalLoopFrame = 6,
    },
  },

  onEnter = function(scene)
    scene:byId("hero"):loop()
  end,
}
```

Альтернатива через шаблоны — то же самое, но компактнее:

```lua
{ type = "SComplexAnimSprite",
  id = "hero",
  sequence = {
    {"hero_spawn_%02d", 0.1, 1, 3},
    {"hero_idle_%02d",  0.1, 1, 3},
  },
  startLoopFrame = 4,
  finalLoopFrame = 6,
}
```

Для более сложной логики (переключения idle/walk/attack, hit-реакция) — см. [SAnimatedObject.md](./SAnimatedObject.md).

---

## См. также

- [SObject.md](./SObject.md) — базовый класс, трансформы, пивот.
- [SAnimatedObject.md](./SAnimatedObject.md) — state-machine поверх `SAnimationSprite`.
- [SLoader.md](./SLoader.md) — как подготовить `resource` с атласами.
