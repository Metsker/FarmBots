# SEInputController — Extended Guide

Абстракция «именованных действий» (actions) над клавиатурой. Каждое действие — имя + список клавиш + набор фаз (press/release/click/longpress/repeat), к которым можно прицепить handler или listener-объект.

Файл: `seinput.lua`.

---

## Оглавление

1. [Зачем](#1-зачем)
2. [Быстрый старт](#2-быстрый-старт)
3. [Фазы действия](#3-фазы-действия)
4. [Определение action-а](#4-определение-action-а)
5. [Методы контроллера](#5-методы-контроллера)
6. [Привязка кнопки к action-у](#6-привязка-кнопки-к-action-у)
7. [Пример: движение + атака с удержанием](#7-пример-движение--атака-с-удержанием)
8. [Пример: UI-кнопка с горячей клавишей](#8-пример-ui-кнопка-с-горячей-клавишей)
9. [Интеграция со сценой](#9-интеграция-со-сценой)

---

## 1. Зачем

Прямая обработка `love.keypressed` / `love.keyreleased` приводит к куче кода, раскиданного по проекту:

- Таймеры долгого нажатия где-то в update.
- Одна и та же клавиша на разных сценах — дублирование.
- UI-кнопки и клавиатурные хоткеи делают одно и то же, но двумя разными путями.

`SEInputController` даёт:

- **Имена действий** (`"fire"`, `"jump"`, `"menu_back"`) — не имена клавиш. Раскладку поменять легко.
- **Фазы** — press, release, click, longpress, repeat. Каждый с отдельным handler.
- **Таймеры** — `longPressTime`, `repeatDelay`, `repeatInterval` встроены, руками не держать.
- **Listener-объекты** — можно привязать `SButton` к action-у, и клавиша запустит ту же логику, что мышь.

---

## 2. Быстрый старт

```lua
local input = SEInputController{
  bindings = {
    fire = {
      keys    = {"space", "return"},
      onPress = function(name, phase) print("fire pressed") end,
    },
    jump = {
      keys  = {"up", "w"},
      onClick = function() player:jump() end,
    },
    menu = {
      keys    = {"escape"},
      onClick = "menu_open",   -- model:fire("ui_menu_open", action, phase)
    },
  },
}

scene:add(input)
```

`SEInputController` — наследник `SObject`. Добавьте его в сцену, и он будет получать `keypressed/keyreleased/update` через обычную event-пропагацию.

---

## 3. Фазы действия

Каждый action проходит через фазы:

```
  keypressed
       │
       ▼
     press  ───────► (через longPressTime сек) ──────► longpress
                                                          │
                                                          │ (через repeatInterval сек)
                                                          ▼
                                                       repeat → repeat → ...
       │
  keyreleased
       │
       ▼
   release + (если не было longpress) click
```

Фазы и соответствующие опции в определении action-а:

| Фаза | Когда срабатывает | Ключ handler-а |
|------|-------------------|----------------|
| `press` | первое нажатие (не `isrepeat`) | `onPress` |
| `release` | отпускание | `onRelease` |
| `click` | release внутри `longPressTime` (т.е. не было longpress) | `onClick` |
| `longpress` | удержание больше `longPressTime` (срабатывает один раз) | `onLongPress` |
| `repeat` | после longpress, каждые `repeatInterval` сек | `onRepeat` |

---

## 4. Определение action-а

Полный список полей:

```lua
bindings = {
  fire = {
    keys           = {"space"},       -- список клавиш
    longPressTime  = 0.5,              -- секунд до longpress (default 0.5)
    repeatDelay    = 0.5,              -- до первого repeat (default = longPressTime)
    repeatInterval = 0.1,              -- между repeat-ами (default 0.1)

    onPress     = fn or "actionName",
    onRelease   = fn or "actionName",
    onClick     = fn or "actionName",
    onLongPress = fn or "actionName",
    onRepeat    = fn or "actionName",

    handler     = fn or "actionName",  -- ловит ВСЕ фазы, полезно для debug
  },
}
```

### handler-форматы

Для каждого поля есть два формата:

| Формат | Эффект |
|--------|--------|
| `function(action, phase)` | прямой вызов; `action` — вся таблица action-а, `phase` — строка фазы |
| `"actionName"` (опциональный префикс `@`) | `model:fire("ui_actionName", action, phase)` на per-scene SEModel |

```lua
-- прямой вызов
onClick = function(action, phase) player:fire() end

-- через модель (в FSM-состоянии ловится через onEvent_ui_player_fire или onUI)
onClick = "player_fire"
-- ...где-то в игре:
model:on("ui_player_fire", function(action, phase) player:fire() end)
-- или из состояния:
function Playing:onEvent_ui_player_fire(action, phase) player:fire() end
```

**Deprecated (удалено 2026-04-22):** раньше строки фаерили `Signal.emit("input", signalName, name, phase)`. Теперь — `model:fire("ui_<name>", action, phase)`. Смотри [SEModel.md § Канал событий](./SEModel.md#10-канал-событий-fire--on--off) и [SEFSM.md § UI-события](./SEFSM.md#8-ui-события-кнопки-inputcontroller-ui_-префикс).

### Универсальный `handler`

Если нужно ловить **все** фазы одного action-а:

```lua
fire = {
  keys    = {"space"},
  handler = function(name, phase)
    if phase == "press" then
      player:startCharge()
    elseif phase == "longpress" then
      player:fullCharge()
    elseif phase == "release" then
      player:fire()
    end
  end,
}
```

`handler` вызывается **дополнительно** к `onPress/onRelease/...` (не вместо).

---

## 5. Методы контроллера

### Управление bindings

```lua
input:bind(name, def)            -- добавить/переопределить action
input:unbind(name)               -- удалить
input:getAction(name)            -- вернуть action-таблицу
input:isDown(name)               -- true если клавиша сейчас удерживается
```

### Listener-объекты

```lua
input:attach(obj, name)   -- obj:press/release/click/longpress будет вызываться на action
input:detach(obj, name)
```

`obj` — любой объект с подходящими методами. Типично — `SButton`. См. [§6](#6-привязка-кнопки-к-action-у).

---

## 6. Привязка кнопки к action-у

Самый частый паттерн — кнопка на экране + клавиша с тем же эффектом.

```lua
local input = SEInputController{
  bindings = {
    confirm = { keys = {"return", "space"} },
  },
}

local btn = SSpriteButton{
  states = "btn_confirm",
  event  = "confirm_action",
  font   = "main",
  text   = "OK",
}

btn:bindAction(input, "confirm")
-- теперь Enter или Space вызовут button's press/release/click визуально
```

Что происходит:

- `SButtonEngine:bindAction(controller, name)` → `controller:attach(self, name)`.
- `SEInputController:_forwardToListener(obj, phase)` вызывает на кнопке метод, соответствующий фазе: `press/release/click/longpress`. В фазе `repeat` — `click` (потому что репит похож на многократный клик).

В результате кнопка «отыгрывает» нажатие визуально (state `press` → `release`), и её `event` стреляет как обычно.

---

## 7. Пример: движение + атака с удержанием

```lua
local input = SEInputController{
  bindings = {
    left = {
      keys    = {"a", "left"},
      onPress    = function() player:startMove(-1) end,
      onRelease  = function() player:stopMove() end,
    },
    right = {
      keys    = {"d", "right"},
      onPress    = function() player:startMove(1) end,
      onRelease  = function() player:stopMove() end,
    },
    attack = {
      keys          = {"space"},
      longPressTime = 0.3,                          -- зарядка от 0.3 сек
      onClick       = function() player:quickAttack() end,
      onLongPress   = function() player:startCharge() end,
      onRelease     = function()
        if player:isCharging() then player:chargedAttack() end
      end,
    },
  },
}

scene:add(input)
```

Поведение:
- Короткий тап `space` → `quickAttack`.
- Удержание > 0.3 сек → начинается зарядка (`startCharge`).
- Отпустил после зарядки → `chargedAttack`.
- Просто тап — `release` сработает и `isCharging()` = false, ничего лишнего.

### Автоповтор для скролла

```lua
scroll_down = {
  keys           = {"down"},
  longPressTime  = 0.3,
  repeatInterval = 0.05,
  onClick  = function() list:scroll(1) end,   -- один клик
  onRepeat = function() list:scroll(1) end,   -- автоповтор
}
```

Короткий тап: один `scroll`. Удержание: через 0.3 сек пошёл автоповтор, каждые 0.05 сек ещё по scroll-у.

---

## 8. Пример: UI-кнопка с горячей клавишей

Самый частый случай в геймплее — менюха, где «PLAY»-кнопка активируется и мышью, и Enter-ом.

```lua
local input = SEInputController{ bindings = {
  menuPlay = { keys = {"return", "space"} },
  menuBack = { keys = {"escape"} },
}}

local btnPlay = SSpriteButton{ states = "btn_play", event = "game.start", font = "main", text = "PLAY" }
local btnBack = SSpriteButton{ states = "btn_back", event = "menu.back",  font = "main", text = "BACK" }

btnPlay:bindAction(input, "menuPlay")
btnBack:bindAction(input, "menuBack")

scene = SGroup{ input, btnPlay, btnBack }
```

Или декларативно в манифесте:

```lua
scene = {
  type = "SGroup", children = {
    { type = "SEInputController", id = "input", bindings = {
        menuPlay = { keys = {"return", "space"}, onClick = "@nav.play" },
        menuBack = { keys = {"escape"},          onClick = "@nav.back" },
    }},
    { type = "SSpriteButton", states = "btn_play",
      event = "@nav.play", font = "main", text = "PLAY" },
    { type = "SSpriteButton", states = "btn_back",
      event = "@nav.back", font = "main", text = "BACK" },
  },
}
```

Привязка кнопок к input-у в декларативном варианте — через атрибут не описана в коде манифеста. Если нужна именно визуальная «проигрыш нажатия» на кнопке при нажатии клавиши — сделайте `bindAction` из `onEnter`:

```lua
onEnter = function(scene)
  local input = scene:byId("input")
  scene:byId("btn_play"):bindAction(input, "menuPlay")
  scene:byId("btn_back"):bindAction(input, "menuBack")
end,
```

Если не нужна — просто держите обе точки входа (`event` у кнопки и `onClick` у action-а) направленные на одно действие.

---

## 9. Интеграция со сценой

`SEInputController` — это `SObject`. Его:

1. Добавляют в сцену как обычный узел.
2. `keypressed/keyreleased` приходят через `__keypressed` по дереву.
3. `update` тоже — через `__update`.

Если контроллер вне сцены (например, в контроллере сцены в виде поля), надо прокидывать события руками:

```lua
function SceneController:keypressed(key, scancode, isrepeat)
  self.input:keypressed(key, scancode, isrepeat)
end

function SceneController:keyreleased(key)
  self.input:keyreleased(key)
end

function SceneController:update(dt)
  self.input:update(dt)
end
```

Обычно проще держать `SEInputController` **в** сцене — он участвует в общей event-пропагации и ничего дополнительно не надо.

### Важное: `used` flag

`SEInputController:keypressed/keyreleased` **всегда возвращает `used`** (пропускает через себя). Он не поглощает события, то есть кнопки и другие `SKeyboardObject`-узлы в том же дереве получат их тоже.

Это может привести к дубликации событий, если:

- `input` содержит `fire = {keys = {"space"}}` с `onClick`.
- В той же сцене есть `SSpriteButton` с `keys = {"space"}`.

Решение — либо убрать `keys` из кнопки (пусть только input слушает), либо привязать кнопку к action-у через `bindAction` (и убрать лишний keypressed из неё).

---

## См. также

- [SObject.md](./SObject.md) — `SKeyboardObject`-миксин; прямой аналог, но без named-action.
- [SButton.md](./SButton.md) — `bindAction` на кнопке.
- [SESceneLoader.md](./SESceneLoader.md) — `SEInputController` регистрируется в лоадере по умолчанию; bindings описываются прямо в манифесте.
