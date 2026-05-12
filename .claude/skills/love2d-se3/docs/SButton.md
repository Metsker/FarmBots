# SButton family — Extended Guide

Кнопки в SE3. Файл `sebutton.lua`.

Семейство:

| Класс | Отличие |
|-------|---------|
| `SButton` | набор state-поддеревьев (любые `SObject`-ы), переключается через `off`/`on` |
| `SSpriteButton` | один спрайт, состояние меняет текущий кадр (`setImg(states[state])`) |
| `SEmptyButton` | без визуала, только логика кнопки (`SButtonEngine` + `SKeyboardObject`) |
| `SButtonEngine` | миксин: конечный автомат состояний, таймаут долгого нажатия, события |

Все кнопки — **и мышиные, и клавиатурные** (включают `SMouseObject` + `SKeyboardObject`).

---

## Оглавление

1. [Концепция: состояния и fallback](#1-концепция-состояния-и-fallback)
2. [SSpriteButton — один спрайт с вариантами](#2-sspritebutton--один-спрайт-с-вариантами)
3. [SButton — состояния как поддеревья](#3-sbutton--состояния-как-поддеревья)
4. [SEmptyButton — невидимая кнопка](#4-semptybutton--невидимая-кнопка)
5. [События: `onClick`, `onLongPress`, `onPress`, `onRelease`, `onRepeat`](#5-события-onclick-onlongpress-onpress-onrelease-onrepeat)
6. [Долгое нажатие и автоповтор](#6-долгое-нажатие-и-автоповтор)
7. [`disable` и `disabled`](#7-disable-и-disabled)
8. [Привязка к `SEInputController`](#8-привязка-к-seinputcontroller)
9. [Текст на кнопке](#9-текст-на-кнопке)
10. [Кастомная кнопка](#10-кастомная-кнопка)

---

## 1. Концепция: состояния и fallback

У кнопки 5 состояний:

| Состояние | Когда активно |
|-----------|---------------|
| `release` | обычное состояние; курсор не наведён и не нажат |
| `over`    | курсор наведён, но не нажат |
| `press`   | нажата мышью или клавишей |
| `disable` | `setDisable(true)` был вызван, не нажата |
| `disablepress` | disabled + press (редко, для обратной связи на «заблокированную кнопку») |

**Fallback.** Если вы не определили какое-то состояние, оно подменяется предыдущим по цепочке:

```
over         → release
press        → over          (и дальше → release если over нет)
disable      → release
disablepress → disable       (и дальше → release)
```

Другими словами, **минимум, что нужно определить — это `release`**. Всё остальное опционально.

---

## 2. SSpriteButton — один спрайт с вариантами

Самый частый случай. Одна кнопка — один спрайт, меняется только картинка.

```lua
SSpriteButton{
  x = 100, y = 200,
  states  = "btn_main",    -- имя «набора» кнопки (см. ниже)
  font    = "main",
  text    = "PLAY",
  onClick = "start_game",
}
```

**Если `states` — строка**, она передаётся в `resource:getButton(name)`, который должен вернуть таблицу вида:

```lua
{
  release      = "btn_main_release",      -- имя спрайта в атласе
  over         = "btn_main_over",
  press        = "btn_main_press",
  disable      = "btn_main_disable",
  -- opt: disablePress
}
```

Какие имена реально существуют в атласе — проверяйте свой TexturePacker-проект.

**Если `states` — таблица**, она уже содержит имена спрайтов напрямую:

```lua
SSpriteButton{
  states = {
    release = "btn_start_release",
    over    = "btn_start_over",
    press   = "btn_start_press",
  },
  onClick = "start_game",
}
```

Переключение состояния подменяет `img` через `setImg(name)` — размеры и offset подхватываются автоматически (см. [SSprite.md §6](./SSprite.md#6-работа-с-атласом-и-оффсетами)).

### Текст с per-state оформлением

```lua
SSpriteButton{
  states = "btn_main",
  font   = "main",
  text   = "START",
  texts  = {
    release = { dx = 0, dy = 0,  color = {1, 1, 1, 1} },
    over    = { dx = 0, dy = -2, color = {1, 1, 0.39, 1} },
    press   = { dx = 0, dy = 2,  color = {0.78, 0.78, 0.78, 1} },
  },
  onClick = "start",
}
```

`dx/dy` — смещение текста внутри кнопки, `color` — цвет (перекрывает дефолтный; компоненты в 0..1 или HEX-строка `"#RRGGBB"` / `"#RRGGBBAA"`).

Если `texts = "some_string"`, SE3 превращает это в минимальный `{release = {...}}` — лишнего кода не требует.

---

## 3. SButton — состояния как поддеревья

Когда каждое состояние — это не просто картинка, а композиция (картинка + иконка + блик), используйте `SButton`. Каждое состояние — полный `SObject`-узел.

```lua
SButton{
  x = 100, y = 200,
  states = {
    release = SGroup{ children = {
      SSprite{ img = "btn_normal_bg" },
      SSprite{ img = "icon_play", x = -40 },
    }},
    over = SGroup{ children = {
      SSprite{ img = "btn_over_bg" },
      SSprite{ img = "icon_play", x = -40, color = {1, 1, 0.78, 1} },
    }},
    press = SSprite{ img = "btn_press_bg" },    -- можно и так
  },
  onClick = "start",
}
```

Внутри `SButton.init`:

1. Проверяется, что `release` существует.
2. Fallback-ы подставляются (`over → release` и т.д.).
3. `w, h` берутся из `release.w, release.h`.
4. Все состояния добавляются как дети через `:add`.
5. Все, кроме `release`, получают `off = true`.

Переключение `state(name)` просто меняет флаги `off`:

```lua
-- пример того, что происходит внутри:
for _, v in pairs(self.states) do v.off = true end
self.states[state].off = false
```

**Важно**: если использовать `SButton` с декларативным `SESceneLoader`, состояния можно писать прямо как table-definition — loader автоматически соберёт вложенные `{type=...}`:

```lua
{ type = "SButton",
  states = {
    release = { type = "SSprite", img = "btn_normal" },
    over    = { type = "SSprite", img = "btn_over" },
    press   = { type = "SSprite", img = "btn_press" },
  },
  onClick = "start",
}
```

---

## 4. SEmptyButton — невидимая кнопка

Без визуала. Реагирует только на клавиатуру (по умолчанию).

```lua
SEmptyButton{
  keys  = {"space", "return"},
  onClick = "submit",
}
```

Полезно для:
- Глобальных хоткеев, прицепленных к сцене.
- Клавиатурной навигации поверх мышечных `SSpriteButton`.
- Debug-команд (`F1` для открытия меню и т.д.).

Можно добавить `__includes` с `SMouseObject`, если нужна и мышь тоже — в этом случае собственная реализация `inBox` обязательна.

---

## 5. События: `onClick`, `onLongPress`, `onPress`, `onRelease`, `onRepeat`

Каждая фаза взаимодействия имеет свой action-проп. Значение — имя UI-action; при срабатывании фазы кнопка делает `model:fire("ui_<action>", self, phase?)` по per-scene SEModel. FSM-состояния ловят это через `onEvent_ui_<action>` или `onUI` catch-all (см. [SEFSM.md](./SEFSM.md)). Контроллеры или компоненты вне FSM — через `model:on("ui_<action>", fn)`.

```lua
SSpriteButton{
  states      = "btn_main",
  onClick     = "start_game",      -- model:fire("ui_start_game", self)
  onLongPress = function(self) print("long") end,
  onPress     = "pressDown",
  onRelease   = "pressUp",
  onRepeat    = "autoFire",        -- при repeatInterval
}
```

Форматы:

| Форма | Эффект |
|-------|--------|
| `onClick = "name"`      | `model:fire("ui_name", self)` |
| `onClick = "@name"`     | то же самое — `@` стилистический префикс, стрипается |
| `onClick = function(self) ... end` | прямой вызов; `self` — сама кнопка |

Слушатель со стороны приложения:

```lua
model:on("ui_start_game", function(btn)
  startGame()
end)
```

Или в FSM-состоянии декларативно:

```lua
function Lobby:onEvent_ui_start_game(btn)
  self:to("loading")
end
```

### Deprecated (удалено 2026-04-22)

`event = "…"` / `longevent = "…"` — раньше фаерили `Signal.emit("click", name)`. Для обратной совместимости **ещё работают** (алиасятся в `onClick` / `onLongPress`), но будут удалены. Миграция:

```lua
-- было                      ->  стало
event     = "play"           ->  onClick     = "play"
longevent = "autoFire"       ->  onLongPress = "autoFire"
Signal.register("click", fn) ->  model:on("ui_<name>", fn)
```

---

## 6. Долгое нажатие и автоповтор

### Один longpress по таймауту

```lua
SSpriteButton{
  states      = "btn_skip",
  onClick     = "skip",
  onLongPress = "skip_all",   -- при удержании 0.8 сек
  timeout     = 0.8,
}
```

Поведение:

1. Пользователь нажал кнопку → `press`.
2. Через `timeout` секунд вызывается `onLongPress` (и **отпускает** кнопку в `release`).
3. Если отпустить раньше `timeout` — обычный `click` → `onClick`.

### Автоповтор — `repeatInterval`

```lua
SSpriteButton{
  states         = "btn_down",
  onClick        = "scroll_down",        -- одиночный клик
  onLongPress    = "scroll_down",        -- первый автоповтор
  onRepeat       = "scroll_down_fast",   -- последующие повторы (optional, иначе onLongPress)
  timeout        = 0.4,                  -- задержка до первого повтора
  repeatInterval = 0.08,                 -- интервал между повторами
}
```

После `timeout` кнопка **не** возвращается в `release`, а остаётся в `press` и каждые `repeatInterval` секунд стреляет `onRepeat` (или `onLongPress`/`onClick` если не задан). Отпускание возвращает в `release` без финального `click`.

Это классический паттерн «плюсик в настройках» — зажал и значение растёт.

---

## 7. `disable` и `disabled`

Два разных флага:

- `self.disable` — **отключает логику кнопки** (клики игнорируются), но визуально кнопка рисует состояние `disable` (серая/полупрозрачная).
- `self.disabled` — **отключает клик**, но не трогает визуал. Используется внутри `SMouseObject` для блокировки конкретного события.

Чаще нужен первый. Управляется:

```lua
btn:setDisable(true)   -- кнопка теперь в disable
btn:setDisable(false)  -- снова кликается
```

После установки `disable` кнопка переключается в состояние `disable` через `SButtonEngine:state("disable")`. При нажатии на disabled-кнопку покажется `disablepress` (если определён).

---

## 8. Привязка к `SEInputController`

`SButtonEngine:bindAction(controller, name)` привязывает кнопку к именованному действию в `SEInputController`. Тогда клавиатурное событие, настроенное на этот action, «вызовет» логику кнопки.

```lua
local input = SEInputController{
  bindings = {
    fire = { keys = {"space"} },
  },
}

local btn = SSpriteButton{ states = "btn_fire", onClick = "fire_weapon" }
btn:bindAction(input, "fire")
-- теперь пробел заставит кнопку отыграть press → release и вызовет event
```

Подробнее — см. [SEInputController.md](./SEInputController.md).

---

## 9. Текст на кнопке

`SSpriteButton` умеет рисовать текст поверх себя. Механизм:

- В конструкторе `SSpriteButton.init` вызывается `setFont(p.font)` — создаётся дочерний `SText` с `align = "center"` и `maxWidth = self.w`.
- `setText(text)` меняет текст этого `SText`.
- `texts = { release = {dx, dy, color}, over = ... }` задаёт per-state смещение и цвет текста.

```lua
SSpriteButton{
  states = "btn_main",
  font   = "main",
  text   = "Long label",
  -- Автоматически переносится по ширине кнопки, центрируется
}
```

Для `SButton` (не-sprite вариант) — текст надо положить как часть `release`-поддерева:

```lua
SButton{
  states = {
    release = SGroup{
      SSprite{ img = "btn_bg" },
      SText{ font = "main", text = "OK", pivot = {0.5, 0.5} },
    },
    ...
  },
}
```

---

## 10. Кастомная кнопка

Минимум для своего класса кнопки — `SObject` + `SButtonEngine` + хотя бы один из миксинов ввода.

```lua
local CircleButton = Class{
  __includes = { SObject, SButtonEngine, SMouseObject, SKeyboardObject },
  init = function(self, p)
    SObject.init(self, p)
    self.radius  = p.radius or 50
    self.onClick = p.onClick
    self.keys    = p.keys or {}
    self._stateColor = {
      release = {0.78, 0.78, 0.78, 1},
      over    = {1,    1,    0.39, 1},
      press   = {1,    0.59, 0.39, 1},
      disable = {0.47, 0.47, 0.47, 1},
    }
    self:state("release")
  end
}

function CircleButton:state(state)
  self.color = self._stateColor[state]
end

function CircleButton:inBox(x, y)
  return x * x + y * y <= self.radius * self.radius
end

function CircleButton:draw(x, y, r, sx, sy)
  if self.color then love.graphics.setColor(self.color) end
  love.graphics.circle("fill", x, y, self.radius * sx)
  love.graphics.setColor(1, 1, 1, 1)
end
```

Что обязательно:

- Вызов `self:state("release")` в `init` (иначе текущее состояние `nil` и первый ховер не отработает).
- Переопределить `state(name)` под ваш способ отрисовки.
- `inBox(x, y)` — если геометрия не прямоугольник.
- `event` (или собственный обработчик `click`).

Дополнительно — `keys`, `setDisable`, `longevent`, `timeout` работают из коробки через `SButtonEngine`.

---

## См. также

- [SObject.md](./SObject.md) — базовый класс и миксины `SMouseObject`/`SKeyboardObject`.
- [SEInputController.md](./SEInputController.md) — именованные actions и bindAction.
- [SText.md](./SText.md) — `STextObject` миксин, используемый внутри `SSpriteButton`.
