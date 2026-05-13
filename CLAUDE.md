# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running

```bash
love .              # launch the game; Esc quits
luac -p <file>      # syntax-check a single Lua file (no test suite exists)
```

There are no automated tests, linters, or build steps — this is a Love2D 11.5 project that runs directly from source.

## Architecture

This is a `FarmBots` prototype: an RTS-flavoured farm where the player plants/harvests crops by hand and autonomous robots handle tilling, watering, and weeding. Crops have Mendelian genetics (yield/growTime/color alleles) and a player-placed stick on a tile breeds two adjacent ripe crops into a hybrid that germinates on the stick's tile.

### Bootstrap chain

1. `conf.lua` — Love window/identity config (1920×1080, windowed, identity "farmbots").
2. `main.lua` — extends `package.path` to resolve from `libs/` and `modules/`, `require("se3")` (the bundled scene-graph engine, exposes globals like `SObject`, `SLoader`, `Class`, `Signal`, ...), `require("love_mcp")` (dev tool, port 21110), then delegates every Love callback to `Farm.*`.
3. `modules/farm.lua` — entry point. Owns rendering, HUD layout, input dispatch.

### Module split (`modules/farm/`)

| File           | Responsibility |
|----------------|----------------|
| `constants.lua` | All tunables: grid size, costs, work times, emoji palette, dominance ladder, mutation rate, water drain/refill gates, robot names. Edit here first when changing gameplay numbers. |
| `state.lua`     | Mutable game state singleton: `tiles` grid, `robots`, `seeds`, `money`, `mode`, helpers (`tileAt`, `screenToTile`, `tileCenter`, `addSeed`, `removeSeed`, `nextRobotCost`, `nextSeedCost`, `newRobot` with unique-name picker). |
| `genetics.lua`  | Pure Mendel logic: `baseGenome`, `cloneGenome`, `phenotype` (avg numeric alleles + min-index dominance for color), `cross` (random allele per slot + 3% mutation per stat). |
| `sim.lua`       | Per-tick robot AI + world tickers. `findRobotJob` (closest matching tile, claims tracked across robots to prevent double-targeting), `pickClosestEmpty` (idle robots walk to nearest wild/tilled tile and stop), `tickCrops`, `tickWeeds` (spawns on wild only), `tickBreeding` (stick tile w/ ≥2 ripe neighbors → hybrid germinates, stick consumed). `SIM_SPEED` constant scales `dt` for the whole sim. |
| `harvest.lua`   | Player-only harvest: ripe→tilled, drops 1–2 cloned seeds + money. Robots never harvest. |
| `farm.lua`      | Draw (tiles/crops/robots/sticks/HUD), font loading, HUD button registry (rebuilt every frame in `rebuildHudButtons`), `pickHover` + `mousepressed` mode dispatch. Modes: `plant`/`harvest`/`stick`/`delete`. |

### Tile state machine

`wild → tilled` (Till robot)
`tilled → growing` (player Plant mode places selected seed)
`growing → ripe` (auto via `tickCrops` once growth ≥ 1, gated by water > `WATER_GROW_GATE`)
`ripe → tilled` (player Harvest mode; drops seeds + money)
`tilled → stick` (player Stick mode, costs `STICK_COST`)
`stick → growing` (auto when ≥2 ripe neighbors; cross their genomes)
any → `wild` (player Dig up mode)

Weeds spawn only on `wild` tiles. Robots with the `Weed` task remove them.

## SE3 engine integration

`libs/se3/` is a bundled scene-graph engine (independent project, see `libs/se3/CLAUDE.md` for its full contract). The prototype's draw path uses Love2D primitives directly (rectangles + emoji text rendering) rather than SE3 nodes — SE3 is loaded for future expansion but currently only its bootstrap path is exercised. When adding scenes, FSM, reactive UI, or animated sprites, **read `libs/se3/docs/*.md` first** and use the SE3 classes (`SObject`, `SGroup`, `SSprite`, `SAnimatedObject`, `SESceneManager`, etc.).

Spine modules (`sespineplayer`/`seanimatedspine`/`sespineatlas`) were stripped from this bundle. `vendor/sysl-text` is kept (required by `serichtext`). `seloader.lua` was patched to `pcall` the spine atlas import lazily.

A global skill at `.claude/skills/love2d-se3/` documents the SE3 API + workflow — it's the canonical reference for engine-level questions.

## Emoji font caveat

`assets/fonts/NotoColorEmoji.ttf` is a **CBDT bitmap font**. FreeType only loads its native strike size (109 px). `farm.lua` loads it once at `EMOJI_NATIVE = 109` and uses Love's draw-time scale to render at smaller sizes. Loading it at any other size errors with `FT_Set_Pixel_Sizes failed`. Don't change this.

The default Love2D UI font (TTF outlines) cannot render emoji glyphs — keep emoji in `fontEmoji*` draws and plain text in `fontUI*` draws.

## Dev tool — love_mcp

`libs/love_mcp.lua` + `libs/love_mcp/` is a Model Context Protocol bridge: when the game is running, an MCP server on `127.0.0.1:21110` exposes Lua execution, state inspection, screenshots, input injection, hot reload, and pause/step to AI agents. Initialised in `main.lua:love.load`. Server source lives outside the repo at `~/.local/share/love2d-mcp-src`; register it in Claude Code with `claude mcp add love2d node <path>/server/dist/index.js`.

## Common pitfalls

- **Tuning numbers**: change `modules/farm/constants.lua`, not the call sites. `SIM_SPEED` in `sim.lua` is the global time scaler.
- **HUD buttons**: `hudButtons` is rebuilt every frame in `rebuildHudButtons`. Don't cache references across frames; identify by `b.id` if you need state.
- **Robot job claiming**: `findRobotJob` builds a `claimed` set from other robots' `workTile` to prevent two robots targeting the same tile. If you add a new task type, the matcher must respect this set.
- **Coords**: tile space uses 1-indexed `(tx, ty)`. Robot positions `r.px, r.py` are floating tile coords. Convert via `State.tileToScreen` / `State.tileCenter` / `State.screenToTile`.
