# CLAUDE.md

## Running

```bash
love .              # launch; Esc quits
luac -p <file>      # syntax check (no test suite)
```

Love2D 11.5. No tests, no lint, no build — runs directly from source.

## What this is

`FarmBots` prototype: RTS-flavoured farm. Player plants/harvests by hand; autonomous robots till, plant, water, weed, and harvest. Crops have minimal genetics (color + tier alleles); cross-breeding is done with **breeders** — a 3-wide structure where the player assigns a crop to each parent slot and the middle tile receives a hybrid once both parents ripen. Harvests yield a random quantity per tier (E ≈ 1.25 avg, S ≈ 6 avg).

## Bootstrap

1. `conf.lua` — 1920×1080 windowed, identity `farmbots`.
2. `main.lua` — extends `package.path` with `libs/` and `modules/`, requires `love_mcp` (dev tool, port 21110) on desktop, then delegates Love callbacks to `Farm.*`. On desktop it also takes a `127.0.0.1:21199` socket lock to prevent double-launch; both the lock and MCP are skipped on web (love.js) builds.
3. `modules/farm.lua` — entry point. Owns drawing, HUD layout, input dispatch.

## Module split (`modules/farm/`)

| File | Responsibility |
|------|----------------|
| `constants.lua` | All tunables: grid, costs, work times, emoji palette, breeder cost curve, yield-tier distributions, water gates, robot names, fertilizers, save schema. **Edit here first** when changing gameplay numbers. |
| `state.lua` | Mutable singleton: `tiles`, `robots`, `crops` (stacked by `[cropIdx][tier]=count`), `money`, popups, toggle states (`breederMode`, `digToggle`, `fertMode`, `selectedCropIdx`/`selectedCropTier`), fertilizer inventory, `breeders` registry (id → tile coords), modal/dropdown state. Helpers for coord conversion, robot creation, fertilizer math, breeder placement/teardown. |
| `genetics.lua` | `baseGenome`, `phenotype` (computes `price = BASE_PRICE × priceMult`, `growTime` by tier), `cross` (random allele per slot, may upgrade tier), `rollHarvestQty(cropIdx, tier)` rolls quantity using `YIELD_TIER_DIST`. |
| `sim.lua` | Per-tick robot AI + world tickers. `findRobotJob` (claim-aware), `tickCrops` (fires `tryBreedAtStructure` on parent-tile ripen), `tickWeeds` (wild/tilled/breeder tiles). `SIM_SPEED` scales `dt` globally. |
| `save.lua` | Persistent save/load with autosave. Schema-versioned via `C.SAVE_SCHEMA`; mismatch starts fresh. |
| `modals.lua` | Immediate-mode overlays drawn with Love2D primitives (not FlexLove): bestiary, reset-confirm. Driven by `State.openModal`. |
| `sounds.lua` | Procedurally generated tones. `Sounds.muted` toggle. |

## Tile state machine

```
wild ──Till─→ tilled ──player or robot plant──→ growing ──auto──→ ripe
                                                                    │
                                                                    └─ Harvest → tilled (+ rolled qty)

Breeder structure (3 horizontal tiles, anchored at center):
  left + right are normal tilled/growing/ripe tiles BUT carry tile.parentSlot = { crop = cropIdx }
  middle has state="breeder" while empty; on both parents ripening,
  cross genomes, consume parents (→ tilled), middle gets hybrid (→ growing).
  After middle is harvested it returns to "breeder" (structure persists).
any → wild   (shovel/dig toggle; Dig on any breeder tile tears down whole structure, no refund)
```

- `growing → ripe` is gated by `crop.water > WATER_GROW_GATE`.
- Weeds spawn on `wild` / `tilled` / `breeder` tiles; the `Weed` robot task clears them. Weeding a breeder tile re-checks the cross trigger via `tryBreedAtStructure`.
- Parent slots are non-harvestable by Plant/Harvest robots. The Plant task respects `tile.parentSlot.crop` as authoritative; robots with `plantCrop = nil` or matching crop will service the slot.
- Harvest yield is rolled per ripe-tile via `Genetics.rollHarvestQty(cropIdx, tier)`. Price (`BASE_PRICE × priceMult`) is per-unit and tier-independent.
- Robots get a primary `task` + fallback `task2`. They claim target tiles via `workTile` — `findRobotJob` consults this claim set, so any new task type must respect it.

## Input model

Toggle-based, not mode-based. Player clicks an action-bar button to activate a toggle (breeder / fertilizer / shovel) or selects a crop from the inventory list, then LMB on a tile applies it. With no toggle active, LMB does the contextually-correct thing: harvest a ripe tile, plant the selected crop on a tilled tile, open the crop-assignment dropdown on an empty parent slot. MMB always queues the nearest robot for a tile. RMB cancels the active toggle/selection if one is active, otherwise queues the nearest robot (so web users without a middle mouse button can still queue). `State.clearModes()` resets all toggles + crop selection.

## Emoji font

`assets/fonts/NotoEmoji-Regular.ttf` is a monochrome TrueType outline emoji font. Loaded once at `EMOJI_NATIVE = 109` in `farm.lua` and scaled at draw time. Outlines render solid black, then `drawCenteredEmojiTinted` colours them per glyph — so every emoji is a single tinted shape, not multicolour. (Color emoji via `NotoColorEmoji.ttf` was dropped because it's a CBDT bitmap font and love.js's bundled FreeType lacks PNG/CBDT support, failing with `FT_Load_Glyph 0x07` on web.)

The default Love2D UI font (TTF outlines) cannot render emoji glyphs — emoji go through `fontEmoji*`, text through `fontUI*`.

## Dev tool — love_mcp

`libs/love_mcp.lua` + `libs/love_mcp/` is a Model Context Protocol bridge: with the game running, an MCP server on `127.0.0.1:21110` exposes Lua exec, state inspection, screenshots, input injection, hot reload, pause/step. Initialised in `main.lua:love.load`. Server source lives outside the repo at `~/.local/share/love2d-mcp-src`; register with `claude mcp add love2d node <path>/server/dist/index.js`.

## Pitfalls

- **Tuning numbers**: edit `modules/farm/constants.lua`, not call sites. `SIM_SPEED` in `sim.lua` is the global time scaler.
- **HUD buttons**: `hudButtons` is rebuilt every frame in `rebuildHudButtons`. Don't cache refs across frames; identify by `b.id`.
- **Robot job claiming**: `findRobotJob` builds a `claimed` set from other robots' `workTile`. A new task type must respect this set or two robots will fight over one tile.
- **Coords**: tile space is 1-indexed `(tx, ty)`. Robot positions `r.px, r.py` are floating tile coords. Convert via `State.tileToScreen` / `State.tileCenter` / `State.screenToTile`.
- **Toggles, not modes**: there is no single `mode` field. State is a set of independent toggles (`breederMode`, `digToggle`, `fertMode`) plus `selectedCropIdx` / `selectedCropTier`.
- **Breeder structure**: tracked in `State.breeders[id] = { leftX, leftY, midX, midY, rightX, rightY }`. Tiles in a structure carry `tile.breederId`, `tile.breederRole`, and (parents) `tile.parentSlot = { crop }`, (middle) `tile.breederMiddle = true`. Cost scales as `BREEDER_BASE_COST * BREEDER_COST_EXP^n` where `n` counts active + queued placements.
- **Save schema**: changing the snapshot shape (`snapshotTiles`/`snapshotRobots`/`snapshotBreeders` in `save.lua`) requires bumping `C.SAVE_SCHEMA` — otherwise old saves silently load with the wrong shape.
