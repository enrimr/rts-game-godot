# Calima: Flames of the Atlantic — CLAUDE.md

## Project Overview

An Age of Empires II inspired 2D real-time strategy game built in **Godot 4** with GDScript.

- **Engine**: Godot 4.3+
- **Language**: GDScript (no C#)
- **Genre**: 2D real-time strategy (top-down isometric-style)
- **Scope**: Single-player skirmish vs AI, 8 civilizations, multiplayer planned later

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
    multiplayer/  ← Networking (future)
    utils/        ← Shared helpers
  resources/      ← .tres/.res data files (CivilizationResource, UnitResource, etc.)
tests/            ← GUT unit and integration tests
docs/             ← Architecture and design documentation
```

## Core Architecture Principles

1. **EventBus pattern** — cross-system communication happens exclusively through signals on `EventBus` (autoload). Never call methods across system boundaries directly.
2. **Data-driven resources** — all tuneable values live in `Resource` subclasses under `resources/`. Scripts read from resources; they do not hardcode stats.
3. **Autoloads (singletons)**: `GameManager`, `EventBus`, `EntityRegistry`, `CommandBus`, `MatchRng`, `ResourceManager`, `SelectionManager`, `CivBonusManager`, `TechManager`, `WeatherManager`, `AgeManager`, `AudioManager`, `TerrainManager`, `PopulationManager`, `SaveManager`, `GameSettings` — access these by name anywhere.
4. **Type hints everywhere** — every GDScript function must declare parameter types and return type.
5. **Area2D for range detection** — attack ranges use Area2D nodes that monitor for enemies entering/leaving range, avoiding per-frame physics queries.
6. **Outward spiral spawn positioning** — units spawn at free positions found via outward spiral physics query, preventing overlap.
8. **Collision layers** — layer 1 = world (buildings, scenery, boundary walls); layer 2 = units (all CharacterBody2D units/animals/ships). Units use `collision_layer=2, collision_mask=1`: they physically collide only with the world — RVO avoidance (not physics) separates units from each other, preventing group jams. Detection Area2Ds (attack range, gate, sheep conversion) and unit-seeking physics queries must include bit 2 in their mask. Locked by `test_collision_layers.gd`.
7. **Grid-snap placement** — the player's building/wall placement snaps to a 16 px grid via `PlacementGrid` (`scripts/map/placement_grid.gd`, pure/testable); units still move continuously. Hold **Alt** for free placement. AI placement is unchanged.
9. **Command pattern** — every simulation-mutating intent, player AND AI, is a `GameCommand` (serializable: EntityRegistry IDs + positions, never node pointers) submitted through `CommandBus.submit()`, which tick-stamps it into the match log (replay/LAN foundation) and executes it. UI feedback and selection stay at the submission site; AI decision-making stays in the AI modules, only its mutations cross the bus.
10. **MatchRng for simulation randomness** — anything random that affects game state (spawn jitter, animal wander, weather, projectile drift, AI position searches) draws from the `MatchRng` autoload, seeded once per match with the map seed. The global `randf()`/`randi()` are reserved for local-only audio/visual noise.

## Key Files

| File | Purpose |
|---|---|
| **Core Systems** ||
| `project/scripts/core/game_manager.gd` | Global game state, pause, game-over, victory conditions (Conquest/Regicide/Wonder) |
| `project/scripts/core/event_bus.gd` | All cross-system signals |
| `project/scripts/core/resource_manager.gd` | Per-player food/wood/gold/stone stockpiles, spatial resource cache |
| `project/scripts/core/selection_manager.gd` | Unit selection, control groups |
| `project/scripts/core/age_manager.gd` | Per-player Age tracking, age advance timer, cost multipliers |
| `project/scripts/core/civ_bonus_manager.gd` | Per-player multipliers for unit stats, gather rates, age-up costs, move speed, attack speed; archer range bonuses per age; per-civ weather resistance |
| `project/scripts/core/tech_manager.gd` | Research queue, applies technology effects, 21 technologies total |
| `project/scripts/core/weather_manager.gd` | Procedural weather state machine (Calima, Atlantic Storm, Sea Fog, Trade Winds, Volcanic Ash); stat-modifier query API |
| `project/scripts/core/population_manager.gd` | Per-player population current/cap tracking |
| `project/scripts/core/save_manager.gd` | Complete game save/load system, JSON-based, 99 save slots |
| `project/scripts/core/match_config.gd` | Lobby settings (map size, resources, civs, victory mode, weather frequency) |
| `project/scripts/core/terrain_manager.gd` | Terrain type detection, coastal zone queries, terrain gameplay effects (laurisilva vision mult, risco vantage, shallow water); `get_speed_mult`/`is_impassable_for`/`nearest_passable` take an `amphibious` flag (ocean is opened by the unit, never by the civ), `deep_water_speed(civ_id)` reads the civ's `deep_water_speed` multiplier (default 0.60); `distance_to_coast` is analytic + memoized per 24 px cell (the weather/fog hot path — invalidate via `reset`/`add_zone`/`set_land_polys` only) |
| `project/scripts/core/audio_manager.gd` | Spatial audio playback, distance attenuation |
| `project/scripts/core/game_settings.gd` | Difficulty, master volume, persisted settings |
| `project/scripts/core/command_bus.gd` | `CommandBus` autoload — single entry point for player intents: tick-stamped command log (replay/LAN foundation), `submit`/`command_from_dict`/`save_log`; bound per match via `start_match(world)` |
| `project/scripts/core/entity_registry.gd` | `EntityRegistry` autoload — stable per-match numeric IDs for units/buildings/resource nodes (tree-order rescan + spawn-signal registration), `id_of`/`resolve` |
| `project/scripts/core/match_rng.gd` | `MatchRng` autoload — the single seeded RNG stream for all simulation randomness; seeded per match by `GameWorld._ready`, mid-match state persisted by `SaveManager` (as String — 64-bit vs JSON doubles), global `randf()` reserved for local audio/visual noise |
| **Unit Classes** ||
| `project/scripts/units/unit_base.gd` | Base class for all units; canonical combat state machine (order_move/order_attack, chase, strike, target re-scan) with ~16 override hooks (`_strike_damage`, `_combat_reposition`, `_combat_side_tick`, `_after_strike`, …) — leaf units override hooks, never copy the machine; Area2D range detection, attack-move, stuck detection, body animation; AoE2 combat stances (`Stance` enum + `set_stance`; every auto-acquisition funnels through `_auto_engage` so PASSIVE vetoes, STAND_GROUND never chases and DEFENSIVE chases up to `DEFENSIVE_LEASH` from its anchor — explicit orders always chase); `is_amphibious()` decides water permission per unit (false here — the ship/Tidecaller overrides open the sea) and feeds every `TerrainManager` query |
| `project/scripts/units/villager.gd` | Gathering and building logic, work/walk animation differentiation |
| `project/scripts/units/hero_unit.gd` | Hero units with 8 unique abilities (extends Militia) |
| `project/scripts/units/militia.gd` | Dark Age infantry |
| `project/scripts/units/man_at_arms.gd` | Feudal Age infantry upgrade |
| `project/scripts/units/long_swordsman.gd` | Castle Age infantry upgrade |
| `project/scripts/units/pikeman.gd` | Castle Age anti-cavalry spearman |
| `project/scripts/units/archer.gd` | Feudal Age ranged infantry, attack-ground, cover fire |
| `project/scripts/units/scout.gd` | Dark Age exploration cavalry, auto-explore ability |
| `project/scripts/units/heavy_scout.gd` | Feudal Age cavalry upgrade |
| `project/scripts/units/knight.gd` | Castle Age heavy cavalry |
| `project/scripts/units/battering_ram.gd` | Castle Age melee siege; ×3 vs buildings, 0.2× vs units |
| `project/scripts/units/mangonel.gd` | Castle Age AoE siege; 72 px splash, minimum range |
| `project/scripts/units/trebuchet.gd` | Imperial Age long-range siege; 48 px splash, deploy/undeploy mechanic |
| `project/scripts/units/fishing_boat.gd` | Naval food gatherer |
| `project/scripts/units/transport_ship.gd` | Naval troop transport, garrison 10 units; `_disembark_position()` always lands passengers on dry ground, even amphibious ones |
| `project/scripts/units/war_galley.gd` | Feudal Age combat ship |
| **Unique Units (8 civs)** ||
| `project/scripts/units/menceyes_guard.gd` | Guanches infantry: Rage Aura at HP < 50% |
| `project/scripts/units/ravine_archer.gd` | Canarii archer: Ambush Shot (×2 first shot when stationary) |
| `project/scripts/units/sand_raider.gd` | Mahos cavalry: Hit & Run (retreat after attack) |
| `project/scripts/units/chevalier_normand.gd` | Franks cavalry: Lance Charge (×2.5 after 80 px movement) |
| `project/scripts/units/longbowman.gd` | Britons archer: Armour Piercing (+4 vs cavalry) |
| `project/scripts/units/conquistador.gd` | Castellanos infantry: Salvo Fire (3 rapid shots, 12 s CD) |
| `project/scripts/units/tidecaller.gd` | Atlantes amphibious: Tidal Pulse (2 splash damage); the only land unit with `is_amphibious()` true (gated on the civ's `can_traverse_ocean`), rides navigation layer 4 |
| `project/scripts/units/trireme.gd` | Fenicios ship: Ram (×2 vs ships, 40 px knockback) |
| **Building Classes** ||
| `project/scripts/buildings/building_base.gd` | Base class for all buildings; outward spiral spawn positioning, rally points; garrison API (`garrison_capacity`/`garrison_unit`/`ungarrison_all` — land units only, occupants die with the building) and the shared ranged-volley machinery (`_ranged_attack_arrows()` > 0 enables it; towers always fire, the TC only while garrisoned, each occupant adds an arrow) |
| `project/scripts/buildings/building_damage_fx.gd` | `BuildingDamageFx` — progressive fire/smoke on damaged buildings (smoke <75% HP, flames <50%, heavy fire <25%; repair walks it back; construction/rubble never burn); attached by BuildingBase and TownCenterBuilding, purely visual (render-side RNG) |
| `project/scripts/buildings/town_center.gd` | Main TC: trains villagers, hero respawn, drop-off |
| `project/scripts/buildings/town_center_buildable.gd` | Castle Age player-built TC (275 wood) |
| `project/scripts/buildings/barracks.gd` | Trains infantry (Militia/Archer/Man-at-Arms/Pikeman/Long Swordsman/unique units) |
| `project/scripts/buildings/archery_range.gd` | Feudal Age: trains Archer |
| `project/scripts/buildings/stable.gd` | Trains cavalry (Scout/Heavy Scout/Knight/unique cavalry) |
| `project/scripts/buildings/siege_workshop.gd` | Castle Age: trains siege (BatteringRam/Mangonel/Trebuchet) |
| `project/scripts/buildings/dock.gd` | Naval: trains ships (FishingBoat/TransportShip/WarGalley/Trireme); spawns them in open water off its seaward side, spiralling around ships already there; `water_access_point()` is the cached berth every ship must navigate to instead of the dock's on-land origin |
| `project/scripts/buildings/blacksmith.gd` | Research weapon/armour upgrades (9 techs) |
| `project/scripts/buildings/university.gd` | Castle Age: research advanced techs (Ballistics/Chemistry/Siege Engineering) |
| `project/scripts/buildings/temple.gd` | Castle Age: research morale/HP buffs (Fervor/Sanctity/Atonement) |
| `project/scripts/buildings/market.gd` | Resource trading with dynamic rates, mercenary hiring |
| `project/scripts/buildings/wonder.gd` | Imperial Age: Wonder victory condition |
| `project/scripts/buildings/watch_tower.gd` | Defensive tower: fires visible arrows at the nearest enemy in the "units" group (the group UnitBase._ready joins — load-bearing for tower targeting, the Menceyes aura and several hero abilities); garrisons 5, each occupant adds an arrow to the volley (machinery lives in BuildingBase) |
| `project/scripts/buildings/wall_segment.gd` | Defensive wall |
| `project/scripts/buildings/gate.gd` | Wall gate (opens for allies) |
| `project/scripts/buildings/house.gd` | +5 population cap |
| `project/scripts/buildings/farm.gd` | Renewable food source |
| `project/scripts/buildings/fish_trap.gd` | Naval renewable food source |
| `project/scripts/buildings/lumber_camp.gd` | Wood drop-off |
| `project/scripts/buildings/mining_camp.gd` | Gold/stone drop-off |
| **Game World (scene root + controllers)** ||
| `project/scripts/game/game_world.gd` | Scene root and thin dispatcher (~385 lines): scene node refs, shared match state (`drop_off`, `_selected_units`, `_ai_town_centers`, `_fog`, saved-game fields), `_ready` wiring, `_process`/`_unhandled_input` routing into the controllers below, and the stable external surface (`jump_camera_to`, `get_zoom`/`set_zoom`, `_start_placement`, `live_selection()` — the prune-on-read barrier every controller must use instead of `_selected_units`, …) |
| `project/scripts/game/world_setup.gd` | `WorldSetup` — match bootstrap: civs, player/AI town centers, hero spawn, tutorial spawns, ambient lighting, AI debug overlay |
| `project/scripts/game/world_victory.gd` | `WorldVictory` — victory/defeat/elimination checks, Wonder countdown, game-over flow |
| `project/scripts/game/world_camera.gd` | `WorldCamera` — pan/zoom/edge-scroll, camera follow, alert ring + SPACE jump |
| `project/scripts/game/world_selection.gd` | `WorldSelection` — click/drag/double-click selection, control-group hotkeys |
| `project/scripts/game/world_commands.gd` | `WorldCommands` — the player's intent layer: right-click resolution (incl. garrisoning military into own TC/towers), target pickers (visible-facade building hit-test), pending actions, HUD action router, current formation choice (`_formation`, local UI state — each move command carries it); every simulation mutation is packaged as a `GameCommand` and submitted through `CommandBus`, UI feedback (flashes, sounds) stays here |
| `project/scripts/game/commands/game_command.gd` | `GameCommand` — command-pattern base: serializable payload (`to_dict`/`read`), execute-time ownership validation (`_own_entities`); 10 leaf commands in the same dir (`UnitPointCommand` move/attack-move/attack-ground + formation, `UnitTargetCommand` attack/gather (`drop_id`)/build/drop-off/board/board_instant/set_drop_off, `UnitActionCommand`, `TransportCommand`, `ProductionCommand`, `BuildingActionCommand`, `MarketCommand` incl. mercenary spawn, `PlaceBuildingCommand` incl. wall runs + AI `instant`/`costs_override`/`last_placed`, `AdvanceAgeCommand`, `SpawnUnitCommand` = the AI's instant villager) |
| `project/scripts/game/world_placement.gd` | `WorldPlacement` — building placement ghost/grid-snap, wall drag, coastal/ocean checks, navmesh rebake; `building_costs()` is the single .tres-backed cost table player and AI both pay |
| **Map Generation (pipeline + modules)** ||
| `project/scripts/map/map_generator.gd` | `MapGenerator` — thin pipeline (~150 lines): reads `MatchConfig`, sequences painter → placer → nav builder per map type, returns `{tc_positions}`. Owns the shared `RandomNumberGenerator`, the land-polygon array and `_island_layout()` (solves island radius + ring distance so islands never overlap at any player count / map size) |
| `project/scripts/map/map_materials.gd` | `MapMaterials` — lazily cached shader materials (terrain per type, deep/shallow water, lava), terrain colour table, `STAIN_TILE` grid |
| `project/scripts/map/terrain_detail.gd` | `TerrainDetail` — tile-dithered ground decals and per-biome detail variants (grass/dune/malpaís/risco/laurisilva/caldera) |
| `project/scripts/map/terrain_painter.gd` | `TerrainPainter` — backgrounds, per-map-type zone layouts, zone visuals, shorelines, island polygons; owns `MapMaterials` + `TerrainDetail` |
| `project/scripts/map/entity_placer.gd` | `EntityPlacer` — spatial-hash occupancy grid (`SPATIAL_CELL = 140`) plus every spawn: TC ring, starting units, animals, player/neutral/scattered resources, laurisilva forests, fish, resource islets |
| `project/scripts/map/resource_visuals.gd` | `ResourceVisuals` — static resource-node art library; also used by `SaveManager` on load and by `ResourceNode` for tree stumps |
| `project/scripts/map/nav_mesh_builder.gd` | `NavMeshBuilder` — bakes the three `NavigationPolygon` meshes via `NavigationServer2D.bake_from_source_geometry_data` (layer 1 land, layer 2 ocean, layer 4 `AMPHIBIOUS_LAYER` = the whole board, never carved because land and ocean are both inset by their agent radius and never touch), terrain-zone obstacles (skipped for civs that traverse them), ocean boundary walls; also owns the shared bake helpers every bake goes through — `RADIUS_NUDGE` (+0.5 px, or Godot's convex partition returns an empty mesh when two grid-snapped footprints pinch at a point) and the `RADIUS_FALLBACKS` ladder |
| **AI Systems** ||
| `project/scripts/ai/world_query.gd` | `WorldQuery` — read-only query service over the unit/building layers (own/enemy/all, of_type/in_state/nearest_to); the AI queries it instead of walking the scene tree. Exposed lazily as `AIPlayer.world` |
| `project/scripts/ai/ai_player.gd` | AI coordinator: EventBus wiring, TC rebuild, elimination logic; owns the `world: WorldQuery` getter |
| `project/scripts/ai/ai_economy.gd` | Villager spawning/assignment, resource targets per age, age-advance trigger |
| `project/scripts/ai/ai_construction.gd` | Building placement, placement-failure cooldowns, population-house management |
| `project/scripts/ai/ai_military.gd` | Military training, research priority, combat targeting, base defense, aggression escalation |
| `project/scripts/ai/ai_naval.gd` | Naval training, galley patrol/retreat, transport assault, fish-trap construction |
| **UI Systems** ||
| `project/scripts/ui/hud_manager.gd` | CanvasLayer controller: action menu, selection panel, timer bars, tutorial; composes the HUD child components below |
| `project/scripts/ui/hud/hud_resource_bar.gd` | `HudResourceBar` — top-bar resource counters + gatherer counts, population label, age label (self-wires to EventBus) |
| `project/scripts/ui/hud/hud_weather.gd` | `HudWeather` — weather announcement banner + countdown pill (self-wires to WeatherManager) |
| `project/scripts/ui/hud/hud_match_stats.gd` | `HudMatchStats` — match clock, per-player/rival stat counters, timeline snapshots, game-over + charts overlays |
| `project/scripts/ui/hud/hud_menus.gd` | `HudMenus` — in-game pause menu, settings panel, save-slot picker, surrender flow |
| `project/scripts/ui/hud/hud_controls.gd` | `HudControls` — game-speed buttons, camera dpad (with panning), idle-villager/idle-military cycle buttons, locate-hero button (selects + centres camera; greyed while respawning) |
| `project/scripts/ui/hud/hud_style.gd` | `HudStyle` — shared StyleBoxFlat panel/button factory, bold font + text outline helpers |
| `project/scripts/ui/hud/hud_hero_widget.gd` | `HudHeroWidget` — persistent hero portrait + HP card in Regicide matches (click centers camera) |
| `project/scripts/ui/hud/hud_control_groups.gd` | `HudControlGroups` — clickable chips for assigned control groups (dominant-type miniature + count) |
| `project/scripts/ui/ui_icons.gd` | `UiIcons` — procedural glyph library (37+ command/resource/stat glyphs, baked once, cost-row builders) |
| `project/scripts/ui/action_button.gd` | `ActionButton` — uniform square command button: glyph/entity miniature, hotkey badge, queue badge, category accent |
| `project/scripts/ui/cursor_manager.gd` | `CursorManager` — contextual mouse cursors (tabona/naife pointer + context glyph); pure resolve_context mapping |
| `project/scripts/ui/train_queue_slot.gd` | `TrainQueueSlot` — training queue slot with entity miniature, progress veil, cancel |
| `project/scripts/utils/icon_baker.gd` | `IconBaker` — runtime-baked entity miniatures (civ-styled) for buttons/portraits/queue |
| `project/scripts/utils/iso_projection.gd` | `IsoProjection` — camera-level isometric math (world/screen, zoom composition) |
| `project/scripts/utils/iso_billboard.gd` | `IsoBillboard` — upright entities on the projected ground, depth sort, z constants |
| `project/scripts/utils/civ_style.gd` | `CivStyle` — per-civ visual identity (wall/roof silhouette/trim/headgear, plus the `NAVAL` hull/deck/sail/accent/motif palettes) |
| `project/scripts/utils/unit_dress.gd` | `UnitDress` — per-civ headgear/sash decoration of shared unit rigs |
| `project/scripts/utils/ship_dress.gd` | `ShipDress` — per-civ hull/deck/sail repaint + prow ornament of the shared hulls (Atlantes bronze fin, Fenicios eye); civ-unique hulls stamp `META_APPLIED` to opt out |
| `project/scripts/utils/entity_names.gd` | `EntityNames` — localized unit/building display names with fallback |
| `project/scripts/utils/alert_ring.gd` | `AlertRing` — ring buffer of attack-alert positions for the SPACE jump |
| `project/scripts/utils/hero_aura.gd` | `HeroAura` — animated Dragon Ball-style golden flame aura behind the hero (3 additive layers, upright billboard space, inserted before Body so the figure reads on top); replaced the static gold ground ring |
| `project/scripts/utils/visual_fx.gd` | `VisualFx` — ground shadows, selection plinths, nameplate visibility |
| `project/scripts/ui/resource_display.gd` | HBoxContainer showing one resource icon + amount |
| `project/scripts/ui/unit_portrait.gd` | PanelContainer showing unit name + HP bar in selection grid |
| `project/scripts/ui/weather_overlay.gd` | Screen-space visual effects (rain, dust, ash, fog) driven by WeatherManager |
| **Resources** ||
| `project/resources/units/unit_resource.gd` | Unit stat definition (Resource) |
| `project/resources/buildings/building_resource.gd` | Building stat definition |
| `project/resources/technologies/technology_resource.gd` | Tech effects |
| `project/resources/civilizations/civilization_resource.gd` | Civ bonuses |

## Coding Conventions

- `snake_case` for variables, functions, file names
- `PascalCase` for class names (`class_name`), node names, scene root names
- Use `@export` for all designer-tunable values
- Use `const` for true constants
- One `class_name` per base script; leaf classes may omit it
- Signals: defined in `EventBus` for cross-system; direct `connect()` within a scene subtree only
- No comments explaining *what* code does — only *why* for non-obvious constraints

## Resources (AoE2 style)

- **Food** — farms, hunt, fish, berries
- **Wood** — trees
- **Gold** — gold mines
- **Stone** — stone quarries

## Age Progression

`GameManager.Age` enum: `DARK=0`, `FEUDAL=1`, `CASTLE=2`, `IMPERIAL=3`

## Testing

Uses the [GUT](https://github.com/bitwes/Gut) addon (vendored at
`project/addons/gut`). Tests live in `project/tests/unit/` and
`project/tests/integration/` (inside the Godot project so they resolve via
`res://`). Run them headlessly with `./run_tests.sh` (all tests) or
`./run_tests.sh res://tests/unit/test_world_query.gd` (one script); set the
`GODOT` env var to the engine binary. Also runnable from the GUT panel in the
editor. There are also standalone headless harnesses under `project/tools/`
(`check_*.gd`) for things GUT can't easily reach (HUD scene load, WorldQuery,
PlacementGrid).

`project/tools/check_map_gen.tscn` is the map-generation regression gate: it
prints a deterministic census (TC positions, zone checksum, per-type resource
counts/amounts/position checksum, animals, nav polygons/obstacles, RNG state,
scene node counts) for every map type at a fixed seed. Capture it before
touching map generation and diff it after — the numbers must not move unless
the change is meant to alter the map.

```sh
$GODOT --headless --path project res://tools/check_map_gen.tscn   # env: CALIMA_SEED, CALIMA_MAPS, CALIMA_RIVALS
# Islands: no overlapping islands, both nav meshes usable, ships can sail out of their dock
CALIMA_RIVALS=3 CALIMA_MAP_SIZE=0 $GODOT --headless --path project res://tools/check_islands_layout.tscn
# Islands: the runtime navmesh rebake keeps land carved and the ocean sailable
$GODOT --headless --path project res://tools/check_nav_islands.tscn   # env: CALIMA_MAP
# Two diagonally placed buildings must not empty the navmesh (the bake-nudge gate)
$GODOT --headless --path project res://tools/check_nav_bake_diag.tscn   # env: CALIMA_MAP, CALIMA_SEED
# Command pattern: a real match driven through CommandBus (move/train/place + rebuildable log)
$GODOT --headless --path project res://tools/check_command_bus.tscn   # env: CALIMA_SEED
# Determinism probe: run twice, diff — identical command logs, positions still diverge (physics)
$GODOT --headless --path project res://tools/check_sim_fingerprint.tscn   # env: CALIMA_SEED, CALIMA_MAP, CALIMA_TICKS
# Amphibious: the Tidecaller swims off the beach, land units are refused water, passengers disembark dry
$GODOT --headless --path project res://tools/check_amphibious.tscn
# Naval civ identity (real renderer, not headless): every hull dressed for every civ
CALIMA_SHOT_DIR=/tmp/calima-ships $GODOT --path project --resolution 1600x900 \
  res://tools/check_ship_gallery.tscn   # env: CALIMA_CIVS=atlantes,fenicios
# Damage fire/smoke stages + watch-tower arrows (real renderer): screenshot review
CALIMA_SHOT_DIR=/tmp/calima-fx $GODOT --path project --resolution 1400x900 \
  res://tools/check_damage_fx.tscn
```

Note: GUT silently *skips* a test script that fails to parse while still
reporting "all passed" — always check the `Scripts` count in the summary and run
`$GODOT --headless --path project --import` after adding a new `class_name`.

## Current Status

**Production-ready** — All core features implemented. Recent work focused on polish and bug fixes.

### Implemented Features

**Core Gameplay:**
- 4 Ages (Dark → Feudal → Castle → Imperial) with age-advance costs and timers
- 4 resources (Food, Wood, Gold, Stone) with villager gathering, drop-off buildings, and farms
- Population cap system (5 per House, starts at 15)
- 3 victory conditions: Conquest (eliminate all enemies), Regicide (kill enemy hero), Wonder (build + hold for timer)
- Fog of War with 3 states: unexplored / explored / visible
- Save/Load system (99 JSON slots with metadata UI)
- Procedural map generation with 5 map types (Plains, Standard, Volcanic Coast, Desert Coast, Islands)
- 4 resource modes (Scarce, Normal, Abundant, Full Combat)

**Units (28 total):**
- Villagers (gather, build, repair)
- Infantry: Militia → Man-at-Arms → Long Swordsman, Pikeman, Archer
- Cavalry: Scout → Heavy Scout → Knight
- Siege: Battering Ram, Mangonel, Trebuchet (deploy mechanic)
- Naval: Fishing Boat, Transport Ship (garrison 10), War Galley
- Animals: Sheep (convertible), generic Animal
- 8 Hero units (one per civ) with unique abilities
- 8 Unique units (one per civ) with special mechanics

**Buildings (22 total):**
- Economy: Town Center, House, Lumber Camp, Mining Camp, Farm, Fish Trap
- Military: Barracks, Archery Range, Stable, Siege Workshop, Dock
- Research: Blacksmith, University, Temple, Market
- Defense: Wall Segment, Gate, Watch Tower
- Special: Wonder (victory condition)

**Technologies (21 total):**
- Blacksmith (9): Loom, Forging, Iron Casting, Blast Furnace, Scale/Chain/Plate Barding, Padded Archer Armour, Fletching, Bodkin Arrow, Shipwright
- University (3): Ballistics, Chemistry, Siege Engineering
- Temple (3): Fervor, Sanctity, Atonement
- Unit Upgrades (4): Man-at-Arms, Long Swordsman, Heavy Scout, Knight
- Instant civ bonus: Castellanos free Blacksmith tech per age

**Civilizations (8 total):**
- Guanches: Stone building HP bonus, infantry-focused, malpaís traversal
- Canarii: Food gather bonus, cheap archers, no heavy cavalry
- Mahos: Cheap buildings, fast cavalry, dune traversal
- Franks: Cheaper age advance, cavalry HP bonus, fast farms
- Britons: Archer range +1/age, warship attack speed bonus
- Castellanos: Free Blacksmith tech/age, balanced roster
- Atlantes: Ship attack speed bonus, distinct sea-stone/bronze fleet (`CivStyle.NAVAL`), amphibious unique unit (Tidecaller wades shallows at full speed, swims deep water at `deep_water_speed` 0.60), harder to spot in Sea Fog (`fog_stealth` 0.5), +50 % vision within 400 px of a shore (`coastal_vision` 1.50, read by `FogOfWar._coastal_vision_mult`)
- Fenicios: Ship cost reduction, ramming naval unique unit

**Weather System:**
- 5 procedural weather types (Calima, Atlantic Storm, Sea Fog, Trade Winds, Volcanic Ash)
- Stat modifiers: vision, movement speed, gather rate, projectile drift, building damage
- Per-civ weather affinity: `CivilizationResource.weather_affinity` ({weather_id: resistance 0..1}) scales penalties per civilization (e.g. Guanches immune to Calima, Atlantes ignore the Atlantic Storm naval penalty); weather query methods take an optional `player_id`. Full matrix: Guanches (calima 0.0, volcanic_ash 0.5), Mahos (calima 0.5), Atlantes (atlantic_storm 0.0, sea_fog 0.5), Fenicios (atlantic_storm 0.5), Britons (atlantic_storm 0.5), Canarii (sea_fog 0.5, trade_winds 0.5), Castellanos (calima 0.5); Franks are the neutral continental baseline (no affinity)
- Volcanic Ash is spatial: only rolls on Volcanic Coast maps and only affects positions within a caldera's radius + 800 px (`WeatherManager._in_volcanic_zone` queries `TerrainManager` CALDERA zones; calderaless maps fall back to whole-map coverage)
- Weather-based cloaking (Sea Fog coastal stealth): the cloak breaks within `WeatherManager.fog_spot_range(owner)` of an own unit/building (180 px, ×`fog_stealth` — Atlantes 90 px) and for `UnitBase.COMBAT_REVEAL_TIME` after the hidden unit strikes; `FogOfWar._breaks_fog_cloak` owns both rules
- Weather forecast: a `forecast` phase warns the player `FORECAST_TIME` seconds before an event ramps in (`WeatherManager.weather_incoming` signal → `HudWeather` banner); weather stays inactive (no penalties) during the warning
- Visual effects overlay (rain, dust, ash, fog vignette)
- Lobby-configurable frequency (Off/Normal/Frequent/Extreme)

**Combat:**
- Melee and ranged damage calculation with armour types (melee/pierce)
- Projectile system with flight time and drift (weather-affected)
- Area-of-effect splash damage (Mangonel 72 px, Trebuchet 48 px)
- Attack-ground command for ranged/siege units
- Cover Fire button (move into range then attack)
- AoE2 combat stances: Aggressive / Defensive (leash + return) / Stand Ground / No Attack
- Group formations: Line (melee front, ranged behind), Box, Spread, Rings — selectable per military selection
- Garrison: land units shelter in the TC (10) and Watch Towers (5); each occupant adds an arrow to the building's volley (the TC only shoots while garrisoned); occupants die if the building falls
- Minimum range mechanic (siege)
- Auto-attack range detection via Area2D nodes (no per-frame queries)

**AI:**
- Economic AI: villager spawning/assignment, resource balancing, age advancement
- Construction AI: building placement with cooldowns, population management
- Military AI: training queues, research priorities, aggression escalation
- Naval AI: ship training, galley patrols, transport assaults, fish-trap construction
- Defensive AI: base defense, TC rebuild, idle unit redeployment

**UI/UX:**
- HUD: resource display, population counter, age indicator, unit selection grid (40 max)
- Minimap with right-click move orders, resource/unit/building icons; enemy buildings remembered at last known position under fog (AoE2-style), forgotten only when re-scouted and gone
- Weather banner and countdown pill
- In-game pause menu (Resume, Settings, Surrender, Exit)
- Game-over screen with victory/defeat message
- Match lobby with civ selection, map type, resource mode, victory mode, weather settings
- Tooltips for all buttons (buildings, units, technologies)
- Camera follow selected units
- Control groups: Ctrl/Cmd+1..9 assign, 1..9 recall, clickable HUD chips (double-click centers camera); SPACE jumps to the last attack alert (5-entry ring, clickable attack toasts)

**Polish:**
- Procedural body animation for all units (walk, attack, work)
- Flying arrow projectiles (visual only)
- Readable Polygon2D figures for all units/buildings/animals (redesigned from placeholder silhouettes — villagers, soldiers, riders, archers, ships, siege, civ-unique units, deer/sheep)
- Random visual gender for all human units (50/50, long hair for female); persisted across save/load; cosmetic only
- Distinct heroine sprites (long hair, golden circlet, gown); hero gender selectable in the lobby (Random/Male/Female)
- Team-colour building accents (roofs, flags, banners, awnings, domes, sails) via the `Team*`-node accent system in `building_base.gd`, plus player colour stripes
- Ground shadows under units and buildings
- Animated water shader (swell + coastal foam), terrain detail shader, animated caldera lava, ambient lighting + vignette
- Smooth terrain-zone blending and rounded sandy coastlines
- Animal walking gait (deer/sheep legs trot); unit & animal orientation follows travel direction
- 2D physics interpolation enabled (smooth movement at high render framerates)
- Tall stone tower visual for Watch Tower
- Selection indicators (green circle for player, yellow for allies)
- Hero energy aura (animated Dragon Ball-style golden flame, `HeroAura`; reviewed via `tools/check_hero_aura.tscn` screenshots) + locate-hero HUD button next to the idle-unit buttons
- Rally point markers for production buildings
- Health bars for units/buildings (hidden when full HP); BuildingBase creates the building bar at runtime — most building scenes ship without a HealthBar node, and before this nothing ever showed building HP (damage LOOKED like it wasn't applied)
- Progressive damage fire/smoke on buildings (smoke <75% HP, flames <50%, heavy fire <25%; repair clears it)
- Sound effects: select, attack, build, gather, hit (with spatial attenuation)

### Recent Bug Fixes (Production-Ready Milestone)

1. Cover Fire: register as pending action, move into range before firing
2. Spawn positioning: outward spiral physics query prevents unit overlap
3. Minimap: fixed revealing entire resource clusters at once
4. Weather HUD: fixed banner/pill centering at non-1920 resolutions
5. Villager: fixed `_animate_body` signature mismatch
6. Town Center: fixed initial graphic, arrow projectile rendering
7. WarGalley: fixed HP check using wrong property names
8. Conquest victory: fixed missing DEAD/DESTROYED node checks
9. Conquest defeat: fixed never triggering for human player
10. Regicide: fixed per-mode victory condition logic
11. Market: fixed page reset on cooldown refresh
12. Volcanic Ash: fixed building damage application
13. Nav mesh: skip obstacles for terrain player civ can traverse
14. Release script: resolve game repo path correctly

### Known Limitations (Planned for Future Milestones)

- No multiplayer (LAN planned for M7)
- Tutorial mode exists but incomplete
- Some unique unit abilities partially implemented
- Mercenary system exists but UI incomplete

## Sub-agents

Five specialized agents live in `.claude/agents/`. Invoke them by name with `@agent-name` or via the Claude Code agent system.

| Agent | File | When to invoke |
|---|---|---|
| `developer` | `.claude/agents/developer.md` | Implementing features, fixing bugs, any coding task |
| `tester` | `.claude/agents/tester.md` | Writing GUT tests, expanding coverage, investigating test failures |
| `code-reviewer` | `.claude/agents/code-reviewer.md` | Before merging a branch, after a large refactor |
| `docs-keeper` | `.claude/agents/docs-keeper.md` | After any `.gd`/`.tscn`/`.tres` change to sync documentation |
| `performance-checker` | `.claude/agents/performance-checker.md` | When a system touches `_process`/`_physics_process`, after adding unit-heavy features, or when performance feels off |

### Recommended workflow

```
developer  →  code-reviewer  →  tester  →  docs-keeper
```

1. `developer` implements the feature
2. `code-reviewer` reviews the diff — blockers must be fixed before proceeding
3. `tester` writes or updates GUT tests for the changed code
4. `docs-keeper` updates `docs/` and `CLAUDE.md` to reflect the new state
