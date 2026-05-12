# SText — Extended Guide

Текст в SE3. Файл `setext.lua`.

- **`SText`** — самостоятельный текстовый узел (наследник `SObject`).
- **`STextObject`** — миксин, добавляющий «дочерний текст» в другие классы (используется внутри `SSpriteButton`).

---

## Оглавление

1. [SText — быстрый старт](#1-stext--быстрый-старт)
2. [Шрифты: строки vs love.Font](#2-шрифты-строки-vs-lovefont)
3. [Выравнивание и перенос](#3-выравнивание-и-перенос)
4. [Auto-fit — вписать текст в бокс](#4-auto-fit--вписать-текст-в-бокс)
5. [Цвет](#5-цвет)
6. [Динамические размеры](#6-динамические-размеры)
7. [STextObject — миксин](#7-stextobject--миксин)
8. [Рекомендации и edge cases](#8-рекомендации-и-edge-cases)

---

## 1. SText — быстрый старт

```lua
local label = SText{
  font  = "main",
  text  = "Hello, SE3",
  x = 100, y = 50,
  align = "left",
  color = {1, 1, 0, 1},
}
```

Все поля опциональны (кроме `font` — без него рисовать нечего).

### Методы

```lua
t:setText(s)         -- обновить текст; пересчитает w/h и масштаб auto-fit
t:setFont(font)      -- поменять шрифт (строка или love.Font)
t:setColor({...})    -- цвет (компоненты в 0..1); также принимает HEX-строку: "#RRGGBB" / "#RRGGBBAA"
t:setMaxWidth(w)     -- ограничение по ширине (см. §3, §4)
t:setMaxHeight(h)    -- ограничение по высоте (в паре с autoFit; см. §4)
t:setWrap(bool)      -- явно включить/выключить перенос по словам
t:setAutoFit(bool)   -- включить масштабирование «вписать в бокс»
t:getTextScale()     -- текущий множитель auto-fit (1, если auto-fit выключен)
t:getFont()          -- вернуть love.Font (даже если self.font — строка)
```

---

## 2. Шрифты: строки vs love.Font

Поле `font` принимает оба варианта:

- **Строка** — имя, ищется через `resource:getFont(name)`. Это типичный случай, когда шрифт загружен через `SLoader`.
- **`love.Font`** — прямой love-объект. Полезно для дефолтного шрифта (`love.graphics.newFont()`) или временных отладочных надписей.

```lua
-- из ресурсов
SText{ font = "main", text = "Title" }

-- love.Font напрямую
SText{ font = love.graphics.newFont(16), text = "debug" }
```

Если имя не находится в `resource:getFont`, `getFont()` вернёт `nil`, и текст просто не отрисуется.

---

## 3. Выравнивание и перенос

### Без `maxWidth`

```lua
SText{ font = "main", text = "Line" }
```

`w` = ширина строки, `h` = `font:getHeight()`. Внутренне используется `love.graphics.printf` с шириной `1280` (чтобы не обрезать на мониторах меньше), но реальная ширина — ровно по тексту.

### С `maxWidth`

```lua
SText{
  font     = "main",
  text     = "Это длинный текст, который должен переноситься.",
  maxWidth = 300,
  align    = "center",
}
```

Включается перенос по словам:

- `w = maxWidth` (не реальная ширина контента — так проще центрировать).
- `h = numLines * font:getHeight() + numLines * font:getLineHeight()` (высота накапливается из строк).
- `align` — `"left"`, `"center"`, `"right"` или `"justify"` (любой, что поддерживает `love.graphics.printf`).

После изменения `maxWidth` или `text` размеры пересчитываются автоматически.

### Отключить перенос при заданном `maxWidth`

По умолчанию `maxWidth` включает `wrap = true`. Если нужен «однострочный бокс фиксированной ширины» (например, для `autoFit`, см. §4), передайте явно `wrap = false`:

```lua
SText{ font = "main", text = "Однострочный", maxWidth = 300, wrap = false }
```

Без `autoFit` такой текст просто будет рендериться в рамках 300px без переноса (то же, что `printf` с достаточно большим `limit`, но с честным `align` внутри 300).

---

## 4. Auto-fit — вписать текст в бокс

Флаг `autoFit = true` включает авто-масштабирование: текст уменьшается так, чтобы влезть в заданный бокс (`maxWidth` × `maxHeight`). Апскейла нет — если текст изначально меньше бокса, масштаб остаётся `1`.

Три типичных режима:

### 4.1. Однострочный fit (`wrap = false`)

Текст в одну строку; если не помещается в `maxWidth` — уменьшается.

```lua
SText{
  font     = "main",
  text     = "Player Name That Is Probably Too Long",
  maxWidth = 240,
  wrap     = false,
  autoFit  = true,
  align    = "center",
  pivot    = {0.5, 0.5},
}
```

- Если текст уже <= 240px — рисуется «как есть».
- Если шире — масштабируется по формуле `scale = maxWidth / textWidth`.
- `maxHeight` тоже учитывается: `scale = min(maxWidth/tw, maxHeight/th, 1)`.

### 4.2. Wrap + fit по высоте

Текст переносится по `maxWidth`, и если общая высота превышает `maxHeight` — всё вписывается масштабированием.

```lua
SText{
  font      = "main",
  text      = "Очень длинный параграф, который должен уместиться целиком в бокс.",
  maxWidth  = 400,
  maxHeight = 120,
  autoFit   = true,
  align     = "left",
}
```

Алгоритм — бинарный поиск по множителю `scale` ∈ (0, 1]:
- На меньшем `scale` глифы уже, но пропорционально растёт пре-скейл `limit`, так что `font:getWrap` даёт меньше строк.
- Поиск находит максимальный `scale`, при котором и каждая строка укладывается в `maxWidth`, и суммарная высота не превышает `maxHeight`.

Если одно слово шире `maxWidth` (неразрывный URL, моноширинный код) — `scale` опустится достаточно, чтобы слово влезло; `font:getWrap` не умеет ломать внутри слов.

### 4.3. Только `maxWidth` + `autoFit`

Аналог 4.1, но с переносом. Используется редко: ширина ограничена, высота — нет, скейлить некуда (если каждое слово короче `maxWidth` — скейл будет `1`). Полезно как защита от переполнения по одному длинному слову.

### Итоговая матрица

| `wrap` | `autoFit` | `maxWidth` | `maxHeight` | Что происходит |
|--------|-----------|------------|-------------|----------------|
| false  | false     | —          | —           | однострочный, натуральный размер |
| true (по умолчанию) | false | ✓        | —           | перенос по словам, натуральный размер (§3) |
| false  | true      | ✓          | (опц.)      | одна строка, скейл в бокс (§4.1) |
| true   | true      | ✓          | ✓           | перенос + скейл по высоте (§4.2) |

### Что `w`/`h` показывают при `autoFit`

Если задан `maxWidth` — `self.w = maxWidth`. Если задан `maxHeight` — `self.h = maxHeight`. Это «бокс», который объявил пользователь; он удобен для пивот-центрирования, даже если реальный отрендеренный текст после скейла занимает меньше. Текущий множитель можно прочитать через `t:getTextScale()`.

### В scene-манифесте

Все флаги — простые props, поддерживаются декларативно:

```lua
{ type = "SText",
  font      = "main",
  text      = "$playerName",     -- реактивный bind; при смене имени пересчитает скейл
  maxWidth  = 240,
  maxHeight = 48,
  autoFit   = true,
  wrap      = false,
  align     = "center",
  pivot     = {0.5, 0.5},
}
```

---

## 5. Цвет

Формат — 0..1 (как в Love2D 11+). Также принимается HEX-строка (`"#RRGGBB"` / `"#RRGGBBAA"`):

```lua
label:setColor({1, 0, 0, 1})
label:setColor("#ff0000")
-- сброс на «белый»:
label.color = nil     -- или label:setColor(nil) — тоже работает
```

В `draw` цвет ставится перед `love.graphics.printf` и возвращается в белый сразу после — так что одна надпись не «красит» остальную отрисовку.

---

## 6. Динамические размеры

Типичная ошибка — прочитать `self.w` сразу после construction и получить 0. Это потому, что `w/h` вычисляются в `setText` и `setFont` — если оба переданы в props, к моменту `SObject.init` размеры уже есть. Но если шрифт ставится позже (`label:setFont(...)` после конструкции), повторный `setText` обновит `w/h`.

```lua
local label = SText{ text = "Hello" }     -- без font → w = 0
label:setFont("main")                       -- font есть, но w не пересчитан
label:setText(label.text)                   -- теперь w = корректное значение
```

Альтернатива — передать всё сразу:

```lua
SText{ font = "main", text = "Hello" }
```

---

## 7. STextObject — миксин

`STextObject` — миксин, добавляющий «дочерний текст» на любой класс. Используется внутри `SSpriteButton` и `SAnimationSprite`.

Что делает:

- `setFont(font)` — создаёт первый раз дочерний `SText` (в `self.__text_object`) с `align = "center"` и `maxWidth = self.w`.
- `setText(text)` — обновляет этот дочерний текст. Если `__text_object` ещё не создан, просто запоминает значение.
- `setTextColor(color)` — цвет дочернего текста (не самого объекта).
- `getTextObject()` — доступ к внутреннему `SText` для тонкой настройки.

```lua
local LabeledIcon = Class{ __includes = { SSprite, STextObject },
  init = function(self, p)
    SSprite.init(self, p)
    if p.font then self:setFont(p.font) end
    if p.text then self:setText(p.text) end
  end
}
```

```lua
LabeledIcon{
  img  = "icon_star",
  font = "small",
  text = "12",
}
```

Дочерний текст автоматически центрирован и ограничен по ширине родителя.

---

## 8. Рекомендации и edge cases

### `printf` с `maxWidth = 1280` по умолчанию

Если вы не зададите `maxWidth`, внутри используется ширина `1280` как «достаточно большая». На экранах шире — текст может обрезаться. Если у вас ultrawide-разрешение — передавайте `maxWidth` явно, даже если не нужен перенос.

### `align = "center"` без `maxWidth`

Без `maxWidth` alignment работает в рамках ширины 1280 от `x, y`. Если хотите именно «центрированный заголовок», задайте:

```lua
SText{
  font     = "main",
  text     = "TITLE",
  maxWidth = 600,
  align    = "center",
  pivot    = {0.5, 0.5},
}
```

`pivot = {0.5, 0.5}` сделает `x, y` точкой центра, `align = "center"` — внутри `maxWidth`.

### Изменение шрифта после construction

```lua
label:setFont(newFont)
label:setText(label.text)    -- пересчитать w/h
```

`setFont` сам не пересчитывает размеры — только `setText` это делает. После смены шрифта нужен повторный `setText` (или `setMaxWidth` — он тоже зовёт `setText`).

### Проверка наличия шрифта

`resource:getFont(name)` возвращает `nil`, если такого шрифта нет в загрузчике. В draw `SText` безопасно выходит при `font == nil` — просто ничего не рисует. Никаких ошибок. Это удобно для «прелоадер показал надпись, хотя шрифт ещё не загрузился» — заклинания типа «если нет, то белым прямоугольником» писать не нужно.

### Юникод и emoji

Love2D поддерживает UTF-8 в `love.graphics.printf`, но шрифт должен содержать нужные глифы. Если используете emoji — добавляйте fallback-шрифт с ними:

```lua
local main = love.graphics.newFont("assets/main.ttf", 32)
local emoji = love.graphics.newFont("assets/emoji.ttf", 32)
main:setFallbacks(emoji)
```

Это особенность Love, не SE3 — но стоит помнить.

---

## См. также

- [SObject.md](./SObject.md) — базовый класс, пивоты, трансформы.
- [SButton.md](./SButton.md) — `SSpriteButton` использует `STextObject` миксин для надписей.
- [SLoader.md](./SLoader.md) — как загрузить шрифты и сделать их доступными через `resource:getFont`.
