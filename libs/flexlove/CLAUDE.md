# FlexLöve — CLAUDE.md

AI-context for the FlexLöve UI library vendored under `libs/flexlove/`.

## What this is

**FlexLöve v0.11.6** — a CSS-flexbox-inspired **immediate-mode and retained-mode UI library** for LÖVE2D 11.0+. Includes theming (9-patch image atlases), text editing, scrollable containers, keyboard navigation, animations, backdrop blur, touch/gesture support, performance monitoring, and garbage-collection tuning. MIT licensed.

- **Upstream:** https://github.com/mikefreno/FlexLove
- **Docs:** https://mikefreno.github.io/FlexLove/
- **This profile:** `full` (100% of modules, including debugging tools)

## Architecture

```
libs/flexlove/
├── FlexLove.lua            — main library file (public API + init wiring)
├── modules/
│   ├── Element.lua         — the Element class (4.6K lines); central node of everything
│   ├── LayoutEngine.lua    — flexbox and grid layout resolver (1.7K lines)
│   ├── Renderer.lua        — drawing: bg, borders, text, images, 9-patch themes, blur, transform
│   ├── EventHandler.lua    — mouse/touch input: hover, press, release, click, drag, touch ownership
│   ├── Theme.lua           — theme loader/manager + per-element ThemeManager (9-patch+colors+fonts)
│   ├── TextEditor.lua      — full text-editing engine: cursor, selection, scroll, wrapping, IME
│   ├── ScrollManager.lua   — overflow scrolling: wheel, touch+momentum, scrollbars, bounce
│   ├── Animation.lua       — property interpolation (easings, transforms, transitions)
│   ├── StateManager.lua    — immediate-mode state persistence across frames (React-like)
│   ├── Color.lua           — RGBA color helper (new/parse hex/fromHSL/interpolate)
│   ├── Calc.lua            — CSS calc() parser: "50% - 10vw" → layout-time value
│   ├── Units.lua           — viewport-relative units (vw, vh, %, ew, eh, px)
│   ├── utils.lua           — enums, table helpers, debug coloring, ID generator
│   ├── Context.lua         — global singleton: focus, z-index registry, mode state
│   ├── RoundedRect.lua     — themed rounded-rect drawing (uses theme colors)
│   ├── Grid.lua            — CSS-grid layout (independent from flexbox)
│   ├── InputEvent.lua      — normalized input events (mouse, touch)
│   ├── Blur.lua            — Gaussian blur via shader + canvas caching
│   ├── NinePatch.lua       — 9-slice image rendering for scalable themed widgets
│   ├── ImageRenderer.lua   — image drawing with object-fit/position/repeat/tint
│   ├── ImageScaler.lua     — image loading with responsive scale factors
│   ├── ImageCache.lua      — LRU cache for loaded Images (prevents duplicate GPU uploads)
│   ├── KeyboardNavigation.lua — Tab/arrow focus traversal, ARIA roles, focus indicator
│   ├── FocusIndicator.lua  — visual focus ring (pulsed outline on focused element)
│   ├── GestureRecognizer.lua — shared touch-gesture recognizer (tap, swipe, pinch)
│   ├── FFI.lua             — LuaJIT FFI optimizations (fallback to pure Lua)
│   ├── ErrorHandler.lua    — structured error/warning logging with log rotation
│   ├── Performance.lua     — per-frame timing, FPS HUD, memory profiling
│   ├── MemoryScanner.lua   — Lua-heap scanner for leak detection (full profile only)
│   ├── ModuleLoader.lua    — safe deferred require with stub support
│   ├── types.lua           — LuaLS type annotations for all props/enums
│   └── UTF8.lua            — minimal UTF-8 validation utilities
├── themes/
│   ├── README.md           — theme authoring guide
│   ├── metal.lua           — built-in "metal" theme definition
│   ├── space.example.lua   — example "space" theme
│   └── metal/              — 9-patch PNG assets for metal theme (buttons, bars, toggles, frames, etc.)
├── LICENSE
└── README.md
```

### Dependency graph (simplified)

```
FlexLove.lua  ──►  Element.lua  ──►  Renderer.lua
                  │  │                 LayoutEngine.lua
                  │  │                 EventHandler.lua
                  │  │                 Theme.lua (ThemeManager per element)
                  │  │                 TextEditor.lua
                  │  │                 ScrollManager.lua
                  │  └─ Animation.lua
                  └─ StateManager.lua (immediate mode only)
```

FlexLove.lua calls `require("flexlove.modules.*")` internally. The consumer only ever `require("flexlove.FlexLove")` / `require("libs.FlexLove")`. Individual modules are NOT meant for external use.

## Two modes: Immediate vs Retained

FlexLove has two lifecycle modes controlled by `FlexLove.setMode()` or per-element `props.mode`:

| | **Retained** (default) | **Immediate** |
|---|---|---|
| Element lifetime | Persistent; you `addChild`/`removeChild`/`destroy` manually | Recreated each frame via `FlexLove.new()` |
| State management | Manual (you track state) | Auto-persisted by `StateManager` across frames |
| Layout | On explicit calls / resize | Auto-computed in `endFrame()` |
| Frame lifecycle | `FlexLove.update(dt)` updates all top-level elements | `beginFrame()` + user code + `endFrame()` (auto if not manual) |
| GC pattern | Stable memory | StateManager cleans stale entries; GC runs per config |
| Best for | Performance-critical, complex state, persistent UI | Declarative UIs, simpler state, rapid iteration |

**In this project** FlexLove runs in **retained mode** (no `immediateMode: true` in `FlexLove.init()`). Elements are created once at module level (e.g., `modules/admin/flex/shell.lua`) and persist until `FlexLove.destroy()`. The `shared/flex_reload.lua` hot-reload module handles destroying and re-creating retained-mode trees on file change.

## Lifecycle hooks in `love.*`

All hooks MUST be wired for FlexLove to function. Follow the pattern from `main.lua`:

```lua
FlexLove.init({ ... })                        -- once in love.load()

love.update    → FlexLove.update(dt)          -- every frame BEFORE FlexLove.draw
love.draw      → FlexLove.draw()              -- renders all topElements
love.keypressed → FlexLove.keypressed(...)
love.textinput  → FlexLove.textinput(...)
love.wheelmoved → FlexLove.wheelmoved(dx, dy)
love.resize     → FlexLove.resize()
love.touchpressed/ moved/ released → FlexLove.touchpressed/ moved/ released(...)
```

**Order matters:** `FlexLove.update(dt)` must run BEFORE `FlexLove.draw()`. In `love.draw`, `FlexLove.draw()` should come AFTER your game/engine draw calls if you use `gameDrawFunc` for backdrop blur.

## Core concepts

### FlexLove.init(config)

Must be called once before `FlexLove.new()`. Key config fields:

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `baseScale` | `{width, height}` | none | Design resolution for responsive scaling (e.g. `{1920, 1080}`) |
| `theme` | string\|table | none | Theme name to autoload, or inline ThemeDefinition table |
| `immediateMode` | bool | `false` | Enable immediate mode |
| `gcStrategy` | `"auto"`\|`"periodic"`\|`"manual"`\|`"disabled"` | `"auto"` | GC management strategy |
| `gcMemoryThreshold` | number | 100 | MB before forced full GC |
| `gcInterval` | number | 60 | Frames between GC steps (periodic) |
| `gcStepSize` | number | 200 | Work units per GC step |
| `keyboardNavigation` | bool\|table | `false` | Enable tab/arrow-key focus navigation |
| `debugDraw` | bool | `false` | Show element bounding boxes with random colors |
| `debugDrawKey` | string | none | Key to toggle `debugDraw` (e.g. `"f2"`) |
| `performanceMonitoring` | bool | `true` | Enable Performance module |
| `autoFrameManagement` | bool | `false` | Auto begin/end frame in immediate mode |

### FlexLove.new(props) → Element

The ONLY way to create UI elements. Returns an `Element` instance.

```lua
local btn = FlexLove.new({
  width = 200, height = 48,
  text = "Click Me",
  themeComponent = "buttonv1",
  onEvent = function(element, event)
    if event.type == "release" then ... end
  end,
})
```

Key props (see `modules/types.lua` for all):

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique ID (auto-generated in immediate mode, required for state persistence) |
| `parent` | Element | Parent element; adds child automatically |
| `x`, `y` | number\|string | Position: number=px, `"50%"`, `"10vw"`, `FlexLove.calc(...)` |
| `width`, `height` | number\|string | Same as x/y |
| `flex` | number\|string | Shorthand for flex-grow (number) or full flex shorthand (`"1 0 auto"`) |
| `positioning` | `"absolute"`\|`"relative"`\|`"flex"`\|`"grid"` | Default: `"relative"` |
| `flexDirection` | `"horizontal"`\|`"vertical"` | Default horizontal |
| `justifyContent`, `alignItems`, `alignContent` | string | See enums below |
| `gap` | number\|string | Space between children (default 0) |
| `padding`, `margin` | number\|table | CSS-like shorthand: number (all sides), `{top,right,bottom,left}`, `{horizontal,vertical}` |
| `text` | string | Display text |
| `textSize` | number\|string | px or preset (`"xs"`..`"4xl"`), or `"2vh"` |
| `textColor` | Color | `Color.new(r,g,b,a)` — 0..1 range |
| `textAlign` | `"start"`\|`"center"`\|`"end"`\|`"justify"` | Horizontal axis only (CSS `text-align` semantics). For vertical positioning, wrap the text element in a flex container with `alignItems` / `justifyContent`. |
| `backgroundColor` | Color | 0..1 range |
| `borderColor` | Color | 0..1 range |
| `cornerRadius` | number\|`{topLeft,topRight,bottomLeft,bottomRight}` | |
| `opacity` | number | 0..1 |
| `disabled` | bool | Disables interaction, propagates to children via `setTreeDisabled` |
| `themeComponent` | string | Theme component name (e.g., `"button"`, `"framev3"`, `"buttonv1"`) |
| `theme` | string | Override theme for this specific element |
| `onEvent` | `fun(element, event)` | Mouse/touch event callback |
| `onFocus`, `onBlur` | `fun(element)` | Focus callbacks |
| `onTextInput`, `onTextChange`, `onEnter` | `fun(element, text?)` | Text-editing callbacks |
| `editable` | bool | Enable text editing (creates TextEditor internally) |
| `multiline` | bool | Multi-line text mode |
| `placeholder` | string | Placeholder when text is empty |
| `maxLength` | number | Max characters |
| `overflow`, `overflowX`, `overflowY` | `"visible"`\|`"hidden"`\|`"scroll"`\|`"auto"` | Overflow behavior |
| `backdropBlur` | `{radius, quality?}` | Blur content behind element |
| `contentBlur` | `{radius, quality?}` | Blur element's own content |
| `objectFit` | `"fill"`\|`"contain"`\|`"cover"`\|`"scale-down"`\|`"none"` | Image fit |
| `image` | `love.Image` | Display an image (also auto-loads via `imagePath`) |
| `animation` | AnimationConfig | Attach a predefined animation |
| `transform` | `{scale?, rotate?, translate?, skew?}` | CSS-like transform |
| `transition` | `{duration?, easing?}` | Transition animation on property change |

### Color conventions

**Colors are 0..1 floats** (same as LÖVE's `love.graphics.setColor`):

```lua
local Color = FlexLove.Color
Color.new(1, 0, 0, 1)         -- red (r, g, b, a)
Color.fromHex("#ffcc00")      -- parse hex string
Color.fromHex("#ffcc0080")    -- with alpha
```

**Never** pass 0..255 values. The `Color` module also supports HSL→RGB, interpolation, and `toRGBA()` unpacking.

### Element tree: parent/children

Elements form a tree via the `parent` prop OR `element:addChild(child)`:

```lua
local root = FlexLove.new({ width = "100%", height = "100%", flexDirection = "vertical" })
FlexLove.new({ parent = root, text = "child 1" })  -- auto-added to root.children
FlexLove.new({ parent = root, text = "child 2" })
```

**Top-level elements** (those without a parent) are tracked in `FlexLove.topElements` and rendered during `FlexLove.draw()`. Use `FlexLove.destroy()` to clean them all up.

### Layout system

FlexLove uses **CSS-flexbox semantics**:

- `positioning = "flex"` — container uses flexbox layout (default `horizontal` direction)
- `positioning = "absolute"` — child is removed from flow, positioned relative to nearest positioned ancestor
- `positioning = "relative"` — normal flow; `top`/`right`/`bottom`/`left` offsets from natural position
- `positioning = "grid"` — CSS-grid layout via `gridRows`/`gridColumns`/`columnGap`/`rowGap`, or explicit per-track sizing via `gridTemplateColumns`/`gridTemplateRows` arrays. Each entry in a template array is a number (px) or string with unit: `"1fr"` (flex fraction), `"44px"`, `"50%"`. Templates override the equal-distribution count props and infer the track count from `#array`.

To hide an element entirely (CSS `display: none` — removed from layout AND hit-testing), use the orthogonal `display` prop:

- `display = true` *(default)* — element participates in layout and is drawn / hit-tested.
- `display = false` — element is dropped from flex/grid calculations, skipped in draw / update, and excluded from `getElementAtPosition`.

Use `element:setDisplay(v)` at runtime — it auto-invalidates layout so the next `layoutChildren()` actually reflows.

**Flex items:** `flexGrow`, `flexShrink`, `flexBasis`, `flex` (shorthand). Children with `flex = 1` expand to fill remaining space equally.

**Calc expressions** for dynamic sizing:
```lua
width = FlexLove.calc("50% - 20px")
width = FlexLove.calc("100vw - 240px")
```

**Viewport-relative units** in string props: `"50%"`, `"10vw"`, `"5vh"`, `"100px"`.

Z-index: `z` prop (higher = on top). Sorted descending by z during draw.

### Enums (from `utils.lua` / `FlexLove.enums`)

```lua
Positioning:     "absolute" | "relative" | "flex" | "grid"
FlexDirection:   "horizontal" | "vertical"   (or "row"/"column")
JustifyContent:  "flex-start" | "center" | "flex-end" | "space-between" | "space-around" | "space-evenly"
AlignItems:      "stretch" | "flex-start" | "center" | "flex-end" | "baseline"
AlignSelf:       "auto" | "stretch" | "flex-start" | "center" | "flex-end" | "baseline"
AlignContent:    "stretch" | "flex-start" | "center" | "flex-end" | "space-between" | "space-around"
FlexWrap:        "nowrap" | "wrap" | "wrap-reverse"
TextAlign:       "start" | "center" | "end" | "justify"
Overflow:        "visible" | "hidden" | "scroll" | "auto"
ObjectFit:       "fill" | "contain" | "cover" | "scale-down" | "none"
Visibility:      "visible" | "hidden"
```

`TextSize` presets: `"xxs"`, `"xs"`, `"sm"`, `"md"`, `"lg"`, `"xl"`, `"xxl"`, `"3xl"`, `"4xl"` — resolve to px via theme's `fontSizes` table.

## Theme system

Themes are **9-patch image-based**. They render ON TOP of `backgroundColor` and BELOW borders and text.

### Key concepts

- **Theme component** (`themeComponent` prop): named component in the active theme (e.g., `"button"`, `"framev3"`, `"panel"`)
- **Theme state**: `normal` / `hover` / `pressed` / `active` / `disabled` — auto-managed by `EventHandler` based on interaction
- **ThemeManager** (internal per-element): resolves the correct 9-patch image and region coordinates for the current state
- **9-patch regions**: `topLeft`, `topCenter`, `topRight`, `middleLeft`, `middleCenter`, `middleRight`, `bottomLeft`, `bottomCenter`, `bottomRight` — define which parts of the source image stretch

### Setting up themes

```lua
-- Load theme definition
local metalDef = require("flexlove.themes.metal")
local metalTheme = FlexLove.Theme.new(metalDef)
FlexLove.Theme.setActive(metalTheme)

-- Or inline
FlexLove.init({ theme = metalDef })
```

### Theme definition structure

```lua
return {
  name = "MyTheme",
  atlas = "path/to/default_atlas.png",    -- global fallback atlas
  colors = {
    primary = { 0.1, 0.5, 1, 1 },
    text = { 1, 1, 1, 1 },
    background = { 0.05, 0.05, 0.1, 1 },
    border = { 0.3, 0.3, 0.3, 1 },
    -- ... more named colors
  },
  fontSizes = {
    xxs = 8, xs = 10, sm = 12, md = 16, lg = 20, xl = 24, xxl = 32, ["3xl"] = 40, ["4xl"] = 48,
  },
  components = {
    panel = {
      atlas = "themes/panel.png",   -- component-specific atlas (overrides global)
      insets = { left = 8, top = 8, right = 8, bottom = 8 },  -- 9-patch slice positions
      scaleCorners = 1,             -- corner scaling multiplier
    },
    button = {
      states = {
        hover = { atlas = "button_hover.png" },
        pressed = { atlas = "button_pressed.png" },
        disabled = { atlas = "button_disabled.png" },
      },
    },
  },
  scrollbars = {
    default = {
      track = { ... },
      thumb = { ... },
      thumbHover = { ... },
    },
  },
}
```

### `Theme.getColor(name)` → Color

Returns a `Color` instance from the active theme's `colors` table:
```lua
local Color = FlexLove.Color
textColor = Theme.getColor("primary")   -- resolves from active theme
borderColor = Theme.getColor("border")
```

### Metal theme (`themes/metal.lua`)

The built-in theme used in the admin panel. Provides these components:
- `buttonv1`, `framev3` — used in admin layouts
- Button states: normal, hover, pressed, disabled
- Named colors: `primary`, `text`, `background`, `border`, etc.
- 9-patch assets live under `themes/metal/` (PNG files with `.9.png` suffix = 9-patch source images)

## Element API cheat sheet

### Structure / lifecycle

```lua
element:addChild(child)          -- append child (auto-removes from previous parent)
element:removeChild(child)       -- remove child (nil-safe)
element:clearChildren()          -- remove all children
element:setParent(newParent)     -- re-parent
element:destroy()                -- recursively destroy element and all children, GC'able
element:resize(w, h)             -- recalculate layout for new viewport size
```

### State / visibility

```lua
element.disabled = true          -- disable interaction
element:setTreeDisabled(true)    -- recursively disable entire subtree
element.opacity = 0.5            -- 0..1
element.visibility = "hidden"    -- still in layout, not drawn
element:setDisplay(false)        -- removed from layout AND hit-testing (display:none) — auto-invalidates layout
```

### Text

```lua
element.text = "new text"        -- change text
element:updateText("text")       -- change text + trigger auto-resize if autoGrow
element:calculateTextWidth()     -- returns computed text width in px
```

### Scroll

```lua
element.overflow = "scroll"      -- enable scrolling
element:setScrollPosition(0, 100) -- scroll to x,y
element:getScrollPosition()      -- → scrollX, scrollY
element:getMaxScroll()           -- → maxScrollX, maxScrollY
element:scrollToTop()            -- convenience
element:hasOverflow()            -- → hasOverflowX, hasOverflowY
```

### Animation

```lua
local anim = FlexLove.Animation.new({
  duration = 0.3,
  start = { opacity = 0 },
  final = { opacity = 1 },
  easing = "easeOutQuad",
})
element.animation = anim
```

Available easings: `linear`, `easeInQuad`, `easeOutQuad`, `easeInOutQuad`, `easeInCubic`, `easeOutCubic`, `easeInOutCubic`, `easeInQuart`, `easeOutQuart`, `easeInExpo`, `easeOutExpo`.

## Event system

### Mouse events (`onEvent` callback)

```lua
onEvent = function(element, event)
  -- event.type: "hover", "unhover", "press", "release", "click", "doubleClick", "dragStart", "drag", "dragEnd"
  -- event.button: 1 (left), 2 (right), 3 (middle)
  -- event.x, event.y: mouse position
end,
```

- **Click detection** uses internal click count + time threshold (double-click support)
- **Drag** fires `dragStart` on press+move, then `drag` each frame, then `dragEnd` on release
- **Hover** tracks mouse enter/leave via `FlexLove.update(dt)` each frame

### Touch events

```lua
onTouchEvent = function(element, touchEvent) end   -- raw touch
onGesture = function(element, gesture) end          -- recognized gesture ({type="tap"|"swipe"|"pinch", ...})
touchEnabled = true                                 -- default true
```

### Keyboard / navigation

Set `keyboardNavigation = true` in `FlexLove.init()` to enable:
- **Tab / Shift+Tab** — cycle through focusable elements (`tabIndex` prop)
- **Arrow keys** — directional navigation (when `directionalNavigation = true`)
- **Enter / Space** — activate focused element
- **FocusIndicator** — pulsing outline on focused element

### Text input

When `editable = true`:
- `FlexLove.textinput(t)` hooks text entry
- `FlexLove.keypressed(k, sc, r)` hooks arrow keys, backspace, delete, Home/End, Ctrl+A/C/V/X
- Cursor blink, selection, clipboard all handled by `TextEditor` internally

## Scroll management

`ScrollManager` implements:
- **Mouse wheel** scrolling (via `FlexLove.wheelmoved`)
- **Touch scrolling** with momentum (friction + deceleration)
- **Overscroll bounce** (spring physics)
- **Scrollbars** — vertical and horizontal, themed via `scrollBarStyle` or `metal` theme's `scrollbars.default`
- **Scroll position** is accessible via `element._scrollX` / `element._scrollY` (immediate mode) or `_scrollManager._scrollX` (retained)
- **scrollbarPlacement**: `"reserve-space"` (default, pushes content) or `"overlay"` (scrollbar floats over content)

## Blur effects

Two types live in the `Blur` module:
- **`contentBlur`** — blurs element's own rendered content (children included)
- **`backdropBlur`** — blurs the game scene BEHIND the element (glassmorphism)

Both use shader-based Gaussian blur with canvas caching. `backdropBlur` requires passing `gameDrawFunc` to `FlexLove.draw()`:

```lua
FlexLove.draw(function() love.graphics.draw(myGameCanvas) end)
```

## GC management

FlexLove manages Lua GC to avoid frame spikes:

| Strategy | Behavior |
|----------|----------|
| `"auto"` | Small incremental GC step every 5 frames |
| `"periodic"` | Step every `gcInterval` frames with `gcStepSize` units |
| `"manual"` | No automatic GC; call `FlexLove.collectGarbage()` explicitly |
| `"disabled"` | No GC at all (memory will grow unbounded) |

Memory threshold: full `collectgarbage("collect")` when memory exceeds `gcMemoryThreshold` MB.

## Performance monitoring

Built into the `Performance` module, toggled via config key (default `"f3"`):
- FPS + frame-time HUD overlay
- Per-frame timing breakdown
- Memory profiling (Lua heap, GPU texture memory)
- Warning/critical thresholds (configurable)

## Blur effects

Two types live in the `Blur` module:
- **`contentBlur`** — blurs element's own rendered content (children included)
- **`backdropBlur`** — blurs the game scene BEHIND the element (glassmorphism)

Both use shader-based Gaussian blur with canvas caching. `backdropBlur` requires passing `gameDrawFunc` to `FlexLove.draw()`:

```lua
FlexLove.draw(function() love.graphics.draw(myGameCanvas) end)
```

## Hot-reload (`shared/flex_reload.lua`)

A companion utility in this project that wraps any FlexLove layout module for live code-edit:

```lua
local live = require("shared.flex_reload")
local panel = live.wrap("modules.admin.flex.shell")

-- panel is a proxy; live-reload transparent when file changes on disk
panel.opacity = 1
panel:setTreeDisabled(false)
```

`flex_reload.update(dt)` (called every frame in `love.update`) polls `love.filesystem.getInfo().modtime` every ~0.5s. On change:
1. Collects `opacity` + `disabled` from every node keyed by `id`
2. Destroys old tree (`FlexLove.topElements` cleanup)
3. Clears `package.loaded`, re-requires, builds fresh tree
4. Restores saved `opacity`/`disabled` onto matching ids

**Important:** works only for modules that return a **single root element**. The proxy only forwards opaque reads/writes; method calls use `__index` wrapper to pass the real element as `self`.

## Project integration patterns

### init (from `main.lua`)

```lua
local FlexLove = require("flexlove.FlexLove")
FlexLove.init({
  baseScale = { width = 1920, height = 1080 },
  gcStrategy = "auto",
  gcMemoryThreshold = 100,
})

-- Load and activate the metal theme
local metalDef = require("flexlove.themes.metal")
local metalTheme = FlexLove.Theme.new(metalDef)
FlexLove.Theme.setActive(metalTheme)

-- Re-register so other modules can require("libs.FlexLove")
package.loaded["libs.FlexLove"] = FlexLove
```

### Creating layout modules (admin pattern)

Layout modules (e.g., `modules/admin/flex/shell.lua`) follow this pattern:
1. `require("libs.FlexLove")` + `require` `Color`/`Theme`
2. Build elements as file-level locals via `FlexLove.new({ ... })`
3. Return the root element (or a table of named elements)

```lua
-- modules/admin/flex/shell.lua
local FlexLove = require("libs.FlexLove")
local Color = FlexLove.Color
local Theme = FlexLove.Theme

local backdrop = FlexLove.new({
  x = 0, y = 0, width = "100%", height = "100%",
  backgroundColor = Color.new(0, 0, 0, 0.82),
  opacity = 0, disabled = true,
})

local sidebar = FlexLove.new({
  parent = backdrop, width = 240, height = "100%",
  flexDirection = "column", gap = 6,
})

-- ... build tree ...

return { backdrop = backdrop, contentArea = contentArea }
```

### Toggling panels

Use `setDisplay` for show/hide — it pulls the element out of layout / paint / hit-testing in one call and auto-invalidates so the parent reflows:

```lua
panel:setDisplay(true)   -- show
panel:setDisplay(false)  -- hide
```

`opacity`, `disabled` / `setTreeDisabled` are orthogonal — use them for fade animations or interaction gating while keeping the element in layout. Bool initial state at creation time: `display = false` in the props table.

Setting `display = false` (via `setDisplay(false)` or the `display` prop) removes the element from layout and hit-testing entirely, so hidden panels don't block clicks to layers below. `opacity = 0` + `setTreeDisabled(true)` keep the element in layout (e.g., for fade transitions) while making it visually transparent and inert.

### Interop with SE3/scene model

Admin panels use FlexLove `onEvent` callbacks to fire events on `_G.model`:

```lua
onEvent = function(_, event)
  if event.type == "release" and _G.model then
    _G.model:fire("pinDigit", label)
  end
end,
```

FlexLove draws ON TOP of the LÖVE scene graph — `FlexLove.draw()` runs AFTER `manager:draw()` in `love.draw()`.

## What NOT to do

- **Don't call `FlexLove.new()` before `FlexLove.init()`** — it will queue but return `nil`.
- **Don't use 0..255 color values** — all colors must be 0..1 floats. Use `Color.new(r, g, b, a)` or `Color.fromHex("#rrggbb")`.
- **Don't require individual modules directly** from consumer code. Always go through `FlexLove.*` (e.g., `FlexLove.Color.new(...)`, `FlexLove.Theme.getColor(...)`, `FlexLove.Animation.new(...)`).
- **Don't call `FlexLove.draw()` inside a canvas** without releasing the canvas first — deferred callbacks may need to execute canvas-incompatible operations. Execute `FlexLove.executeDeferredCallbacks()` at the very end of `love.draw()` after all canvases are released.
- **Don't forget to wire ALL love.* callbacks** — missing `love.textinput` breaks text editing; missing `love.wheelmoved` breaks scrolling; missing `love.resize` breaks responsive layout.
- **Don't create elements during `FlexLove.draw()`** — element creation should happen in `love.load()` or in response to events, not in the draw loop.
- **Don't rely on manual `element.x = ...` positioning for flex items** — let the flexbox layout engine compute positions. Use `width`/`height`/`flex`/`gap`/`padding` to control layout.
- **Don't confuse `disabled` prop with `setTreeDisabled()`** — `disabled` only affects the single element; `setTreeDisabled(v)` propagates recursively to all children.
- **Don't set `positioning = "absolute"` on top-level elements** unless you want manual `x`/`y` positioning — top-level elements use `positioning = "relative"` by default.
- **Don't mix `require("flexlove.FlexLove")` and `require("libs.FlexLove")` without the `package.loaded` alias** — the project's `main.lua` does `package.loaded["libs.FlexLove"] = FlexLove` so admin modules can use the shorter path.
- **Don't destroy the root element from inside an event handler** — use `FlexLove.deferCallback()` to schedule destruction for after the current draw cycle.
- **Don't set `overflow = "scroll"` on a container that doesn't have constrained dimensions** — `ScrollManager` needs known bounds to calculate overflow.
- **Don't hot-reload a module that returns NOT a single root element** — `flex_reload` expects exactly one FlexLove root from the required module. Tables of elements need a wrapper.
- **Don't forget `FlexLove.destroy()` on scene transitions** — it cleans up `topElements`, canvases, StateManager, caches, and touch state. Without it, memory leaks.
- **Don't call `FlexLove.update(dt)` after `FlexLove.draw()`** — update must precede draw for correct layout + interaction states in the current frame.
