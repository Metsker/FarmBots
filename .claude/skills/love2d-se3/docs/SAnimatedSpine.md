# SAnimatedSpine — Extended Guide

`SAnimatedSpine` — декларативный конечный автомат поверх [`SESpinePlayer`](./SESpinePlayer.md). Даёт именованные состояния, в каждом из которых — короткий сценарий типа «покажи узел, проиграй `in`, зациклись на `idle`». Настроен так, чтобы его было удобно привязать к ключу модели через `$state` и дальше управлять исключительно через `model:set("state", ...)`.

Файл: `seanimatedspine.lua`.

---

## Оглавление

1. [Зачем нужен ещё один state machine](#1-зачем-нужен-ещё-один-state-machine)
2. [Минимальный пример](#2-минимальный-пример)
3. [Поля определения состояния](#3-поля-определения-состояния)
4. [Scripts — шаги сценария](#4-scripts--шаги-сценария)
5. [Хуки состояния](#5-хуки-состояния)
6. [Управление: setState, getState, defineState](#6-управление-setstate-getstate-definestate)
7. [Интеграция с SEModel через `$state`](#7-интеграция-с-semodel-через-state)
8. [Мульти-трек](#8-мульти-трек)
9. [Плавные переходы — mix](#9-плавные-переходы--mix)
10. [Типовые паттерны](#10-типовые-паттерны)
11. [Edge cases](#11-edge-cases)

---

## 1. Зачем нужен ещё один state machine

`SESpinePlayer` — сырая обёртка: у неё есть `setAnimation`, `addAnimation`, `setSkin`, `setTimeScale`, но нет понятия «состояние» и «цепочка шагов». Типичный сценарий попапа — `setAnimation("in")`, повесить слушатель на `complete`, внутри вызвать `setAnimation("idle", true)` — быстро превращается в клубок из колбэков и ручной синхронизации с видимостью, моделью и звуком.

`SAnimatedSpine` делает ровно одно: превращает это в декларацию.

```lua
state = {
  show = [[включи видимость; проиграй in; когда закончится — зациклись на idle]],
  hide = [[проиграй out; выключи видимость]],
}
```

На Lua это выглядит так:

```lua
SAnimatedSpine{
  spine = "mega_win",
  state = "$state",                  -- live-биндинг ключа модели "state"
  states = {
    hidden = { off = true },
    show = {
      off = false,
      scripts = {
        {"play", "in"},
        {"play", "idle", loop = true},
      },
    },
    hide = {
      scripts = {
        {"play", "out"},
        {"set",  {off = true}},
      },
    },
  },
}
```

Дальше всё поведение раскручивается через `model:set("state", "show")` / `model:set("state", "hide")`.

### Что он даёт и чего не даёт

Даёт:

- именованные состояния со своими сценариями;
- жёсткую интеграцию с видимостью: `off = true` гасит и отрисовку, и `update` — рантайм Spine перестаёт считать кадры;
- soft-interrupt со встроенным **cross-fade** при смене состояния и между шагами (см. [§9](#9-плавные-переходы--mix));
- мульти-трек (`track = N`), в том числе non-blocking `wait = false` для параллельных эффектов;
- декларативный биндинг через `$state` — бесплатно, потому что setter для `state` — это просто `setState`.

Не даёт и не будет:

- tween-скриптов как у [`SAnimatedObject`](./SAnimatedObject.md) (`easyng`/`custom`/`shake`). Tween работает на Lua-стороне; `SAnimatedSpine` же намеренно оставляет анимацию Spine'у — скелет для этого и нужен;
- нативных событий Spine из `.json`. Слушаем только `complete` трека — ровно столько, сколько нужно для цепочек `play`.

---

## 2. Минимальный пример

Path-форма, без лоадера (для отладки):

```lua
local win = SAnimatedSpine{
  x = 640, y = 360,
  skeleton = "assets/mega_win.json",
  atlas    = "assets/mega_win.atlas",
  scale    = 0.6,

  initial = "hidden",
  states = {
    hidden = { off = true },

    show = {
      off = false,
      scripts = {
        {"play", "in"},                       -- блокирует до complete
        {"play", "idle", loop = true},        -- loop → auto fire-and-forget
      },
    },

    hide = {
      scripts = {
        {"play", "out"},
        {"set",  {off = true}},
      },
    },
  },
}
scene:add(win)

-- вручную:
win:setState("show")
-- позже:
win:setState("hide")
```

Name-форма через манифест сцены — та же декларация, ресурс уезжает в `SLoader`:

```lua
return {
  resources = {
    spineSkeletons = {
      { name = "mega_win",
        skeleton = "assets/mega_win.json",
        atlas    = "assets/mega_win.atlas",
        scale    = 0.6 },
    },
  },
  model = "...",                      -- опционально — ключ "state" здесь и будет
  scene = {
    type = "SGroup", x = 640, y = 360,
    { type    = "SAnimatedSpine",
      id      = "popup",
      spine   = "mega_win",
      state   = "$state",             -- live-биндинг; init + setState уже подтянут
      states  = {
        hidden = { off = true },
        show = { off = false,
          scripts = { {"play", "in"}, {"play", "idle", loop = true} } },
        hide = {
          scripts = { {"play", "out"}, {"set", {off = true}} } },
      },
    },
  },
}
```

Где-нибудь в контроллере или в `onEnter` сцены:

```lua
scene:byId("popup"):setState("hidden")   -- или model:set("state", "hidden") при bindе
```

---

## 3. Поля определения состояния

Все поля опциональны. Пустое состояние — это просто маркер, в котором ничего не происходит.

| Поле | Эффект |
|------|--------|
| `off` | `true` / `false` / `nil` — проставляется на `SAnimatedSpine` при входе в state. `true` гасит отрисовку и update поддерева; `false` включает обратно. `nil` — не трогать. |
| `skin` | имя скина Spine; применяется через `player:setSkin`. `nil` = не менять. |
| `timeScale` | глобальный спид-фактор анимации (`player.animationState.timeScale`). |
| `x`, `y`, `r`, `sx`, `sy` | применяются к самому `SAnimatedSpine` на входе. Только присутствующие поля переопределяют объект. |
| `mix` | секунды; cross-fade по умолчанию для всех `play`/`queue`-шагов внутри этого state. Перебивает класс-уровневый дефолт; перебивается per-step `mix`. См. [§9](#9-плавные-переходы--mix). |
| `scripts` | цепочка шагов (см. [§4](#4-scripts--шаги-сценария)). Пустая/отсутствующая — тогда состояние только применяет top-level поля и вызывает `onEnter`. |
| `onEnter` | `function(self, prevStateName)` — после применения top-level полей, перед стартом scripts. |
| `onExit` | `function(self, nextStateName)` — перед сменой состояния (до сброса очереди и применения нового state). |
| `onAnimationEnd` | `function(self)` или `"stateName"` — когда `scripts` добежали до конца. |

### Порядок вещей при `setState("X")`

1. `onExit` у предыдущего состояния (если было).
2. **Soft-interrupt:** очередь аннимаций (`addAnimation`-entries) сбрасывается, но активные треки остаются — первый `play` нового state мягко переходит из них через cross-fade. Если новый state хочет жёстко гасить трек — он использует `{"clear", track = N}` или `{"clear"}` шаг (см. [§4](#4-scripts--шаги-сценария)).
3. `_currentState` становится `X`.
4. Top-level поля `X` применяются: `off`, `skin`, `timeScale`, `x/y/r/sx/sy`.
5. `onEnter` у `X`.
6. Если у `X` есть `scripts` — запускается первый шаг + прогон всех немедленно-выполняемых шагов в том же тике.
7. **Auto-`forceApply`** — если `off` переключился из `true` в `false` через шаг 4 (popup стал видим), вызывается `self:forceApply()`. Это сбрасывает skeleton в setup-pose и применяет текущий animation track НА СВЕЖУЮ — без этого один кадр между `setState` и следующим `__update` skeleton рендерился бы в setupPose (= полностью открытый popup для типичного `you_win`-style спайна) или в финальной позе предыдущего state'а.

Важный нюанс: `setState("X")` при `_currentState == "X"` — **no-op**. Ни `onExit/onEnter`, ни reset скриптов. Нужна «перезагрузка» — пропустите через промежуточное состояние (`setState("hidden")` → `setState("show")`) или добавьте отдельный reset-state.

### `forceApply()` — публичный метод

Принудительно прогнать skeleton к свежей позе текущего animation track'а:

```lua
skeleton:setToSetupPose()       -- bones + slots → setup defaults
animationState:apply(skeleton)  -- применить активные tracks
skeleton:updateWorldTransform() -- пересчитать world-coords костей
```

Авто-вызывается setState'ом на `off=true→false`-переходе (см. шаг 7 выше). Вручную вызывайте когда нужен hard-reset позы по другой причине — например когда `setState` ранне-возвратился (`_currentState == name`) и вы хотите всё равно re-применить state, или когда смена pose должна стать видимой в этом же кадре до следующего `__update`.

---

## 4. Scripts — шаги сценария

`scripts` — массив шагов, выполняемых последовательно. Управление **имплицитное**: большинство шагов завершаются сразу в текущем тике, а «блокирующие» (`play` без loop, `wait`) дожидаются своего условия и только потом отдают управление следующему шагу.

```lua
scripts = {
  {"play",  "in"},
  {"play",  "idle", loop = true},     -- loop автоматически делает шаг non-blocking
  {"wait",  0.3},
  {"set",   {skin = "gold"}},
  {"fire",  "ui_mega_win_shown"},
  {"call",  function(self) print("done") end},
  {"goto",  "hide"},
}
```

### `play` — проиграть анимацию

```lua
{"play", "in"}                                -- track 0, один раз, блокирует до complete
{"play", "idle", loop = true}                 -- loop → wait=false автоматически
{"play", "sparkles", track = 1, wait = false} -- non-blocking FX на track 1
{"play", "run", loop = true, track = 0}       -- loop + явный track
{"play", "in", mix = 0.3}                     -- 0.3s cross-fade из текущей анимации
{"play", "out", mix = 0}                      -- хард-кат, без fade
```

Параметры:

| Ключ | Default | Значение |
|------|---------|----------|
| `[2]` | обязателен | имя анимации |
| `track` | `0` | индекс трека Spine |
| `loop` | `false` | зацикливать |
| `wait` | `not loop` | ждать `complete` трека. При `loop = true` игнорируется и форсируется в `false` — иначе шаг висел бы навечно. |
| `mix` | inherit | cross-fade в секундах. `nil` (default) — наследовать: state.mix → class.mix → vendor (0.25). `0` — хард-кат. См. [§9](#9-плавные-переходы--mix). |

`complete` детектируется через per-track listener: `animationState.tracks[i].listener = {complete = fn}`. С патчем mixingFrom каждый `setAnimation` создаёт новый объект-трек (старый уезжает в `mixingFrom` для fade), так что listener привязывается ровно к новой анимации и не прилетает на ту, на которую уже не подписаны.

### `queue` — поставить анимацию в очередь на тот же трек

```lua
{"queue", "idle", loop = true}                -- после текущей на track 0
{"queue", "hit", delay = 0.2, track = 1}      -- через 0.2 сек на track 1
{"queue", "idle", loop = true, mix = 0.5}     -- mix перенесётся в момент срабатывания
```

Шаг всегда non-blocking — сразу идём дальше, Spine сам запустит запись когда нужно. Это транзит к `player:addAnimation`. Поле `mix` переезжает на queue-entry и применяется в момент, когда entry превращается в `setAnimation` (т.е. fade случится между «текущей в момент срабатывания» и этой queued).

### `wait` — пауза

```lua
{"wait", 0.4}
```

Блокирует `scripts` на `N` секунд. Треки Spine при этом продолжают крутиться — это пауза **сценария**, не анимации.

### `set` — применить поля к объекту

```lua
{"set", {off = true}}
{"set", {skin = "gold", timeScale = 0.5}}
{"set", {x = 100, sx = 1.2}}
```

Ключи — подмножество top-level полей состояния: `off`, `skin`, `timeScale`, `x`, `y`, `r`, `sx`, `sy`. Применяется тот же код, что и при входе в state, так что поведение идентично.

`set` — способ выключить узел **в конце сценария**, когда `play "out"` доиграл:

```lua
hide = {
  scripts = {
    {"play", "out"},
    {"set",  {off = true}},
  },
}
```

### `fire` — отправить событие в модель

```lua
{"fire", "ui_mega_win_shown"}
{"fire", "slot_popup_done", extraPayload}
```

Транслируется в `_G.model:fire(name, ...)`, если `model` в скоупе. Если модели нет — шаг молча no-op (так что SAnimatedSpine без сцены не падает).

### `call` — произвольная функция

```lua
{"call", function(self)
  self._player:setSkin(somethingComputed)
end}
```

`self` — текущий `SAnimatedSpine`.

### `goto` — перейти в другое состояние

```lua
{"goto", "hidden"}
```

Эквивалент `self:setState("otherName")`. После него текущий `scripts` больше не тикается — управление уезжает в новый state (с его cross-fade-логикой).

### `clear` — жёстко погасить трек(и)

```lua
{"clear"}                 -- сбросить ВСЕ активные треки и очередь (no fade)
{"clear", track = 1}      -- сбросить только trk 1 + queue-записи на него
```

`setState` сам по себе тёплый: он не трогает активные треки, чтобы дать новому state мягко зайти через mix. Но если новый state ХОЧЕТ выкинуть, скажем, FX с track 1 (который пускался в outgoing-state как `wait = false, loop = true`), он явно ставит `{"clear", track = 1}` первым шагом своих scripts. `{"clear"}` без аргумента — полный hard-interrupt, аналог старого поведения.

Шаг всегда выполняется мгновенно (без fade), потому что мы убираем источник, из которого можно было бы фейдить.

### Как ведёт себя `onAnimationEnd`

Срабатывает когда последний шаг списка закончился. Для сценария «play in; play idle looped» это происходит **сразу после** старта idle (loop-шаг non-blocking → списком ничего не осталось). Для «play out; set off» — после того как `out` отыграл.

Не срабатывает, если state был прерван через `setState` (прилетевший извне). В этом случае вызывается `onExit`, а `onAnimationEnd` не запускается.

---

## 5. Хуки состояния

```lua
show = {
  off = false,
  scripts = { {"play", "in"}, {"play", "idle", loop = true} },

  onEnter = function(self, prev)
    print("showing, prev =", prev)
  end,

  onExit = function(self, nextName)
    print("leaving show, going to", nextName)
  end,

  onAnimationEnd = function(self)
    print("intro done, idle running")
  end,

  -- альтернатива: onAnimationEnd = "hide"   -- автопереход
}
```

| Хук | Когда |
|-----|-------|
| `onEnter(self, prev)` | сразу после применения top-level полей и перед стартом scripts |
| `onExit(self, next)`  | перед сменой состояния (до сброса очереди и применения нового state) |
| `onAnimationEnd(self)` | когда scripts дошли до конца естественным путём |

Все три — опциональные. `onAnimationEnd` принимает строку имени состояния как shortcut для автоперехода.

---

## 6. Управление: setState, getState, defineState

```lua
obj:setState("show")                   -- переключиться
obj:setState(nil)                      -- no-op
obj:setState("noSuchState")            -- no-op (неизвестное — игнорируется)

obj:getState()                         -- текущее имя или nil

obj:defineState("glow", { ... })       -- добавить/перезаписать одно состояние
obj:setDescriptions({ ... })           -- добавить/перезаписать сразу несколько

obj:player()                           -- доступ к нижележащему SESpinePlayer
```

`setState` идемпотентен при совпадении имени — см. §3. `defineState` умеет перезаписать определение прямо под носом у активного состояния, но тогда изменение применится только со следующим `setState`. Если нужно чтобы немедленно — после `defineState` сделайте `setState("other") + setState(name)`.

---

## 7. Интеграция с SEModel через `$state`

Биндинг получается автоматически, потому что сцена резолвит любой `$key` в prop-е в setter `setKey`. У `SAnimatedSpine` setter для `state` — это сам `setState`, так что `state = "$state"` даёт ровно то, что хочется:

1. При build сцены `props.state = mdl:get("state")` — если в модели уже что-то лежит, оно становится initial-состоянием.
2. Каждая последующая `model:set("state", "show")` диспетчится в `node:setState("show")`.

```lua
-- в манифесте сцены
{ type = "SAnimatedSpine",
  spine = "mega_win",
  state = "$state",
  states = { ... },
}

-- где-то в контроллере:
model:set("state", "show")          -- анимация сама проиграется
model:set("state", "hide")
```

Модификации: `$?state` — skipNil (начальный nil не зовёт setter), `$$state` — global model. Всё как у прочих биндингов — см. [SEModel.md](./SEModel.md#5-декларативный-bind-в-манифесте).

Если же модели нет, static-initial тоже работает — через `initial` или `state`:

```lua
SAnimatedSpine{
  spine = "mega_win",
  initial = "hidden",
  states = { ... },
}
```

`state` приоритетнее `initial`, если заданы оба.

---

## 8. Мульти-трек

Spine поддерживает до N треков — можно одновременно крутить, скажем, тело персонажа на track 0 и эффект свечения на track 1. `SAnimatedSpine` это тоже умеет:

```lua
show = {
  off = false,
  scripts = {
    {"play", "sparkles", track = 1, loop = true, wait = false},  -- постоянный FX
    {"play", "in",       track = 0},
    {"play", "idle",     track = 0, loop = true},
  },
}
```

Порядок: первый шаг запускает `sparkles` на track 1 и, поскольку `wait = false` (loop уже это форсирует), сразу передаёт управление. Второй шаг блокирует на `complete` track 0. Третий — ставит `idle` в loop и закрывает скрипт. В кадре одновременно играют `sparkles` (track 1) + `idle` (track 0).

Смена состояния через `setState` **не** трогает активные треки автоматически — их подхватывает первый `play` нового state и плавно сmix-ится. Если sparkles на track 1 нужно явно погасить при переходе в `hide`, кладут `{"clear", track = 1}` первым шагом hide-scripts. `{"clear"}` без аргумента — гасит всё.

Блокирующие `play` всегда привязаны к своему `track` — listener ставится ровно на одну запись, а не на «любую анимацию». Два параллельных блокирующих шага на разных треках `scripts` сделать нельзя, потому что цепочка линейная: для параллелизма есть `wait = false` + `queue`.

---

## 9. Плавные переходы — mix

При переходе с одной анимации на другую (как внутри `scripts`, между шагами `play`, так и при `setState`) Spine умеет плавно перетекать одной позой в другую. Это называется **mixing** или **cross-fade**: пока новая анимация набирает «силу», старая постепенно отпускается. Без него каждая смена анимации = резкий скачок поз костей.

Наш `vendor/spine-love2d` оригинально это **не делал** — поля для mix были, но `apply` всегда использовал `alpha = 1`. Мы добавили реальный mixing-патч (см. `vendor/spine-love2d/PATCHES.md` §5), и `SAnimatedSpine` пробрасывает контроль над ним.

### Откуда берётся длительность mix

Когда выполняется `play`-шаг, длительность cross-fade резолвится по цепочке:

1. **Per-step:** `{"play", "idle", mix = 0.5}` — этот шаг сделает 0.5s fade.
2. **Per-state:** `states.show = { mix = 0.3, scripts = {...} }` — все `play`-шаги в `show` без своего `mix`-поля используют 0.3s.
3. **Per-instance (class default):** `SAnimatedSpine{ mix = 0.2, ... }` — глобальный дефолт для этого SAnimatedSpine.
4. **Vendor default:** если ничего не задано выше, действует `AnimationStateData.defaultMix` (0.25s в нашей версии).

Любой явный `mix = 0` в любой из позиций — это **запрос на хард-кат без fade**. Не путать с `mix = nil` (наследовать).

### Пример

```lua
SAnimatedSpine{
  spine = "mega_win",
  mix   = 0.2,                          -- класс-уровень: между всеми анимациями
  states = {
    show = {
      mix = 0.4,                          -- show-уровень: in→idle мягче
      scripts = {
        {"play", "in"},                   -- 0.4s fade из того, что играло до setState
        {"play", "idle", loop = true},    -- 0.4s fade in→idle
      },
    },
    hide = {
      scripts = {
        {"play", "out"},                  -- 0.2s fade idle→out (берём class default)
        {"set",  {off = true}},
      },
    },
    surprise = {
      scripts = {
        {"play", "shock", mix = 0},       -- 0 — мгновенный кат, без fade
        {"play", "idle",  loop = true},
      },
    },
  },
}
```

### Per-pair mix (точечный override)

Если для конкретной пары анимаций (например, `idle → out`) нужен особый mix вне зависимости от того, в каком state это происходит — есть классический Spine-API:

```lua
local sp = SAnimatedSpine{ ... }
sp:player():setMix("idle", "out", 0.6)        -- ровно эта пара
sp:player():setDefaultMix(0.15)               -- глобально на этом плеере
```

`setMix` записывает значение в `AnimationStateData.animationToMixTime`, и каждый раз, когда `play`-шаг **не** задаёт свой собственный `mix`, рантайм спрашивает значение через `getMix(from.name, to.name)` — попадание по паре заберёт ваш override, иначе — `defaultMix`.

### Что НЕ блендится плавно

Spine умеет cross-fade для ключей **поз** (rotation/translate/scale/shear, IK/Transform constraints, deform, color), но **не** для дискретных эффектов:

- **Attachment swaps** (timeline меняет какой attachment в слоте) — мгновенны, выигрывает «последняя применённая анимация». Если в момент mix новая анимация переключает attachment, его видно сразу. Лечится либо `mix = 0` на этом шаге, либо «переходной» анимацией в Spine, где attachment меняется до/после критической точки.
- **DrawOrder timeline** — то же самое, дискретно.
- **Events** (`event`-timeline-ы из Spine .json) — мы их вообще не слушаем (см. CLAUDE.md), не тема.

Эти ограничения — общие для любого рантайма Spine, не специфичные для нашего вендора.

### Соотношение с `setState`

setState больше **не** делает hard-interrupt всех треков. Что он делает:

- сбрасывает только **очередь** (queue) — чтобы запланированные `addAnimation`-записи из outgoing-state не выстрелили на incoming;
- активные треки остаются — следующий `play`-шаг внутри incoming-state сам мягко перетечёт.

Если нужно жёстко гасить треки — явно ставится `{"clear"}` или `{"clear", track = N}` первым шагом scripts (см. [§4](#4-scripts--шаги-сценария)).

---

## 10. Типовые паттерны

### show/hide через модель

```lua
{ type = "SAnimatedSpine", spine = "mega_win", state = "$state",
  states = {
    hidden = { off = true },
    show = { off = false,
      scripts = { {"play", "in"}, {"play", "idle", loop = true} } },
    hide = {
      scripts = { {"play", "out"}, {"set", {off = true}} } },
  },
}

-- в контроллере:
model:set("state", "show")
-- ...
model:set("state", "hide")
```

### Автоцепочка: показал → поиграл → скрылся

```lua
states = {
  hidden = { off = true },

  show = {
    off = false,
    scripts = { {"play", "in"}, {"play", "hold"} },
    onAnimationEnd = "hide",             -- после hold сразу в hide
  },

  hide = {
    scripts = {
      {"play", "out"},
      {"set",  {off = true}},
    },
  },
}
```

### Победный попап с долгим idle и ручным выходом

```lua
states = {
  show = {
    off = false,
    scripts = {
      {"play", "in"},
      {"fire", "ui_mega_win_shown"},     -- внутри шаблона — например, звук
      {"play", "idle", loop = true},
    },
  },
  dismiss = {
    scripts = {
      {"play", "out"},
      {"set", {off = true}},
    },
  },
}
```

Контроллер слушает `ui_mega_win_shown` и запускает таймер на `dismiss` по тапу или по истечении таймаута.

### Смена скина между состояниями

```lua
states = {
  normal = { skin = "default", scripts = { {"play", "idle", loop = true} } },
  gold   = { skin = "gold",    scripts = { {"play", "idle", loop = true} } },
}

model:set("state", "gold")       -- скин переключится на входе
```

### Параллельный FX на вторичном треке

```lua
states = {
  fight = {
    off = false,
    scripts = {
      {"play", "swoosh", track = 1, loop = true, wait = false},
      {"play", "swing",  track = 0},
      {"play", "idle",   track = 0, loop = true},
    },
  },
}
```

На `setState("idle")` или любом другом переходе `swoosh` сам по себе **не** гасится — `setState` теперь soft. Чтобы прибить FX-трек 1 при выходе, целевой state кладёт `{"clear", track = 1}` первым шагом своих scripts. Если же FX должен пережить переход — ничего делать не надо, он остаётся.

---

## 11. Edge cases

### `setState("same")` — no-op

Защита от дребезга: частая причина — модельный `set` с тем же значением. Гарантируется, что ни `onExit`, ни `onEnter`, ни scripts не перезапустятся. Если нужен рестарт — `setState("other") + setState(name)`.

### `off = true` и последующий `setState`

Когда `off = true`, parent перестаёт звать `__update`/`__draw` → рантайм Spine замерзает. Но `setState` можно вызвать снаружи — биндинг `$state` или ручной вызов от контроллера. Вход в новое состояние снимет `off`, и через парент в следующий тик пойдёт нормальный update.

Модель: «state умеет разбудить сам себя», потому что `setState` не зависит от update-цикла.

### Interrupt внутри scripts

`setState("X")` извне прерывает текущий scripts: срабатывает `onExit` прошлого, **не** срабатывает `onAnimationEnd`. В отличие от первой версии класса треки **не** сбрасываются — новый state мягко перетекает из них через mix (если он не задал `mix = 0` или `clear`-шаг). Если нужна аккуратная передача состояния — пишите side-effect в `onExit` (например, `model:fire("popup_cancelled")`).

### `wait = true` + `loop = true` — невозможная комбинация

Loop-анимация никогда не стреляет `complete`, поэтому такой шаг висел бы вечно. `SAnimatedSpine` это детектит в парсере и форсит `wait = false` при `loop = true`. Явный `wait = true` в этом случае **игнорируется** — это не ошибка, а страховка.

### `queue` не блокирует

```lua
scripts = {
  {"play",  "in"},
  {"queue", "idle", loop = true},     -- встала в очередь
  {"play",  "fx", track = 1, wait = false},
}
```

Здесь `queue` только регистрирует запись в `player.animationState.queue` и сразу отдаёт управление третьему шагу. Первый `play "in"` всё ещё блокирующий, а `fx` стартует одновременно с ним. Это нормальный паттерн для «подготовить следующую анимацию пока текущая ещё играет».

### Порядок update: children → self

`SAnimatedSpine:__update` обращает стандартный порядок SObject: сначала дети (нижележащий `SESpinePlayer` продвигает `AnimationState` и стреляет `complete` listener), потом self (scripts видят свежий флаг `_stepDone`). Это убирает лишний тик задержки между `in` и `idle`. Побочный эффект: если добавлять дополнительных детей в `SAnimatedSpine`, их `update` тоже пойдёт до логики scripts. На практике это не проблема, но учитывайте, если вы пишете кастомный класс-потомок.

### `initial` vs `state`

Оба задают начальное состояние. Если заданы оба — выигрывает `state` (обычно приходящее из `$state`-биндинга, т.е. модельное значение актуальнее статического дефолта).

```lua
SAnimatedSpine{
  initial = "hidden",        -- fallback, если биндинг дал nil
  state   = "$state",        -- приоритет
  states  = { ... },
}
```

### Доступ к нижележащему player

`self:player()` возвращает `SESpinePlayer`-инстанс — это даёт полный runtime API, если нужно что-то нестандартное (`attachToBone`, `replaceSlot`, `setSpine`, прямой `animationState.timeScale` и т.п.).

```lua
onEnter = function(self, prev)
  self:player():attachToBone("head", glowEffect)
end,
onExit = function(self, next)
  self:player():clearFollowers()
end,
```

---

## См. также

- [SESpinePlayer.md](./SESpinePlayer.md) — нижележащий плеер: загрузка, followers, skin, ASTC, bundle lifecycle.
- [SAnimatedObject.md](./SAnimatedObject.md) — аналогичный state machine для кадровой анимации (`SAnimationSprite`). Другие шаги (`easyng`, `shake`, `custom`), без Spine.
- [SEModel.md](./SEModel.md) — декларативные `$` / `$?` биндинги и императивный `node:bind`.
- [SEFSM.md](./SEFSM.md) — state machine **уровня сцены**. Если состояний много и они связаны не только с анимацией, но и с логикой сцены, — ведите верхнеуровневую логику там и оставьте `SAnimatedSpine` на «как выглядит конкретный попап».
- [SESceneLoader.md](./SESceneLoader.md) — `SAnimatedSpine` регистрируется по умолчанию, работает в манифесте как `{ type = "SAnimatedSpine", ... }`.
