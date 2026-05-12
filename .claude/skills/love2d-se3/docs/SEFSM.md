# SEFSM — Extended Guide

`SEFSM` — state machine сцены. Состояния описаны отдельными классами (наследниками `SEFSMState`), переключение через `:to(name, params)`, внутренние таймеры с автоотменой, автоматические биндеры на поля `SEModel` и на события (включая клики по кнопкам). Менеджер сцен сам создаёт и уничтожает FSM вокруг `onEnter`/`onLeave`, как он это делает с `model`.

Файл с реализацией: `sefsm.lua`.

---

## Оглавление

1. [Зачем FSM](#1-зачем-fsm)
2. [Минимальный пример](#2-минимальный-пример)
3. [Жизненный цикл и порядок вызовов](#3-жизненный-цикл-и-порядок-вызовов)
4. [Магия имён: `onModel_`, `onEvent_`, `onUI`](#4-магия-имён-onmodel_-onevent_-onui)
5. [Таймеры: `once` и `every`](#5-таймеры-once-и-every)
6. [Переходы, история, `back()`](#6-переходы-история-back)
7. [Как состояние говорит с UI](#7-как-состояние-говорит-с-ui)
8. [UI-события: кнопки, InputController, `ui_` префикс](#8-ui-события-кнопки-inputcontroller-ui_-префикс)
9. [Ручные биндинги: `bindModel`, `bindEvent`](#9-ручные-биндинги-bindmodel-bindevent)
10. [Полный пример: аркада с лобби, игрой, смертью](#10-полный-пример-аркада-с-лобби-игрой-смертью)
11. [Антипаттерны](#11-антипаттерны)
12. [API Reference](#12-api-reference)

---

## 1. Зачем FSM

Как только в сцене появляется нетривиальный поток «подождал → кнопка нажата → играем → смерть → экран результатов → перезапуск», возникает вопрос — где это жить? Вариантов без FSM два:

- **Всё в контроллере сцены с флагами** — `self.state = "playing"` и набором `if`-ов. Быстро превращается в спагетти.
- **Свои подписки на Signal + ручная отписка в переходах** — работает, но каждое состояние тащит за собой бухгалтерию «что подписано».

`SEFSM` добавляет слой, который:

- Держит «текущее состояние» как объект с собственными коллбэками.
- Автоматически собирает и рвёт подписки на модель / события при входе/выходе.
- Даёт таймеры `once`/`every`, которые отменяются сами при выходе из состояния.
- Ведёт стек истории для переходов типа «назад» (ESC из паузы, retry после смерти).

Сцена при этом всё равно имеет контроллер (для raw-событий Love2D, если нужны) и модель (данные). FSM — это «что сейчас происходит в игре».

---

## 2. Минимальный пример

```lua
-- scenes/arena/scene_description.lua
return {
  fsm = "arena_fsm",
  scene = { type = "SGroup" },
}
```

```lua
-- scenes/arena/arena_fsm.lua — форма (b): plain-table
return {
  initial = "idle",
  states = {
    idle    = "states.idle",
    playing = "states.playing",
    dead    = "states.dead",
  },
}
```

```lua
-- scenes/arena/states/idle.lua
local Idle = Class{__includes = {SEFSMState}}

function Idle:onEnter(params, prevName)
  self:every(0.5, function(self)
    self.fsm.model:set("blink", not self.fsm.model:get("blink"))
  end)
end

function Idle:onEvent_ui_play(btn)
  self:to("playing", { reason = "user" })
end

function Idle:onModel_hp(v, k)
  if v and v <= 0 then self:to("dead") end
end

return Idle
```

```lua
-- scenes/arena/states/playing.lua
local Playing = Class{__includes = {SEFSMState}}

function Playing:onEnter(params, prevName)
  print("entered playing, reason =", params and params.reason)
end

function Playing:onEvent_ui_quit()
  self:to("idle")
end

return Playing
```

Готово. Клик по кнопке с `onClick = "@play"` переведёт FSM в `playing`. Падение `hp` до нуля — в `dead`. Таймер в `idle` живёт пока FSM там, и умирает при переходе.

---

## 3. Жизненный цикл и порядок вызовов

### На входе сцены (`manager:change("arena")`)

1. `preload` читает `manifest.fsm`, создаёт инстанс FSM (но **не стартует**).
2. Модель создана. `_G.model` и `_G.fsm` выставлены в глобалы.
3. Строится scene tree.
4. `controller:onEnter(scene, params)` — если есть контроллер.
5. **`fsm:start()`** — переходит в `initial` состояние. В этот момент:
   - Создаётся инстанс `initial`-состояния (класс вызывается через `cls(fsm)`).
   - Конструктор `SEFSMState.init` сканирует методы класса и запоминает магические имена (`onModel_*`, `onEvent_*`, `onUI`), но **не подписывается**.
   - Бежит `state:onEnter(params=nil, prevName=nil)`.
   - **После** `onEnter` регистрируются магические подписки. Это важно: ваш `onEnter` может инициализировать поля, которые нужны в `onModel_*` обработчиках, — и первый initial-fire придёт уже в готовое состояние.
6. `manifest.onEnter(scene, params)` — последним.

### На каждом кадре

- `controller:update(dt)` (если есть)
- `fsm:update(dt)` — тикает таймеры текущего состояния. Контроллер перед этим успел обновить свой frame-state; сцена после этого получит актуальные значения в model.
- `scene:__update(dt)`
- `scene:__draw()` → controller `:draw()`

### На переходе `self:to("next", params)`

1. `prev_state:_deactivate(next_name)`:
   - `state:onExit(nextName)` — если определён.
   - Все таймеры сбрасываются.
   - Все магические подписки отписываются.
2. Текущее имя кладётся в стек истории.
3. `next_state = NextClass(fsm)` — конструктор.
4. `state:onEnter(params, prevName)`.
5. Магические подписки регистрируются.

### На выходе сцены (`manager:change("other")`)

1. `manifest.onLeave` → `controller:onLeave`.
2. **`fsm:destroy()`** — внутри вызывается `stop()` → `state:_deactivate` текущего состояния → все подписки/таймеры рвутся.
3. `model:destroy()` — рвёт всё, что FSM (и UI) держал через KV и события.
4. Сброс `_G.fsm` и `_G.model`.

Порядок важен: FSM уничтожается до модели, чтобы его `onExit` могли ещё писать в неё последним штрихом («сохранить прогресс», «записать итог»).

---

## 4. Магия имён: `onModel_`, `onEvent_`, `onUI`

При создании экземпляра состояния `SEFSMState:init` сканирует все методы своего класса (включая унаследованные). Если имя метода начинается с одного из префиксов — регистрируется автоматическая подписка.

| Метод | Канал | Что подписывает |
|---|---|---|
| `onModel_<key>(v, k)` | KV модели | `fsm.model:subscribe("<key>", …)` — ключ бит-в-бит |
| `onEvent_<name>(...)` | events модели | `fsm.model:on("<name>", …)` — имя бит-в-бит |
| `onUI(name, ...)` | events catch-all | `fsm.model:on("*", …)`, фильтр на `ui_`-префикс, имя в коллбэк приходит **без префикса** |

### Правила

- **Регистр ключа/имени важен.** `onModel_HP` → ключ `"HP"`, не `"hp"`. Договоритесь на уровне проекта и держите единый стиль.
- **Разделитель в имени события — всё что после префикса до конца.** `onEvent_ui_play` → имя `"ui_play"` (именно поэтому кнопки фаерят `ui_<action>` — получаешь один обработчик под конкретный клик).
- **Первый initial-fire приходит после `onEnter`.** Ваш `onEnter` полностью проинициализирует инстанс до того, как `onModel_hp(nil, "hp")` попытается что-то прочитать из `self`.
- **`onUI` — только префикс `ui_`.** Если событие `shop_open` (нет префикса) — `onUI` не вызывается. `onEvent_shop_open` — вызывается.

### `onUI` — зачем

Это единый catch-all под все пользовательские события. Удобно для дебага/логов/звуков «на любой клик». Пример:

```lua
function Playing:onUI(name, btn)
  print("UI event:", name)
  if name == "quit" or name == "pause" then
    soundManager:play("click")
  end
end
```

`onUI` срабатывает **дополнительно** к специфичному `onEvent_ui_<name>` — оба хука активны одновременно.

### Multi-key и сложное — руками

Магия покрывает single-key case. Для multi-key или динамических биндингов — `bindModel`/`bindEvent` в `onEnter`:

```lua
function Playing:onEnter(params, prevName)
  self:bindModel({"hp", "mp"}, function(self, v, k)
    self:refreshStats()
  end)
  self:bindEvent("shop_transaction", function(self, delta)
    self.fsm.model:set("coins", (self.fsm.model:get("coins") or 0) + delta)
  end)
end
```

Токены трекуются и автоматически чистятся в `onExit`.

---

## 5. Таймеры: `once` и `every`

```lua
self:once(1.0, function(self)
  print("one second after entering state")
end)

self:every(0.5, function(self)
  self.fsm.model:set("blink", not self.fsm.model:get("blink"))
end)
```

- `fn(self)` — вызывается с инстансом состояния.
- Оба метода регистрируют таймер, привязанный к **текущему состоянию**. При `onExit` таймер автоматически отменяется, даже если не успел сработать.
- Можно ставить сколько угодно таймеров в одном состоянии — все они тикают параллельно.
- Внутри таймер-коллбэка можно звать `self:to("next")` — это безопасно, дальнейшие тики того же состояния не будут вызваны.

### Каскад `once`

```lua
function Opening:onEnter()
  self:once(0.5, function(self)
    self.fsm.model:set("intro_text", "Ready…")
    self:once(1.0, function(self)
      self.fsm.model:set("intro_text", "Go!")
      self:once(0.5, function(self) self:to("playing") end)
    end)
  end)
end
```

Вложенные `once` работают как ожидаете — всё дерево отменяется, если состояние меняется раньше срока.

### Что делать если нужно пропустить первый тик `every`

Нет встроенного `{delay=0.5}` — используйте комбинацию:

```lua
self:once(initialDelay, function(self)
  self:every(interval, tickFn)
end)
```

---

## 6. Переходы, история, `back()`

```lua
self:to("next")                      -- без params
self:to("next", { reason = "user" }) -- params придут в next.onEnter
```

`onEnter` получает `(params, prevName)`:

```lua
function Dead:onEnter(params, prevName)
  print("died, came from:", prevName)     -- "playing"
  if params and params.reason == "hp" then
    self.fsm.model:fire("ui_showDeathModal")
  end
end
```

### История

Полный стек, без ограничения глубины.

```lua
fsm:previous()       -- имя предыдущего состояния (или nil), без перехода
fsm:back()           -- переход в предыдущее, pop со стека
fsm:back(params)     -- то же, с params в onEnter предыдущего
fsm:history()        -- копия стека {oldest, …, newest}
```

### Что пушится в стек

При каждом `:to(name)` текущее имя кладётся в стек. `:back()` снимает верх стека и переходит туда. **Обратного стека нет** — после `back` ты потерял ту ветку; если нужно forward-redo, делайте его руками.

`:start()` (первый переход в initial) стек не трогает — нельзя вернуться в «до-начала».

### Зачем

Типовые use cases:
- **Pause overlay.** Из `playing` → `paused`. В `paused` кнопка Resume → `fsm:back()`.
- **Settings из любого экрана.** Вместо того чтобы явно помнить, откуда пришли — `fsm:back()`.
- **Retry.** После `dead` кнопка Retry переходит в `playing`. History для записи статистики «сколько раз переигрывали».

---

## 7. Как состояние говорит с UI

**Принципиальный момент:** у состояния **нет прямого доступа к scene graph** — ни `fsm.scene`, ни `byId`. Канал в UI один — **запись в модель**. Компоненты подписаны на модель декларативно (через `$key` в манифесте или `node:bind`), любой `model:set` сам пропагируется.

```lua
function Playing:onEnter(params, prevName)
  self.fsm.model:set("gameover_visible", false)
  self.fsm.model:set("score", 0)
end

function Playing:onExit(nextName)
  if nextName == "dead" then
    self.fsm.model:set("gameover_visible", true)
  end
end
```

В манифесте:

```lua
{
  type = "SGroup",
  id = "gameover",
  -- привязываем поле модели к пропу
  off = "$?gameover_off",          -- true = скрыт и без событий; nil = пропускаем
  ...
}
```

**Важно:** для `SGroup` используем `off` — `.hidden` проверяется только в `SSprite` / `SText` внутри их собственного `draw()`. `.off` отключает и рендер, и события для всего поддерева. SE3 предоставляет `setOff` / `setHidden` / `setEventoff` на `SObject` — все nil-толерантные, с нормализацией boolean.

### Когда нужно широковещать событие (не данные)

`fsm.model:fire("name", args)` — событие без сохранения. Компонент подписывается через `model:on` или FSM-состояние через `onEvent_<name>`.

```lua
-- из состояния
function Dead:onEnter()
  self.fsm.model:fire("ui_showDeathModal")
end

-- в другом состоянии
function ResultsScreen:onEvent_ui_showDeathModal()
  self:fadeIn()
end
```

Использовать когда:
- Событие не имеет «текущего значения» — просто факт (triggered VFX, played sound).
- Несколько подписчиков должны узнать.
- Не нужно, чтобы новые подписчики получали его постфактум.

---

## 8. UI-события: кнопки, InputController, `ui_` префикс

### Правило

Все пользовательские события имеют префикс `ui_` в канале модели:

- Кнопка с `onClick = "play"` при клике делает `model:fire("ui_play", btn)`.
- Input controller с action `shoot` и `onClick = "fire"` при срабатывании делает `model:fire("ui_fire", action, phase)`.
- Жест/кастомный ввод — по той же схеме, `model:fire("ui_" .. name, ...)`.

### Кнопки (SButton / SSpriteButton)

Вместо старого `event = "play"` теперь per-phase поля:

```lua
{ type = "SSpriteButton",
  states = "play_btn",
  onClick     = "play",        -- → model:fire("ui_play", self)     при клике
  onLongPress = "autoFire",    -- → model:fire("ui_autoFire", self) при долгом нажатии
  onPress     = "pressDown",
  onRelease   = "pressUp",
  onRepeat    = "autoFire",    -- при repeatInterval, если задан timeout
  timeout     = 0.5,
  repeatInterval = 0.1,
}
```

- Префикс `@` у значения опционален: `onClick = "@play"` и `onClick = "play"` — эквивалентны.
- Если фаза не указана — ничего не фаерим.
- Если `_G.model` отсутствует (кнопка вне управляемой сцены) — тихо ничего не фаерим; функции-обработчики продолжают работать.
- **Deprecated (убрано 2026-04-22):** `event = "..."` и `longevent = "..."`. Но для обратной совместимости всё ещё поддерживаем — просто они алиасятся в `onClick` и `onLongPress`.

### SEInputController

Те же per-phase action-имена в `bind(name, def)`:

```lua
ic:bind("shoot", {
  keys         = {"space", "lclick"},
  onClick      = "fire",        -- → ui_fire при отпускании (если не было long press)
  onLongPress  = "autoFire",    -- → ui_autoFire после longPressTime
  onRepeat     = "autoFire",    -- → ui_autoFire каждые repeatInterval, пока держат
  onPress      = "aimStart",    -- → ui_aimStart на press
  onRelease    = "aimEnd",      -- → ui_aimEnd на release
})
```

Коллбэк в модели получает `(action, phase)` — иногда полезно знать, в какой фазе сработало:

```lua
function Playing:onEvent_ui_autoFire(action, phase)
  if phase == "longpress" then play_sfx("charge") end
  spawn_bullet()
end
```

### `onUI(name, ...)` catch-all vs `onEvent_ui_<name>` конкретный

Оба могут сосуществовать. Вот типовой паттерн — универсальный sfx + специфичная логика:

```lua
function Playing:onUI(name, ...)
  soundManager:play("click")        -- абсолютно любой UI-клик играет звук
end

function Playing:onEvent_ui_play()
  self:to("playing2")               -- только конкретная кнопка делает переход
end

function Playing:onEvent_ui_autoFire()
  spawn_bullet()
end
```

### Когда буттон не привязан к FSM

Ничего не ломается. `model:fire("ui_play", btn)` произойдёт всё равно; если в модели нет никого, кто `on("ui_play", fn)` — событие просто никуда не придёт. Ваш контроллер сцены может сам подписаться:

```lua
function Controller:onEnter(scene, params)
  self._playSub = model:on("ui_play", function(btn)
    print("play clicked")
  end)
end

function Controller:onLeave()
  model:off(self._playSub)
end
```

Но в 90% случаев FSM покрывает сценарии.

---

## 9. Ручные биндинги: `bindModel`, `bindEvent`

Для случаев, которые магия не ловит:
- Multi-key подписка на модель.
- Динамические подписки (по условию, в рантайме).
- Подписка на `globalModel` или другую модель.
- Nested / сложная логика с `immediate = false`.

```lua
function Playing:onEnter(params, prevName)
  -- multi-key: обновить HUD когда хоть одно из полей сменилось
  self:bindModel({"hp", "mp", "shield"}, function(self, v, k)
    self:refreshHUD()
  end)

  -- конкретное событие (как onEvent_*, но с динамикой)
  local eventName = params and params.eventName or "default"
  self:bindEvent(eventName, function(self, ...)
    print("got", eventName)
  end)

  -- globalModel напрямую (магия смотрит только на fsm.model)
  self._coinsSub = globalModel:subscribe("coins", function(v)
    self.fsm.model:set("coinsDisplay", v)
  end)
end

function Playing:onExit()
  -- bindModel/bindEvent чистятся сами — а вот globalModel НЕТ
  if self._coinsSub then globalModel:unsubscribe(self._coinsSub) end
end
```

`bindModel` принимает те же `opts` что `SEModel:subscribe` (`immediate`, `skipNil`).

---

## 10. Полный пример: аркада с лобби, игрой, смертью

```lua
-- scenes/arena/scene_description.lua
return {
  model      = "arena_model",
  fsm        = "arena_fsm",
  controller = "arena_controller",
  resources  = {
    fonts = {{ name = "hud", path = "assets/font.ttf", size = 24 }},
  },
  scene = {
    type = "SGroup", id = "root",
    {
      type = "SText", id = "status", font = "hud",
      text = "$status_text", x = 400, y = 50,
    },
    {
      type = "SText", id = "hp", font = "hud",
      text = "$?hp_text", x = 50, y = 50,
    },
    {
      type = "SGroup", id = "overlay_dead",
      off = "$?dead_off",            -- true = экран смерти скрыт целиком
      {
        type = "SSpriteButton", states = "retry_btn",
        onClick = "retry",
        x = 400, y = 300,
      },
    },
    {
      type = "SSpriteButton", states = "play_btn",
      onClick = "play",
      x = 400, y = 400,
      off = "$?lobby_off",           -- скрываем кнопку вне лобби
    },
  },
}
```

```lua
-- scenes/arena/arena_model.lua
local AM = Class{__includes = {SEModel}}

function AM:init(data)
  SEModel.init(self, data or {
    hp = 100, maxHP = 100,
    status_text = "Press PLAY",
    lobby_off = false,
    dead_off  = true,
  })
end

function AM:override_hp(v, cur)
  if v == nil then return v end
  return math.max(0, math.min(self:get("maxHP"), v))
end

function AM:bind_hp(v)
  if v == nil then self:set("hp_text", nil); return end
  self:set("hp_text", string.format("HP %d/%d", v, self:get("maxHP")))
end

return AM
```

```lua
-- scenes/arena/arena_fsm.lua
local AFSM = Class{__includes = {SEFSM}}
function AFSM:init()
  SEFSM.init(self, {
    initial = "lobby",
    states = {
      lobby   = "states.lobby",
      playing = "states.playing",
      dead    = "states.dead",
    },
  })
end
return AFSM
```

```lua
-- scenes/arena/states/lobby.lua
local Lobby = Class{__includes = {SEFSMState}}

function Lobby:onEnter(params, prevName)
  self.fsm.model:set("status_text", prevName == "dead" and "Try again?" or "Press PLAY")
  self.fsm.model:set("lobby_off", false)
  self.fsm.model:set("dead_off",  true)
end

function Lobby:onEvent_ui_play()
  self:to("playing")
end

function Lobby:onEvent_ui_retry()
  self.fsm.model:set("hp", self.fsm.model:get("maxHP"))
  self:to("playing")
end

return Lobby
```

```lua
-- scenes/arena/states/playing.lua
local Playing = Class{__includes = {SEFSMState}}

function Playing:onEnter(params, prevName)
  self.fsm.model:set("lobby_off", true)
  self.fsm.model:set("status_text", "FIGHT!")
  self.fsm.model:set("hp", self.fsm.model:get("maxHP"))

  -- раз в секунду игрок получает чуть-чуть урона
  self:every(1.0, function(self)
    self.fsm.model:set("hp", self.fsm.model:get("hp") - 10)
  end)
end

function Playing:onModel_hp(v, k)
  if v and v <= 0 then self:to("dead", { cause = "hp" }) end
end

function Playing:onEvent_ui_autoFire(action, phase)
  -- input action или кнопка с onLongPress = "autoFire"
  print("shooting, phase:", phase)
end

return Playing
```

```lua
-- scenes/arena/states/dead.lua
local Dead = Class{__includes = {SEFSMState}}

function Dead:onEnter(params, prevName)
  self.fsm.model:set("status_text", "DEAD")
  self.fsm.model:set("dead_off", false)

  -- через 3 секунды переход в лобби, если пользователь не нажал Retry
  self:once(3.0, function(self)
    self:to("lobby")
  end)
end

function Dead:onEvent_ui_retry()
  self.fsm.model:set("hp", self.fsm.model:get("maxHP"))
  self:to("playing")
end

return Dead
```

Что происходит:

- Входим в сцену → initial `lobby` → на экране «Press PLAY», PLAY видна.
- Клик PLAY → `ui_play` → `Lobby:onEvent_ui_play` → `:to("playing")`.
- В `playing`: HP = 100, раз в секунду `-10`. SText привязан к `$?hp_text` → обновляется сам.
- HP доходит до 0 → `override_hp` сжимает в 0 → `bind_hp` обновляет `hp_text` → `Playing:onModel_hp` ловит значение → `:to("dead")`.
- В `dead`: показан retry. Если пользователь не жмёт — через 3 секунды `once` фаерит `:to("lobby")`. В `lobby:onEnter` видно `prevName == "dead"`, меняем надпись.
- Retry → `Dead:onEvent_ui_retry` → сбрасывает HP → `:to("playing")`.

---

## 11. Антипаттерны

### ❌ Использовать `fsm.scene` или `byId` из состояния

Состояние не должно знать про scene graph. Всё через модель:

```lua
-- ❌ плохо
function Playing:onEnter()
  self.fsm.scene:byId("hud.score"):setText("0")
end

-- ✅ правильно
function Playing:onEnter()
  self.fsm.model:set("score", 0)   -- SText с text = "$score" обновится сам
end
```

### ❌ Забывать про автоматический initial fire в `onModel_*`

`onModel_hp` сработает сразу после `onEnter` с текущим значением. Если это nil — обработчик должен быть готов:

```lua
-- ❌ упадёт при входе, если hp ещё не установлен
function State:onModel_hp(v, k)
  if v <= 0 then ...

-- ✅ ок
function State:onModel_hp(v, k)
  if v and v <= 0 then ...
end
```

### ❌ Делать `self:to()` в цикле / конфликтный переход

Если в одном тике несколько подписок дёрнут `:to()` — сработает только первая, остальные попадут в уже уничтоженное состояние:

```lua
-- ❌
function Idle:onModel_hp(v, k)  if v <= 0 then self:to("dead") end end
function Idle:onModel_mp(v, k)  if v <= 0 then self:to("dead") end end
-- в mp-обработчике self уже destroyed

-- ✅ проверять что ещё актуален
function Idle:onModel_hp(v, k)
  if v and v <= 0 and self.fsm:currentState() == self then self:to("dead") end
end
```

Таймеры `every` делают это автоматически — после `to` они бейлят из цикла. Коллбэки подписок — нет.

### ❌ Подписываться на `globalModel` магией

`onModel_*` магия смотрит только на scene `fsm.model`. Для `globalModel` — руками:

```lua
-- ❌ не сработает
function State:onModel_playerCoins(v)  -- это про fsm.model.playerCoins, не globalModel

-- ✅
function State:onEnter()
  self._sub = globalModel:subscribe("coins", function(v) ... end)
end
function State:onExit()
  if self._sub then globalModel:unsubscribe(self._sub) end
end
```

### ❌ Хранить state-локальные данные на FSM

```lua
-- ❌
function Playing:onEnter()
  self.fsm.score = 0   -- загрязняет FSM, переживёт своё состояние
end

-- ✅
function Playing:onEnter()
  self.score = 0       -- живёт на инстансе состояния, умирает с ним
  -- или через модель:
  self.fsm.model:set("score", 0)
end
```

---

## 12. API Reference

### `SEFSM`

```lua
SEFSM(def)                         -- или SEFSM.new(def)
-- def = { initial = "name", states = { name = "require.path" or Class } }
```

Методы:

```lua
fsm:start()                        -- enter initial state
fsm:stop()                         -- exit current, no further transitions
fsm:to(name, params?)              -- transition; pushes current onto history
fsm:current()                      -- current state name
fsm:currentState()                 -- current SEFSMState instance
fsm:previous()                     -- prev name or nil
fsm:back(params?)                  -- pop history, transition
fsm:history()                      -- copy of history stack
fsm:update(dt)                     -- tick timers of current state
fsm:destroy()                      -- stop + release everything
fsm:isAlive()                      -- bool
```

Поля (устанавливаются менеджером до `:start()`):

- `fsm.model` — per-scene SEModel.
- `fsm.controller` — контроллер сцены (или nil).

Менеджер сам зовёт `:start()` после `controller:onEnter` и `:destroy()` до `model:destroy()`. Вручную вызывать не нужно.

### `SEFSMState`

Базовый класс. Подклассы — через hump.class:

```lua
local MyState = Class{__includes = {SEFSMState}}
-- init опционален; если есть — первым делом SEFSMState.init(self, fsm)
function MyState:init(fsm)
  SEFSMState.init(self, fsm)
  ...
end
```

Поля инстанса:

- `self.fsm` — родительский SEFSM.
- `self.parent` — алиас `self.fsm`.

Хуки (переопределяйте):

```lua
function MyState:onEnter(params, prevName)   end
function MyState:onExit(nextName)            end
```

Магические префиксы методов (скан в `SEFSMState.init`):

```lua
function MyState:onModel_<key>(v, k)          -- fsm.model:subscribe("<key>", ...)
function MyState:onEvent_<name>(...)          -- fsm.model:on("<name>", ...)
function MyState:onUI(name, ...)              -- fsm.model:on("*", ...), фильтр ui_*
```

Таймеры и хелперы:

```lua
state:once(sec, fn)                -- fn(state), разово, отменяется на onExit
state:every(sec, fn)               -- fn(state), периодически
state:to(name, params?)            -- shortcut fsm:to
state:bindModel(keyOrList, fn, opts?)    -- ручная KV-подписка, auto-cleanup
state:bindEvent(name, fn)                -- ручная event-подписка, auto-cleanup
```

### `SEModel` — новое: канал событий

```lua
model:fire(name, ...)              -- broadcast
token = model:on(name, fn)         -- subscribe; fn(...)
token = model:on("*", fn)          -- catch-all; fn(name, ...)
model:off(token)
```

Не путать с KV-методами (`set`/`subscribe`/`emit`) — это отдельный dispatcher. События транзитны: подписались после `fire` — пропустили.

### Манифест

```lua
return {
  model      = "arena_model",        -- опционально
  fsm        = "arena_fsm",          -- опционально; require-путь относительно сцены
  controller = "arena_controller",   -- опционально
  scene      = { ... },
}
```

FSM-модуль возвращает:
- (a) класс: `Class{__includes = {SEFSM}}` с `init = function(self) SEFSM.init(self, {...}) end`
- (b) plain table: `{ initial = "…", states = {...} }` — автоматически оборачивается в `SEFSM(...)`

Пути состояний (`states = { idle = "states.idle" }`) относительны сценарной директории. Абсолютный путь с `!`: `"!shared.states.idle"`.

### `SESceneManager`

```lua
manager:currentFSM()               -- текущий SEFSM или nil
```

`_G.fsm` — глобал на время жизни сцены, менеджер свопает его вместе с `_G.model`.

---

## См. также

- [SEModel.md](./SEModel.md) — реактивная модель, KV-канал, декларативный `$` в манифестах.
- [SESceneLoader.md](./SESceneLoader.md) / [SESceneManager.md](./SESceneManager.md) — жизненный цикл сцен, в который FSM встроен.
- [SButton.md](./SButton.md) — per-phase action props (`onClick`, `onLongPress`, …).
- [SEInputController.md](./SEInputController.md) — per-phase action props для клавиатуры/жестов.
