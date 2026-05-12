# SLoader + SEEnvironment — Extended Guide

Загрузка ассетов и `resource`-контекст, который движок использует для поиска картинок/шрифтов/звуков.

Файлы: `seloader.lua`, `seenv.lua`.

---

## Оглавление

1. [Роли SLoader и SEEnvironment](#1-роли-sloader-и-seenvironment)
2. [SLoader — очередь и загрузка](#2-sloader--очередь-и-загрузка)
3. [SEEnvironment — стек лоадеров](#3-seenvironment--стек-лоадеров)
4. [Готовый `resource` для движка](#4-готовый-resource-для-движка)
5. [Прогресс-бар с `SLoader`](#5-прогресс-бар-с-sloader)
6. [Слоты: common, scene, default](#6-слоты-common-scene-default)
7. [Типичные ошибки](#7-типичные-ошибки)

---

## 1. Роли SLoader и SEEnvironment

- **`SLoader`** — инкрементальный загрузчик. Держит очередь ассетов, умеет грузить по одному (`step()`) или все сразу (`loadAll()`). Экспортирует `get/getFont/getSound/getButton` — интерфейс, совместимый с глобальным `resource`.
- **`SEEnvironment`** — стек именованных лоадеров. Реализует тот же интерфейс (`get/...`), но ищет по слотам сверху вниз. Это позволяет иметь одновременно «общий» слот и «сценовый» слот, не мешая их.

Минимальная схема:

```
Love2D
  │
  │ resource = SEEnvironment
  │
  ├──── slot "scene"   →  SLoader(current-scene-assets)
  ├──── slot "common"  →  SLoader(shared-across-scenes)
  └──── slot "default" →  SLoader(default-font, fallbacks)
         (поиск идёт сверху вниз: scene → common → default)
```

Почему не один `SLoader`: при переходе между сценами надо **освободить** память от старых ассетов, но оставить общие. Отдельные слоты решают это: `setLoader(newScene, "scene")` автоматически выгружает старый «scene» и заменяет его, а `"common"` остаётся.

---

## 2. SLoader — очередь и загрузка

```lua
local loader = SLoader.new()

loader:addImage("bg", "assets/bg.png")
loader:addFont ("main", "assets/font.ttf", 32)
loader:addSound("click", "assets/click.ogg")
loader:addSound("bgm",   "assets/bgm.ogg", "stream")   -- streamed

loader:addAtlas("atlases.ui", "assets/ui/")

loader:loadAll()
```

### API

| Метод | Что делает |
|-------|-----------|
| `SLoader.new([{ threaded?, workers? }])` | новый пустой лоадер; опциональный threaded-режим (см. §Threaded decode) |
| `:addImage(name, path [, hint])` | очередь: `newImage(path)` (см. §ASTC-резолвер) |
| `:addSound(name, path [, "static"\|"stream"])` | очередь: `newSource(path, type)` |
| `:addFont(name, path, size)` | очередь: `newFont(path, size)` |
| `:putFont(name, fontObj)` | сразу, без очереди — для готовых Love-fонтов |
| `:addAtlas(requirePath, basePath [, hint])` | очередь: require + развёртка текстур атласа |
| `:addSpineAtlas(atlasPath, basePath [, hint])` | Spine v4 text-атлас (см. `SESpineAtlas`) |
| `:addSpineSkeleton(name, skelPath, atlasPath [, scale] [, hint])` | Spine-скелет: `.json` + `.atlas` под логическим именем (см. [SESpinePlayer.md](./SESpinePlayer.md)) |
| `:step()` | загрузить один ассет; возвращает `true` когда очередь пуста |
| `:loadAll()` | блокирующая полная загрузка |
| `:progress()` | `0..1` (1 если ничего не добавлено) |
| `:done()` | `true` если очередь пуста |
| `:unload()` | освободить все Love-ресурсы, очистить мапы |

### Ключевые особенности

**`addAtlas`.** Один шаг — парсинг Lua-файла атласа (дёшево, без I/O). Затем для каждой уникальной текстуры атласа **добавляется отдельный шаг** в очередь — это позволяет видеть прогресс по текстурам. У больших атласов (4-8 PNG) это даёт плавный прогресс-бар, а не одну длинную паузу.

### ASTC-резолвер (опциональный хинт)

Все текстуро-грузящие методы (`addImage`, `addAtlas`, `addSpineAtlas`) принимают третьим параметром хинт формата:

| Хинт | Поведение |
|------|-----------|
| `nil` (default) | Если GPU поддерживает `ASTC6x6` **и** рядом с `.png` лежит `.astc` — грузится `.astc`; иначе `.png`. |
| `"astc"` | Форсит попытку `.astc` независимо от GPU-капы. Падает, если GPU не умеет ASTC. Удобно для боевого таргета (RPi5). |
| `"png"` | Отключает резолвер полностью — всегда грузит декларированный `.png`. Удобно для дебага визуального качества. |

Резолвер свапает только расширение `.png → .astc`. Пути с другими расширениями проходят как есть. Отсутствующий `.astc`-сибл прозрачно откатывает на `.png`.

В scene-манифесте хинт ставится полем `texture` на entries:

```lua
resources = {
  spineAtlases = {
    { path = "assets/spine/sym_backet_win.atlas" },                    -- auto
    { path = "assets/spine/sym_grapes_win.atlas", texture = "astc" },  -- force astc
    { path = "assets/spine/sym_cherry_win.atlas", texture = "png" },   -- force png
  },
  spineSkeletons = {
    { name = "mega_win",
      skeleton = "assets/mega_win.json",
      atlas    = "assets/popups_fire.atlas",
      scale    = 0.6,
      texture  = "astc" },      -- страницы атласа через ASTC-резолвер
  },
  images = {
    { name = "bg", path = "assets/bg.png", texture = "png" },
  },
}
```

`spineSkeletons` — полноценные скелеты Spine (не просто атлас). Бандл доступен плееру как `SESpinePlayer{ spine = "mega_win" }`. Подробнее — в [SESpinePlayer.md](./SESpinePlayer.md#3-объявление-на-сцене-манифест).

Результирующие `.astc`-файлы делает `make build` (см. корневой `Makefile` + `PRE_INSTALL.md` для тулчейна `astcenc`).

**Почему `.astc`, а не `.ktx2`.** Love 11.5 не читает KTX2 (появился только в Love 12). `.astc` — raw ASTC-контейнер с 16-байтным заголовком; Love 11.5 грузит его нативно. Тот же самый кодек, другая обёртка. Apple macOS через OpenGL-бэкенд Love 11.5 не поддерживает ASTC вообще — так что на Mac dev-машине резолвер молча падает в PNG и загрузка не ускоряется (нужно мерять на target-железе).

### Threaded decode

`SLoader.new({ threaded = true, workers = N })` переводит лоадер в многопоточный режим: PNG / KTX / ASTC / DDS / PKM / PVR декодируются в пуле из `N` воркер-тредов (`love.image.newImageData` / `newCompressedData` — thread-safe в Love). Main thread через `step()` только делает `love.graphics.newImage(data)` (обязан быть на main thread). Публичный API не меняется.

Цифры с боевого слота (M1 Max, 10 ядер, 24 PNG-атласа в `slot_2`, Mac OpenGL без ASTC):

| Config | Load time |
|--------|-----------|
| `threaded = false` (legacy) | ~1.38 s |
| `threaded = true, workers = 2` | ~0.59 s (2.3×) |
| `threaded = true, workers = 4` | ~0.33 s (4.2×) |

С `.astc`-сиблингами на RPi5 выигрыш будет ещё больше — декод PNG вообще пропадает, остаётся только file I/O + GPU upload.

**Что остаётся синхронным на main thread:**

- `atlas` / `spine_atlas` — парсинг манифеста (require или `love.filesystem.read`). Дёшево, одна `step()` на атлас; после парсинга он разворачивается в отдельные `atlas_texture`-items которые уходят в пул.
- `font`, `sound` — `love.graphics.newFont` и `love.audio.newSource` не умеют грузиться из треда. Для slot-сцен это небольшая статика, не bottleneck.

**Workers count.** Дефолт 2 — консервативный, подходит для 4-ядерных embedded. На десктопе `workers = 4` даёт почти идеальный линейный scale (до количества ядер минус 1). Выше 4 профита мало — упираемся в file I/O и main-thread GPU upload.

**Lazy init.** Тред-пул стартует на первом threadable-итеме. Если лоадер несёт только font/sound/atlas-parse (тиничные стартап-лоадеры), пул не создаётся и оверхеда нет.

**`unload()`.** Шлёт `"shutdown"` в inChan каждому воркеру, ждёт `t:wait()` на всех тредах. Всегда зовите `unload()` (или позвольте SEEnvironment позвать его при ротации слотов), иначе воркеры переживут лоадер.

**`putFont`.** Для `love.graphics.newFont(size)` (без path) или любого уже построенного шрифта. Не идёт в очередь, не меняет `progress()`. Полезно для дефолтного шрифта в `"default"` слоте (см. [§6](#6-слоты-common-scene-default)).

**Типы источников звука.** По умолчанию `"static"` — звук целиком в память. Для длинных треков (музыка) используйте `"stream"` — частичная подгрузка с диска. Меньше памяти, но задержка на старт.

### `get` — совместимость с `resource`

```lua
loader:get(name)       -- для картинок/атласных спрайтов
loader:getFont(name)
loader:getSound(name)
loader:getSpine(name)  -- pre-built Spine bundle (для SESpinePlayer{ spine = name })
```

`get` возвращает:

- Для **атласного спрайта**: `(texture, quad, rect, nil, offset)` — кортеж, ожидаемый `SSprite:setImg`.
- Для **обычной картинки**: `image, nil, nil, nil, nil` (первое значение — love.Image, остальные nil).

Это унифицированная форма, которую потребляют все спрайтовые классы.

### Unload

```lua
loader:unload()
```

Что происходит:

- Вызывается `:release()` на всех Love-объектах (картинки, звуки — но **не** шрифты, потому что Love-шрифты не имеют `release` в старых версиях; они освобождаются GC).
- Мапы очищаются, `_total = 0`, `_loaded = 0`.
- После этого лоадер снова пустой и готов принимать новую очередь.

`SEEnvironment:setLoader(new, name)` делает unload предыдущего лоадера автоматически — руками обычно не надо.

---

## 3. SEEnvironment — стек лоадеров

`SEEnvironment` — глобальный синглтон. Не создаётся через `new`, используется прямо как объект.

### API

```lua
SEEnvironment:setLoader(loader, name)      -- добавить/заменить слот
SEEnvironment:removeLoader(name)            -- удалить слот
SEEnvironment:getLoader(name)               -- получить slot's loader
SEEnvironment:unloadAll()                   -- выгрузить всё

-- resource-совместимые:
SEEnvironment:get(name)
SEEnvironment:getFont(name)
SEEnvironment:getSound(name)
SEEnvironment:getButton(name)
```

### Поиск по стеку

`_find` обходит стек **от конца к началу** (последние добавленные — первые проверяются):

```
stack = {"default", "common", "scene"}
         ↑ старые            ↑ новые

resource:get(X)
  → ищет в "scene"
  → если не нашёл, в "common"
  → потом в "default"
  → если нигде нет → nil
```

Поэтому scene-слот **переопределяет** common-слот — если в сцене свой спрайт `"ui.btn"`, он затрёт common-вариант.

### setLoader идемпотентен

```lua
SEEnvironment:setLoader(newSceneLoader, "scene")
```

Если слот `"scene"` уже был — старый лоадер `unload()`-ится автоматически, новый встаёт на его место. Если слота нет — добавляется в конец (высший приоритет).

### removeLoader

```lua
SEEnvironment:removeLoader("scene")
```

Вызывает unload и полностью удаляет слот. Используется `SESceneManager` когда новая сцена не имеет `resources` — иначе предыдущий scene-loader остался бы висеть в памяти.

### unloadAll

```lua
SEEnvironment:unloadAll()
```

Выгружает всё (типично — при выходе из игры или перед глобальной перезагрузкой).

---

## 4. Готовый `resource` для движка

Движок SE3 ищет ассеты через глобаль `resource`. Типичная настройка:

```lua
-- в main.lua
require("se3")

function love.load()
  resource = SEEnvironment
end
```

Это же делает `init.lua` автоматически при загрузке, если глобаль `resource` ещё не установлен — так что в большинстве случаев ничего руками делать не надо.

Всё, что требуется далее — наполнить хотя бы один слот:

```lua
local common = SLoader.new()
common:addFont("main", "assets/font.ttf", 32)
common:addAtlas("atlases.ui", "assets/ui/")
common:loadAll()
SEEnvironment:setLoader(common, "common")
```

После этого `resource:get("ui.btn_ok")` будет искать спрайт в атласе `atlases.ui`, `resource:getFont("main")` — шрифт и т.д.

---

## 5. Прогресс-бар с `SLoader`

Ручная полная настройка без менеджера:

```lua
-- main.lua
local resource_ready = false

function love.load()
  require("se3")
  resource = SEEnvironment

  local slow = SLoader.new()
  slow:addAtlas("atlases.ui", "assets/ui/")
  slow:addFont ("main", "assets/font.ttf", 32)
  slow:addImage("logo", "assets/logo.png")
  -- ... добавьте остальные

  _G.preloader = slow
end

function love.update(dt)
  if not resource_ready then
    if preloader:step() then
      SEEnvironment:setLoader(preloader, "common")
      resource_ready = true
      buildScene()
    end
    return
  end
  scene:__update(dt)
end

function love.draw()
  if not resource_ready then
    local p = preloader:progress()
    love.graphics.rectangle("line", 100, 300, 600, 30)
    love.graphics.rectangle("fill", 100, 300, 600 * p, 30)
    return
  end
  scene:__draw()
end
```

Для прогресс-бара на переключении сцен — см. [CustomPreloader.md](./CustomPreloader.md).

---

## 6. Слоты: common, scene, default

Рекомендуемая схема на проект любого размера:

```lua
-- default: один раз при старте
local default = SLoader.new()
default:putFont("default", love.graphics.newFont(14))
SEEnvironment:setLoader(default, "default")

-- common: ресурсы для UI, общих диалогов, loading-экрана
local common = SLoader.new()
common:addAtlas("atlases.ui", "assets/ui/")
common:addFont ("main", "assets/font.ttf", 32)
common:loadAll()
SEEnvironment:setLoader(common, "common")

-- scene: строится SESceneManager-ом автоматически для каждой сцены
```

| Слот | Время жизни | Что туда |
|------|-------------|----------|
| `default` | весь процесс | шрифт-fallback, дефолтные иконки для debug-а |
| `common` | весь процесс | общий UI, кнопки, навигация, loading-assets |
| `scene` | текущая сцена | тяжёлые специфичные ассеты (бэкграунды, анимации) |

Имена слотов произвольные — движок не проверяет их. Но `SESceneManager` жёстко использует `"scene"`, так что этот слот трогать руками не рекомендуется.

---

## 7. Типичные ошибки

### `resource:get(name)` возвращает `nil`

Причины:

- **Слот с этим ассетом не в `SEEnvironment`.** Проверьте `SEEnvironment:getLoader("scene")` / `"common"` — в каком слоте лежит.
- **`SLoader` не был `loadAll()`.** Pending-ассеты не отдаются через `get` до полной загрузки (ну технически — до своего конкретного `step`, но вы можете запросить до того, как очередь дошла до него).
- **Опечатка в имени.** Атласы TexturePacker-а часто меняют имена (пробелы → подчёркивания, расширения отрезаются). `loader:names()` в `SAtlas` (см. [SAtlas.md](./SAtlas.md)) или `for k in pairs(loader._atlasSprites) do print(k) end` в `SLoader` — быстрый способ проверить.

### Старый лоадер не выгружается

Если вы сами делаете `SLoader.new()` для сцены и забываете вызвать `unload` перед заменой — утечка памяти:

```lua
SEEnvironment:setLoader(newLoader, "scene")   -- выгружает старый автоматически
```

`setLoader` — безопасный путь. Если заменять руками без него (писать напрямую в `_stack`) — не надо.

### `unload` во время использования

`SEEnvironment:removeLoader("scene")` **сразу** выгружает Love-объекты. Если в тот же момент на экране что-то рисуется из этого лоадера — краш. `SESceneManager` это решает: он сначала вырывает ссылку на активную сцену (`_current = nil`), и только потом менеджерит слоты.

Если вы работаете с `SEEnvironment` руками в не-менеджерном коде — убедитесь, что уже заменили дерево сцены на пустое/новое перед `removeLoader`.

### Атлас с одинаковыми именами спрайтов в двух слотах

```lua
common: ui.button_play
scene:  ui.button_play     -- перекрывает
```

Скопы resolve-а читают сверху (от добавленных позже). Если scene-атлас имеет спрайт с именем из common-а, общий перекрывается. Это штатное поведение (то, что мы хотели — scene specific overrides), но если случайно — переименуйте один из атласов.

### `love.graphics.newFont` с size vs без size

Love-шрифт — это `size + path`. Если вы дважды делаете `newFont(path, 32)` — получаете два разных объекта. Каждое место, где нужен шрифт размера `32`, должно ссылаться на **один и тот же** объект (через `resource:getFont("main")` или прямо на love.Font). Хранить два одинаковых шрифта — лишняя память.

Для шрифтов разного размера от одного файла — зарегистрируйте несколько имён:

```lua
loader:addFont("main",  "assets/font.ttf", 32)
loader:addFont("small", "assets/font.ttf", 18)
loader:addFont("tiny",  "assets/font.ttf", 12)
```

---

## См. также

- [SESceneLoader.md](./SESceneLoader.md) — manifest.resources превращается в `SLoader` автоматически.
- [SESceneManager.md](./SESceneManager.md) — управление слотом `"scene"` при переключении.
- [SAtlas.md](./SAtlas.md) — как устроен TexturePacker-атлас, который грузит `SLoader:addAtlas`.
- [CustomPreloader.md](./CustomPreloader.md) — прогресс-бар на базе `SLoader`.
