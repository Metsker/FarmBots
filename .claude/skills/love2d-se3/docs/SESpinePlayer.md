# SESpinePlayer — Extended Guide

`SESpinePlayer` — это `SObject`, который проигрывает скелетную анимацию **Spine 4.2**. Он оборачивает vendored-рантайм `zhengying/spine-love2d` (`vendor/spine-love2d/`) и подаёт его в сцену как обычный нод: трансформы композятся с родителем, `update`/`draw` гоняются через стандартную пропагацию, `.off`/`.hidden`/`.eventoff` работают как ожидаешь.

Файл: `sespineplayer.lua`.

---

## Оглавление

1. [Что даёт SESpinePlayer](#1-что-даёт-sespineplayer)
2. [Способы загрузки](#2-способы-загрузки)
3. [Объявление на сцене (манифест)](#3-объявление-на-сцене-манифест)
4. [API — создание и props](#4-api--создание-и-props)
5. [Переключение spine / animation / skin](#5-переключение-spine--animation--skin)
6. [Followers — узлы, следующие за костью/слотом](#6-followers--узлы-следующие-за-костьюслотом)
7. [Z-order внутри SGroup](#7-z-order-внутри-sgroup)
8. [ASTC-текстуры](#8-astc-текстуры)
9. [Жизненный цикл ресурсов](#9-жизненный-цикл-ресурсов)
10. [Типичные ошибки](#10-типичные-ошибки)

---

## 1. Что даёт SESpinePlayer

- **Скелетный проигрыватель как нод дерева.** Позиционируется через `x/y/sx/sy/r/pivot` как и любой `SObject`, участвует в z-сортировке внутри `SGroup`.
- **Общие ресурсы.** Несколько плееров, ссылающихся на один и тот же `spine = "name"`, делят одну `SkeletonData` и один атлас (каждый клонирует свои `Skeleton` + `AnimationState`). JSON парсится один раз, текстуры загружаются один раз.
- **Декларативное объявление на сцене.** Регистрируется в `SESceneLoader` как встроенный тип — можно писать `{ type = "SESpinePlayer", spine = "mega_win", animation = "in" }` прямо в манифесте, без ручных require и конструкторов.
- **Интеграция с `SLoader` / `SEEnvironment`.** `resources.spineSkeletons` в манифесте сцены попадает в стандартный queue-loader — тот же прогресс-бар, то же авто-выгружение при смене сцены, что и у обычных атласов и картинок.
- **Followers.** SE3-ноды (текст, спрайты, целые `SGroup`) можно пришпилить к кости или слоту скелета — узел поедет вслед за анимацией.

Базовая особенность: **класс называется `SESpinePlayer`** (не `SSpinePlayer`), и именно эта строка идёт в `type` манифеста и в глобаль `_G.SESpinePlayer`.

---

## 2. Способы загрузки

У плеера два конструкторских режима, они взаимоисключающие.

### (а) Name-форма — через `SLoader`

Рекомендуемый путь для прод-сцен: скелет объявляется в `resources.spineSkeletons`, попадает в лоадер, плеер ссылается на него по логическому имени.

```lua
-- где-то в main.lua на старте (для общего ресурса):
local common = SLoader.new()
common:addSpineSkeleton("mega_win",
                         "assets/mega_win.json",
                         "assets/popups_fire.atlas",
                         0.6)       -- scale
common:loadAll()
SEEnvironment:setLoader(common, "common")

-- и теперь в любой сцене:
local player = SESpinePlayer{ spine = "mega_win", animation = "in" }
```

`SLoader:addSpineSkeleton(name, skelPath, atlasPath [, scale] [, textureHint])` ставит **один** `spine_skeleton`-item в очередь. Этот шаг выполняет JSON-parse + parse атласа + декод всех страниц + GPU-upload в один заход — большой шаг по времени, но предсказуемый для прогресс-бара (один Spine = один тик прогресса независимо от числа страниц атласа).

Имя ищется по слотам `SEEnvironment` сверху вниз (`scene` → `common` → `default`) — та же логика, что и для картинок.

### (б) Path-форма — ad-hoc

Полезно в примерах или отладке, когда лоадер не хочется заводить:

```lua
local player = SESpinePlayer{
  skeleton  = "assets/mega_win.json",
  atlas     = "assets/popups_fire.atlas",
  scale     = 0.6,
  animation = "in",
}
```

Плеер сам прочтёт файлы и построит bundle в `init`. Но каждый такой плеер строит свою собственную `SkeletonData` + собственный атлас с собственными текстурами — **делёжки ресурсов между инстансами нет**. Для прод-кода используйте name-форму.

---

## 3. Объявление на сцене (манифест)

Типовой сценарий — попап, анимация, slot-символ — полностью описываются в манифесте, без ручных `require`.

### Объявление ресурсов

```lua
return {
  resources = {
    spineSkeletons = {
      { name = "mega_win",
        skeleton = "assets/mega_win.json",
        atlas    = "assets/popups_fire.atlas",
        scale    = 0.6 },
      { name = "sym_traveler_win",
        skeleton = "assets/spine/sym_traveler_win.json",
        atlas    = "assets/spine/sym_traveler_win.atlas",
        texture  = "astc" },                                -- force ASTC pages
    },
  },
  -- ...
}
```

| Поле | Обязательность | Описание |
|------|-----------------|----------|
| `name` | обязательно | логическое имя, под которым плеер найдёт bundle (`spine = "..."`) |
| `skeleton` | обязательно | путь к `.json`-файлу скелета |
| `atlas` | обязательно | путь к `.atlas`-файлу |
| `scale` | опц. (1) | `SkeletonData.scale` — мировой масштаб |
| `texture` | опц. (`auto`) | `"astc"` / `"png"` / `nil` — см. [§8](#8-astc-текстуры) |

Пути префиксуются `pathPrefix`-ом сцены так же, как у обычных ресурсов — standalone-сцена из `examples/` работает как есть, та же сцена, смонтированная в большой проект через `SESceneManager:register("lobby", "modules.scenes.lobby.scene_description")`, получает префикс автоматически. Если путь должен остаться «проектным» — начните его с `!`:

```lua
{ name = "megawin_shared",
  skeleton = "!shared/spine/megawin.json",
  atlas    = "!shared/spine/megawin.atlas" }
```

### Объявление нода

```lua
scene = {
  type = "SGroup", x = 640, y = 360,
  {
    type      = "SESpinePlayer",
    id        = "popup",
    spine     = "mega_win",    -- ← имя из resources.spineSkeletons
    skin      = "gold",        -- ← опционально, применяется после setup-pose
    animation = "in",          -- ← опционально, стартовая анимация на track 0
    loop      = false,
    scale     = 1.0,           -- игнорируется когда spine = "name"
  },
}
```

| Поле | Описание |
|------|----------|
| `spine` | логическое имя bundle-а (name-форма) |
| `skeleton` + `atlas` | пути для path-формы (альтернатива `spine`) |
| `scale` | только для path-формы; при `spine = "name"` масштаб был зафиксирован при регистрации |
| `animation` | имя анимации на track 0; если нет — скелет стоит в setup-pose |
| `loop` | закольцевать стартовую анимацию (default: `false`) |
| `skin` | имя скина; применяется после `setSlotsToSetupPose` |

Всё остальное — стандартные `SObject`-поля (`x, y, z, sx, sy, r, pivot, color, alpha, off, eventoff, hidden`).

### Цепочка анимаций через `onEnter`

Плеер не знает про «сначала intro, потом idle». Для этого используют `addAnimation`:

```lua
return {
  resources = { spineSkeletons = { { name = "mega_win", ... } } },
  scene = {
    type = "SGroup", x = 640, y = 360,
    { type = "SESpinePlayer", id = "popup",
      spine = "mega_win", animation = "in", loop = false },
  },
  onEnter = function(scene)
    local popup = scene:byId("popup")
    popup:addAnimation("idle", true, 0)       -- idle зациклится после intro
  end,
}
```

---

## 4. API — создание и props

### Конструктор

```lua
SESpinePlayer{
  -- name-форма:
  spine     = "mega_win",

  -- или path-форма:
  skeleton  = "assets/foo.json",
  atlas     = "assets/foo.atlas",
  scale     = 0.5,

  -- общее:
  animation = "in",
  loop      = false,
  skin      = "gold",

  -- все общие поля SObject (x, y, sx, sy, r, pivot, color, alpha, off, ...)
}
```

### Рантайм-API

```lua
player:setAnimation(name [, loop] [, track] [, mix])       -- заменить анимацию на треке (default track=0)
player:addAnimation(name [, loop] [, delay] [, track] [, mix])  -- поставить в очередь после текущей
player:setTimeScale(scale)                                  -- глобальный спид-фактор анимации
player:setSkin(name)                                        -- переключить скин (с пересбором slot-attachments)
player:setSpine(nameOrBundle [, opts])                      -- целиком заменить скелет (см. §5)
player:setDefaultMix(seconds)                               -- дефолтный cross-fade между любой парой
player:setMix(fromAnim, toAnim, seconds)                    -- per-pair override
```

`mix` — длительность cross-fade между уходящей и приходящей анимациями в секундах. `nil` — взять значение из `AnimationStateData` (per-pair `setMix` или `defaultMix`, по умолчанию 0.25). `0` — хард-кат, без fade. Реальный mixing был добавлен патчем поверх vendored-рантайма; см. `vendor/spine-love2d/PATCHES.md` §5.

### Followers

```lua
player:attachToBone(boneName, node [, opts])       -- пришпилить к кости
player:replaceSlot(slotName, node [, opts])        -- подменить slot-attachment на узел
player:removeFollower(handle)                      -- удалить один
player:clearFollowers()                            -- сбросить всех
```

### Внутренние поля (read-only, для продвинутого использования)

| Поле | Что это |
|------|---------|
| `self.skeleton` | `spine.Skeleton` — можно дёргать `findBone`, `findSlot`, `setToSetupPose` |
| `self.animationState` | `spine.AnimationState` — `timeScale`, `getCurrent(track)` и т.д. |
| `self._bundle` | текущий shared bundle (`{ skeletonData, atlas, attachmentLoader, scale }`) |
| `self._atlas` | текущий Spine-Atlas |

---

## 5. Переключение spine / animation / skin

### Смена анимации

```lua
player:setAnimation("idle", true)                  -- track 0, loop
player:setAnimation("hit", false, 1)               -- на track 1 (параллельно idle)
player:addAnimation("run", true, 0.2)              -- после hit через 0.2s, зациклить
```

`addAnimation` уважает очередь: анимация срабатывает когда (а) `delay` с момента окончания предыдущей истёк **и** (б) текущая запись на этом треке завершилась. Это правило пропатчено в нашем vendored-рантайме относительно upstream — см. `vendor/spine-love2d/PATCHES.md`.

### Смена скина

```lua
player:setSkin("gold")
player:setSkin(nil)        -- вернуться на default skin
```

После смены скина `setSlotsToSetupPose` вызывается автоматически — иначе слоты, которых нет в новом скине, оставались бы со «старым» attachment-ом. Есть минорный побочный эффект: attachment-timeline сбрасывается ровно на один тик, следующий `apply` его восстановит.

### Смена самого скелета (swap bundle)

Кейс: символ на барабане меняется — вместо «wild» теперь «wild_gold» с другим скелетом и атласом.

```lua
player:setSpine("wild_gold", {
  animation = "win",
  loop      = true,
  skin      = "gold",       -- опц.
  track     = 0,            -- опц., default 0
})
```

Что происходит:

1. Все **followers сбрасываются** — их ссылки на bone/slot указывали в старый скелет и больше не валидны.
2. Старые `skeleton` + `animationState` отпускаются на GC (сам bundle остаётся — его могут держать другие плееры).
3. Строятся новые из свежего bundle, применяется setup-pose.
4. Опции `skin` → `animation` применяются в этом порядке (так же, как в конструкторе).
5. Первый `apply` + `updateWorldTransform` выполняются сразу, чтобы на ближайшем `draw` скелет уже был в новой позе — без кадра-зазора.

Если после свопа нужно переприкрепить узлы:

```lua
player:setSpine("wild_gold", { animation = "win", loop = true })
player:replaceSlot("$", winAmountText)      -- followers опять надо пришпилить руками
```

Можно передать готовый bundle (таблицу `{ skeletonData, atlas, attachmentLoader, scale }`) напрямую — так работают специализированные кейсы, где bundle строится вручную через `buildSpineBundle` или кастомный кэш:

```lua
local bundle = buildSpineBundle("a.json", "a.atlas", 1.0)
player:setSpine(bundle, { animation = "idle", loop = true })
```

---

## 6. Followers — узлы, следующие за костью/слотом

Follower — это механизм, позволяющий «прибить» любой `SObject` (текст, спрайт, группу) к **кости** или **слоту** скелета. Каждый кадр, сразу после того как скелет отрендерился, follower-узел рисуется в системе координат кости — с позицией, опционально поворотом и масштабом.

```lua
local winText = SText{ font = "main", text = "0", pivot = {0.5, 0.5}, color = "#fff" }
local handle  = player:replaceSlot("$", winText)      -- скрыть attachment слота "$" и отрисовать текст вместо него

-- позже:
winText:setText(tostring(currentWin))                  -- следует за слотом вместе со скелетом

player:removeFollower(handle)                          -- убрать один
player:clearFollowers()                                -- убрать всех (делает setSpine автоматически)
```

| Метод | Что делает |
|-------|-----------|
| `attachToBone(boneName, node [, opts])` | узел рисуется поверх скелета в системе координат кости |
| `replaceSlot(slotName, node [, opts])` | то же + скрывает native attachment слота на время этого кадра (восстанавливается перед следующим `apply`, чтобы attachment-timeline продолжал работать) |
| `removeFollower(handle)` | убрать конкретный (handle — то, что вернул `attachToBone`/`replaceSlot`) |
| `clearFollowers()` | убрать всех |

`opts` (оба метода):

| Поле | Default | Описание |
|------|---------|----------|
| `keepRotation` | `true`  | следовать за поворотом кости |
| `keepScale`    | `true`  | следовать за масштабом кости |
| `offsetX`      | `0`     | px добавляется к bone.worldX **до** rotate/scale → остаётся в screen-space (не плывёт со scale кости) |
| `offsetY`      | `0`     | то же по Y |
| `inheritAlpha` | `false` | если `true` — каждый кадр перед draw'ом follower'а его `node.color[4]` умножается на `skeleton.a × slot.color.a` (и восстанавливается после). Это даёт «как у нативного слота» поведение alpha — текст-follower плавно проявляется/прячется синхронно с spine-анимациями (`open` / `idle` / `close` обычно колбасят `slot.color.a`). Требует `node.color` (SObject's color-table); если у ноды его нет — opt тихо игнорируется. |
| `bone`         | `slot.bone` | **Только для `replaceSlot`.** Имя bone, за которым реально следить. По умолчанию это bone-владелец слота. Override полезен, когда слот-источник (например baked `$`-attachment с суммой) сидит на root-parented кости без scale/translate-таймлайна, а сама плашка зумится через parent-кость (типа `popup_all`). Тогда `slot` выбирает что **скрыть** (нативный `$`-attachment с placeholder-картинкой), а `bone` — за чем **следить** (parent-кость с правильной анимацией). Если bone не найден — ошибка. |

`offsetX/Y` живёт в **мировых пикселях**, потому что translate происходит до rotate/scale. Если нужен offset который масштабируется вместе с костью — клади его на `node.x` / `node.y`, оно применяется уже в bone-local transform внутри `node:__draw`.

### Декларативная привязка (через манифест)

То же самое можно описать **прямо в scene-описании** через поле `followers = {...}` на любой ноде, у которой есть `:player()` (то есть на `SAnimatedSpine`). `SESceneLoader` автоматически вызовет `replaceSlot` или `attachToBone` после построения родительской ноды:

```lua
{ type = "SAnimatedSpine", id = "jackpot_popup",
  spine = "jackpot",
  ...
  followers = {
    -- replaceSlot вариант с alpha-наследованием от спайна
    { slot = "_numbers", id = "jackpot_amount",
      inheritAlpha = true,                       -- fade synced со спайном
      offsetX = 0, offsetY = -10,
      keepRotation = true, keepScale = true,    -- defaults, можно опустить
      type  = "SText",
      font  = "popup_amount",
      text  = "$jackpotText",                    -- $-bind работает как в обычной ноде
      pivot = {0.5, 0.5},
      color = "#ffffff",
    },
    -- attachToBone вариант
    { bone = "head", offsetY = -10,
      type = "SSprite", img = "crown" },

    -- replaceSlot + bone override: скрыть baked '$'-attachment, но
    -- following-кость взять из "popup_all" (у "$"-bone-а нет нужной
    -- scale-таймлайны, а у "popup_all" есть).
    { slot = "$", bone = "popup_all",
      inheritAlpha = true,
      type = "SText", text = "$bigWinText",
      pivot = {0.5, 0.5}, color = "#ffffff",
      font = "popup_amount",
      y = 122 },
  },
},
```

Каждая запись:
1. Должна иметь **хотя бы одно** из `slot = "..."` (→ `replaceSlot`) или `bone = "..."` (→ `attachToBone`). **Можно указать оба** одновременно — `slot` + `bone` означает «replaceSlot, но following-кость override'нута на `bone`» (тот же эффект, что `handle.bone = findBone(name)` в imperative-варианте). Иначе loader выбросит ошибку.
2. Опциональные `offsetX / offsetY / keepRotation / keepScale / inheritAlpha` — те же, что в imperative-API.
3. Остальные поля (`type`, `id`, `font`, `text`, и т.д.) — обычный node-descriptor: рекурсивно строится `_buildNode`, регистрируется в `byId`, биндится `$key`-strings.

Loader автоматически ставит `off = true` на follower-ноду, чтобы parent-итерация в `__draw` её не отрендерила второй раз (follower-путь `f.node:__draw(...)` рисует напрямую и off-флаг не читает — иначе была бы двойная отрисовка).

**Imperative API не отменяется.** `replaceSlot` / `attachToBone` остаются работоспособными в `scene.lua:onEnter`. Декларативная форма теперь покрывает и bone-override-кейс (раньше это было причиной идти в imperative).

Смешивать обе формы в одной сцене безопасно — каждый follower живёт в своём `_followers[]` независимо.

### Порядок рисования

Все followers рисуются **после всего скелета**, в том порядке, в котором они были добавлены. Промежуточные z-слои внутри скелета (нод между двумя slots) **не поддерживаются** — если нужен такой порядок, выведите узел из плеера в родительский `SGroup` и сортируйте его там через z-индекс.

### Реализация (для любопытных)

- `keepRotation` читает `atan2(bone.c, bone.a)` — это работает корректно при `flipY = true`, потому что флип учтён в самом повороте. Повторно инвертировать Y не нужно.
- `keepScale` восстанавливает `bsx = √(a² + c²)` и `bsy = √(b² + d²)` из world-transform кости.
- `replaceSlot` делает `slot.attachment = nil` только на время `draw`, потом восстанавливает. Это важно: без восстановления `AnimationState:apply` на следующем тике продолжит видеть пустой attachment и attachment-timeline сломается.

---

## 7. Z-order внутри SGroup

`SESpinePlayer` реализует `cacheCoords` + `drawCached` — значит он полноценно участвует в z-сортировке внутри `SGroup`. Конкретно:

```lua
SGroup{ x = 640, y = 360,
  SSprite        { img = "bg",            z = 0 },
  SESpinePlayer  { spine = "player_idle", z = 5 },
  SSprite        { img = "foreground",    z = 10 },
  SText          { text = "HUD",          z = 100 },
}
```

`SGroup` при рендере сначала зовёт `cacheCoords` на всех детях (в том числе на плеере — тот сохраняет свой `x, y, r, sx, sy, tx, ty`), затем сортирует `zchilds` по `.z` и проходит `drawCached` по порядку. Плеер рисует скелет + followers из `drawCached` с закэшированными координатами — в итоге рисование попадает на нужное место z-стека.

Внутри самого скелета собственной z-сортировки между слотами нет — там порядок слотов фиксирован схемой Spine (draw-order в `.json`). Если нужна динамическая z-перестановка между частями персонажа, Spine-сторона решает это разными слотами и attachment-ами, а не SE3-уровнем.

---

## 8. ASTC-текстуры

Страницы Spine-атласа участвуют в том же `.png → .astc` резолвере, что и обычные атласы `SLoader:addAtlas`:

| Хинт | Поведение |
|------|-----------|
| `nil` (default) | Если GPU поддерживает `ASTC6x6` и рядом с `.png` есть `.astc` — грузится `.astc`; иначе `.png`. |
| `"astc"` | Форсит `.astc`. Падает, если GPU не умеет ASTC. |
| `"png"` | Всегда `.png`. Отключает резолвер. |

Реализовано через поле `Atlas.textureHint`, которое читает vendored `Atlas:loadPageTexture`. См. `vendor/spine-love2d/PATCHES.md` §3.

На Mac OpenGL ASTC недоступен (Love 11.5 → GL transition layer), поэтому `nil`-режим на Mac тихо откатывается на PNG и скорости загрузки не прибавляет. Реальные цифры измеряются на target-железе (RPi5 / iOS / Android).

---

## 9. Жизненный цикл ресурсов

### Slots и SESceneManager

При `manager:change("lobby")` слот `"scene"` в `SEEnvironment` замещается свежим `SLoader`. Все ресурсы предыдущей сцены — включая `_spineBundles` — выгружаются. Каждый bundle, уходя, вызывает `atlas:dispose()`, что релизит все текстуры страниц атласа. Плееры, которые всё ещё могли бы на них ссылаться, уже ушли из дерева вместе со сценой.

Слот `"common"` при смене сцены не трогается — если spine-скелет нужен нескольким сценам, зарегистрируйте его в common-слоте один раз на старте.

### Shared-bundle между плеерами

Один `addSpineSkeleton("mega_win", ...)` — **один** парс JSON, **один** атлас, **одни** текстуры в VRAM. Каждый `SESpinePlayer{ spine = "mega_win" }` клонирует свой `Skeleton` + `AnimationState`, но делит с остальными `SkeletonData` и текстуры. Если у вас на экране 6 одинаковых spine-символов — это примерно та же стоимость, что и один, с небольшим оверхедом на `AnimationState`.

### Явный unload

`SLoader:unload()` чистит `_spineBundles` и зовёт `bundle.atlas:dispose()` на каждом. Руками обычно не нужно — `SEEnvironment:setLoader(newLoader, "scene")` и `removeLoader("scene")` делают это автоматически.

---

## 10. Типичные ошибки

### «`no spine bundle named '...'` при построении плеера»

Имя не зарегистрировано в `SLoader` видимом из `resource`. Чеклист:

- `resources.spineSkeletons = { { name = "x", ... } }` действительно есть в манифесте сцены?
- Сцена вошла через `SESceneManager:change(...)` (чтобы слот `"scene"` заполнился), или вы строите вручную через `SESceneLoader:load(...)` — в обоих случаях лоадер должен быть зарегистрирован в `SEEnvironment`?
- `resource` указывает на `SEEnvironment`? (По умолчанию — да, `init.lua` это настраивает.)

Быстрая проверка:

```lua
for _, slot in ipairs(SEEnvironment._stack) do
  print(slot.name, slot.loader._spineBundles and
                    ("bundles: " .. #({})+0) or "no bundles field")
end
print(resource:getSpine("x"))     -- либо bundle-таблица, либо nil
```

### «Followers стоят на месте, скелет двигается»

Типичная причина: `keepRotation` / `keepScale` случайно отключены, или follower на подъёме привязан к другой кости. Убедитесь, что `boneName` совпадает с реальной костью в Spine (зависит от регистра). `self.skeleton:findBone(boneName)` должно вернуть не-`nil`.

### «Плеер не рисуется, хотя `animation` задан»

Либо `self.off = true` (в т.ч. по цепочке родителей), либо `color.a == 0`, либо скелет целиком ушёл за область отрисовки из-за `scale` bundle-а. Быстрый тест:

```lua
print(player.off, player.color and player.color[4])
print(player.skeleton:findBone("root").worldX,
      player.skeleton:findBone("root").worldY)
```

### «После `setSpine` followers пропали»

Это by design — handle-ссылки из старого скелета невалидны. Перевязывайте после свопа:

```lua
player:setSpine("new_skeleton", { animation = "idle", loop = true })
player:replaceSlot("$", winText)
player:attachToBone("head", glowEffect)
```

### «Прогресс-бар мигает, когда я добавляю много скелетов»

Каждый `spine_skeleton`-item — один шаг прогресс-бара. Если в сцене 20 скелетов, и вы рисуете бар из долей (`loaded/total`), он дёрнется 20 раз. Это нормально: spine-шаги дорогие (в пересчёте на шаг — тяжелее, чем шаг на текстуру атласа), но ровные по количеству. Если нужен гладкий визуал — сгладьте значение бара с `lerp` (см. [CustomPreloader.md](./CustomPreloader.md)).

### «Изменил `.atlas`-файл, но рендер не обновляется»

`SLoader` кэширует текстуры страниц атласа в `_atlasImages` по имени файла. Если имя файла не поменялось — старая текстура осталась в VRAM. Вариант — `SLoader:unload()` + пересоздать лоадер, либо переключить сцену через менеджер (он выгружает сам).

---

## См. также

- [SAnimatedSpine.md](./SAnimatedSpine.md) — декларативный state machine поверх `SESpinePlayer` для сценариев вида `show`/`idle`/`hide`, с биндингом через `$state`.
- [SLoader.md](./SLoader.md) — `addSpineSkeleton`, `addSpineAtlas`, `SEEnvironment:getSpine`, ASTC-резолвер.
- [SESceneLoader.md](./SESceneLoader.md#4-ресурсы) — секция `resources` в манифесте, включая `spineSkeletons`.
- [SESceneManager.md](./SESceneManager.md) — как «scene»-слот выгружает spine-bundle при переходе.
- Vendored runtime: `vendor/spine-love2d/PATCHES.md` — наши отличия от upstream (multi-page atlas, queue/delay fix, textureHint).
- Примеры: `examples/spine_popup/` (полноценная сцена с манифестом), `examples/spine_mesh/`.
