# SAnimatedObject + SEEasings — Extended Guide

`SAnimatedObject` — декларативный конечный автомат для анимированных объектов. Держит таблицу именованных состояний, внутри каждого — последовательность кадров, переходы, набор tween-скриптов и колбэки.

Файлы: `seanimatedobject.lua`, `seeasings.lua`.

---

## Оглавление

1. [Зачем нужен state machine](#1-зачем-нужен-state-machine)
2. [Минимальный пример](#2-минимальный-пример)
3. [Поля определения состояния](#3-поля-определения-состояния)
4. [Scripts — tween-цепочки](#4-scripts--tween-цепочки)
5. [Кастомные script-типы](#5-кастомные-script-типы)
6. [Управление: setState, getState, defineState](#6-управление-setstate-getstate-definestate)
7. [Easings — полный список](#7-easings--полный-список)
8. [Типовые паттерны](#8-типовые-паттерны)
9. [Edge cases](#9-edge-cases)

---

## 1. Зачем нужен state machine

Если на `SAnimationSprite` вы уже делали что-то вроде:

```lua
hero:setSequence(idleFrames); hero:loop()
-- ... потом ...
hero:setSequence(attackFrames)
hero:setCallback(function()
  hero:setSequence(idleFrames); hero:loop()
end)
hero:play()
-- ... ещё состояние ...
```

и у вас наметилось 4-5 таких переходов — пора брать `SAnimatedObject`. Он:

- Даёт **декларацию состояний**: `{frames=…, delay=…, next=…, scripts=…}`.
- Переключает состояния одним вызовом `setState(name)` — атомарно меняет кадры, трансформы, цвет, запускает tween-скрипты.
- Поддерживает **цепочки переходов** через `next` и `onFramesEnd`.
- Делает tween-анимацию полей (`x`, `y`, `sx`, `r`, `alpha`, `color`) **независимо** от кадровой анимации — параллельно.

---

## 2. Минимальный пример

```lua
local Hero = SAnimatedObject{
  x = 400, y = 500,
  defaultState = "idle",
  states = {
    idle = {
      frames = {"hero_idle_%02d", 0.15, 1, 4},
      loop   = true,
    },

    attack = {
      frames = {"hero_attack_%02d", 0.06, 1, 6},
      loop   = false,
      next   = "idle",             -- автоматически вернуться в idle
    },

    hit = {
      frames = "hero_hit",         -- одиночный кадр
      loop   = false,
      next   = "idle",
      scripts = {
        {"shake", 0.25, {dx = 6, dy = 4}},     -- потрясти 0.25 сек
      },
    },
  },
}
```

Запуск:

```lua
Hero:setState("attack")
-- воспроизведётся attack, в конце автоматически перейдёт в idle

Hero:setState("hit")
-- hit с shake-скриптом; после завершения → idle
```

---

## 3. Поля определения состояния

Любое поле, кроме `frames`, опционально.

| Поле | Дефолт | Эффект |
|------|--------|--------|
| `frames` | (обязательно) | строка = одиночный кадр; массив = sequence (см. [SSprite §3](./SSprite.md#3-sanimator--логика-кадров)) |
| `delay` | `1/24` | сек между кадрами |
| `loop` | `true` | зацикливать кадры; `false` = один проход |
| `next` | nil | имя состояния, в которое перейти по завершении one-shot |
| `sx`, `sy` | — | применить к `SAnimatedObject`-узлу на входе в состояние |
| `r`, `x`, `y` | — | то же |
| `alpha` | — | установить `_sprite.color[4]` (0..1); не трогает `color` |
| `color` | — | установить `_sprite.color`; таблица 0..1 или HEX-строка (`"#RRGGBB"` / `"#RRGGBBAA"`); `nil` = сбросить в белый |
| `scripts` | `{}` | tween-цепочка (см. [§4](#4-scripts--tween-цепочки)) |
| `stopScriptAtEnd` | `false` | остановить скрипт после одного прохода; `false` = loop |
| `onScriptsEnd` | nil | `function(self)` или `"stateName"` — когда скрипт-цепочка завершилась |
| `stopFramesAtEnd` | `false` | переопределить `loop`: играть один раз, остановиться на последнем кадре |
| `onFramesEnd` | nil | `function(self)` или `"stateName"` — когда sequence кадров доиграла до конца |

### Короткие записи

```lua
-- одиночный кадр, не зацикливается
states.freeze = "frame_freeze"
-- == { frames = {"frame_freeze"}, loop = false, delay = 1/24 }

-- массив кадров без других полей — зацикленный
states.walk = {"walk_01", "walk_02", "walk_03"}
-- == { frames = {...}, loop = true, delay = 1/24 }

-- таблица с полем frames — полное определение
states.walk = {
  frames = {"walk_%02d", 0.1, 1, 8},
  next   = "idle",
}
```

---

## 4. Scripts — tween-цепочки

Scripts — массив шагов, выполняющихся последовательно. Каждый шаг — строка-тип + параметры.

```lua
scripts = {
  {"wait",   0.1},                            -- пауза
  {"easyng", 0.3, "outQuad", { sx = {from=1, to=1.2} }},
  {"wait",   0.5, { sx = 1.2 }},              -- удержать значение
  {"easyng", 0.3, { sx = {from=1.2, to=1} }},
  {"shake",  0.2, {dx = 5, dy = 5}},
  {"custom", 0.4, function(obj, t, d) obj.r = math.sin(t) end},
}
```

### Встроенные типы шагов

#### `wait` — пауза, опционально фиксирует значения

```lua
{"wait", duration}
{"wait", duration, {sx = 1.2, alpha = 0.78}}  -- удерживает значения на время паузы
```

Ключи в таблице параметров: `sx`, `sy`, `r`, `x`, `y`, `alpha`, `color`.

#### `easyng` — tween

```lua
{"easyng", duration, { scale = {from=1, to=1.2} }}
{"easyng", duration, "outQuad", { x = {from=0, to=100} }}
```

Ключи tween-параметров:

- `scale` — `sx` и `sy` одновременно.
- `scaleX`, `scaleY` — раздельно.
- `rotate` — `r`.
- `x`, `y` — позиция.
- `alpha` / `colorA` — альфа.
- `color` — значение для всех RGB-каналов (полезно для fade to black/white).

Каждый `{from, to}` может иметь собственное `name = "easingName"` — персональный easing:

```lua
{"easyng", 0.5, { scale = {from=1, to=2, name="outElastic"} }}
```

Если на уровне шага задан easing (третий позиционный аргумент строкой), он применяется по умолчанию ко всем параметрам шага. Перекрыть можно через `name`.

#### `custom` — произвольная функция

```lua
{"custom", duration, function(obj, t, d)
  obj.r = math.sin(t * 10) * 0.1
end}
```

`t` — прошедшее время (0..d), `d` — длительность. Функция вызывается каждый кадр.

#### `shake` — встроенный тип для дрожания

```lua
{"shake", duration, {dx = 5, dy = 5}}
```

Случайно смещает `obj.x, obj.y` каждый кадр, восстанавливает при завершении.

Технически `shake` — обычный `scriptTypes["shake"]` из реестра кастомных типов (см. [§5](#5-кастомные-script-типы)) — просто движок регистрирует его как встроенный.

### Цикл vs один проход

- Дефолт: скрипт **зацикливается** — после последнего шага идёт обратно на первый.
- `stopScriptAtEnd = true` — скрипт проходит один раз и замирает.
- `onScriptsEnd = "stateName"` — переход после одного прохода.
- `onScriptsEnd = function(self) ... end` — вызов функции.

Кадровая анимация — **независимая**. Можно зациклить кадры (`loop=true`) и запустить scripts один раз (`stopScriptAtEnd=true`), или наоборот. Или и то, и другое циклить. Или и то, и другое — один раз.

---

## 5. Кастомные script-типы

Если встроенных `wait` / `easyng` / `custom` / `shake` не хватает — можно зарегистрировать свой тип.

```lua
SAnimatedObject.scriptTypes["pulse"] = {
  init = function(step, obj)
    step._origSx = obj.sx
    step._origSy = obj.sy
  end,

  apply = function(step, elapsed, obj)
    local p = step.params or {}
    local freq = p.freq or 10
    local amp  = p.amp  or 0.1
    local k    = 1 + math.sin(elapsed * freq) * amp
    obj.sx = step._origSx * k
    obj.sy = step._origSy * k
  end,

  done = function(step, obj)
    obj.sx = step._origSx
    obj.sy = step._origSy
  end,
}
```

Использование:

```lua
states.heartbeat = {
  frames = {"heart"},
  loop   = true,
  scripts = {
    {"pulse", 2.0, {freq = 6, amp = 0.15}},
  },
}
```

### Три хука

| Хук | Когда |
|-----|-------|
| `init(step, obj)` | при входе в шаг (включая циклы) |
| `apply(step, elapsed, obj)` | каждый кадр пока шаг активен |
| `done(step, obj)` | при выходе из шага (включая прерывание `setState`) |

**Где хранить состояние:** пишите в `step`, не в `obj`. Одна и та же parsed-таблица шагов переиспользуется между циклами, но `init` вызывается заново, так что сохранение начального значения надёжно живёт в `step._origX` и т.п.

`done` вызывается всегда перед следующим `init` (и при `setState`, который прерывает текущий скрипт) — так что восстановление начального значения — ваша ответственность.

---

## 6. Управление: setState, getState, defineState

```lua
obj:setState(name)                     -- просто переключить
obj:setState(name, fn)                 -- fn вызовется когда one-shot закончится
obj:setState(name, { saveFrame = true })     -- сохранить текущий индекс кадра
obj:setState(name, { saveFrame = true, callback = fn })
obj:getState()                         -- вернуть текущее имя или nil
obj:defineState(name, def)             -- добавить/перезаписать одно состояние
obj:setDescriptions({ ... })           -- добавить/перезаписать сразу много
```

### `saveFrame`

Если старое и новое состояния имеют «одинаковую по смыслу» sequence (типа **direction change** — walk_right → walk_left), `saveFrame = true` переключит без «перемотки на первый кадр»:

```lua
hero:setState("walk_left",  { saveFrame = true })
-- анимация ходьбы продолжается с того же индекса
```

Естественно, если у нового состояния кадров меньше — индекс обрезается до `#frames`.

### Колбэк

```lua
hero:setState("attack", function()
  print("attack animation done")
end)
```

Сработает когда:
- Кадры дошли до конца (в `loop=false`-состояниях).
- Или сразу, если `#frames == 1` и `loop=false` — тогда «анимация кончилась» моментально.

### Переопределение состояний на лету

```lua
obj:defineState("new_move", { frames = "...", ... })
obj:setDescriptions({
  victory = { frames = "...", next = "idle" },
  defeat  = { frames = "...", loop = false },
})
```

Полезно, когда описание сцены грузит базовые состояния, а геймплейный код добавляет специальные.

---

## 7. Easings — полный список

Модуль `seeasings.lua` экспортирует **классические Penner easings** в двух формах:

- Базовая форма: `fn(t, b, c, d)` — `b` = начало, `c` = изменение, `d` = длительность. Классика.
- `...To`-форма: `fn(t, b, e, d)` — `b` = начало, `e` = конец. Это то, что использует `SAnimatedObject` при вычислении tween-ов (`linearTo`, `outQuadTo` и т.д.).

Глобально — `SEEasings`; также доступно как `SAnimatedObject.easings`.

### Семейства

| Семейство | Варианты |
|-----------|----------|
| `Quad`, `Cubic`, `Quart`, `Quint` | `in…`, `out…`, `inOut…`, `outIn…` |
| `Sine` | то же |
| `Expo` | то же |
| `Circ` | то же |
| `Elastic` | то же (принимают опциональные `a, p`: амплитуда, период) |
| `Back` | то же (принимает опциональный `s`: overshoot) |
| `Bounce` | то же |
| `linear` | без вариантов |

### Именование в SAnimatedObject

В `scripts` вы указываете имя **без** суффикса `To`:

```lua
{"easyng", 0.5, "outElastic", { scale = {from=1, to=1.5} }}
-- движок добавит "To" → будет использован outElasticTo
```

Если ваше имя не находится — используется `linearTo`.

### Кастомные easings

```lua
SAnimatedObject.easings.myWobbleTo = function(t, b, e, d)
  local c = e - b
  return b + c * (1 - math.cos(t / d * math.pi * 2)) / 2
end
-- теперь можно: "easyng", 1, "myWobble", { ... }
```

---

## 8. Типовые паттерны

### Idle + Attack + Hit, автовозврат

```lua
states = {
  idle = { frames = {"idle_%02d", 0.15, 1, 4}, loop = true },

  attack = {
    frames = {"attack_%02d", 0.08, 1, 6},
    loop = false, next = "idle",
    scripts = {
      {"wait", 0.1},
      {"easyng", 0.1, "outQuad", { x = {from=0, to=20} }},
      {"easyng", 0.2, "inQuad",  { x = {from=20, to=0} }},
    },
    stopScriptAtEnd = true,
  },

  hit = {
    frames = "hit", loop = false, next = "idle",
    scripts = { {"shake", 0.3, {dx=8, dy=4}} },
    stopScriptAtEnd = true,
  },
}
```

### Мигание при уроне

```lua
states.invulnerable = {
  frames = {"hero_idle_%02d", 0.15, 1, 4},
  loop = true,
  scripts = {
    {"wait", 0, { alpha = 1 }},
    {"wait", 0.1},
    {"wait", 0, { alpha = 0.24 }},
    {"wait", 0.1},
  },
  -- scripts зациклены, кадры тоже — моргаем, пока не сменим состояние
}
```

### Scale-punch на click

```lua
states.clicked = {
  frames = "icon_normal", loop = false, next = "idle",
  scripts = {
    {"easyng", 0.08, "outQuad", { scale = {from=1,    to=1.25} }},
    {"easyng", 0.15, "outBack", { scale = {from=1.25, to=1.0}  }},
  },
  stopScriptAtEnd = true,
}
```

### Victory-пульс с окончанием через событие

```lua
states.victory = {
  frames = {"victory_%02d", 0.1, 1, 8},
  loop = true,
  scripts = {
    {"pulse", 0.6, {freq = 10, amp = 0.1}},
  },
  onScriptsEnd = function(self)
    -- пульс прошёл один раз? Это и есть «конец» — вернёмся в idle через 2 секунды
    self:setState("idle")
  end,
}
```

### Intro → Loop через `onFramesEnd`

```lua
states.appear = {
  frames = {"appear_%02d", 0.1, 1, 6},
  loop = false,
  onFramesEnd = "idle",      -- когда 6 кадров доиграли, switch
}
```

Альтернативно `next = "idle"` — эффект тот же, но `onFramesEnd` позволяет также вызвать функцию.

---

## 9. Edge cases

### `setState` с тем же именем

Не перезапускает состояние. Если хотите «сбросить» — сначала переключитесь на что-то другое, потом обратно.

Если нужна возможность сбросить — простой паттерн: добавьте состояние `reset` с `next = "yourState"` и `frames = "first_frame", loop = false`. Или явно вызовите `obj._sprite:setCurrentFrame(1)`.

### Scripts выполняются в `update`, кадры — через child-пропагацию

Вам не нужно об этом думать до момента debug-а синхронизации, но знайте:

- `SAnimatedObject:update(dt)` — это **только** продвижение scripts.
- Кадровая анимация (`_sprite.update`) идёт через обычный child-`__update` — когда `SAnimatedObject:__update` рекурсивно вызывает детей.

То есть и то, и другое обновляется в одном кадре, но через разные пути.

### `_sprite.color` vs `self.color`

- `self.color` — цвет самого `SAnimatedObject`-узла (обычно не используется, потому что рендер идёт через `_sprite`).
- `self._sprite.color` — цвет кадровой анимации. Это именно он меняется через `alpha` / `color` в state-definition и в scripts.

Если вы применили шейдер к поддереву с `SAnimatedObject`, и цвет не работает — проверьте, что вы меняете `_sprite.color`, а не `self.color`.

### `saveFrame` и последний кадр

```lua
obj:setState("walk_left", { saveFrame = true })
-- новое состояние имеет меньше кадров, чем старое
```

`frame = math.min(prevFrame, #newFrames)` — кадр обрежется до последнего доступного. Это не баг, а практичное поведение: две последовательности редко имеют одинаковую длину, а «переключить между сценами ходьбы без сброса» — самый частый случай.

### Прерывание scripts через `setState`

Когда вы делаете `setState(newName)`, а в старом состоянии был запущен script-шаг — движок вызывает `done(step, obj)` на текущем шаге перед переходом. Это гарантирует, что ваши кастомные типы имеют возможность откатить изменения (восстановить `origX`, вернуть цвет и т.д.).

Если `done` нет или не реализован — состояние объекта может «зависнуть» в промежуточной позиции (например, между `shake`-кадрами). Всегда определяйте `done`, если `init` что-то захватывает.

### `onScriptsEnd` vs `onFramesEnd`

Эти два хука независимы. `scripts` — tween-цепочка, `frames` — кадровая sequence. У них могут быть разные длительности, и их окончания эмитятся отдельно. Если нужна строгая синхронизация — подгоните длительности или объедините оба в одно состояние с коротким `frames` и правильно рассчитанным `scripts`.

---

## См. также

- [SSprite.md](./SSprite.md) — `SAnimationSprite` используется внутри `SAnimatedObject` как `_sprite`.
- [SObject.md](./SObject.md) — базовый класс (SAnimatedObject наследует).
- [SESceneLoader.md](./SESceneLoader.md) — `SAnimatedObject` регистрируется в лоадере по умолчанию; манифест может описать states прямо в дереве.
