---
name: love2d-se3
description: Build 2D games with Love2D using the SE3 scene-graph engine. Use when starting a new Love2D project, integrating SE3, wiring scenes/FSM/model, loading assets, building UI w/ SButton + flexlove, or writing tween animations with SAnimatedObject.
---

# love2d-se3 — Build 2D games with Love2D + SE3

## When to use this skill

Trigger when the user wants to:
- Init a Love2D project (with or without explicitly naming SE3)
- Add SE3 to an existing Love2D game
- Build scenes, HUDs, buttons, animated sprites, tweens, FSM state machines
- Wire reactive UI w/ SEModel + `$key` bindings
- Set up asset loading (atlases, fonts, sounds, images)
- Add flexlove-based flex layouts

Don't trigger for: pure Love2D w/o SE3 (use plain Love2D), engine-development on SE3 itself.

## Workflow — the decision tree

For any task in a Love2D+SE3 project, walk this tree before writing code:

```
1. Is project initialised?
   ├─ No  → §1 Init
   └─ Yes → 2.
2. Does it need assets (images/atlases/fonts/sounds)?
   ├─ Yes → §2 SLoader + resource global
   └─ No  → 3.
3. Single scene or many?
   ├─ Single → §3 Direct scene
   └─ Many  → §4 SESceneManager + manifests
4. Does logic need state machine?
   ├─ Yes → §5 SEFSM
   └─ No  → 6.
5. UI driven by data?
   ├─ Yes → §6 SEModel + bindings
   └─ No  → 6.
6. Need animated sprites with tweens?
   ├─ Yes → §7 SAnimatedObject
   └─ No  → 7.
7. Layout-driven HUD?
   ├─ Yes → §8 flexlove
   └─ No  → done.
```

## §1 Init — directory layout + bootstrap

A working Love2D+SE3 project looks like:

```
project/
  conf.lua
  main.lua
  libs/
    se3/            (engine + bundled hump + lume + docs)
    flexlove/       (optional: flex layouts)
    inspect.lua     (debug)
    log.lua         (logging)
  assets/
    fonts/
    images/
    sounds/
  modules/          (game code)
```

**`conf.lua`** — minimal:

```lua
function love.conf(t)
  t.identity = "your-game"
  t.version  = "11.5"
  t.window.title  = "Your Game"
  t.window.width  = 1280
  t.window.height = 720
  t.window.resizable = true
  t.console = true   -- Windows console
end
```

**`main.lua` package.path** — required so `require("se3")` resolves from `libs/`:

```lua
local base = love.filesystem.getSource()
package.path = base .. "/libs/?.lua;"
            .. base .. "/libs/?/init.lua;"
            .. base .. "/modules/?.lua;"
            .. base .. "/modules/?/init.lua;"
            .. package.path

require("se3")   -- registers SObject, SSprite, SLoader, etc. as globals
```

After `require("se3")`, these are global: `SObject SGroup SCanvas SShader SText STextObject SRichText SMouseObject SKeyboardObject SSprite SAnimationSprite SStretchedSprite SComplexAnimSprite SButton SSpriteButton SEmptyButton SSoundManager SAtlas SLoader SEEnvironment SEEasings SAnimatedObject SEInputController SEModel SEFSM SEFSMState SESceneLoader SESceneManager SEColor Class Signal lume resource`.

## §2 SLoader — asset pipeline

SLoader builds a queue of assets, then runs through them. Two modes:
- **Blocking** (`loader:loadAll()`) — call in `love.load`, freezes the screen until ready. Fine for tiny games.
- **Incremental** (`loader:step()` per frame) — for progress bars / many assets.

```lua
function love.load()
  resource = SLoader.new()
  resource:addImage("bg",       "assets/images/bg.png")
  resource:addAtlas("assets.ui", "assets/ui/")     -- TexturePacker .lua
  resource:addFont("main",      "assets/fonts/main.ttf", 32)
  resource:addSound("click",    "assets/sfx/click.ogg")
  resource:loadAll()
  buildScene()
end
```

For an incremental loader pattern see `docs/SLoader.md` and `docs/Recipes.md`.

`resource` is the magic global every SE3 class consults — `SSprite{img="bg"}` calls `resource:get("bg")`. Replace via `SEEnvironment` if you need scoped resource layering (common for scene-local atlases on top of a global font).

## §3 Direct scene — single-screen games

```lua
local scene

function buildScene()
  scene = SGroup{
    SSprite{ img = "bg", x = 0, y = 0, pivot = {0,0} },
    SText{ font = "main", text = "Hello SE3!", x = 100, y = 100 },
    SSpriteButton{
      x = 300, y = 500,
      states = { release="btn_norm", over="btn_hover", press="btn_press" },
      event  = function() print("clicked!") end,
      font   = "main", text = "Play",
      keys   = {"space"},
    },
  }
end

function love.update(dt)            scene:__update(dt) end
function love.draw()                scene:__draw() end
function love.mousemoved(x,y,dx,dy,t) scene:__mousemoved(x,y,dx,dy,t) end
function love.mousepressed(x,y,b,t)   scene:__mousepressed(x,y,b,t) end
function love.mousereleased(x,y,b,t)  scene:__mousereleased(x,y,b,t) end
function love.keypressed(k,s,r)       scene:__keypressed(k,s,r) end
function love.keyreleased(k)          scene:__keyreleased(k) end
```

Read `docs/SObject.md` for props-table convention + transform rules; `docs/SSprite.md` for sprite specifics; `docs/SButton.md` for button states & fallback chain; `docs/SText.md` for text + STextObject mixin.

## §4 SESceneManager — multi-scene routing

When a game has Title → Game → GameOver type flow, declarative scene manifests + `SESceneManager` keep main.lua thin.

- Each scene = a `scene_description.lua` returning `{ resources=..., controller=..., model=..., fsm=..., scene={...} }`.
- Register paths once: `manager:register("title", "scenes.title.scene_description")`.
- Switch: `manager:change("game", { player_name = name })`.

Read `docs/SESceneLoader.md` (manifest format, prefabs, `@`-refs, prefixes) + `docs/SESceneManager.md` (states: idle/loading/active, event forwarding, controller hooks).

## §5 SEFSM — per-scene state machine

States as classes extending `SEFSMState`, registered by require path. Auto-binds via magic method names:

- `onModel_<key>(v, k)` — subscribes to model KV change
- `onEvent_<name>(...)` — subscribes to model event channel (e.g. button click fires `ui_play`, handler is `onEvent_ui_play`)
- `onUI(name, ...)` — catch-all for ui events (without `ui_` prefix in name)
- `once(dt, fn)` / `every(dt, fn)` — per-state timers, dropped on exit
- `:to(name)` / `:back()` — transitions, full history stack

Read `docs/SEFSM.md` for lifecycle + auto-bind scan rules.

## §6 SEModel — reactive data

Per-scene model instance + optional `globalModel` singleton. Flat-key reactive dict:

```lua
model:set("balance", 100)
model:subscribe("balance", function(v) hud_balance:setText(tostring(v)) end)
node:bind(model, "balance", "setText")  -- same, owned by node
```

In manifests, `$key` does this declaratively:

```lua
SText{ font = "main", text = "$balance" }   -- live bind to model.balance
SText{ font = "main", text = "$?balance" }  -- skipNil
SText{ font = "main", text = "$$message" }  -- globalModel
```

Subclass `SEModel` to add `override_Foo(new, cur)` validators + `bind_Foo(v)` auto-subscribers. Read `docs/SEModel.md`.

## §7 SAnimatedObject — animation state machine

`SAnimatedObject` wraps a sprite in a named-state machine. Each state declares frames + transforms + optional tween scripts.

```lua
local hero = SAnimatedObject{
  x = 300, y = 300, defaultState = "idle",
  states = {
    idle = "hero_idle",
    walk = {"hero_walk_1","hero_walk_2"},
    hit  = { frames={"hero_hit_1","hero_hit_2"}, loop=false, next="idle" },
    win  = {
      frames = {"hero_win"}, loop=false,
      scripts = {
        {"easyng", 0.15, "outBack", { scale = {from=1, to=1.3} }},
        {"wait",   0.3,             { sx=1.3, sy=1.3 }},
        {"easyng", 0.15,            { scale = {from=1.3, to=1} }},
      },
      onScriptsEnd = function(self) self:setState("idle") end,
    },
  },
}
hero:setState("walk")
```

Step types: `wait`, `easyng` (tween), `custom`, `shake`. Tween param keys: `scale`, `scaleX`, `scaleY`, `rotate`, `x`, `y`, `color`, `colorA`/`alpha`. Easings: full Penner set (`linear`, `inQuad`/`outQuad`/`inOutQuad`, same for Cubic/Quart/Quint/Sine/Expo/Circ/Elastic/Back/Bounce).

Read `docs/SAnimatedObject.md` for the full state def + custom script-types.

## §8 flexlove — flex layouts

`libs/flexlove/FlexLove.lua` provides flexbox-style layouts in Love2D. Use for HUDs that need responsive layout:

```lua
local Flex = require("flexlove.FlexLove")
local hud = Flex.new({
  direction = "column", padding = 16, gap = 12,
  width = 320, x = 1600, y = 0, height = 1080,
  children = { ... },
})
```

Read `libs/flexlove/README.md` for the full API. For SE3 integration, host the Flex root inside an `SGroup` and forward `:update(dt)` + `:draw()` in your scene controller.

## Conventions you MUST follow

1. **Single props table.** Every SE3 class takes `Class{key=val, ...}`. The array part is children. Never use positional args.
2. **Colors 0..1.** `{1,1,1,1}` is white, `{0,0,0,0}` is transparent. HEX strings (`"#ffcc00"`, `"#f80"`, `"#ffcc0080"`) accepted everywhere — parsed by `SEColor.parse`.
3. **Property access.** Don't poke `node.x = 10` after construction — use `node:setX(10)` (nil-tolerant). For composite values (color, pos) the setters do extra bookkeeping.
4. **Z-ordering.** Only inside `SGroup`. Children get `.z` field; lower z = drawn first (back). Plain `SObject` containers walk insertion order.
5. **`.off` vs `.eventoff` vs `.hidden`.** `off` = skip draw + events for whole subtree. `eventoff` = events only. `hidden` = honoured by SSprite/SText only (skip own draw); for groups use `off`.
6. **Bootstrap order.** `require("se3")` BEFORE creating any SE3 instance. `resource` global must exist before sprites construct (SLoader.new() sets it as you build).
7. **Event method naming.** `__eventname` = internal propagation; `eventname` = user-overridable. Don't override `__mousemoved` — override `mousemoved`.

## Common pitfalls

- **Forgetting `pivot = {0,0}`** on background sprites: defaults to `{0.5,0.5}`, so a bg drawn at `x=0,y=0` ends up centred at origin and clipped to a quarter.
- **Calling `:setState` before assets loaded**: SE3 expects `resource:get(name)` to resolve. If you build sprites in `love.load` before `loader:loadAll()`, they get nil textures.
- **Animation doesn't start**: `SAnimationSprite` and `SAnimatedObject` need `:loop()` or `:play()` called explicitly. Frames defined in props table do NOT autoplay.
- **Module global names**: SE3 dumps everything into `_G`. If a host module already defined `SObject` etc., it gets shadowed silently.
- **Cyrillic comments inside se3 .lua**: many SE3 files have Russian comments. Don't think they're broken — engine is fully working.

## Decision shortcuts

| If you need to... | Use |
|-------------------|-----|
| Static image | `SSprite{ img = "..." }` |
| Stretchable image (9-slice-ish, not real 9-slice) | `SStretchedSprite{ img="...", scaleX=2, scaleY=1 }` |
| Frame animation | `SAnimationSprite{ sequence={"f1","f2"}, delay=1/12 }:loop()` |
| Multi-state animated character | `SAnimatedObject{ states = {...} }` |
| Clickable | `SSpriteButton{ states={release="...",over="...",press="..."}, event=fn }` |
| Invisible clickable | `SEmptyButton{ x=..., y=..., w=..., h=..., event=fn }` |
| Plain text | `SText{ font="main", text="...", color={1,1,0,1} }` |
| Mouse hit area | `SMouseObject` mixin + `setCollider(fn)` for non-rect |
| Tween a value | `SAnimatedObject`'s script steps OR `SEEasings` directly |
| Keyboard handler | `SKeyboardObject` mixin + `self.keys={"space"}` |
| Multi-key actions | `SEInputController` |
| Reactive HUD | `SEModel` + `$key` in manifest |
| FSM logic | `SEFSM` + `SEFSMState` subclasses |
| Multi-scene game | `SESceneManager` + manifest per scene |
| Custom drawing | extend `SObject`, override `draw(x,y,r,sx,sy,tx,ty)` |
| Z-sorted child | extend `SObject`, implement `cacheCoords(x,y,r,sx,sy,tx,ty)`, parent must be `SGroup` |

## Bundled reference docs

`docs/` contains the full SE3 docs. Read them on demand — don't try to memorise:

- `Architecture.md` — engine overview
- `CustomPreloader.md` — replacing the default loader
- `Debugging.md` — common issues + tools
- `EventPropagation.md` — input flow + early-out semantics
- `Inheritance.md` — Class{}/__includes patterns
- `Performance.md` — z-ordering, cached-coords, draw batching
- `Recipes.md` — common patterns (typewriter, modals, screen shake, scroll lists, ...)
- `SAnimatedObject.md` — full state machine def + script types
- `SButton.md` — state machine + sprite swap
- `SEFSM.md` — per-scene FSM details
- `SEInputController.md` — named-action input
- `SEModel.md` — reactive model + bindings
- `SESceneLoader.md` — manifest format
- `SESceneManager.md` — multi-scene router
- `SLoader.md` — asset loading (blocking + incremental)
- `SObject.md` — base class, transforms, events
- `SSprite.md` — atlas + image sprites
- `SSound_SShader_SAtlas.md` — secondary classes
- `SText.md` — text + STextObject
- `Signals.md` — engine-wide signal table
- `Recipes.md` — patterns

When working on a component, **read `docs/<ComponentName>.md` first**. Don't reinvent — SE3 already has the building block.

## Smoke-test before claiming done

After scaffolding, run `love .` in the project dir. Verify:
- Window opens at declared resolution
- No `[ERROR]` lines in console
- One or two visible elements

If the user reports a UI / rendering bug, reproduce in `love .` before guessing.
