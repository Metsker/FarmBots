# SSoundManager, SShader, SAtlas — Extended Guide

Три вспомогательных класса-обёртки. Один гайд, потому что каждый — самодостаточный тонкий слой над Love2D.

Файлы: `sesound.lua`, `seshader.lua`, `seatlas.lua`.

---

## Оглавление

### [SSoundManager](#ssoundmanager)
1. [Зачем нужен пул звуков](#1-зачем-нужен-пул-звуков)
2. [Быстрый старт](#2-быстрый-старт)
3. [API](#3-api)
4. [Типичные паттерны](#4-типичные-паттерны)

### [SShader](#sshader)
5. [Что делает SShader](#5-что-делает-sshader)
6. [Быстрый старт](#6-быстрый-старт)
7. [Параметры шейдера](#7-параметры-шейдера)
8. [Типичные сценарии](#8-типичные-сценарии)

### [SAtlas](#satlas)
9. [Что это и почему оно отдельно от SLoader](#9-что-это-и-почему-оно-отдельно-от-sloader)
10. [API](#10-api)

---

## SSoundManager

### 1. Зачем нужен пул звуков

`love.audio.Source:play()` нельзя вызвать дважды на одном source без остановки. Если клик звучит одновременно 5 раз — нужен либо 5 отдельных Source, либо клонирование. Без менеджера это превращается в бойлерплейт.

`SSoundManager` решает:

- Держит пул `love.audio.Source` по имени.
- На `play(name)` находит первый свободный или клонирует новый.
- Отслеживает, какие играют.
- `stop(name)` — остановить все экземпляры этого имени.
- `stopAll()` — выгрузить всё звучание.

### 2. Быстрый старт

```lua
-- где-то в startup, один раз:
Sound = SSoundManager()

-- звуки загружены через SLoader:
loader:addSound("click", "assets/click.ogg")
loader:addSound("hit",   "assets/hit.ogg")
loader:loadAll()
SEEnvironment:setLoader(loader, "common")

-- использование:
Sound:play("click")
Sound:play("hit")
Sound:play("hit")     -- оба звучат одновременно
```

**Имена** — это имена, под которыми звуки лежат в `resource:getSound` (а значит, в `SLoader`).

### 3. API

```lua
Sound:play(name)        -- проиграть один раз; клонирует source если все заняты
Sound:stop(name)        -- остановить все экземпляры этого звука
Sound:stopAll()         -- остановить всё
Sound:isPlaying(name)   -- true если хотя бы один экземпляр играет
```

Внутренне:

- `self.map[name]` — массив `love.audio.Source`.
- `play`: ищет первый `not s:isPlaying()`, если нет — делает `love.audio.newSource(resource:get(name))` и пушит в массив.
- `stop(name)`: вызывает `:stop()` на всех.
- `isPlaying(name)`: `any(s:isPlaying())`.

### 4. Типичные паттерны

#### Короткие эффекты (клики, удары)

Обычный `play` на каждое событие. Пул автоматически клонирует source если нужно.

```lua
function onHit()
  Sound:play("hit_metal")
end
```

#### Зацикленный звук (двигатель, ambient)

`SSoundManager` не поддерживает loop напрямую — он создан для «fire-and-forget». Для зацикленных source-ов используйте Love напрямую:

```lua
local engine = love.audio.newSource("assets/engine.ogg", "stream")
engine:setLooping(true)
engine:play()
```

`SSoundManager` хорош для SFX, не для музыки или ambient-треков.

#### Остановка одного канала

Если вам нужна возможность остановить **конкретный** экземпляр (например, «remember this one и потом выключи»), `SSoundManager` не поможет — он не возвращает ссылку на созданный source. Решение — завести параллельное хранилище:

```lua
local handles = {}

function playLooped(name)
  local data = resource:get(name)
  local src = love.audio.newSource(data)
  src:setLooping(true)
  src:play()
  handles[name] = src
  return src
end

function stopLooped(name)
  if handles[name] then
    handles[name]:stop()
    handles[name]:release()
    handles[name] = nil
  end
end
```

#### Громкость и pitch

`play(name)` не принимает громкость/pitch. Если надо варьировать:

```lua
-- прямой доступ к пулу
Sound:play("click")
local list = Sound.map["click"]
list[#list]:setVolume(0.7)
list[#list]:setPitch(0.8 + math.random() * 0.4)
```

Грубовато. В более сложных проектах — пишите свой wrapper или расширяйте `SSoundManager`.

---

## SShader

### 5. Что делает SShader

`SShader` — `SObject`-контейнер, который включает GLSL-шейдер **на время отрисовки своего поддерева**. Всё, что рисуется внутри — идёт через шейдер.

```lua
local shader = love.graphics.newShader("shaders/chromatic.glsl")

local wrap = SShader{
  shader = shader,
  children = {
    SSprite{ img = "bg" },
    SText{ font = "main", text = "Shaded" },
  }
}
```

### 6. Быстрый старт

```lua
-- shaders/grayscale.glsl
extern number strength;
vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 screen_coords) {
  vec4 px = Texel(tex, texcoord);
  float gray = dot(px.rgb, vec3(0.299, 0.587, 0.114));
  return vec4(mix(px.rgb, vec3(gray), strength), px.a) * color;
}
```

```lua
local gray = love.graphics.newShader("shaders/grayscale.glsl")

local wrap = SShader{
  shader = gray,
  children = {
    SSprite{ img = "bg" },
    SSprite{ img = "hero" },
  }
}

wrap:setShaderParam("strength", 0.8)
```

### 7. Параметры шейдера

```lua
wrap:setShaderParam("name", value)
wrap:setShaderParam("scale", 2.5)
wrap:setShaderParam("color", {1, 0.5, 0.2})
```

Параметры хранятся в `self.__shader_params[name] = {value}` (обёрнуты в таблицу, потому что потом `unpack` на `:send`). Флаг `needRefreshShaderParam = true` ставится, чтобы `refreshParams` вызвался перед следующей отрисовкой.

Если у шейдера несколько параметров, вызывайте `setShaderParam` для каждого. Под капотом всё обновляется разом:

```lua
function SShader:refreshParams()
  for k,v in pairs(self.__shader_params) do
    self.shader:send(k, unpack(v))
  end
end
```

### 8. Типичные сценарии

#### Гамма/тинт для всей сцены

Самый простой вариант. `SShader`-обёртка поверх корня сцены:

```lua
local tint = love.graphics.newShader([[
  extern vec3 tint;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    return Texel(tex, tc) * color * vec4(tint, 1.0);
  }
]])

scene = SShader{ shader = tint, children = { ... } }
scene:setShaderParam("tint", {1.2, 1.0, 0.8})  -- тёплый тон
```

#### Пост-эффект для канваса

Для более тяжёлых эффектов (blur, distortion) часто нужно сперва отрендерить в canvas, потом прогнать через шейдер с целой текстурой. Комбинация:

```lua
SShader{
  shader = blur,
  children = {
    SCanvas{
      canvasSize = {1920, 1080},
      children = { ... complex scene ... }
    }
  }
}
```

Сначала дети рисуются в canvas (эффективно сохраняется в текстуру), потом `SShader` прогоняет эту текстуру через шейдер. Подробнее про SCanvas — [SObject.md §4](./SObject.md#4-scanvas--рендер-в-canvas).

#### Анимированный параметр

```lua
function Scene:update(dt)
  self.elapsed = (self.elapsed or 0) + dt
  self.shaderWrap:setShaderParam("time", self.elapsed)
end
```

Каждый `setShaderParam` взводит `needRefreshShaderParam`; в следующем `__draw` параметры будут отправлены в шейдер.

---

## SAtlas

### 9. Что это и почему оно отдельно от SLoader

`SAtlas` — тонкий wrapper над Lua-атласами TexturePacker-а. `SLoader:addAtlas` внутри использует **ту же логику**, так что по факту `SAtlas` — это самостоятельный вариант для сценариев, где `SLoader` не нужен: например, у вас уже есть свой loader или вы хотите разово использовать атлас без сцены и `resource`.

Если у вас типичный SE3-pipeline (`SLoader` + `SEEnvironment`), `SAtlas` трогать не нужно.

### 10. API

```lua
local atlas = SAtlas.new("atlases.ui")      -- require-путь к .lua файлу атласа
atlas:load("assets/ui/")                     -- basePath — где лежат текстуры

local tex, quad, rect, _, offset = atlas:get("btn_play")
-- совместимо с resource:get()

local names = atlas:names()                  -- список всех спрайтов в атласе
```

Конструктор принимает только require-путь (модуль TexturePacker-а). `load(basePath)` делает:

1. `require` модуля — получает объект с `.sprites` и `.textures`.
2. Для каждой текстуры: `love.graphics.newImage(basePath .. filename)`.
3. Кладёт всё в мапу для `get(name)`.

`get` возвращает пятёрку, совместимую с `resource:get` — те же семантика и поля, что у `SLoader:get`.

`names()` возвращает список всех ключей `self._sprites` — удобно для debug-а, когда не знаешь, как TexturePacker переименовал файлы.

### Формат TexturePacker

SE3 поддерживает две формы:

- **Modern**: модуль возвращает функцию-фабрику (`return function(basePath) … end`).
- **Classic**: модуль устанавливает глобаль `create = function(basePath) … end` как side-effect.

Оба формата обрабатываются автоматически — `createAtlas = type(mod) == "function" and mod or create`.

Что возвращает `createAtlas(basePath)`:

```lua
{
  sprites = {
    ["sprite_name"] = {
      txt = "textureFilename.png",
      quad = love.graphics.Quad(...),
      rect = {x, y, w, h},
      offset = {offsetX, offsetY, origW, origH},   -- если есть trim
    },
    ...
  },
  textures = {"sheet_01.png", "sheet_02.png", ...},
}
```

Вы обычно не смотрите в это руками — TexturePacker генерирует Lua-файл автоматически, SE3 его парсит.

---

## См. также

- [SLoader.md](./SLoader.md) — стандартный путь загрузки атласов; используйте его вместо прямого `SAtlas`.
- [SObject.md](./SObject.md) — `SCanvas` в паре с `SShader` для пост-эффектов.
- [SSprite.md](./SSprite.md) — потребитель атласных спрайтов.
