# Signals — Extended Guide

`Signal` — глобальная шина сообщений (pub/sub). SE3 сам использует её для кликов кнопок, событий анимации и input-handler-ов. Понимание того, **какие имена сигналов движок эмитит** и **как не заплевать регистр** — это примерно 30% всего «работа с SE3 за пределами одной сцены».

Источник: `hump/signal.lua` (Matthias Richter, MIT).

---

## Оглавление

1. [API модуля](#1-api-модуля)
2. [Сигналы, которые эмитит движок](#2-сигналы-которые-эмитит-движок)
3. [Регистрация и отписка](#3-регистрация-и-отписка)
4. [Паттерны неймспейсов](#4-паттерны-неймспейсов)
5. [Локальные реестры](#5-локальные-реестры)
6. [Сигналы в сценах и переходах](#6-сигналы-в-сценах-и-переходах)
7. [Типичные ошибки](#7-типичные-ошибки)
8. [Когда НЕ использовать Signal](#8-когда-не-использовать-signal)

---

## 1. API модуля

Глобаль `Signal` — singleton-реестр колбэков, сгруппированных по имени сигнала.

```lua
Signal.register("signal_name", fn)           -- подписаться
Signal.emit    ("signal_name", arg1, arg2)   -- вызвать всех подписчиков
Signal.remove  ("signal_name", fn)           -- отписать конкретного
Signal.clear   ("signal_name")               -- отписать всех на этот сигнал

Signal.emitPattern  (pattern, ...)           -- emit по Lua-паттерну имени
Signal.removePattern(pattern, fn)            -- remove по паттерну
Signal.clearPattern (pattern)                -- clear по паттерну

local sub = Signal.new()                     -- свой изолированный реестр
```

**Важные нюансы:**

- `register` возвращает **ту же функцию** — её можно сохранить и передать в `remove`.
- Порядок вызова подписчиков **не гарантирован** (внутри — `pairs` по таблице).
- Если во время `emit` подписчик сам удалит другого подписчика — безопасно (итерация идёт по `pairs` с модификацией, Lua 5.1+ разрешает удаление).
- Если подписчик **добавляет нового** во время emit — новый не будет вызван в этом же цикле.

---

## 2. Сигналы, которые эмитит движок

Движок сам стреляет двумя-тремя сигналами; знать их имена обязательно.

### `"click"` — от кнопок

Источник: `SButtonEngine:click()`, `longpress()`, `repeatfire()` (если `event` — строка).

```lua
-- внутри SE3:
if type(self.event) == "string" then Signal.emit("click", self.event) end
```

То есть:

```lua
SSpriteButton{ states = "btn_play", event = "game.start" }
-- при клике эмитится: Signal.emit("click", "game.start")
```

Типичная обработка:

```lua
Signal.register("click", function(name)
  if     name == "game.start" then manager:change("game")
  elseif name == "menu.back"  then manager:change("menu")
  elseif name == "audio.mute" then toggleMute()
  end
end)
```

`longevent` и `repeatevent` используют **ту же шину** `"click"` — имя у них отдельное, но шина одна:

```lua
SSpriteButton{ event = "jump", longevent = "jump.charged" }
-- короткий клик → Signal.emit("click", "jump")
-- долгое нажатие → Signal.emit("click", "jump.charged")
```

**Функциональные `event`-ы шину не трогают.** `event = function(self) ... end` вызывается напрямую; `Signal.emit` не происходит. Это даёт выбор: глобальная шина (строка) или локальное замыкание (функция).

### `"input"` — от SEInputController

Источник: `SEInputController:_fire(action, phase)` если обработчик — строка.

```lua
-- внутри SE3:
elseif type(h) == "string" then Signal.emit("input", h, name, phase)
```

Формат:

```lua
SEInputController{ bindings = {
  fire = { keys = {"space"}, onClick = "weapon.fire" }
}}

-- при клике "space":
-- Signal.emit("input", "weapon.fire", "fire", "click")
--                         ^              ^       ^
--                         handler name   action  phase
```

Три аргумента — `handlerName, actionName, phase`. Подписчик:

```lua
Signal.register("input", function(handler, action, phase)
  if handler == "weapon.fire" then fireWeapon() end
end)
```

Функциональные обработчики (`onClick = function(name, phase) ... end`) шину `"input"` не трогают — как и с кнопками.

### `"animation.stop"` — от SComplexAnimSprite

Источник: `SComplexAnimSprite:nextFrame` (когда анимация доигра) и `:stop()`.

```lua
-- внутри SE3:
Signal.emit("animation.stop", self)
```

Второй аргумент — сам объект. Типичное использование:

```lua
Signal.register("animation.stop", function(sprite)
  if sprite == specialSprite then
    specialSprite:setState("idle")
  end
end)
```

**Обычный `SAnimationSprite` сигнал не эмитит** — только `SComplexAnimSprite`. Если надо знать о завершении обычной анимации — используйте `:setCallback(fn)`.

---

## 3. Регистрация и отписка

### Сохраняйте возвращаемое значение

```lua
local onClick = Signal.register("click", function(name) ... end)
-- ... позже ...
Signal.remove("click", onClick)
```

Без этого отписаться нельзя — `remove` ищет по **ссылке на функцию**, а не по имени. Если вы зарегистрировали anonymous-лямбду и потеряли ссылку — она останется подписанной до явного `Signal.clear("click")`.

### Отписка при смене сцены

Самая частая ошибка в SE3 — подписаться в `onEnter`, забыть отписаться в `onLeave`, и в следующей сцене сработать дважды.

```lua
-- scenes/game_ctrl.lua
local Game = Class{}

function Game:onEnter(scene, params)
  self._onClick = Signal.register("click", function(name)
    if name == "jump" then self:jump() end
  end)
end

function Game:onLeave(scene, manager)
  Signal.remove("click", self._onClick)    -- важно!
end
```

Если забыть — старый контроллер продолжит реагировать на `"click"` даже после выхода из сцены. Хуже: после нескольких входов-выходов накапливается N подписчиков, каждый клик = N вызовов.

### Паттерн: уничтожить всё, что подписали в сцене

```lua
-- В контроллере:
function Game:_sub(signal, fn)
  self._subs = self._subs or {}
  local ref = Signal.register(signal, fn)
  self._subs[#self._subs + 1] = { signal, ref }
end

function Game:onEnter(scene)
  self:_sub("click", function(name) ... end)
  self:_sub("input", function(h, a, p) ... end)
  self:_sub("animation.stop", function(sp) ... end)
end

function Game:onLeave()
  for _, s in ipairs(self._subs or {}) do Signal.remove(s[1], s[2]) end
  self._subs = nil
end
```

Удобный приём — все подписки в одном списке, отписка в одном месте.

---

## 4. Паттерны неймспейсов

Глобальная шина быстро засоряется — все `"click"` сыпятся в одно место. Используйте «доменные» имена в `event`:

```
"game.start"         — запустить игру
"game.pause"         — пауза
"game.resume"        — возобновление
"menu.back"          — назад в меню
"menu.settings"      — открыть настройки
"audio.mute"         — выкл звук
"audio.sfx.click"    — проиграть клик-звук (редко, обычно прямо Sound:play)
```

Подписчики **не** фильтруют по домену автоматически — сами делают `if name == "game.start"`. Но если домен нужно обработать целиком, есть `emitPattern`:

```lua
-- все, что начинается с "audio.":
Signal.emitPattern("^audio%.", "mute")       -- эмитит на все signal-имена, попадающие в pattern
```

Это **эмитит** на все имена сигналов, чьё **имя** совпадает с паттерном. Не путайте с подписчиком на pattern (такого нет — `register` работает только по точному имени).

### Пример: аудиомодуль, слушающий свои события

```lua
-- audio.lua
Signal.register("click", function(name)
  if name == "audio.mute"   then Sound:setMute(true)  end
  if name == "audio.unmute" then Sound:setMute(false) end
end)
```

`"click"` — общий; внутри логика фильтрует по неймспейсу. Минус — все аудио-события и игровые события смешаны, регистр читает все. Плюс — кнопки проще делать: `event = "audio.mute"` и всё.

Альтернатива — разнести шины:

```lua
-- Отдельный сигнал для аудио:
Signal.register("audio", function(cmd)
  if cmd == "mute" then Sound:setMute(true) end
end)

-- Но кнопки не могут эмитить в произвольный сигнал!
-- event = "audio.mute" — всё равно emit("click", "audio.mute").
-- Чтобы полностью отделить, кнопка должна использовать функциональный event:
SSpriteButton{ event = function() Signal.emit("audio", "mute") end, ... }
```

Так что практичный подход — держать одну шину `"click"` и фильтровать по префиксу имени.

---

## 5. Локальные реестры

`Signal.new()` создаёт отдельный независимый реестр:

```lua
local sub = Signal.new()
sub:register("event", function() print("local") end)
sub:emit("event")

Signal.emit("event")   -- это глобальный; sub не видит
```

Полезно, когда:

- Хочется изолировать сцену от остального мира (всё, что сцена эмитит, видно только ей).
- Для тестов — создали свой реестр, наполнили, проверили результат, выкинули.
- Для плагинов/подсистем, которые не должны засорять глобальный регистр.

Недостаток: **стандартные** компоненты SE3 (кнопки, `SEInputController`) всегда используют `Signal` (глобальный). Чтобы они эмитили в ваш локальный реестр — надо переопределить `event` функцией и делегировать вручную.

---

## 6. Сигналы в сценах и переходах

### Регистрация handler-ов через менеджер

`SESceneManager:loader()` шарит `SESceneLoader` между всеми сценами, поэтому handler-ы, зарегистрированные в нём, **переживают** переключение:

```lua
manager:loader():registerHandler("nav.play",  function() manager:change("game") end)
manager:loader():registerHandler("nav.menu",  function() manager:change("menu") end)
```

Это **не** `Signal`, а другая механика — handler-ы в лоадере. Но в манифесте к ним обращаются через `@`-ссылки:

```lua
{ include = "prefabs.button",
  params = { label = "PLAY", event = "@nav.play" } }
```

Внутри loader вычислит `event = closure calling "nav.play"`. `Signal.emit("click", ...)` при этом **не** произойдёт — handler-ы минуют шину.

Когда что выбрать:

| Инструмент | Когда |
|-----------|-------|
| `Signal.emit("click", "name")` | событие нужно получить из нескольких мест (например, «кликнуто» + «аналитика» + «аудио») |
| handler в лоадере (`@nav.play`) | одна точка приёма, сцена должна быть переиспользуема в разных контекстах |
| контроллер с `@self:method` | событие обслуживает текущая сцена; state живёт в контроллере |
| функциональный `event = function(self) ... end` | локальная логика кнопки, ничего снаружи не должно знать |

### Очистка подписок в онлив

Если в сцене подписались на `Signal` — отпишитесь в `onLeave` (см. [§3](#3-регистрация-и-отписка)). Handler-ы лоадера **не надо** трогать — они шарятся.

### Межсценные сообщения

Если сцена A должна «сообщить» что-то сцене B (которая будет после неё), варианты:

1. **Через `params` в `change()`**: `manager:change("B", { fromA = true, score = 100 })`. В `B:onEnter(scene, params)` — читаете.
2. **Через глобальный модуль состояния**: `GameState.score = 100` перед `change` → следующая сцена читает `GameState.score`.
3. **Через Signal**: сцена B подписывается на что-то в `onEnter`, A эмитит перед уходом. **Опасно**: если подписки B нет к моменту эмита — пропустит.

Первые два варианта предсказуемее. Signal хорош для broadcast в **живых** сценах (когда получатели уже существуют), не для межсценной передачи.

---

## 7. Типичные ошибки

### Дубликат-подписки после возврата в сцену

```lua
-- НЕПРАВИЛЬНО — каждый onEnter добавляет ещё одну подписку
function Game:onEnter()
  Signal.register("click", function(name) self:onClick(name) end)
end
```

После нескольких входов-выходов каждый клик сработает N раз.

**Решение** — отписаться в `onLeave` или использовать стабильную ссылку:

```lua
function Game:init()
  self._onClick = function(name) self:onClick(name) end
end

function Game:onEnter()
  Signal.register("click", self._onClick)
end

function Game:onLeave()
  Signal.remove("click", self._onClick)
end
```

Теперь ссылка одна и та же, повторные `register` — no-op (Signal хранит `self[s][fn] = fn`, то есть ключ = сама функция — дубли невозможны).

### `self` внутри подписчика

```lua
function Game:onEnter()
  Signal.register("click", function(name)
    self:handle(name)   -- нормально, replica self захватывается замыканием
  end)
end
```

Работает, но убедитесь, что `self` — это тот `self`, что вы ожидаете. Если регистрация в `init` — это инстанс ещё только создаётся; обычно OK, но не используйте `self.someField`, если оно ставится позже.

### `Signal.clear` убивает чужие подписки

```lua
Signal.clear("click")   -- убьёт ВСЕ подписки на "click"
```

Не используйте `clear` в боевом коде — он затирает и ваши, и движка, и чужие плагины. Используйте `remove(signal, fn)` для точечной отписки.

### Не путайте emit-arguments

```lua
-- Кнопка:
Signal.emit("click", "game.start")
-- Подписчик получает 1 аргумент:
Signal.register("click", function(name) ... end)

-- Input:
Signal.emit("input", "weapon.fire", "fire", "click")
-- Подписчик получает 3:
Signal.register("input", function(handler, action, phase) ... end)

-- Animation:
Signal.emit("animation.stop", self)
-- Подписчик — 1 аргумент (сам SSprite):
Signal.register("animation.stop", function(sp) ... end)
```

Если приходится писать универсального подписчика — используйте `vararg`:

```lua
Signal.register("click", function(...)
  local args = {...}
  print(args[1])   -- имя события
end)
```

---

## 8. Когда НЕ использовать Signal

Сигналы — инструмент «отвязанной» коммуникации. Это сильная сторона — и слабая.

**Используйте Signal:**
- Событие может иметь 0, 1, 5 подписчиков — не знаете заранее.
- Источник и получатель в разных местах кода.
- Кликовые/вводные события UI.

**Не используйте Signal:**
- Есть ровно один получатель, известный заранее — делайте прямой вызов или callback-параметр.
- Нужны возвращаемые значения — Signal вызывает все подписчики, ничего не возвращает.
- Порядок важен — Signal вызывает в произвольном порядке.

### Плохой пример

```lua
-- Сцена эмитит "game.scoreChanged", слушатель — один — обновляет HUD
Signal.emit("game.scoreChanged", newScore)

Signal.register("click", function(name)    -- !!! Эта регистрация на click, не scoreChanged
  ...
end)
```

Для «изменился score, обнови HUD» лучше:

- Прямой вызов: `hud:setScore(newScore)`.
- Или callback на game-объекте: `game.onScoreChanged = function(n) hud:setScore(n) end`.

### Хороший пример

```lua
-- Любой, кому интересно "игра завершилась":
Signal.emit("game.over", finalScore)

-- ... в HUD: обновить экран
Signal.register("game.over", function(s) hud:showGameOver(s) end)

-- ... в Analytics: записать событие
Signal.register("game.over", function(s) analytics:track("game_over", {score=s}) end)

-- ... в Audio: проиграть джингл
Signal.register("game.over", function() Sound:play("game_over") end)
```

Три независимых подписчика, источник о них не знает.

---

## См. также

- [SButton.md](./SButton.md) — откуда берётся `"click"`.
- [SEInputController.md](./SEInputController.md) — откуда берётся `"input"`.
- [SSprite.md](./SSprite.md) — `SComplexAnimSprite` эмитит `"animation.stop"`.
- [Architecture.md](./Architecture.md) — когда Signal vs handlers в лоадере vs прямые ссылки.
