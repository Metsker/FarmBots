# Inheritance & Composite Objects — Extended Guide

Как расширять классы SE3 и как собирать составные объекты из нескольких спрайтов, инкапсулированных в один `SObject`. Это два разных подхода с разными границами применения — в гайде обсуждается оба.

---

## Оглавление

1. [Два подхода: наследование vs композиция](#1-два-подхода-наследование-vs-композиция)
2. [Наследование — базовый шаблон](#2-наследование--базовый-шаблон)
3. [Расширяем `SObject` — свой визуальный узел](#3-расширяем-sobject--свой-визуальный-узел)
4. [Расширяем `SSprite` — спрайт с дополнительной логикой](#4-расширяем-ssprite--спрайт-с-дополнительной-логикой)
5. [Расширяем `SGroup` — свой контейнер](#5-расширяем-sgroup--свой-контейнер)
6. [Несколько миксинов (`__includes = {...}`)](#6-несколько-миксинов-__includes--)
7. [Расширяем `SAnimatedObject` — state machine с кастомной логикой](#7-расширяем-sanimatedobject--state-machine-с-кастомной-логикой)
8. [Композитные объекты](#8-композитные-объекты)
9. [Паттерн: два спрайта в одном SObject](#9-паттерн-два-спрайта-в-одном-sobject)
10. [Пример: health bar (фон + заливка)](#10-пример-health-bar-фон--заливка)
11. [Пример: иконка с подписью](#11-пример-иконка-с-подписью)
12. [Пример: карточка героя (портрет + рамка + имя + HP)](#12-пример-карточка-героя-портрет--рамка--имя--hp)
13. [Пример: анимированный персонаж (тело + глаза как отдельные спрайты)](#13-пример-анимированный-персонаж-тело--глаза-как-отдельные-спрайты)
14. [Регистрация кастомных классов в `SESceneLoader`](#14-регистрация-кастомных-классов-в-sesceneloader)
15. [Рекомендации и edge cases](#15-рекомендации-и-edge-cases)

---

## 1. Два подхода: наследование vs композиция

В SE3 почти любой кастомный узел можно сделать **либо** наследованием от `SObject`/`SSprite`/..., **либо** композицией (группа с вложенными детьми и методами на обёртке). Практические границы:

| Ситуация | Что брать |
|----------|-----------|
| Новый рендер-примитив (круг, gradient, mesh) | наследование от `SObject`, переопределить `draw` |
| Спрайт + логика (health_bar, stat_label) | наследование от `SSprite` — у вас уже есть картинка |
| Несколько спрайтов + методы, работающие как один узел | композиция: класс = `SObject`/`SGroup`, дети — `:add`-нутся в `init` |
| Сложный state machine (персонаж с ходьбой) | наследование от `SAnimatedObject` |
| Переиспользуемое поддерево без своих методов | prefab в манифесте (см. [SESceneLoader §6](./SESceneLoader.md#6-prefab-ы-через-include)) |

**Главный критерий:** если у объекта есть внутренние методы (`setHealth`, `flash`, `toggle`), делайте его классом — наследованием или композицией с `__includes`. Если нет внутренних методов и это просто «шаблон поддерева» — делайте prefab.

---

## 2. Наследование — базовый шаблон

Движок использует `hump.class` (через глобаль `Class`). Базовый шаблон:

```lua
local MyClass = Class{ __includes = SObject,
  init = function(self, p)
    SObject.init(self, p)       -- ОБЯЗАТЕЛЬНО вызвать родителя первым
    -- Теперь читаем СВОИ поля из p:
    self.myField = p.myField or "default"
  end
}

function MyClass:myMethod()
  -- ...
end

return MyClass
```

Три обязательных правила:

1. **Родитель первый.** `SObject.init(self, p)` — до всего остального. Он читает `x/y/z/r/sx/sy/w/h/pivot/color/alpha/off/eventoff/hidden/children` и добавляет детей из массивной части `p` через `self:add`.
2. **Читайте свои поля из `p`.** SE3-конвенция — единая props-таблица. Не изобретайте позиционные аргументы.
3. **Не трогайте `self.childs` напрямую в `init`.** Используйте `self:add(child)` — он ставит `parent` и вызывает `zrefresh`.

---

## 3. Расширяем `SObject` — свой визуальный узел

Минимум для нового визуального узла — `draw(x, y, r, sx, sy, tx, ty)`.

```lua
local Ring = Class{ __includes = SObject,
  init = function(self, p)
    SObject.init(self, p)
    self.radius   = p.radius   or 50
    self.width    = p.width    or 4
    self.segments = p.segments or 32
    -- Логический размер — важен для пивота и inBox
    self.w = self.radius * 2
    self.h = self.radius * 2
  end
}

function Ring:draw(x, y, r, sx, sy, tx, ty)
  if self.hidden then return end
  if self.color then love.graphics.setColor(self.color) end
  local prevWidth = love.graphics.getLineWidth()
  love.graphics.setLineWidth(self.width)
  love.graphics.circle("line", x, y, self.radius * sx, self.segments)
  love.graphics.setLineWidth(prevWidth)
  if self.color then love.graphics.setColor(1, 1, 1, 1) end
end
```

Использование:

```lua
Ring{ x = 100, y = 100, radius = 40, width = 6, color = {1, 0.78, 0, 1} }
```

**Важные детали:**

- `x, y` — уже содержат трансформ родителей. Просто передавайте их в `love.graphics.*`.
- `r, sx, sy` — итоговые поворот и масштаб. Если рендерите через `love.graphics.draw(img, x, y, r, sx, sy, tx, ty)`, Love сам их применит. Если рисуете примитивом (circle, rectangle) — умножайте вручную.
- `tx, ty` — смещения от пивота (уже правильно посчитаны). Передавайте как 7-й и 8-й аргументы в `love.graphics.draw`.
- Возврат цвета в белый в конце — **обязательный ритуал**, иначе следующие объекты будут краситься вашим цветом.

### Участие в z-сортировке

Дефолтный путь отрисовки `__draw` работает сразу. Чтобы класс **также** корректно рисовался внутри `SGroup` с z-сортировкой, ничего не надо делать — `SObject` уже реализует `cacheCoords` и `drawCached`. Единственное — не переопределяйте `__draw`, вы и так всё получите бесплатно.

---

## 4. Расширяем `SSprite` — спрайт с дополнительной логикой

Если у вас уже есть картинка, и хочется добавить поля + методы — наследуйтесь от `SSprite`:

```lua
local HealthIcon = Class{ __includes = SSprite,
  init = function(self, p)
    SSprite.init(self, p)
    self.value    = p.value or 100
    self.maxValue = p.maxValue or 100
    self:_updateColor()
  end
}

function HealthIcon:setValue(v)
  self.value = math.max(0, math.min(v, self.maxValue))
  self:_updateColor()
  return self
end

function HealthIcon:_updateColor()
  local frac = self.value / self.maxValue
  if frac > 0.5 then
    self.color = {0.39, 1, 0.39, 1}      -- зелёный
  elseif frac > 0.2 then
    self.color = {1, 1, 0.39, 1}         -- жёлтый
  else
    self.color = {1, 0.39, 0.39, 1}      -- красный
  end
end
```

Использование:

```lua
local hp = HealthIcon{ img = "hp_heart", value = 75, maxValue = 100 }
hp:setValue(30)   -- перекрашивается в жёлтый автоматически
```

Принципы:

- `SSprite.init(self, p)` сам вызовет `SObject.init(self, p)` внутри — двойной вызов не нужен.
- Все `p.x/y/z/...` обрабатываются ровнее — вы читаете **только** свои поля.
- Отрисовка наследуется бесплатно: `SSprite:draw` читает `self.color`, так что изменение `self.color` из методов сразу видно.

---

## 5. Расширяем `SGroup` — свой контейнер

Когда нужен контейнер с собственной логикой (например, «ряд иконок, автоматически раскладывающий детей»):

```lua
local IconRow = Class{ __includes = SGroup,
  init = function(self, p)
    SGroup.init(self, p)
    self.spacing = p.spacing or 32
    self:_layout()
  end
}

function IconRow:add(child)
  local result = SObject.add(self, child)       -- важно: SObject, а не SGroup (SGroup:add не переопределён, но будьте явны)
  self:_layout()
  return result
end

function IconRow:_layout()
  for i, c in ipairs(self.childs) do
    c.x = (i - 1) * self.spacing
  end
end
```

Использование:

```lua
IconRow{ spacing = 40,
  SSprite{ img = "icon_gold"   },
  SSprite{ img = "icon_gem"    },
  SSprite{ img = "icon_ticket" },
}
```

Автораскладка сработает и на построении (дети из `p[]` прогоняются через `:add` → `_layout`), и при динамическом `row:add(SSprite{...})`.

### Важное про `SGroup` — `self.zchilds = {}` до `SGroup.init`

Если в `SGroup`-наследнике вы переопределяете `init` и создаёте какие-то поля **до** вызова `SGroup.init`, помните, что `SGroup.init` сам уже ставит `zchilds = {}` перед `SObject.init`. Но если ваш `init` ставит какие-то поля, которые должны быть доступны в `add` (вызывается для детей из `p[]`), — ставьте до `SGroup.init`. Пример выше с `self.spacing` работает потому, что `_layout` вызывается **после** `SGroup.init`, а дети к тому моменту уже добавлены (но ещё не разложены).

Если нужна раскладка по месту при добавлении — перенесите `self.spacing` *до* `SGroup.init`:

```lua
init = function(self, p)
  self.spacing = p.spacing or 32   -- до
  SGroup.init(self, p)              -- :add будет вызываться для детей из p[]
  self:_layout()
end
```

---

## 6. Несколько миксинов (`__includes = {...}`)

Миксин в hump.class — это класс, методы которого «прилипают» к вашему. Несколько миксинов — массив в `__includes`.

Типичная комбинация — своя кнопка:

```lua
local CircleButton = Class{
  __includes = { SObject, SButtonEngine, SMouseObject, SKeyboardObject },
  init = function(self, p)
    SObject.init(self, p)
    self.radius = p.radius or 50
    self.event  = p.event
    self.keys   = p.keys or {}
    self:state("release")
  end
}

function CircleButton:state(s)  self.color = (s == "over") and {1,1,0,1} or {0.78,0.78,0.78,1} end
function CircleButton:inBox(x, y) return x*x + y*y <= self.radius*self.radius end
function CircleButton:draw(x, y, r, sx, sy)
  love.graphics.setColor(self.color)
  love.graphics.circle("fill", x, y, self.radius * sx)
  love.graphics.setColor(1,1,1,1)
end
```

### Порядок миксинов имеет значение

hump.class применяет миксины **слева направо**. Первый в списке становится первым слоем; последний — самым верхним. При конфликте методов побеждает последний из `__includes`, но если ваш класс сам определяет метод, он всегда побеждает.

Конкретно:

- `SObject` обычно первый (базовый).
- `SButtonEngine`, `SMouseObject`, `SKeyboardObject` идут как «слои поведения».
- Свои методы в классе — всегда имеют приоритет.

Проверить конфликт легко: запустите проект, и если один метод поверх другого — разносите по разным именам или явно вызывайте нужный через `ClassName.method(self, ...)`.

### Вызов метода миксина явно

```lua
function MyButton:click()
  SButtonEngine.click(self)     -- если надо — вызвать родительский click
  -- дальше своя логика
end
```

---

## 7. Расширяем `SAnimatedObject` — state machine с кастомной логикой

Когда у вас анимированный персонаж со сложным поведением — наследуйтесь от `SAnimatedObject`:

```lua
local Hero = Class{ __includes = SAnimatedObject,
  init = function(self, p)
    -- Дефолтные состояния передаём через p.states; init родителя их зарегистрирует
    p.states = p.states or {
      idle   = { frames = {"hero_idle_%02d",   0.15, 1, 4}, loop = true },
      walk   = { frames = {"hero_walk_%02d",   0.1,  1, 6}, loop = true },
      attack = { frames = {"hero_attack_%02d", 0.08, 1, 5}, loop = false, next = "idle" },
      hit    = { frames = "hero_hit", loop = false, next = "idle",
                 scripts = { {"shake", 0.3, {dx=8, dy=4}} }, stopScriptAtEnd = true },
    }
    p.defaultState = p.defaultState or "idle"
    SAnimatedObject.init(self, p)

    self.hp       = p.hp or 100
    self.maxHp    = p.maxHp or 100
  end
}

function Hero:takeDamage(amount)
  self.hp = math.max(0, self.hp - amount)
  if self.hp == 0 then
    self:setState("death")
  else
    self:setState("hit")
  end
end

function Hero:attack()
  if self:getState() == "attack" then return end    -- не прерывать текущую
  self:setState("attack")
end
```

Использование в сцене:

```lua
local hero = Hero{ x = 400, y = 500, hp = 100 }
hero:attack()
hero:takeDamage(15)
```

### Добавление состояний на лету из наследника

```lua
init = function(self, p)
  p.states = p.states or {}
  -- добавляем состояние только если не переопределено снаружи:
  p.states.celebrate = p.states.celebrate
    or { frames = {"hero_win_%02d", 0.1, 1, 8}, loop = true }
  SAnimatedObject.init(self, p)
end
```

Это позволяет внешнему коду (или манифесту) переопределить конкретное состояние, оставив остальные по умолчанию.

---

## 8. Композитные объекты

«Композит» — класс, внутри которого живёт несколько вложенных `SObject`-ов. Сам класс — обычно `SObject` или `SGroup`. Дети добавляются в `init` через `:add` и сохраняются в полях класса для последующего обращения из методов.

Разница с наследованием:

- **Наследник `SSprite`** = «это один спрайт + чуть больше».
- **Композит** = «это несколько элементов, ведущих себя как один объект снаружи».

У композита обычно есть публичные методы, которые манипулируют внутренними детьми (меняют их свойства, скрывают/показывают, тинтят).

### Шаблон

```lua
local MyComposite = Class{ __includes = SObject,
  init = function(self, p)
    SObject.init(self, p)
    -- Создаём детей и сохраняем их в поля:
    self._bg    = self:add(SSprite{ img = p.bgImg or "default_bg" })
    self._icon  = self:add(SSprite{ img = p.iconImg })
    self._label = self:add(SText{ font = p.font, text = p.text or "" })
    -- Задаём их начальное положение/размер:
    self._bg.pivot  = {0.5, 0.5}
    self._icon.x, self._icon.y = -40, 0
    self._label.x, self._label.y = 20, 0
  end
}

function MyComposite:setText(t)   self._label:setText(t)    end
function MyComposite:setIcon(img) self._icon:setImg(img)    end
function MyComposite:flash()
  self._bg.color = {1, 1, 0.39, 1}
  -- сбросить через 0.2 сек — см. ниже про таймеры
end
```

Ключевая идея: **ссылки на детей хранятся в полях с префиксом `_`** — это конвенция «приватные внутренние дети». Внешний код общается с композитом через его методы, а не лезет в `_bg`/`_icon`.

---

## 9. Паттерн: два спрайта в одном SObject

Самый простой композитный случай — узел из двух спрайтов. Например, «значок с фоном».

```lua
local BadgeIcon = Class{ __includes = SObject,
  init = function(self, p)
    SObject.init(self, p)
    self._bg    = self:add(SSprite{ img = p.bg or "badge_bg" })
    self._front = self:add(SSprite{ img = p.front })
    -- Размер берём от фона, чтобы inBox / pivot работали правильно:
    self.w, self.h = self._bg.w, self._bg.h
  end
}

function BadgeIcon:setFrontImg(img) self._front:setImg(img); return self end
function BadgeIcon:setBgColor(c)    self._bg.color = c;       return self end
function BadgeIcon:setHighlighted(on)
  self._bg.color = on and {1, 1, 0.39, 1} or nil
end
```

Использование:

```lua
local b = BadgeIcon{ x = 100, y = 100, bg = "badge_gold", front = "icon_star" }
b:setHighlighted(true)
b:setFrontImg("icon_skull")
```

### Почему `self.w/h` важен

Без `self.w, self.h = bg.w, bg.h`:
- `pivot = {0.5, 0.5}` посчитает пустой размер (0×0) и не сместит отрисовку.
- `inBox` (если наш композит — интерактивный) всегда вернёт false.

Размер должен отражать «логический» размер композита — обычно размер главного фонового элемента.

### Альтернатива: композит как `SGroup`

Если внутри композита есть z-сортировка (например, иконки, которые иногда перекрываются по-разному), используйте `SGroup`:

```lua
local Badge = Class{ __includes = SGroup,
  init = function(self, p)
    SGroup.init(self, p)
    self._bg    = self:add(SSprite{ img = p.bg,    z = 0 })
    self._front = self:add(SSprite{ img = p.front, z = 1 })
    self.w, self.h = self._bg.w, self._bg.h
  end
}
```

Но если z-порядок фиксирован (фон всегда под, иконка всегда над) и не меняется — `SObject` достаточно; дети рисуются в порядке добавления.

---

## 10. Пример: health bar (фон + заливка)

Двухслойная полоса здоровья с анимированной заливкой:

```lua
local HealthBar = Class{ __includes = SObject,
  init = function(self, p)
    SObject.init(self, p)
    self.max   = p.max   or 100
    self.value = p.value or self.max
    local w    = p.barWidth  or 200
    local h    = p.barHeight or 12

    self._bg = self:add(SStretchedSprite{
      img = p.bgImg or "bar_bg",
      w   = w, h = h,
    })

    self._fill = self:add(SStretchedSprite{
      img   = p.fillImg or "bar_fill",
      w     = w, h = h,
      pivot = {0, 0.5},                        -- растягиваем от левого края
      x     = -w * 0.5,                        -- левый край полосы
    })

    self.w, self.h = w, h
    self:_updateFill()
  end
}

function HealthBar:setValue(v)
  self.value = math.max(0, math.min(v, self.max))
  self:_updateFill()
  return self
end

function HealthBar:setMax(m)
  self.max = m
  self:_updateFill()
  return self
end

function HealthBar:_updateFill()
  local frac = self.max > 0 and (self.value / self.max) or 0
  self._fill.sx = frac
  -- Подкрасить при низком HP:
  if frac < 0.25 then
    self._fill.color = {1, 0.31, 0.31, 1}
  elseif frac < 0.5 then
    self._fill.color = {1, 0.78, 0.31, 1}
  else
    self._fill.color = nil
  end
end

function HealthBar:flash()
  self._bg.color = {1, 1, 1, 1}
  -- чтобы сбросить — нужен таймер; см. §12 или используйте SAnimatedObject-скрипты
end
```

Использование:

```lua
local bar = HealthBar{ x = 100, y = 50, max = 100, value = 100 }
bar:setValue(75)    -- заливка до 75%
bar:setValue(20)    -- подкрашивается красным
```

Ключевые приёмы:

- **Фон и заливка как `SStretchedSprite`** — чтобы можно было менять `sx` заливки, не затрагивая логическую ширину полосы.
- **Pivot на заливке `{0, 0.5}`** и сдвиг `x = -w*0.5` — растягивание идёт от левого края.
- **`self.w, self.h` = размеры полосы** — наследник корректно работает с пивотом родителя.

---

## 11. Пример: иконка с подписью

Классический UI-элемент для ресурса (золото, жизни, ключи):

```lua
local ResourceLabel = Class{ __includes = SObject,
  init = function(self, p)
    SObject.init(self, p)
    self._icon = self:add(SSprite{
      img   = p.icon,
      x     = -30,
      pivot = {0.5, 0.5},
    })
    self._text = self:add(SText{
      font  = p.font or "main",
      text  = tostring(p.value or 0),
      x     = 0,
      pivot = {0, 0.5},
    })
    self._value = p.value or 0
  end
}

function ResourceLabel:setValue(v)
  self._value = v
  self._text:setText(tostring(v))
  return self
end

function ResourceLabel:getValue() return self._value end

function ResourceLabel:bump()
  -- небольшой scale-punch когда значение изменилось
  self._icon.sx, self._icon.sy = 1.3, 1.3
  -- для плавного сброса — см. про SAnimatedObject-scripts или love.timer
end
```

Использование:

```lua
local gold = ResourceLabel{ x = 40, y = 40, icon = "icon_gold", value = 100 }
gold:setValue(gold:getValue() + 50)
gold:bump()
```

### Декларативно через `SESceneLoader`

Если зарегистрировать `ResourceLabel` в лоадере:

```lua
loader:register("ResourceLabel", ResourceLabel)
```

можно в манифесте:

```lua
scene = {
  type = "SGroup", children = {
    { type = "ResourceLabel", x = 40,  y = 40, icon = "icon_gold",  value = 100, id = "gold" },
    { type = "ResourceLabel", x = 200, y = 40, icon = "icon_gem",   value = 5,   id = "gems" },
    { type = "ResourceLabel", x = 360, y = 40, icon = "icon_ticket", value = 12, id = "tickets" },
  }
}
```

Про регистрацию подробнее — см. [§14](#14-регистрация-кастомных-классов-в-sesceneloader).

---

## 12. Пример: карточка героя (портрет + рамка + имя + HP)

Композит из 4 элементов, один из которых сам композит (`HealthBar` из [§10](#10-пример-health-bar-фон--заливка)):

```lua
local HeroCard = Class{ __includes = SObject,
  init = function(self, p)
    SObject.init(self, p)

    -- Рамка — сзади
    self._frame = self:add(SSprite{
      img   = p.frameImg or "card_frame",
      pivot = {0.5, 0.5},
    })

    -- Портрет — в центре рамки
    self._portrait = self:add(SSprite{
      img   = p.portraitImg,
      pivot = {0.5, 0.5},
      y     = -20,
    })

    -- Имя — под портретом
    self._name = self:add(SText{
      font     = p.font or "main",
      text     = p.name or "Hero",
      y        = 60,
      pivot    = {0.5, 0},
      align    = "center",
      maxWidth = self._frame.w,
    })

    -- Полоса HP — внизу
    self._hp = self:add(HealthBar{
      y         = 110,
      max       = p.maxHp or 100,
      value     = p.hp or p.maxHp or 100,
      barWidth  = self._frame.w - 20,
      barHeight = 10,
    })

    self.w, self.h = self._frame.w, self._frame.h
  end
}

function HeroCard:setName(n)       self._name:setText(n)         end
function HeroCard:setHP(v)          self._hp:setValue(v)           end
function HeroCard:setMaxHP(v)       self._hp:setMax(v)             end
function HeroCard:getHP()           return self._hp.value          end
function HeroCard:setPortrait(img) self._portrait:setImg(img)     end

function HeroCard:highlight(on)
  self._frame.color = on and {1, 0.9, 0.51, 1} or nil
end
```

Использование:

```lua
local card = HeroCard{
  x = 200, y = 300,
  portraitImg = "portrait_warrior",
  name        = "Warrior",
  maxHp       = 150,
}

card:setHP(80)
card:highlight(true)
```

### Ценность такого композита

- Внешний код делает **один** `HeroCard{...}` с понятными полями, не собирает 4 узла руками.
- Взаимные позиции детей (портрет, имя, HP) — внутренняя деталь композита. Измените `y` портрета внутри класса — все карточки в игре обновятся.
- Методы `setHP`/`setName` имеют семантический смысл, не привязаны к конкретным внутренним узлам.

---

## 13. Пример: анимированный персонаж (тело + глаза как отдельные спрайты)

Часто в пиксель-арт-играх «тело» и «глаза» — отдельные спрайты, чтобы глаза могли моргать и смотреть независимо.

```lua
local Character = Class{ __includes = SObject,
  init = function(self, p)
    SObject.init(self, p)

    -- Тело — state machine
    self._body = self:add(SAnimatedObject{
      states = {
        idle = { frames = {"body_idle_%02d", 0.2, 1, 4}, loop = true },
        walk = { frames = {"body_walk_%02d", 0.1, 1, 6}, loop = true },
      },
      defaultState = "idle",
    })

    -- Глаза — отдельный SAnimationSprite; может мигать независимо
    self._eyes = self:add(SAnimationSprite{
      sequence = {"eyes_open"},
      y        = -30,                  -- смещение от центра тела
    })

    self._blinkTimer = 0
    self._blinkNext  = love.math.random() * 3 + 2

    self.w, self.h = self._body.w, self._body.h
  end
}

function Character:update(dt)
  -- Мигание глаз раз в 2-5 секунд
  self._blinkTimer = self._blinkTimer + dt
  if self._blinkTimer >= self._blinkNext then
    self._blinkTimer = 0
    self._blinkNext  = love.math.random() * 3 + 2
    self:_blink()
  end
end

function Character:_blink()
  self._eyes:setImg("eyes_closed")
  -- Через 0.1 сек — открыть. Тут можно использовать SAnimatedObject-скрипт,
  -- или — простейше — через love.timer:
  -- (упрощение: установить состояние, через тик сбросить.
  --  В реальном проекте — через tween-script или scheduler)
end

function Character:setState(name) self._body:setState(name) end
function Character:getState()     return self._body:getState() end

function Character:lookAt(dx, dy)
  -- Глаза смотрят в сторону цели — ограничим смещение в пикселях
  local maxOffset = 2
  local mag = math.sqrt(dx * dx + dy * dy)
  if mag < 1 then
    self._eyes.x, self._eyes.y = 0, -30
    return
  end
  self._eyes.x = (dx / mag) * maxOffset
  self._eyes.y = -30 + (dy / mag) * maxOffset
end
```

Обратите внимание:

- `update(dt)` на композите **автоматически** вызывается движком (стандартная пропагация `__update`). `SAnimatedObject` внутри `_body` тоже обновляется сам — вам не надо вызывать его `update` вручную.
- Композит переопределяет только **свою** логику (мигание), а анимация тела идёт через встроенный state machine.
- `lookAt(dx, dy)` демонстрирует, как публичный метод композита манипулирует одним конкретным внутренним узлом.

Для реалистичного «мигания» лучше не использовать `love.timer.schedule` (которого в Love нет), а встроить вторую sequence-анимацию в `_eyes` или использовать `SAnimatedObject` для глаз со скриптом `{"wait", 0.1}` и возвратом в `idle`.

---

## 14. Регистрация кастомных классов в `SESceneLoader`

Если вы используете `SESceneLoader` для декларативных сцен, ваши кастомные классы надо **зарегистрировать** — иначе `type = "HeroCard"` упадёт с ошибкой «unknown type».

### Способ 1: через `:register` на конкретном лоадере

```lua
local HeroCard   = require("game.widgets.hero_card")
local HealthBar  = require("game.widgets.health_bar")

local loader = SESceneLoader.new()
loader:register("HeroCard",  HeroCard)
loader:register("HealthBar", HealthBar)

local scene = loader:load("scenes.main")
```

### Способ 2: через `components` в манифесте (рекомендуется)

Обернули классы в модуль, экспортирующий `{ name, class }`:

```lua
-- game/widgets/hero_card.lua
local HeroCard = Class{ __includes = SObject, init = ... }
function HeroCard:setHP(v) ... end
return { name = "HeroCard", class = HeroCard }
```

или сразу несколько:

```lua
-- game/widgets/all.lua
return { components = {
  HeroCard  = HeroCard,
  HealthBar = HealthBar,
  BadgeIcon = BadgeIcon,
}}
```

В манифесте сцены:

```lua
-- scenes/main.lua
return {
  components = { "game.widgets.all" },
  scene = {
    type = "SGroup", children = {
      { type = "HeroCard", x = 100, y = 200, portraitImg = "portrait_warrior", name = "Knight" },
    },
  },
}
```

Регистрация через `components` удобнее, потому что манифест самодостаточен: открывая его, видишь, какие классы используются и откуда они.

### Чтобы класс работал как префаб (prefab)

Если это **поддерево без методов** (просто «шаблон + params»), используйте `include` вместо класса. См. [SESceneLoader §6](./SESceneLoader.md#6-prefab-ы-через-include).

Разница — в одной строчке:

| Класс (`components`) | Префаб (`include`) |
|----------------------|---------------------|
| Может держать состояние между кадрами | Развёртывается один раз при сборке |
| Имеет публичные методы (`setHP`, `flash`) | После сборки — обычные `SObject`-узлы |
| Реагирует на `update(dt)` | Нет |
| `type = "HeroCard"` | `include = "prefabs.hero_card"` |

Если ваша «карточка героя» не имеет методов и не реагирует на события — делайте её префабом. Если есть `setHP` / `flash` / `lookAt` — делайте классом.

---

## 15. Рекомендации и edge cases

### Не забывайте `self.w, self.h`

Ошибка уровня «почему ничего не работает» — забыть установить `w/h` у композита.

Последствия:
- `pivot = {0.5, 0.5}` не смещает узел (w*pivot = 0).
- `inBox` на миксине `SMouseObject` всегда вернёт false.
- `getBoundingBox` вернёт нулевой бокс, что может ломать отладочные оверлеи.

Правило: в конце `init`-а композита — `self.w, self.h = <размер-главного-элемента>`. Обычно это размер фонового спрайта.

### Не переопределяйте `__draw`, если только не знаете зачем

`__draw` отвечает за трансформы и рекурсию по детям. Если переопределили — обеспечьте и то, и другое. Обычно вам нужен `draw`, а не `__draw`.

Исключение — `SCanvas` и `SShader`, которые как раз меняют `__draw`, чтобы обернуть отрисовку детей в canvas/шейдер.

### Порядок детей = порядок отрисовки (внутри одного z)

В `SObject` дети рисуются в том порядке, в котором добавлены. Поэтому в `init`:

```lua
self._bg    = self:add(SSprite{ img = "bg" })       -- рисуется первым (под)
self._front = self:add(SSprite{ img = "front" })    -- рисуется вторым (поверх)
```

Если надо динамически менять порядок — используйте `z` и `SGroup`.

### Не создавайте детей после `init` без `:add`

```lua
self._extra = SSprite{ img = "foo" }   -- НЕПРАВИЛЬНО
```

Такой спрайт не попадёт в `self.childs`, не будет нарисован, не получит событий. Используйте:

```lua
self._extra = self:add(SSprite{ img = "foo" })
```

### Не пишите в `self.childs` напрямую

```lua
table.insert(self.childs, child)   -- НЕ ДЕЛАТЬ
```

`:add` делает несколько вещей: пушит в `childs`, ставит `child.parent = self`, вызывает `zrefresh` (который в `SGroup` пересортирует `zchilds`). Прямое добавление в массив — пропустит эти шаги.

### Удаление ребёнка

В SE3 нет встроенного `removeChild`. Стандартный паттерн — `off = true`:

```lua
self._extra.off = true   -- перестал рисоваться и получать события
self._extra.off = false  -- снова живой
```

Если надо удалить физически (например, для GC большого поддерева), пишите хелпер:

```lua
function SObject:removeChild(child)
  for i, c in ipairs(self.childs) do
    if c == child then table.remove(self.childs, i); break end
  end
  child.parent = nil
  -- если вы в SGroup — также очистите zchilds
  if self.zchilds then
    for i, c in ipairs(self.zchilds) do
      if c == child then table.remove(self.zchilds, i); break end
    end
  end
end
```

### Частая ошибка: забыть родительский `init`

```lua
local Broken = Class{ __includes = SObject,
  init = function(self, p)
    self.myField = p.myField   -- НЕТ SObject.init
  end
}
```

Без `SObject.init(self, p)` не будут установлены `x/y/z/w/h/pivot/color/childs` — при первой же попытке отрисовки или добавления ребёнка всё упадёт. Всегда первым делом зовите родителя.

### Композит + миксин ввода

Если хотите «кнопку из двух спрайтов + текст», комбинируйте композицию с `SButtonEngine`:

```lua
local FancyButton = Class{
  __includes = { SObject, SButtonEngine, SMouseObject, SKeyboardObject },
  init = function(self, p)
    SObject.init(self, p)
    self._bg    = self:add(SSprite{ img = p.bg or "btn_bg" })
    self._icon  = self:add(SSprite{ img = p.icon })
    self._label = self:add(SText{ font = p.font, text = p.label, pivot = {0.5, 0.5}, y = 40 })
    self.w, self.h = self._bg.w, self._bg.h
    self.event  = p.event
    self:state("release")
  end
}

function FancyButton:state(s)
  if s == "release" then
    self._bg.color, self._icon.color = nil, nil
  elseif s == "over" then
    self._bg.color, self._icon.color = {1,1,0.59,1}, nil
  elseif s == "press" then
    self._bg.color = {0.78,0.78,0.47,1}
    self._icon.y = 2      -- сдвинуть иконку чуть вниз
  end
end
```

Все миксины работают одинаково — порядок в `__includes`, переопределение методов, явный вызов родителя (`SObject.init` + потом `SButtonEngine.*` если нужно).

---

## См. также

- [SObject.md](./SObject.md) — базовые механики, которые вы расширяете.
- [SSprite.md](./SSprite.md) — спрайты, от которых удобно наследоваться.
- [SAnimatedObject.md](./SAnimatedObject.md) — state machine для сложного поведения.
- [SESceneLoader.md](./SESceneLoader.md) — как подключить свои классы декларативно.
- [SButton.md](./SButton.md) — примеры кастомных интерактивных узлов.
