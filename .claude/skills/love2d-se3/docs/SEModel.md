# SEModel — Extended Guide

`SEModel` — реактивная модель данных: плоский словарь с `get/set` и подпиской на изменения. Движок создаёт свежий экземпляр на каждую сцену и уничтожает старый при переключении, разрывая все подписки. Компоненты привязываются к полям модели императивно (`node:bind`) или декларативно в манифесте (`$key` / `$$key`).

Файл с реализацией: `semodel.lua`.

---

## Оглавление

1. [Зачем модель](#1-зачем-модель)
2. [Минимальный пример](#2-минимальный-пример)
3. [Что происходит при переключении сцены](#3-что-происходит-при-переключении-сцены)
4. [Подписка: single-key, multi-key, опции](#4-подписка-single-key-multi-key-опции)
5. [Декларативный bind в манифесте — `$` / `$$` / `$?` / `$$?`](#5-декларативный-bind-в-манифесте)
6. [Императивный bind на ноде — `node:bind`](#6-императивный-bind-на-ноде)
7. [Наследование модели: `bind_Foo` и `override_Foo`](#7-наследование-модели-bind_foo-и-override_foo)
8. [`globalModel` — данные, переживающие переключения сцен](#8-globalmodel--данные-переживающие-переключения-сцен)
9. [Декомпозиция объектов через `bind_*`](#9-декомпозиция-объектов-через-bind_)
10. [Канал событий: `fire` / `on` / `off`](#10-канал-событий-fire--on--off)
11. [Числовые хелперы и дефолты: `inc` / `dec` / `get(k, default)`](#11-числовые-хелперы-и-дефолты-inc--dec--getk-default)
12. [`emit` и `emitAll` — ручная рассылка KV-подписчиков](#12-emit-и-emitall--ручная-рассылка-kv-подписчиков)
13. [Уничтожение и жизненный цикл](#13-уничтожение-и-жизненный-цикл)
14. [Полный пример: HUD с балансом, HP и прогрессом](#14-полный-пример-hud-с-балансом-hp-и-прогрессом)
15. [Антипаттерны](#15-антипаттерны)
16. [API Reference](#16-api-reference)

---

## 1. Зачем модель

Типичная сцена в игре — это UI + данные. Без модели данные разбросаны: балансы лежат на одном контроллере, HP — на другом, скорости обновления текста — в третьем. Каждый раз, когда сервер пришёл с новой цифрой, надо самому найти нужную ноду через `byId` и вызвать `setText`. Код переполняется низкоуровневыми «проталкиваниями»:

```lua
function controller:onBalanceUpdate(new)
  self.scene:byId("hud.balance"):setText(tostring(new))
  self.scene:byId("shop.balance"):setText(tostring(new))
  self.scene:byId("topbar.coins"):setText("$"..new)
end
```

С моделью это превращается в одну строку `model:set("balance", 100)` — всё, что забиндилось на ключ `"balance"`, обновится само. А три места в манифесте просто пишут `text = "$balance"`.

Модель решает три задачи:

1. **Единая точка записи** — `model:set(k, v)`. Никто не дёргает сеттеры на нодах руками.
2. **Подписки без ручного учёта** — `model:subscribe` и `node:bind` хранят токены; `model:destroy` при уходе со сцены рвёт их все разом.
3. **Декларативный маппинг «поле модели → свойство ноды»** — `text = "$balance"` в манифесте, и дальше без единой строки glue-кода.

---

## 2. Минимальный пример

```lua
-- main.lua
require("se3")

function love.load()
  manager = SESceneManager.new()
  manager:register("lobby", "scenes.lobby")
  manager:change("lobby")
end

function love.update(dt)  manager:update(dt) end
function love.draw()      manager:draw()     end
```

```lua
-- scenes/lobby/scene_description.lua
return {
  model      = "lobby_model",            -- опционально; без него — базовый SEModel
  controller = "lobby_controller",
  scene = {
    type = "SGroup",
    {
      type = "SText", id = "balance_label",
      font = "main", text = "$balance",   -- ← декларативный bind
      x = 100, y = 40,
    },
  },
}
```

```lua
-- scenes/lobby/lobby_model.lua
local LobbyModel = Class{__includes = {SEModel}}
function LobbyModel:init(data)
  SEModel.init(self, data or { balance = 0 })
end
return LobbyModel
```

```lua
-- scenes/lobby/lobby_controller.lua
local Controller = Class{}
function Controller:onEnter(scene, params)
  self.scene = scene
  -- любая запись в модель автоматически пробрасывается в SText:setText
  model:set("balance", 1250)
end
return Controller
```

Всё. Текст `balance_label` без единого `setText`-вызова покажет `1250`. `model` — это глобал, который менеджер свопает для каждой сцены.

---

## 3. Что происходит при переключении сцены

`manager:change("new")`:

1. На текущей сцене вызывается `manifest.onLeave` → `controller:onLeave`.
2. `current_model:destroy()` — все подписки (включая те, что держат ноды через `node:bind`) обнуляются. Ноды становятся GC-совместимыми.
3. Сбрасываются все ссылки менеджера и `_G.model = nil`.
4. Запускается preload новой сцены. Если в её манифесте есть `model = "..."` — модуль `require`-ится и создаётся экземпляр класса (по умолчанию — базовый `SEModel`).
5. Перед `build()` менеджер ставит `_G.model` = новая модель. Build разбирает `$`-ссылки в манифесте (уже видя правильную модель) и регистрирует биндинги.
6. Вызываются `controller:onEnter(scene, params)` → `manifest.onEnter(scene, params)`. К этому моменту `model` уже содержит все поля из `manifest.modelData` (если задано) или `opts.modelData`, а все `$`-бинды уже поставлены.

Важно: **модель не переживает сцену**. Если вам нужно хранить баланс игрока между сценами — это `globalModel`, см. §8.

---

## 4. Подписка: single-key, multi-key, опции

### Single-key

```lua
local token = model:subscribe("balance", function(v, k)
  print("balance is now", v)
end)
```

- `v` — новое значение (может быть `nil`).
- `k` — имя ключа (`"balance"`). Для single-key почти всегда избыточен, но сигнатура везде одинаковая.
- `token` — то, что вернул `subscribe`. Передайте его в `model:unsubscribe(token)` когда подписка больше не нужна.

Коллбэк фаерится **сразу** с текущим значением (в том числе `nil`, если ключ ещё не записан). Это позволяет не писать отдельную «первоначальную синхронизацию» — подписчик всегда получает консистентное состояние.

### Multi-key — паттерн «refresh»

Когда виджет зависит от нескольких полей и проще «перерисовать его целиком», чем отдельно обрабатывать каждое поле:

```lua
model:subscribe({"hp", "mp", "level"}, function(v, k)
  self:refresh()   -- сам читает model:get(...) по всем полям
end)
```

Сигнатура коллбэка та же `fn(value, key)`:

- Первый раз фаерится как `fn(nil, nil)` — сигнал «начальная синхронизация, читай что нужно».
- При любом изменении одного из ключей вызывается `fn(newValue, "ключ_который_изменился")`.

### Опции

```lua
model:subscribe(key, fn, { immediate = false })   -- не вызывать сразу
model:subscribe(key, fn, { skipNil    = true  })  -- фильтровать nil
```

- `immediate = false` — пропустить начальный вызов. Полезно, если коллбэк не готов работать с текущим состоянием модели сразу.
- `skipNil = true` — любой вызов коллбэка с `v == nil` пропускается (включая начальный).

Опции композируются: `{ immediate = false, skipNil = true }` — ни начального вызова, ни вызовов на `nil`.

### Отписка

```lua
model:unsubscribe(token)
```

`token` — именно то, что вернул `subscribe`. Для multi-key токен один, отписывает сразу от всех ключей.

---

## 5. Декларативный bind в манифесте

### Базовый синтаксис

Значение любого пропса ноды можно заменить специальной строкой `"$ключ"` или `"$$ключ"`. Движок:

1. При build-е читает `model:get("ключ")` и кладёт результат в props — конструктор видит готовое значение.
2. После создания инстанса регистрирует подписку: на любой последующий `model:set("ключ", x)` дёргается сеттер `setПроп(x)` у этой ноды.

```lua
-- scene_description.lua
{
  type = "SText", font = "main",
  text  = "$balance",        -- scene model
  color = "$$themeColor",    -- globalModel
}
```

### Четыре формы

| Синтаксис | Модель | Поведение при `nil` |
|-----------|--------|---------------------|
| `"$key"`      | scene `model`   | фаерит сеттер с `nil` |
| `"$?key"`     | scene `model`   | пропускает `nil` |
| `"$$key"`     | `globalModel`   | фаерит сеттер с `nil` |
| `"$$?key"`    | `globalModel`   | пропускает `nil` |

Выбор между `$` и `$?` — это вопрос «умеет ли сеттер жить с `nil`». Например, `SText:setText(nil)` корректно очищает текст, а `SSprite:setImg(nil)` — тоже ок. Но ваш кастомный `setPercent(nil)` может упасть на арифметике — для него используйте `$?percent`.

Числовые сеттеры SObject (`setX/Y/Z/R/W/H/SX/SY/Size/...`) специально сделаны no-op на `nil`, чтобы `x = "$playerX"` не крашился, когда модель ещё пустая. То же правило у boolean-сеттеров видимости: `setOff` / `setHidden` / `setEventoff` — no-op на `nil`, а на любой non-nil normalize к `true` (truthy) или `nil` (falsy). Так `off = "$overlay_off"` можно дёргать хоть `false`-ом, хоть `true`-ом, хоть `0`-ом — engine всегда увидит чистый `not c.off`. Но `.hidden` реально скрывает только `SSprite` и `SText` (они проверяют флаг в собственном `draw()`); для скрытия целой `SGroup`-ветки используйте `.off`.

### Как вычисляется имя сеттера

`text` → `setText`, `maxWidth` → `setMaxWidth`, `x` → `setX`. Правило: `"set" + PropName` с заглавной первой буквой. Если у класса нет такого метода — `SESceneLoader` кинет понятную ошибку при build-е.

### Top-level only

`$`-биндинг работает только для **верхнего уровня пропсов ноды**. Если написать:

```lua
{
  type = "SSpriteButton",
  states = {
    release = { color = "$highlight" },    -- ← не live-bind!
  }
}
```

— `$highlight` прочитается ровно один раз на build-е и подставится как текущее значение. Никакой подписки не зарегистрируется. Для live-обновлений вложенных полей используйте императивный `node:bind` из контроллера (см. §6).

### Через какую модель смотрит `$`

- `$key` смотрит на тот `SEModel`, который менеджер подставил в `_G.model` для текущей сцены. Если сцена не декларировала `manifest.model`, это будет базовый `SEModel`, созданный автоматически.
- `$$key` смотрит на `_G.globalModel`. Если `globalModel` не задан — build упадёт с ошибкой «globalModel is not set» (см. §8).

---

## 6. Императивный bind на ноде

`node:bind(model, keyOrList, methodOrFn, opts?)` — тот же механизм, но с явным указанием, какой метод ноды вызывать. Нужен для:

- биндингов на ноды, до которых сложно добраться декларативно (вложенные состояния, canvas children);
- биндингов на **не-сеттеры** (любой метод ноды, включая `refresh`, `play`, `shake`);
- multi-key подписок (`$` не поддерживает multi-key);
- биндингов на `globalModel` из контроллера, когда `$$` в манифесте не подходит по структуре.

### Формы вызова

```lua
-- по имени метода (строка)
node:bind(model, "balance", "setText")

-- по функции-методу
node:bind(model, "balance", SText.setText)

-- произвольный коллбэк (получает self первым аргументом)
node:bind(model, "balance", function(self, v, k)
  self:setText(string.format("%05d", v or 0))
end)

-- multi-key: "рефрешнись когда что-то из этого поменялось"
node:bind(model, {"hp", "mp", "level"}, "refresh")
```

### Опции

Те же, что у `subscribe`: `{ immediate = false, skipNil = true }`.

### Отписка

```lua
node:unbindAll()
```

Рвёт **все** подписки, которые этот нод сделал через `:bind`. Обычно вызывать не нужно — при `model:destroy()` (т.е. при уходе со сцены) все подписки на модели и так рвутся. `unbindAll` имеет смысл, когда нод переиспользуется или когда есть долгоживущая модель (`globalModel`) и нод, который надо раньше отключить.

`unbindAll` на ноде, чья модель уже уничтожена, безопасен — это no-op.

---

## 7. Наследование модели: `bind_Foo` и `override_Foo`

Подклассы `SEModel` могут объявлять методы с префиксами `bind_` и `override_`. Конструктор `SEModel.init` их сканирует и регистрирует автоматически.

### `bind_Foo(value)` — авто-подписчик

```lua
local MyModel = Class{__includes = {SEModel}}
function MyModel:bind_Player(value)
  if not value then return end
  print("Player object updated:", value.name)
  -- можно разложить по полям:
  self:set("playerHP", value.hp)
  self:set("playerMP", value.mp)
end
```

- Ключ берётся **байт-в-байт** из имени после `bind_`. `bind_Player` → ключ `"Player"`. Регистр важен. Если вы сидите данные как `{player = ...}` (строчная буква), метод `bind_Player` не сработает — нужен либо `bind_player`, либо правильный ключ в данных.
- Фаерится сразу при конструкции с текущим значением (может быть `nil` — готовьтесь к этому).
- Внутри `bind_Foo` можно звать `self:set(...)` для других ключей — каскад сработает правильно.

### `override_Foo(newValue, currentValue)` — хук перед записью

```lua
function MyModel:override_HP(newValue, currentValue)
  if newValue == nil then return newValue end        -- разрешаем очистить
  if newValue > self:get("maxHP") then
    return self:get("maxHP")                         -- clamp
  end
  if newValue < 0 then return 0 end
  return newValue
end
```

- Вызывается **внутри** `set("HP", x)` до записи и до рассылки.
- Принимает оба значения: что хотят записать и что сейчас лежит. `nil` — валидное значение (его нельзя использовать как «сигнал отмены»).
- Возвращаемое значение — то, что реально попадёт в модель. Вернули `currentValue` → запись отменяется (по правилу skip-if-unchanged).

### Порядок на `m:set(k, v)`

```
    set(k, v)
      ↓
    override_K(v, current)     ← clamp / валидация / отказ
      ↓
    value == current?          ← skip-if-unchanged (если не force=true)
      ↓
    _data[k] = value
      ↓
    все подписчики ключа k     ← включая bind_K, $k в манифесте, node:bind
```

---

## 8. `globalModel` — данные, переживающие переключения сцен

Per-scene `model` уничтожается на `change()`. Для данных уровня «весь игровой сеанс» (профиль игрока, настройки, баланс монет) заведите свой `SEModel` и положите его в `_G.globalModel`. Менеджер его **не трогает**.

### Создание

```lua
-- main.lua
function love.load()
  globalModel = SEModel({
    playerName = "",
    coins      = 0,
    music      = 1.0,
  })

  manager = SESceneManager.new()
  manager:register("lobby", "scenes.lobby")
  manager:change("lobby")
end
```

Или свой подкласс с override-хуками:

```lua
-- global_model.lua
local GM = Class{__includes = {SEModel}}
function GM:override_Music(v, cur)
  if type(v) ~= "number" then return cur end
  return math.max(0, math.min(1, v))
end
return GM
```

```lua
-- main.lua
globalModel = require("global_model")({ music = 1.0 })
```

### Использование в манифестах

```lua
{
  type = "SText", font = "main",
  text = "$$playerName",            -- читает globalModel.playerName
}
```

```lua
{
  type = "SText", font = "main",
  text = "$$?coins",                -- skip nil
}
```

### Использование в императиве

Из любого места (контроллер, компонент, handler):

```lua
globalModel:set("coins", 500)
node:bind(globalModel, "coins", "setText")
```

### Синхронизация между моделями

Иногда поле из `globalModel` хочется видеть и в scene model (например, чтобы per-scene логика не знала, откуда приходят монеты). Bridge делается в контроллере сцены:

```lua
-- lobby_controller.lua
function Controller:onEnter(scene, params)
  self._bridge = globalModel:subscribe("coins", function(v)
    model:set("coins", v)
  end)
end
function Controller:onLeave()
  globalModel:unsubscribe(self._bridge)    -- важно! model сам уйдёт, globalModel — нет
end
```

---

## 9. Декомпозиция объектов через `bind_*`

Модель хранит плоские ключи, но значения могут быть любыми — в том числе таблицами. Когда с сервера приходит «игрок целиком» (`{name, hp, mp, gold}`), удобно записать его одним `set`, а разложить на плоские поля внутри `bind_*`:

```lua
local MyModel = Class{__includes = {SEModel}}

function MyModel:bind_Player(player)
  if not player then return end
  self:set("playerName",  player.name)
  self:set("playerHP",    player.hp)
  self:set("playerMaxHP", player.maxHP)
  self:set("playerGold",  player.gold)
end
```

Все «плоские» поля получают стандартные изменения, на них можно биндить виджеты через `$playerHP`, `$playerGold`, и т.д. А со стороны сервера/логики остаётся один грубый `model:set("Player", newPlayerObject)`.

Это и есть ответ «как работать с вложенными данными в плоской модели»: сам факт хранения плоский, а декомпозицию делает подкласс.

---

## 10. Канал событий: `fire` / `on` / `off`

Кроме KV-канала (ключ → значение, persistent) в модели есть второй, независимый канал — **события**. Транзитные широковещательные сообщения, у которых нет «текущего значения»: подписались после того, как оно отработало — пропустили.

```lua
model:fire(name, ...)              -- broadcast
token = model:on(name, fn)         -- subscribe; fn(...)
token = model:on("*", fn)          -- catch-all; fn(name, ...) — имя события первым аргом
model:off(token)
```

### Где используется

- **Пользовательский ввод.** Кнопки и `SEInputController` фаерят `model:fire("ui_<action>", …)` при взаимодействии. FSM-состояния ловят через `onEvent_ui_<action>` или `onUI` catch-all (см. [SEFSM.md](./SEFSM.md)).
- **Игровые сигналы без сохраняемого состояния.** «Игрок только что собрал монетку», «анимация закончилась», «покупка в магазине совершена» — у этих событий нет смыслового «текущего значения», нужен чистый broadcast.
- **Триггеры визуальных эффектов.** fire → controller слышит → запустить VFX, сыграть звук. Не загрязнять KV «последним случившимся эффектом».

### Пример

```lua
-- В состоянии / контроллере — генерация
function Playing:onEnter()
  self.fsm.model:fire("game.start", { level = 1 })
end

function Playing:onModel_hp(v)
  if v and v <= 0 then
    self.fsm.model:fire("game.over", { cause = "hp" })
  end
end

-- Подписчик (другое состояние, другой контроллер, что угодно)
function Results:onEvent_game_over(data)
  self.fsm.model:set("final_score", computeScore(data))
end
```

### Разница с KV `emit(key)` и `set`

- `model:emit(key)` — перефаерить KV-подписчиков **текущим** значением по ключу. Для событий нерелевантен (у них нет значения).
- `model:set(k, v)` — записать и пробросить, если значение изменилось.
- `model:fire(name, ...)` — вызвать событие с произвольными аргументами. Ничего не хранит.

Если вам хочется «переключатель, который ещё и пинает подписчиков при любой смене» — это KV (`set`/`subscribe`). Если «факт произошедшего, без последующего чтения» — события (`fire`/`on`).

### UI-события и префикс `ui_`

Всё, что приходит от пользователя, по соглашению использует префикс `ui_`:
- Кнопка с `onClick = "play"` → `model:fire("ui_play", btn)`.
- Input-action с `onLongPress = "autoFire"` → `model:fire("ui_autoFire", action, phase)`.

FSM-магия `onUI(name, ...)` внутри SEFSMState — это `model:on("*", fn)` с фильтром на `ui_`. Если вам нужен такой же catch-all вне FSM, делайте руками:

```lua
local token = model:on("*", function(name, ...)
  if name:sub(1, 3) == "ui_" then
    print("UI event:", name:sub(4), ...)
  end
end)
```

---

## 11. Числовые хелперы и дефолты: `inc` / `dec` / `get(k, default)`

Три удобных метода поверх базовых `get`/`set` — убирают бойлерплейт вокруг числовых полей и отсутствующих значений.

### `get(key, default)`

Второй аргумент возвращается, если в модели по ключу `nil`.

```lua
local balance = model:get("balance", 0)     -- не ронёт арифметику если ключа нет
local lives   = model:get("lives",   3)     -- "если ни разу не задавалось — дефолт 3"
```

Эквивалент `(model:get(k) or default)`, но:
- Корректно работает, когда `0` или `false` — валидные значения. `or`-идиома заменит их на default, `get(k, default)` — нет.
- Читается естественнее: «возьми ключ, с дефолтом такой-то».

Если в модели лежит `false`, `0`, `""` — всё это **не `nil`**, дефолт игнорируется:

```lua
model:set("debug", false)
model:get("debug", true)        -- false (не true! false != nil)
```

### `inc(key, amount?)` и `dec(key, amount?)`

Инкремент/декремент числового поля. `nil` трактуется как `0`, поэтому первый `inc` по неинициализированному ключу корректно запишет `amount` (или `1` по умолчанию).

```lua
model:inc("coins")          -- nil → 1
model:inc("coins")          -- 1 → 2
model:inc("coins", 10)      -- 2 → 12
model:dec("lives")          -- 3 → 2
model:dec("score", 5)       -- -5 от текущего (или от 0 если не было)
```

### Возвращаемое значение

`inc`/`dec` возвращают **фактически сохранённое значение — уже после `override_<key>`**. Это важно: если ваш хук клампит (например, HP в диапазоне 0..max), вы получаете именно зажатое число одним вызовом:

```lua
function MyModel:override_HP(new, cur)
  if new == nil then return new end
  return math.max(0, math.min(self:get("maxHP", 100), new))
end

-- …
local after = model:inc("HP", 50)   -- HP=95, попытка → 145, клампнулось → 100
assert(after == 100)
```

Без этого пришлось бы писать `model:inc(...); local after = model:get(k)`.

### Подписчики, dispatch, force

`inc`/`dec` проходят через `set` — значит:

- Работает правило «не изменилось — не фаерим». `model:inc("x", 0)` — `x` не меняется, подписчики не срабатывают.
- Все `override_<key>` / `bind_<key>` / `on...`-магия работает одинаково.
- Если нужен форс-дыр, делайте `model:set(k, model:get(k, 0) + amount, {force=true})` руками — `inc`/`dec` не принимают `opts`.

### Типовые use cases

**Счётчики (монеты, опыт, очки).** Раньше:
```lua
model:set("coins", (model:get("coins") or 0) + reward)
```
Теперь:
```lua
model:inc("coins", reward)
```

**Жизни / здоровье с `override_*`-клампом.**
```lua
local newHP = model:dec("HP", damage)
if newHP <= 0 then fsm:to("dead") end
```

**Инициализация «по факту первого изменения».** Если счётчику не нужно стартовое значение в `modelData`, просто `inc` от `nil`. Первый вызов запишет `1`.

### После `destroy`

- `get(k, default)` возвращает `default` (внутренний `_data` пуст).
- `inc`/`dec` возвращают `nil` и ничего не записывают (модель уже мертва, `set` — no-op).

---

## 12. `emit` и `emitAll` — ручная рассылка KV-подписчиков

Бывают случаи, когда значение в модели не менялось, но перерисовать надо. Например, вы поменяли формат вывода баланса и хотите дёрнуть все подписки.

```lua
model:emit("balance")    -- фаерит всех подписчиков "balance" с текущим значением
model:emitAll()          -- фаерит каждую подписку ровно один раз
```

`emitAll` корректно обрабатывает multi-key подписки: они получают один вызов `fn(nil, nil)` (как и при первичной подписке), а не N вызовов по количеству ключей.

Другой способ «рассылки с тем же значением» — `model:set(k, v, { force = true })`. Разница: `set` может быть отклонён `override_K`; `emit` — прямая рассылка без прохода через override.

---

## 13. Уничтожение и жизненный цикл

### Когда модель уничтожается сама

- При `manager:change("other")` — текущая модель уничтожается после `onLeave`, до drop-а ссылок на сцену.
- При `manager:change()` на `"idle"` с перезаписи (редко — например, через ручной `manager._state = ...`) — не полагайтесь на это.

### Когда уничтожать самому

- Для `globalModel` при завершении игры (опционально — Lua GC и так отпустит всё).
- Для ad-hoc моделей, созданных вне менеджера (например, модель «диалогового окна», живущая отдельно).

```lua
myModel:destroy()
```

После этого:
- `myModel:isAlive()` → `false`.
- `myModel:subscribe(...)` бросит ошибку.
- `myModel:set(...)` — тихо no-op.
- `myModel:get(k)` → `nil`.
- Все существующие токены подписок становятся мёртвыми. `node:unbindAll()` на ноде, забинденной в уничтоженную модель, безопасен.

### Важные детали

- `onLeave` бежит **до** `destroy()`. То есть в `onLeave` модель ещё жива — можно последний раз её прочитать, синхронизировать с `globalModel`, сохранить в файл.
- `destroy()` синхронный. По возвращению из `change()` старая модель уже мертва.
- Подписки в другую модель, которая пережила сцену (`globalModel`), **не** рвутся автоматически. Если нод из уничтоженной сцены забиндил что-то на `globalModel` напрямую, его callback в `globalModel._subs` всё ещё лежит — при `globalModel:set(...)` он сработает. Решение: вызывать `node:unbindAll()` в `onLeave` контроллера, или заводить bridge через scene model (см. §8).

---

## 14. Полный пример: HUD с балансом, HP и прогрессом

```lua
-- scenes/game/scene_description.lua
return {
  model      = "game_model",
  controller = "game_controller",
  resources  = { fonts = {{ name = "hud", path = "assets/font.ttf", size = 24 }} },
  scene = {
    type = "SGroup", id = "hud",
    {
      type = "SText",  id = "balance", font = "hud",
      text = "$balance",   x = 40,  y = 20,
    },
    {
      type = "SText",  id = "hp",      font = "hud",
      text = "$?hpText",   x = 40,  y = 60,   -- skip nil: пока HP не пришёл, надпись пустая
    },
    {
      type = "SText",  id = "level",   font = "hud",
      text = "$$playerLevel",  x = 40, y = 100,  -- из globalModel
    },
  },
}
```

```lua
-- scenes/game/game_model.lua
local GameModel = Class{__includes = {SEModel}}

function GameModel:init(data)
  SEModel.init(self, data or { balance = 0 })
end

-- clamp HP в [0..maxHP]
function GameModel:override_HP(newValue, currentValue)
  if newValue == nil then return newValue end
  local max = self:get("maxHP") or 100
  return math.max(0, math.min(max, newValue))
end

-- раскладываем "player" на плоские поля
function GameModel:bind_Player(player)
  if not player then return end
  self:set("maxHP",  player.maxHP)
  self:set("HP",     player.hp)
  self:set("balance", player.gold)
end

-- форматированный HP-текст для UI
function GameModel:bind_HP(hp)
  if hp == nil then
    self:set("hpText", nil)      -- $?hpText пропустит вызов
    return
  end
  local max = self:get("maxHP") or 100
  self:set("hpText", string.format("%d / %d", hp, max))
end

return GameModel
```

```lua
-- scenes/game/game_controller.lua
local Controller = Class{}

function Controller:onEnter(scene, params)
  self.scene = scene

  -- при входе получаем "игрока" одним пакетом
  model:set("Player", params.player)

  -- слушаем изменения в globalModel.coins и сливаем в scene model
  self._coinsSub = globalModel:subscribe("coins", function(v)
    model:set("balance", v)
  end)
end

function Controller:onLeave()
  globalModel:unsubscribe(self._coinsSub)
  -- model:destroy() вызовет менеджер автоматически
end

function Controller:mousepressed(x, y, btn)
  -- при клике теряем 10 HP — clamp сработает, override не пустит ниже 0
  model:dec("HP", 10)    -- nil трактуется как 0; override_HP зажмёт в 0..100
end

return Controller
```

Что получится:

- `params.player = { maxHP=100, hp=80, gold=250 }` → `bind_Player` раскладывает → три последовательных `set`-а → `$balance`/`$?hpText` обновляются.
- `bind_HP` формирует `hpText = "80 / 100"` → подписка на `$?hpText` срабатывает → SText рендерит.
- Клик: `model:set("HP", 70)` → override не трогает (в диапазоне) → `bind_HP` пересчитывает `hpText = "70 / 100"`. Сеттер `setText` вызывается один раз, с правильным форматом.
- Клик 20 раз подряд: `HP` станет `-120`, но override зажмёт до `0`. `bind_HP` получит `0`. `$?hpText` покажет `"0 / 100"`.
- `globalModel:set("coins", 300)` в любом месте (инвентарь, магазин) → bridge в `onEnter` увидит → `model:set("balance", 300)` → `$balance` обновится.

---

## 15. Антипаттерны

### ❌ Хранить ссылки на ноды и дёргать их вместо bind

```lua
-- не надо
function Controller:onEnter(scene)
  self.balanceLabel = scene:byId("balance")
  model:subscribe("balance", function(v) self.balanceLabel:setText(tostring(v)) end)
end
```

**Как правильно:** `text = "$balance"` в манифесте. Или `scene:byId("balance"):bind(model, "balance", "setText")` в `onEnter`.

### ❌ Делать `model:set` в `bind_Foo` при незначащих изменениях

```lua
function MyModel:bind_Player(player)
  self:set("playerHP", player.hp)     -- сработает каждый раз
  self:set("playerMP", player.mp)     -- даже если поменялось только gold
end
```

Не баг (skip-if-unchanged защищает), но лишняя работа. Если `Player` большой и меняется часто — подумайте, не стоит ли публиковать только дельты.

### ❌ Использовать `$?key` там, где нужен default

```lua
text = "$?name"    -- если name nil — setText не вызовется, текст останется таким, каким был в init
```

Если ожидаете, что иногда ключ будет `nil`, но хотите видеть заглушку — сделайте `bind_Name` и кладите туда заглушку:

```lua
function MyModel:bind_name(v)
  self:set("nameText", v or "Guest")
end
-- text = "$nameText"
```

### ❌ Подписываться на globalModel без bridge

Bind из per-scene ноды напрямую на `globalModel`:

```lua
scene:byId("coins"):bind(globalModel, "coins", "setText")
```

Это работает, но при уходе со сцены нод исчезает, а подписка в `globalModel._subs` остаётся. `globalModel:set("coins", ...)` потом дёргает мёртвую замыкание. Сборщик всё соберёт (замыкание держит только ссылку на нод, сам `globalModel` её переживёт), но callback будет зря вызываться, пока подписка жива.

**Как правильно:** либо bridge-подписка в контроллере с `unsubscribe` в `onLeave`, либо `node:unbindAll()` в `onLeave`.

### ❌ Регистр ключа в `bind_Foo`

```lua
function MyModel:bind_HP(v) ... end
-- ... а потом:
m:set("hp", 50)   -- НЕ сработает: ключ "hp", а метод ждёт "HP"
```

Ключи — case-sensitive. Определитесь на старте проекта, как пишете: `HP` / `hp` / `Hp` — и держитесь одного варианта.

### ❌ `override_Foo` возвращает `nil` для «отказа»

```lua
function MyModel:override_HP(v, cur)
  if v > 100 then return nil end   -- ← нет! nil запишется как валидное значение
end
```

**Как правильно:** `return cur`.

---

## 16. API Reference

### `SEModel`

```lua
SEModel.new(data?)                           -- data : table, seed для начальных значений
-- также вызывается как SEModel(data)
```

Подклассы: `Class{__includes = {SEModel}, init = function(self, data) SEModel.init(self, data) ... end}`.

### Чтение / запись

```lua
model:get(key)                               -- returns value or nil
model:get(key, default)                      -- default если value == nil
model:set(key, value)                        -- пропускает, если value == current
model:set(key, value, { force = true })      -- форсит dispatch
model:inc(key)                               -- +1, nil → 1; возвращает новое значение
model:inc(key, amount)                       -- +amount
model:dec(key)                               -- -1, nil → -1
model:dec(key, amount)                       -- -amount
model:emit(key)                              -- рассылает текущее значение
model:emitAll()                              -- рассылает всем подпискам, multi-key — один (nil,nil)
```

`inc` / `dec` проходят через `set`, поэтому `override_<key>` применяется (например, clamp в [0..max]), и возвращаемое значение — уже зажатое.

### Подписки

```lua
token = model:subscribe(key,        fn, opts?)     -- fn(value, key)
token = model:subscribe({k1, k2,…}, fn, opts?)     -- fn(value, changedKey); init fn(nil, nil)
model:unsubscribe(token)                           -- token — то, что вернул subscribe
```

Опции: `{ immediate = bool, skipNil = bool }`. Обе `true` по умолчанию-ложны (`immediate = true`, `skipNil = false`).

### Канал событий

```lua
model:fire(name, ...)              -- broadcast
token = model:on(name, fn)         -- fn(...) — аргументы fire после name
token = model:on("*", fn)          -- catch-all; fn(name, ...)
model:off(token)                   -- token — то, что вернул on; на уничтоженной модели — no-op
```

Независим от KV. Транзитен — `fire` не сохраняется, подписались после — пропустили.

### Жизненный цикл

```lua
model:destroy()                              -- после этого subscribe бросает, set — no-op
model:isAlive()                              -- bool
```

### Хуки на подклассе (авто-сканируются в `init`)

```lua
function MyModel:bind_KeyName(value)                   end   -- авто-подписчик
function MyModel:override_KeyName(newValue, current)   end   -- pre-set hook
```

Имя ключа — байты после `bind_` / `override_`. Регистр сохраняется.

### `SObject:bind`

```lua
token = node:bind(model, keyOrList, methodName,  opts?)   -- methodName : string
token = node:bind(model, keyOrList, methodFn,    opts?)   -- methodFn   : function(self, v, k)
node:unbindAll()                                          -- рвёт все биндинги этого нода
```

Опции те же, что у `subscribe`.

### Манифест

```lua
return {
  model     = "scenes.lobby.lobby_model",   -- опционально, относительный require-путь
  modelData = { balance = 0, HP = 100 },    -- опционально, seed, передаётся в init
  scene     = { ... },
}
```

Модуль `model` должен возвращать класс (hump.class), factory-функцию, либо таблицу с полем `SEModel` (или любым другим полем-классом — первый попавшийся).

Абсолютные пути через `!` работают здесь так же, как для `controller`/`include`/`components`:
`model = "!shared.models.base_model"` — не префиксится при монтировании в родительский проект.

### Декларативные bind-строки

| Форма | Модель | Пропуск nil |
|-------|--------|-------------|
| `"$key"`    | `_G.model`        | нет |
| `"$?key"`   | `_G.model`        | да  |
| `"$$key"`   | `_G.globalModel`  | нет |
| `"$$?key"`  | `_G.globalModel`  | да  |

Работает только для top-level props. Имя сеттера — `"set" + PropName:capitalize()`.

### `SESceneManager`

```lua
manager:currentModel()       -- текущий SEModel, или nil если state ≠ "active"
```

Менеджер сам создаёт и уничтожает per-scene модель. `globalModel` — зона ответственности пользователя.

---

## См. также

- [SESceneLoader.md](./SESceneLoader.md) — контекст для `manifest.model`, `$`-ссылок, resolution-порядка.
- [SESceneManager.md](./SESceneManager.md) — жизненный цикл сцены, в который встроена модель.
- [Signals.md](./Signals.md) — `Signal.emit` для игровых событий (не путать с моделью: Signal — именованные шины широковещания; SEModel — ключ-значение с подписками).
- [Architecture.md](./Architecture.md) — куда класть state (модель vs controller vs globalModel vs Signal).
