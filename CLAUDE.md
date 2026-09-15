# Calima: Flames of the Atlantic — CLAUDE.md

## Project Overview

An Age of Empires II inspired 2D real-time strategy game built in **Godot 4** with GDScript.

- **Engine**: Godot 4.6+ — **Language**: GDScript only (no C#) — **Genre**: 2D RTS, top-down isometric-style
- **Scope**: skirmish vs AI, 4-mission campaign, 8 civilizations, LAN/Internet multiplayer (host-authoritative), replays. **Status: production-ready.**
- Resources (AoE2 style): Food (farms/hunt/fish/berries), Wood, Gold, Stone
- Ages: `GameManager.Age` enum — `DARK=0`, `FEUDAL=1`, `CASTLE=2`, `IMPERIAL=3`

## Repository Layout

```
project/          ← Open this in Godot editor (contains project.godot)
  assets/         ← Art, audio, fonts, shaders
  scenes/         ← .tscn scene files
  scripts/        ← .gd source files
    core/         ← Singletons: GameManager, EventBus, ResourceManager, SelectionManager, CivBonusManager, TechManager
    units/        ← UnitBase, Villager, military unit classes
    buildings/    ← BuildingBase and specific building scripts
    economy/      ← ResourceNode, drop-off logic
    map/          ← MapGenerator + its modules (TerrainPainter, EntityPlacer,
                    NavMeshBuilder, MapMaterials, TerrainDetail, ResourceVisuals),
                    FogOfWar, PlacementGrid, terrain overlays
    combat/       ← Projectiles, damage calculation
    ai/           ← AIPlayer coordinator + AIConstruction, AIEconomy, AIMilitary, AINaval modules
    research/     ← TechTree, ResearchQueue
    ui/           ← HUD, menus, minimap
    multiplayer/  ← NetworkSession, StateReplicator, ReplayFile
    utils/        ← Shared helpers
  resources/      ← .tres/.res data files (CivilizationResource, UnitResource, etc.)
tests/            ← GUT unit and integration tests
docs/             ← Architecture and design documentation (publishable static site)
```

## Core Architecture Principles

1. **EventBus pattern** — cross-system communication happens exclusively through signals on `EventBus` (autoload). Never call methods across system boundaries directly.
2. **Data-driven resources** — all tuneable values live in `Resource` subclasses under `resources/`. Scripts read from resources; they do not hardcode stats.
3. **Autoloads (singletons)**: `GameManager`, `EventBus`, `EntityRegistry`, `CommandBus`, `MatchRng`, `NetworkSession`, `ResourceManager`, `SelectionManager`, `CivBonusManager`, `TechManager`, `WeatherManager`, `AgeManager`, `AudioManager`, `TerrainManager`, `PopulationManager`, `SaveManager`, `GameSettings`, `MatchConfig`, `CampaignManager` — access by name anywhere.
4. **Type hints everywhere** — every GDScript function declares parameter types and return type.
5. **Area2D for range detection** — attack ranges use Area2D monitoring, never per-frame physics queries.
6. **Outward spiral spawn positioning** — units spawn at free positions found via outward spiral physics query.
7. **Grid-snap placement** — player building/wall placement snaps to a 16 px grid via `PlacementGrid` (pure/testable); Alt = free placement. AI placement unchanged.
8. **Collision layers** — layer 1 = world (buildings, scenery, walls); layer 2 = units (all CharacterBody2D units/animals/ships). Units use `collision_layer=2, collision_mask=1`: physics collides them only with the world — RVO, not physics, separates units. Detection Area2Ds and unit-seeking queries must include bit 2. Locked by `test_collision_layers.gd`.
9. **Command pattern** — every simulation-mutating intent, player AND AI, is a `GameCommand` (serializable: EntityRegistry IDs + positions, never node pointers) through `CommandBus.submit()`, tick-stamped into the match log. UI feedback and selection stay at the submission site.
10. **MatchRng for simulation randomness** — anything random that affects game state draws from the `MatchRng` autoload (seeded per match). Global `randf()`/`randi()` are reserved for local-only audio/visual noise.

## Key Files

One line per file. **Long-form notes (constants, bug history, rationale): `docs/architecture/key_files.md`. Per-system design: `docs/architecture/systems.md`.**

| File | Purpose |
|---|---|
| **Core Systems** ||
| `core/game_manager.gd` | Global state, pause, game-over, victory conditions (Conquest/Regicide/Wonder) |
| `core/event_bus.gd` | All cross-system signals |
| `core/resource_manager.gd` | Per-player stockpiles, spatial resource cache |
| `core/selection_manager.gd` | Unit selection, control groups |
| `core/age_manager.gd` | Per-player Age tracking, advance timer, cost multipliers |
| `core/civ_bonus_manager.gd` | Per-player stat/cost/gather multipliers from civ bonuses + techs |
| `core/tech_manager.gd` | Per-building research queues (paid at enqueue, full refund on cancel), applies tech effects |
| `core/weather_manager.gd` | Procedural weather state machine + stat-modifier query API |
| `core/population_manager.gd` | Per-player population current/cap |
| `core/save_manager.gd` | JSON save/load, 99 slots, `SCHEMA_VERSION` 2 read-enforced; `save_game` is a coroutine — await it |
| `core/match_config.gd` | Lobby settings (map, resources, civs, victory, weather) |
| `core/terrain_manager.gd` | Terrain type/passability/speed queries (amphibious-aware); memoized `distance_to_coast` (hot path) |
| `core/audio_manager.gd` | ALL sfx/music/voices procedurally baked at startup (zero audio assets); see `docs/architecture/audio_synthesis.md` |
| `core/game_settings.gd` | Persisted settings; `unit_style` CLASSIC/ENHANCED/REDESIGNED with live re-dress signal |
| `core/command_bus.gd` | Single entry point for commands: tick-stamped log, `submit`/`command_from_dict`/`save_log`; bound per match via `start_match(world)` |
| `core/entity_registry.gd` | Stable per-match numeric IDs for units/buildings/resource nodes |
| `core/match_rng.gd` | The single seeded simulation RNG stream |
| `multiplayer/network_session.gd` | Host-authoritative ENet session: lobby, client→host command pipe with wire hardening, version guard, save/resume. Tag releases ONLY with `scripts/release_tag.sh` |
| `multiplayer/state_replicator.gd` | Host→client state stream at 15 Hz, puppet mirror worlds, full resync for rejoin/resume |
| `multiplayer/replay_file.gd` | Replay recording/playback (zstd snapshot stream, never re-simulates) |
| **Campaign** ||
| `campaign/*`, `ui/campaign_screen.gd` | `CampaignData` const mission table; `CampaignManager` progress + launch; `MissionDirector` in-match objectives/waves; mission selector UI |
| **Units** ||
| `units/unit_base.gd` | Base class: canonical combat state machine — leaf units override its hooks, NEVER copy the machine; stances, idle acquisition, RVO tuning, sea-containment veto |
| `units/villager.gd` | Gathering, building, repair |
| `units/healer_unit.gd` | Harimaguada healer (Temple, Castle Age; always female, never fights, auto-triage) |
| `units/presa_canario.gd` | Herding dog (Mill, Dark Age; fetch-and-lead, shepherd's yield, guard bite) |
| `units/hero_unit.gd` | 16 named heroes (2 per civ), unique abilities |
| `units/militia.gd` → `man_at_arms.gd` → `long_swordsman.gd`, `pikeman.gd`, `archer.gd` | Infantry line; stats + counter bonuses in their `.tres` |
| `units/scout.gd` → `heavy_scout.gd` → `knight.gd` | Cavalry line (scout: auto-explore) |
| `units/battering_ram.gd`, `mangonel.gd`, `trebuchet.gd` | Siege: anti-building ×3, AoE splash, deploy/undeploy |
| `units/fishing_boat.gd`, `transport_ship.gd`, `war_galley.gd` | Navy; transport capacity 8, always disembarks on dry land |
| `units/` civ-uniques (8 scripts) | One special mechanic per civ; Tidecaller is the only amphibious land unit |
| **Buildings** ||
| `buildings/building_base.gd` | Base class: construction FSM, spawn spiral, rally points, garrison API, shared ranged-volley machinery |
| `buildings/building_damage_fx.gd` | Progressive fire/smoke on damaged buildings (purely visual) |
| `buildings/town_center.gd`, `town_center_buildable.gd` | Trains villagers, hero respawn, drop-off; buildable TC from Castle Age |
| `buildings/barracks.gd`, `archery_range.gd`, `stable.gd`, `siege_workshop.gd` | Military production, age/civ-gated rosters |
| `buildings/dock.gd` | Trains ships; navigate to its `water_access_point()` berth, never to the on-land origin |
| `buildings/blacksmith.gd`, `university.gd`, `temple.gd`, `market.gd` | Research/trade; Temple also field hospital + trains Harimaguada; Market dynamic rates + mercenaries |
| `buildings/watch_tower.gd`, `wall_segment.gd`, `gate.gd` | Defense; tower targets the `"units"` group (joined by `UnitBase._ready` — load-bearing) |
| `buildings/house.gd`, `farm.gd`, `fish_trap.gd`, `lumber_camp.gd`, `mining_camp.gd`, `mill.gd` | Economy; camps/Mill are drop-offs AND research their resource line; Mill trains the dog |
| `buildings/wonder.gd` | Wonder victory condition |
| **Game World** ||
| `game/game_world.gd` | Scene root, thin dispatcher; `live_selection()` is the prune-on-read barrier every controller must use instead of `_selected_units` |
| `game/world_setup.gd` | Match bootstrap: civs, TCs, hero, tutorial, AI brains (host-only gate) |
| `game/world_victory.gd` | Victory/defeat/elimination, Wonder countdown, resignation → spectate, end-of-game freeze |
| `game/world_camera.gd`, `world_selection.gd` | Camera pan/zoom/follow + SPACE alert jump; click/drag selection, control groups |
| `game/world_commands.gd` | Player intent layer: right-click resolution, pending actions, formations; every mutation goes through CommandBus |
| `game/commands/game_command.gd` | Command-pattern base + 9 leaf commands in the same dir; execute-time ownership validation, `remote_origin` privilege stripping |
| `game/world_placement.gd` | Placement ghost/grid-snap, wall drag, navmesh rebake; `building_costs()` single cost table; `placement_legal` re-validates wire-borne placements |
| **Map Generation** ||
| `map/map_generator.gd` | Thin pipeline: painter → placer → nav builder; owns the map RNG and island layout solver |
| `map/map_materials.gd`, `terrain_detail.gd`, `terrain_painter.gd`, `resource_visuals.gd` | Shader materials, ground decals, zone layouts/shorelines, resource-node art |
| `map/entity_placer.gd` | Spatial-hash occupancy + every spawn (TC ring, resources, animals, wild flocks) |
| `map/nav_mesh_builder.gd` | Bakes the 4 nav layers (1 land, 2 ocean, 4 amphibious, 8 malpaís); impassable zones CARVED into the mesh, never RVO-only obstacles |
| `map/fog_of_war.gd` | 3-state per-player fog grid, vision multipliers, sea-fog cloak rules |
| `map/placement_grid.gd` | Pure/testable 16 px grid snap |
| **AI** ||
| `ai/world_query.gd` | Read-only query service + fog-honest sighting layer (`sighted_enemy_units` / `known_enemy_buildings`) |
| `ai/ai_player.gd` | Coordinator: EventBus wiring, TC rebuild, elimination |
| `ai/ai_economy.gd` | Villager management, age-advance trigger, pastoral economy (dogs + flock) |
| `ai/ai_construction.gd` | Building placement; every building villager-built at player cost/time — no cheats |
| `ai/ai_military.gd` | Training, research priority, fog-honest targeting, base defense, escalation |
| `ai/ai_naval.gd` | Ship training, galley patrols, transport assaults, fish traps |
| **UI** ||
| `ui/hud_manager.gd` | CanvasLayer coordinator: selection panel, queue/research row, composes the `ui/hud/*` components |
| `ui/hud/hud_action_defs.gd` | Static action tables + pure builders — costs ALWAYS resolved from the same .tres data the sim charges; no hardcoded prices anywhere |
| `ui/hud/hud_action_menu.gd` | Command grid: rendering, paging, hotkeys, per-selection layouts; refuses actions in replay/spectate |
| `ui/hud/` (rest) | Focused components, self-wired to their signals: resource bar, weather banner, match stats, menus, controls, tutorial, hero widget, control groups, chat, style factory |
| `ui/` (rest) | Minimap (AoE2 building memory), procedural glyphs (`ui_icons`), shared button/cursor/toast/portrait widgets, weather overlay |
| **Utils** ||
| `utils/icon_baker.gd`, `iso_projection.gd`, `iso_billboard.gd` | Runtime-baked miniatures; isometric camera math; upright billboards + depth sort |
| `utils/civ_style.gd`, `unit_dress.gd`, `team_dress.gd`, `ship_dress.gd` | Per-civ visual identity; unit/ship decoration; team-colour repaint (cloth only) |
| `utils/unit_enhancer.gd`, `unit_redesign.gd` | The ENHANCED and REDESIGNED unit styles; both idempotent, both strip cleanly back to CLASSIC |
| `utils/` (rest) | Localized names, attack-alert ring, hero flame aura, shadows/plinths/nameplates |
| **Resources** ||
| `resources/*/{unit,building,technology,civilization}_resource.gd` | The four data-driven Resource definitions (stats, effects, civ bonuses) |

## Coding Conventions

- `snake_case` for variables, functions, file names; `PascalCase` for class names, node names, scene roots
- Use `@export` for designer-tunable values; `const` for true constants — at class level, never inside functions
- One `class_name` per base script; leaf classes may omit it
- Signals: defined in `EventBus` for cross-system; direct `connect()` within a scene subtree only
- No comments explaining *what* code does — only *why* for non-obvious constraints

## Testing

- **GUT** (vendored at `project/addons/gut`); tests in `project/tests/unit/` and `project/tests/integration/`. Run with `./run_tests.sh` (runs BOTH dirs) or `./run_tests.sh res://tests/unit/test_x.gd`; set `GODOT` to the engine binary.
- **GUT trap**: a test script that fails to parse is silently *skipped* while GUT still reports "all passed" — always check the `Scripts` count in the summary and run `$GODOT --headless --path project --import` after adding a new `class_name`.
- **Harnesses**: 56 standalone `check_*` tools under `project/tools/` for what GUT can't reach. Full catalog with env vars: `docs/testing/harnesses.md` (regen with `python3 docs/testing/regen_harness_catalog.py`). The curated CI-gate command block lives in `docs/architecture/key_files.md`.
- **Map-gen gate**: `check_map_gen.tscn` prints a deterministic census per map type at a fixed seed. Capture it BEFORE touching map generation and diff after — the numbers must not move unless the change is meant to alter the map.
- **Docs site**: `python3 docs/build_site.py` regenerates every HTML page in `docs/` from Markdown — edit the Markdown, never the generated HTML (hand-crafted: index*, tech_tree, guia-visual, civ gallery).

## Current Status

**Production-ready.** 4 ages, 26 unit types + 16 heroes, 20 buildings, 32 technologies, 8 civilizations, 5 map types, procedural weather, save/load (schema v2), full AI (fog-honest, no cheats), campaign, replays with video export, multiplayer phases 1–2 (host-authoritative, reconnection, save/resume, Steam prototype). Full feature inventory: `docs/architecture/key_files.md`.

Pending: live Steam-lobby test; lockstep simulation (needs deterministic physics-free movement); balance tuning from real playtesting.

## Sub-agents

Five specialized agents live in `.claude/agents/`: `developer` (implementation), `code-reviewer` (before merge / after refactor), `tester` (GUT coverage), `docs-keeper` (sync docs after `.gd`/`.tscn`/`.tres` changes), `performance-checker` (hot paths, unit-heavy features). Recommended flow: developer → code-reviewer → tester → docs-keeper.

## Maintaining this file

Keep CLAUDE.md under ~15 KB. The Key Files table stays at ONE line per file — when a change deserves longer notes (constants, bug history, rationale), put them in `docs/architecture/key_files.md` or `docs/architecture/systems.md` and keep the table line short. Never paste feature inventories, harness command blocks, or changelogs here.
