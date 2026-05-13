# CLAUDE.md

## Running

```bash
love .              # launch; Esc quits
luac -p <file>      # syntax check (no test suite)
```

Love2D 11.5. No tests, no lint, no build — runs directly from source.

## What this is

`FarmBots` prototype: RTS-flavoured farm. Player plants/harvests by hand; autonomous robots till, water, weed, and Replant (auto-harvest + restart growing). Crops have Mendelian genetics (yield/growTime/color alleles); a stick on a tile breeds two adjacent ripe crops into a hybrid that germinates on the stick.

## Bootstrap

1. `conf.lua` — 1920×1080 windowed, identity `farmbots`.
2. `main.lua` — extends `package.path` with `libs/` and `modules/`, requires `se3` (exposes `SObject`, `SLoader`, `Class`, `Signal`, …) and `love_mcp` (dev tool, port 21110), then delegates Love callbacks to `Farm.*`. Also takes a `127.0.0.1:21199` socket lock to prevent double-launch.
3. `modules/farm.lua` — entry point. Owns drawing, HUD layout, input dispatch.

## Module split (`modules/farm/`)

| File | Responsibility |
|------|----------------|
| `constants.lua` | All tunables: grid, costs, work times, emoji palette, dominance ladder, mutation rate, water gates, robot names, fertilizers, save schema. **Edit here first** when changing gameplay numbers. |
| `state.lua` | Mutable singleton: `tiles`, `robots`, `seeds`, `money`, popups, toggle states (`stickMode`, `digToggle`, `fertMode`, `restrictMode`, `selectedSeedId`), fertilizer inventory, modal/dropdown state. Helpers for coord conversion, seed/robot creation, fertilizer math, toggle ops. |
| `genetics.lua` | Pure Mendel: `baseGenome`, `cloneGenome`, `phenotype`, `cross` (random allele per slot + 3% mutation). |
| `sim.lua` | Per-tick robot AI + world tickers. `findRobotJob` (claim-aware), `tickCrops`, `tickWeeds` (wild only), `tickBreeding` (stick + ≥2 ripe neighbors → hybrid). `SIM_SPEED` scales `dt` globally. |
| `harvest.lua` | Player harvest (LMB on ripe): ripe→tilled, drops 1–2 cloned seeds + money. The robot `Replant` task in `sim.lua` is different — instant money + reset to growing, no seeds. |
| `save.lua` | Persistent save/load with autosave. Schema-versioned via `C.SAVE_SCHEMA`; mismatch starts fresh. |
| `modals.lua` | Immediate-mode overlays drawn with Love2D primitives (not FlexLove): bestiary, reset-confirm. Driven by `State.openModal`. |
| `sounds.lua` | Procedurally generated tones. `Sounds.muted` toggle. |

## Tile state machine

```
wild ──Till─→ tilled ──player plant──→ growing ──auto──→ ripe
                │                          ↑               │
                ↓                          │               ├─ player Harvest → tilled (+seeds, +money)
              stick ──≥2 ripe neighbors────┘               └─ robot Replant   → growing (+money only)
                       cross genomes
any → wild   (shovel/dig toggle)
```

- `growing → ripe` is gated by `crop.water > WATER_GROW_GATE`.
- Weeds spawn on `wild` only; the `Weed` robot task clears them.
- `tile.restrict` (set by `restrictMode` player toggle) blocks `Replant`.
- Robots get a primary `task` + fallback `task2`. They claim target tiles via `workTile` — `findRobotJob` consults this claim set, so any new task type must respect it.

## Input model

Toggle-based, not mode-based. Player clicks an action-bar button to activate a toggle (stick / fertilizer / shovel / restrict) or selects a seed, then LMB on a tile applies it. With no toggle active, LMB does the contextually-correct thing: harvest a ripe tile, plant the selected seed on a tilled tile. MMB queues the nearest robot for a tile. RMB cancels the active toggle. `State.clearModes()` resets all toggles.

## SE3 engine

`libs/se3/` is a bundled scene-graph engine — see `libs/se3/CLAUDE.md` and the global skill at `.claude/skills/love2d-se3/` for the full API. Current draw path uses Love2D primitives directly; SE3 is loaded but only its bootstrap runs. When adding scenes, FSM, reactive UI, or animated sprites, **read `libs/se3/docs/*.md` first**.

Spine modules (`sespineplayer`/`seanimatedspine`/`sespineatlas`) were stripped. `vendor/sysl-text` is kept (required by `serichtext`). `seloader.lua` was patched to `pcall` the spine atlas import lazily.

## Emoji font caveat

`assets/fonts/NotoColorEmoji.ttf` is a **CBDT bitmap font** — FreeType only accepts its native strike size `EMOJI_NATIVE = 109`. Loaded once in `farm.lua` and scaled at draw time. Any other load size errors with `FT_Set_Pixel_Sizes failed`. Don't change.

The default Love2D UI font (TTF outlines) cannot render emoji glyphs — emoji go through `fontEmoji*`, text through `fontUI*`.

## Dev tool — love_mcp

`libs/love_mcp.lua` + `libs/love_mcp/` is a Model Context Protocol bridge: with the game running, an MCP server on `127.0.0.1:21110` exposes Lua exec, state inspection, screenshots, input injection, hot reload, pause/step. Initialised in `main.lua:love.load`. Server source lives outside the repo at `~/.local/share/love2d-mcp-src`; register with `claude mcp add love2d node <path>/server/dist/index.js`.

## Pitfalls

- **Tuning numbers**: edit `modules/farm/constants.lua`, not call sites. `SIM_SPEED` in `sim.lua` is the global time scaler.
- **HUD buttons**: `hudButtons` is rebuilt every frame in `rebuildHudButtons`. Don't cache refs across frames; identify by `b.id`.
- **Robot job claiming**: `findRobotJob` builds a `claimed` set from other robots' `workTile`. A new task type must respect this set or two robots will fight over one tile.
- **Coords**: tile space is 1-indexed `(tx, ty)`. Robot positions `r.px, r.py` are floating tile coords. Convert via `State.tileToScreen` / `State.tileCenter` / `State.screenToTile`.
- **Toggles, not modes**: there is no single `mode` field. State is a set of independent toggles (`stickMode`, `digToggle`, `fertMode`, `restrictMode`) plus `selectedSeedId`.
- **Save schema**: changing the snapshot shape (`snapshotTiles`/`snapshotSeeds`/`snapshotRobots` in `save.lua`) requires bumping `C.SAVE_SCHEMA` — otherwise old saves silently load with the wrong shape.
