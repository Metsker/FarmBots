# Recipes — Cookbook

Небольшие сфокусированные рецепты для типовых задач. Каждый — самодостаточный, можно копировать и адаптировать. Написано из расчёта «мне нужен такой-то элемент UI, как это делается в SE3».

---

## Оглавление

1. [Таймер / отложенный вызов](#1-таймер--отложенный-вызов)
2. [Tween без SAnimatedObject](#2-tween-без-sanimatedobject)
3. [Fade-in / Fade-out сцен](#3-fade-in--fade-out-сцен)
4. [Toast-уведомление](#4-toast-уведомление)
5. [Модальное окно](#5-модальное-окно)
6. [Параллакс-фон](#6-параллакс-фон)
7. [Drag & drop](#7-drag--drop)
8. [Tooltip по hover](#8-tooltip-по-hover)
9. [Скроллирующийся список](#9-скроллирующийся-список)
10. [Выпадающий список / меню](#10-выпадающий-список--меню)
11. [Screen shake](#11-screen-shake)
12. [Pause overlay без смены сцены](#12-pause-overlay-без-смены-сцены)
13. [Timer-bar (ограничение времени)](#13-timer-bar-ограничение-времени)
14. [Draggable HUD (слайдер)](#14-draggable-hud-слайдер)
15. [Follow-мышь и фокус](#15-follow-мышь-и-фокус)

---

## 1. Таймер / отложенный вызов

SE3 не имеет встроенного `setTimeout`. Два варианта:

### A. Через `SAnimatedObject`-script

Если у вас уже анимированный объект:

```lua
states.wait_then_do = {
  frames = "current_frame",
  loop = false,
  scripts = {
    {"wait", 0.5},
  },
  onScriptsEnd = function(self)
    doSomething(self)
  end,
  stopScriptAtEnd = true,
}
```

Дороговато для одного таймера. Лучше:

### B. Пул таймеров в обычном SObject

```lua
-- model/timers.lua
local Timers = SObject{}

function Timers:after(delay, fn)
  self._q = self._q or {}
  self._q[#self._q + 1] = { time = delay, fn = fn }
end

function Timers:every(period, fn)
  self._every = self._every or {}
  self._every[#self._every + 1] = { time = period, period = period, fn = fn }
end

function Timers:update(dt)
  if self._q then
    for i = #self._q, 1, -1 do
      local t = self._q[i]
      t.time = t.time - dt
      if t.time <= 0 then
        t.fn()
        table.remove(self._q, i)
      end
    end
  end
  if self._every then
    for _, t in ipairs(self._every) do
      t.time = t.time - dt
      if t.time <= 0 then
        t.fn()
        t.time = t.time + t.period
      end
    end
  end
end

return Timers
```

Использование:

```lua
local Timers = require("model.timers")
scene:add(Timers)

Timers:after(0.5, function() print("half second passed") end)
Timers:every(1.0, function() print("every second") end)
```

### C. hump.timer

В комплект SE3 входит `hump/timer.lua` (не подключается автоматически):

```lua
local Timer = require("hump.timer")

Timer.after(0.5, function() print("half second") end)
Timer.every(1.0, function() print("tick") end)

-- прокинуть в main:
function love.update(dt) Timer.update(dt); manager:update(dt) end
```

Тот же API, но живёт в собственной инфраструктуре. Удобно, когда таймер не привязан к конкретной сцене.

**Главное правило**: таймер, поставленный в сцене, должен уметь отмениться в `onLeave`, иначе после перехода колбэк выстрелит в уже-несуществующую сцену.

---

## 2. Tween без SAnimatedObject

Если у вас простой узел без state machine, но хочется плавной анимации — маленький хелпер:

```lua
local Tween = Class{ __includes = SObject,
  init = function(self, p)
    SObject.init(self, p)
    self._tweens = {}
  end
}

function Tween:to(target, duration, values, easing)
  easing = easing or "linearTo"
  local fn = SEEasings[easing] or SEEasings.linearTo
  local spec = { target = target, time = 0, duration = duration, fn = fn, params = {} }
  for k, v in pairs(values) do
    spec.params[k] = { from = target[k], to = v }
  end
  self._tweens[#self._tweens + 1] = spec
end

function Tween:update(dt)
  for i = #self._tweens, 1, -1 do
    local t = self._tweens[i]
    t.time = t.time + dt
    local done = t.time >= t.duration
    local x = math.min(t.time, t.duration)
    for k, v in pairs(t.params) do
      t.target[k] = t.fn(x, v.from, v.to, t.duration)
    end
    if done then
      if t.callback then t.callback() end
      table.remove(self._tweens, i)
    end
  end
end

scene:add(Tween)
```

Использование:

```lua
Tween:to(sprite, 0.5, { x = 200, sx = 1.5 }, "outQuad")
```

Напомню: `SAnimatedObject` делает то же самое декларативно; Tween-хелпер — когда надо анимировать обычный `SSprite` без перехода на state machine.

---

## 3. Fade-in / Fade-out сцен

SESceneManager не имеет встроенных переходов. Простейший fade — это оверлей, управляемый контроллером.

```lua
-- prefabs/fade.lua
return function(p)
  return {
    type = "SStretchedSprite",
    img   = p.img or "pixel_black",    -- 1×1 чёрный пиксель
    w     = p.w or 1920, h = p.h or 1080,
    color = {0, 0, 0, 1},
    alpha = 0,                           -- начинаем прозрачным
    id    = "fade",
    z     = 1000,                        -- поверх всего
  }
end
```

Контроллер сцены делает fade-in при входе:

```lua
function Scene:onEnter(scene)
  self.fade = scene:byId("fade")
  self.fade.color = {0, 0, 0, 1}
  self.fade.color[4] = 1
  self._fadeIn = 0.5
end

function Scene:update(dt)
  if self._fadeIn and self._fadeIn > 0 then
    self._fadeIn = self._fadeIn - dt
    local t = math.max(0, self._fadeIn / 0.5)
    self.fade.color[4] = t
    if self._fadeIn <= 0 then
      self.fade.off = true     -- больше не рисуем и не слышим события
    end
  end
end
```

Fade-out перед сменой сцены — чуть сложнее: надо дождаться завершения анимации, только потом `manager:change`.

```lua
function Scene:leaveTo(sceneName)
  self.fade.off = false
  self._fadeOut = 0.5
  self._fadeOutTarget = sceneName
end

function Scene:update(dt)
  if self._fadeOut and self._fadeOut > 0 then
    self._fadeOut = self._fadeOut - dt
    local t = 1 - math.max(0, self._fadeOut / 0.5)
    self.fade.color[4] = t
    if self._fadeOut <= 0 then
      manager:change(self._fadeOutTarget)
    end
  end
end
```

### Альтернатива — глобальный fade

Вынести fade-слой из сцены в `main.lua`, сделать его отдельным overlay поверх менеджера:

```lua
-- main.lua
local fade = SStretchedSprite{ img = "pixel_black", w = 1920, h = 1080, color = {0, 0, 0, 0} }

function love.draw()
  manager:draw()
  fade:__draw()
end

function goToSceneWithFade(name)
  -- анимация fade-out, потом change, потом fade-in
  ...
end
```

Это аккуратнее, если fade нужен между **любыми** сценами.

---

## 4. Toast-уведомление

Небольшое всплывающее сообщение в углу, которое само появляется и исчезает.

```lua
local Toast = Class{ __includes = SObject,
  init = function(self, p)
    SObject.init(self, p)
    self._bg = self:add(SStretchedSprite{
      img   = "toast_bg", w = 300, h = 60,
      color = {0.16, 0.16, 0.16, 0.86},
    })
    self._text = self:add(SText{
      font  = "main", text = p.text or "",
      pivot = {0.5, 0.5},
      maxWidth = 280, align = "center",
    })
    self.w, self.h = 300, 60

    self._time = 0
    self._duration = p.duration or 2.5
    self._fadeIn   = 0.2
    self._fadeOut  = 0.3
    self.color     = self.color or {1, 1, 1, 0}
  end
}

function Toast:update(dt)
  self._time = self._time + dt
  local alpha
  if self._time < self._fadeIn then
    alpha = self._time / self._fadeIn
  elseif self._time < self._duration - self._fadeOut then
    alpha = 1
  elseif self._time < self._duration then
    alpha = (self._duration - self._time) / self._fadeOut
  else
    alpha = 0
    self.off = true    -- сам выгружает себя
    if self.parent then
      -- пометить, чтобы сцена могла прибрать (в SE3 нет removeChild)
      self._dead = true
    end
  end
  self._bg.color[4] = 0.86 * alpha
  self._text.color = { 1, 1, 1, alpha }
end
```

Использование:

```lua
function showToast(scene, message)
  scene:add(Toast{ x = 200, y = 50, text = message })
end

showToast(scene, "Level saved!")
```

Если много toast-ов в очередь — центральный «ToastManager» (SGroup, в которую кладутся новые Toast-ы) упростит менеджмент.

---

## 5. Модальное окно

```lua
local Modal = Class{ __includes = SGroup,
  init = function(self, p)
    SGroup.init(self, p)
    self.z = 500   -- поверх всего в своём парент-е

    -- Блокер событий
    local Blocker = Class{ __includes = { SObject, SMouseObject },
      init = function(s, sp)
        SObject.init(s, sp)
        s.w, s.h = sp.w or 1920, sp.h or 1080
      end
    }
    function Blocker:inBox() return true end
    function Blocker:mousepressed()  return true end
    function Blocker:mousereleased() return true end

    self:add(SStretchedSprite{
      img = "pixel_black", w = 1920, h = 1080,
      color = {0, 0, 0, 0.71},
    })
    self:add(SStretchedSprite{
      img = "dialog_bg",
      w = p.w or 500, h = p.h or 300,
      pivot = {0.5, 0.5},
    })
    self:add(SText{
      font = "main", text = p.title or "",
      pivot = {0.5, 0}, y = -((p.h or 300)/2) + 20,
      align = "center", maxWidth = p.w or 500,
    })

    -- дети-кнопки (приходят в массивной части p)
    -- SGroup.init уже их добавил

    -- Blocker последним — съедает всё, что не попало в кнопки
    self:add(Blocker{ w = 1920, h = 1080 })
  end
}
```

Использование:

```lua
local dialog = Modal{ w = 500, h = 280, title = "Вы уверены?",
  SSpriteButton{ states = "btn_yes", event = "dialog.yes", x = -80, y = 50 },
  SSpriteButton{ states = "btn_no",  event = "dialog.no",  x =  80, y = 50 },
}
-- Добавить первым в childs, чтобы он перехватывал события:
table.insert(scene.childs, 1, dialog)
dialog.parent = scene
```

Подробнее про «почему первым в childs» — см. [EventPropagation §7](./EventPropagation.md#7-мышь-поверх-кнопок--кто-победит).

---

## 6. Параллакс-фон

Несколько слоёв фона, двигающихся с разной скоростью.

```lua
local Parallax = Class{ __includes = SGroup,
  init = function(self, p)
    SGroup.init(self, p)
    self._layers = {}
    for _, layer in ipairs(p.layers or {}) do
      local sprite = self:add(SSprite{
        img = layer.img,
        x = 0, y = layer.y or 0,
        z = layer.z or 0,
      })
      self._layers[#self._layers + 1] = {
        sprite = sprite,
        speed  = layer.speed or 1,
      }
    end
    self._cameraX = 0
  end
}

function Parallax:setCamera(x)
  self._cameraX = x
  for _, l in ipairs(self._layers) do
    l.sprite.x = -x * l.speed
  end
end
```

Использование:

```lua
local bg = Parallax{ layers = {
  { img = "bg_sky",      speed = 0.1, z = 0 },
  { img = "bg_mountains", speed = 0.3, z = 1 },
  { img = "bg_trees",     speed = 0.7, z = 2 },
}}

function Scene:update(dt)
  self.cameraX = self.cameraX + dt * 60
  bg:setCamera(self.cameraX)
end
```

Для цикличного фона — в update оборачивайте `sprite.x` по модулю ширины картинки, плюс добавьте копию справа.

---

## 7. Drag & drop

```lua
local Draggable = Class{ __includes = { SObject, SMouseObject },
  init = function(self, p)
    SObject.init(self, p)
    self._child = self:add(p.child or SSprite{ img = p.img })
    self.w, self.h = self._child.w, self._child.h
  end
}

function Draggable:mousepressed(mx, my, button, istouch, used)
  if used or not self:inBox(mx, my) then return used end
  self._dragging = true
  self._dragDX = self.x - (mx + self.x)   -- self.x — локальная в parent; mx — локальные
  self._dragDY = self.y - (my + self.y)
  return true
end

function Draggable:mousemoved(mx, my, istouch, used)
  if self._dragging then
    -- mx, my локальные; переводим обратно к parent-координатам:
    self.x = self.x + mx   -- курсор сместился на mx от текущего origin
    self.y = self.y + my
    return true
  end
  return used
end

function Draggable:mousereleased(mx, my, button, istouch, used)
  if self._dragging then
    self._dragging = false
    return true
  end
  return used
end
```

Использование:

```lua
Draggable{ img = "token", x = 100, y = 100 }
```

Внимание: точная арифметика координат при drag-е зависит от иерархии родителей. Если `Draggable` вложен в группу с поворотом/масштабом — нужно брать глобальные координаты через `transformMouse`. Этот рецепт работает для прямого родителя без трансформаций.

### Более надёжный вариант — глобальные координаты

```lua
function Draggable:mousepressed(mx, my, button, istouch, used)
  if used or not self:inBox(mx, my) then return used end
  self._dragging = true
  self._startX, self._startY = love.mouse.getPosition()
  self._startObjX, self._startObjY = self.x, self.y
  return true
end

function Draggable:mousemoved(mx, my, istouch, used)
  if self._dragging then
    local gx, gy = love.mouse.getPosition()
    self.x = self._startObjX + (gx - self._startX)
    self.y = self._startObjY + (gy - self._startY)
    return true
  end
  return used
end
```

`love.mouse.getPosition()` возвращает координаты в окне — их легче использовать как delta.

---

## 8. Tooltip по hover

```lua
local Tooltip = Class{ __includes = SGroup,
  init = function(self, p)
    SGroup.init(self, p)
    self.z = 900
    self.off = true   -- скрыт по умолчанию

    self._bg = self:add(SStretchedSprite{
      img = "tooltip_bg", w = 200, h = 40, color = {0.12, 0.12, 0.12, 0.9},
    })
    self._text = self:add(SText{
      font = "small", text = "",
      maxWidth = 190, align = "center",
      pivot = {0.5, 0.5},
    })
  end
}

function Tooltip:show(text, x, y)
  self._text:setText(text)
  self.x, self.y = x, y - 30
  self.off = false
end

function Tooltip:hide()
  self.off = true
end
```

Кнопка, показывающая tooltip по hover:

```lua
local TooltipButton = Class{ __includes = SSpriteButton,
  init = function(self, p)
    SSpriteButton.init(self, p)
    self._tooltip    = p.tooltip
    self._tooltipRef = p.tooltipRef   -- ссылка на общий Tooltip-узел
  end
}

function TooltipButton:over()
  SSpriteButton.over(self)
  if self._tooltipRef and self._tooltip then
    local gx, gy = love.mouse.getPosition()
    self._tooltipRef:show(self._tooltip, gx, gy)
  end
end

function TooltipButton:release()
  SSpriteButton.release(self)
  if self._tooltipRef then self._tooltipRef:hide() end
end
```

Использование:

```lua
local tt = scene:add(Tooltip{})
scene:add(TooltipButton{
  states  = "btn_main",
  event   = "something",
  tooltip = "Hover help text",
  tooltipRef = tt,
})
```

Tooltip добавляется в сцену один раз, его ссылка передаётся кнопкам. Все tooltip-ы шарят один узел.

---

## 9. Скроллирующийся список

Элементарный вертикальный скролл с `SCanvas` для обрезки:

```lua
local ScrollList = Class{ __includes = SGroup,
  init = function(self, p)
    SGroup.init(self, p)
    self._viewH   = p.viewH or 400
    self._content = self:add(SGroup{})   -- содержимое, сдвигаемое по y
    self.w, self.h = p.viewW or 300, self._viewH
    self._scroll = 0
    self._contentH = 0
  end
}

function ScrollList:addItem(item, height)
  item.y = self._contentH
  self._content:add(item)
  self._contentH = self._contentH + (height or item.h or 40)
end

function ScrollList:scroll(delta)
  self._scroll = math.max(0, math.min(self._scroll + delta, math.max(0, self._contentH - self._viewH)))
  self._content.y = -self._scroll
end

-- Если прокидываете `wheelmoved` в сцену (см. EventPropagation §9):
function ScrollList:mousewheel(mx, my, dx, dy, used)
  if used or not self:inBox(mx, my) then return used end
  self:scroll(dy * -40)
  return true
end
```

Для **обрезки** по viewport-у оберните в `SCanvas` или добавьте `love.graphics.setScissor` в своём `draw`. Самый простой вариант — `SCanvas{ canvasSize = {300, 400} }` как корневой контейнер, но тогда скроллинг должен сбрасывать кэш (что не здорово для производительности).

Для большого листа — лучше делать `setScissor` внутри `draw`, а содержимое хранить в обычном `SGroup`.

---

## 10. Выпадающий список / меню

```lua
local Dropdown = Class{ __includes = SGroup,
  init = function(self, p)
    SGroup.init(self, p)
    self._options = p.options or {}
    self._onSelect = p.onSelect or function() end

    -- Основная кнопка
    self._trigger = self:add(SSpriteButton{
      states = "btn_dropdown",
      font = "main", text = p.label or "Select",
      event = function() self:toggle() end,
    })

    -- Контейнер для опций — скрыт
    self._list = self:add(SGroup{ off = true, y = 50 })
    for i, opt in ipairs(self._options) do
      self._list:add(SSpriteButton{
        states = "btn_dropdown_item",
        font = "main", text = opt.label,
        y = (i - 1) * 40,
        event = function() self:select(i) end,
      })
    end
  end
}

function Dropdown:toggle()
  self._list.off = not self._list.off
end

function Dropdown:select(i)
  self._list.off = true
  local opt = self._options[i]
  if opt then
    self._trigger:setText(opt.label)
    self._onSelect(opt)
  end
end
```

Использование:

```lua
Dropdown{ x = 100, y = 100, label = "Difficulty",
  options = {
    {label = "Easy",   value = 1},
    {label = "Normal", value = 2},
    {label = "Hard",   value = 3},
  },
  onSelect = function(opt) Settings.difficulty = opt.value end,
}
```

---

## 11. Screen shake

Камера-эффект «встряска экрана» реализуется через трансляцию корня сцены.

```lua
local ScreenShake = Class{ __includes = SObject,
  init = function(self, p) SObject.init(self, p); self._time = 0; self._duration = 0; self._amount = 0 end
}

function ScreenShake:trigger(duration, amount)
  self._time = 0
  self._duration = duration
  self._amount = amount
end

function ScreenShake:update(dt)
  if self._duration <= 0 then self.x, self.y = 0, 0; return end
  self._time = self._time + dt
  local left = math.max(0, self._duration - self._time)
  local t = left / self._duration
  self.x = (math.random() * 2 - 1) * self._amount * t
  self.y = (math.random() * 2 - 1) * self._amount * t
  if self._time >= self._duration then
    self._duration = 0
    self.x, self.y = 0, 0
  end
end
```

Обычный паттерн — `ScreenShake` как корневой контейнер сцены:

```lua
scene = SGroup{
  ScreenShake{ children = {
    -- всё содержимое сцены
    SSprite{ img = "bg" },
    hero,
    hud,
  }}
}

-- триггер:
scene.childs[1]:trigger(0.3, 15)
```

---

## 12. Pause overlay без смены сцены

Пауза — это не новая сцена, а **состояние** текущей, с оверлеем и приостановкой update-а.

```lua
-- Контроллер игровой сцены:
function Game:onEnter(scene)
  self.paused = false
  self.pauseOverlay = scene:byId("pause_overlay")   -- описан в манифесте с off = true
end

function Game:togglePause()
  self.paused = not self.paused
  self.pauseOverlay.off = not self.paused
end

function Game:update(dt)
  if self.paused then return end    -- не обновляем игровую логику
  -- обычный update
end

function Game:keypressed(key)
  if key == "escape" then self:togglePause() end
end
```

Манифест:

```lua
scene = {
  type = "SGroup",
  { type = "SGroup", id = "gameplay",
    children = { ... игровой контент ... }
  },
  { type = "SGroup", id = "pause_overlay", off = true, z = 500,
    children = {
      { type = "SStretchedSprite", img = "black", w = 1920, h = 1080, color = {0, 0, 0, 0.59} },
      { type = "SText", font = "main", text = "PAUSED", pivot = {0.5, 0.5} },
      { include = "prefabs.button", params = { label = "RESUME", event = "@self:togglePause", y = 100 } },
      { include = "prefabs.button", params = { label = "QUIT",   event = "@nav.menu",        y = 160 } },
    }
  },
}
```

Важно: **Контроллер `update` в SESceneManager** вызывается **до** `scene:__update` (см. [SESceneManager §6](./SESceneManager.md#6-форвардинг-love2d-событий)). Чтобы ваш `Game:update` мог «останавливать» `scene:__update`, сцена должна вам это позволить — по умолчанию менеджер **всегда** вызывает scene update.

Решение — приостановить внутреннюю логику через флаг, а не пытаться остановить scene `:__update`. То есть: все ваши игровые объекты проверяют `if self.paused then return end` или ставят `off = true` на геймплейный `SGroup`.

Для полного «заморозить всё» — отключите геймплейный поддерево через `off`:

```lua
function Game:togglePause()
  self.paused = not self.paused
  scene:byId("gameplay").off = self.paused
  self.pauseOverlay.off = not self.paused
end
```

`gameplay.off = true` вырубит и `draw`, и `update`, и события. Идеально для паузы.

---

## 13. Timer-bar (ограничение времени)

Полоса обратного отсчёта:

```lua
local TimerBar = Class{ __includes = SObject,
  init = function(self, p)
    SObject.init(self, p)
    self._bg = self:add(SStretchedSprite{
      img = "bar_bg", w = p.width or 400, h = p.height or 10,
    })
    self._fill = self:add(SStretchedSprite{
      img = "bar_fill", w = p.width or 400, h = p.height or 10,
      pivot = {0, 0.5}, x = -(p.width or 400) * 0.5,
    })
    self.w, self.h = p.width or 400, p.height or 10

    self._total     = p.duration or 30
    self._remaining = self._total
    self._running   = false
    self._onEnd     = p.onEnd or function() end
  end
}

function TimerBar:start()    self._running = true end
function TimerBar:pause()    self._running = false end
function TimerBar:reset()    self._remaining = self._total end

function TimerBar:update(dt)
  if not self._running then return end
  self._remaining = math.max(0, self._remaining - dt)
  self._fill.sx = self._remaining / self._total
  -- цветовая индикация
  if self._remaining < self._total * 0.2 then
    self._fill.color = {1, 0.31, 0.31, 1}
  elseif self._remaining < self._total * 0.5 then
    self._fill.color = {1, 0.78, 0.31, 1}
  else
    self._fill.color = nil
  end
  if self._remaining <= 0 and self._running then
    self._running = false
    self._onEnd()
  end
end
```

Использование:

```lua
TimerBar{ x = 500, y = 30, width = 600, duration = 60,
  onEnd = function() self:setState("gameover") end }
```

---

## 14. Draggable HUD (слайдер)

Громкость, яркость, что угодно — слайдер с горизонтальным dragом.

```lua
local Slider = Class{ __includes = { SObject, SMouseObject },
  init = function(self, p)
    SObject.init(self, p)
    self._track = self:add(SStretchedSprite{
      img = "slider_track", w = p.width or 300, h = 6,
    })
    self._handle = self:add(SSprite{
      img = "slider_handle",
      pivot = {0.5, 0.5},
    })
    self.w, self.h = p.width or 300, 30

    self._value  = p.value  or 0.5
    self._onChange = p.onChange or function() end
    self:_updateHandle()
  end
}

function Slider:_updateHandle()
  local w = self.w
  self._handle.x = -w/2 + self._value * w
end

function Slider:setValue(v)
  self._value = math.max(0, math.min(1, v))
  self:_updateHandle()
  self._onChange(self._value)
end

function Slider:mousepressed(mx, my, button, istouch, used)
  if used or not self:inBox(mx, my) then return used end
  self._dragging = true
  self:_setFromMouse(mx)
  return true
end

function Slider:mousemoved(mx, my, istouch, used)
  if self._dragging then self:_setFromMouse(mx); return true end
  return used
end

function Slider:mousereleased(mx, my, button, istouch, used)
  if self._dragging then self._dragging = false; return true end
  return used
end

function Slider:_setFromMouse(mx)
  -- mx — локальные координаты; 0 — центр слайдера
  self:setValue((mx + self.w/2) / self.w)
end
```

Использование:

```lua
Slider{ x = 200, y = 100, value = Settings.soundVolume,
  onChange = function(v) Settings.soundVolume = v end }
```

---

## 15. Follow-мышь и фокус

Курсор со своей графикой, который всегда под курсором системы:

```lua
local Cursor = Class{ __includes = SObject,
  init = function(self, p)
    SObject.init(self, p)
    self._sprite = self:add(SSprite{ img = p.img or "cursor", pivot = {0, 0} })
    self.w, self.h = self._sprite.w, self._sprite.h
  end
}

function Cursor:update(dt)
  self.x, self.y = love.mouse.getPosition()
end
```

Использование:

```lua
scene:add(Cursor{ img = "cursor_hand" })
love.mouse.setVisible(false)   -- спрятать системный курсор
```

Для эффекта «курсор меняется при hover на кнопке» — контроллер сцены меняет `cursor._sprite:setImg(name)` в обработчике ховера.

---

## См. также

- [Inheritance.md](./Inheritance.md) — базовые шаблоны наследования/композиции, на которых построены рецепты.
- [EventPropagation.md](./EventPropagation.md) — как события работают в drag-examples.
- [SAnimatedObject.md](./SAnimatedObject.md) — когда вместо рукописных update стоит использовать state machine.
- [Architecture.md](./Architecture.md) — куда класть Timers / Cursor в структуре проекта.
