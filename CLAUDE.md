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
    map/          ← MapManager (tilemap, fog of war, pathfinding)
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
3. **Autoloads (singletons)**: `GameManager`, `EventBus`, `ResourceManager`, `SelectionManager`, `CivBonusManager`, `TechManager`, `WeatherManager`, `AgeManager`, `AudioManager`, `TerrainManager`, `PopulationManager`, `SaveManager`, `GameSettings` — access these by name anywhere.
4. **Type hints everywhere** — every GDScript function must declare parameter types and return type.
5. **Area2D for range detection** — attack ranges use Area2D nodes that monitor for enemies entering/leaving range, avoiding per-frame physics queries.
6. **Outward spiral spawn positioning** — units spawn at free positions found via outward spiral physics query, preventing overlap.

## Key Files

| File | Purpose |
|---|---|
| **Core Systems** ||
| `project/scripts/core/game_manager.gd` | Global game state, pause, game-over, victory conditions (Conquest/Regicide/Wonder) |
| `project/scripts/core/event_bus.gd` | All cross-system signals |
| `project/scripts/core/resource_manager.gd` | Per-player food/wood/gold/stone stockpiles, spatial resource cache |
| `project/scripts/core/selection_manager.gd` | Unit selection, control groups |
| `project/scripts/core/age_manager.gd` | Per-player Age tracking, age advance timer, cost multipliers |
| `project/scripts/core/civ_bonus_manager.gd` | Per-player multipliers for unit stats, gather rates, age-up costs, move speed, attack speed; archer range bonuses per age |
| `project/scripts/core/tech_manager.gd` | Research queue, applies technology effects, 21 technologies total |
| `project/scripts/core/weather_manager.gd` | Procedural weather state machine (Calima, Atlantic Storm, Sea Fog, Trade Winds, Volcanic Ash); stat-modifier query API |
| `project/scripts/core/population_manager.gd` | Per-player population current/cap tracking |
| `project/scripts/core/save_manager.gd` | Complete game save/load system, JSON-based, 99 save slots |
| `project/scripts/core/match_config.gd` | Lobby settings (map size, resources, civs, victory mode, weather frequency) |
| `project/scripts/core/terrain_manager.gd` | Terrain type detection, coastal zone queries |
| `project/scripts/core/audio_manager.gd` | Spatial audio playback, distance attenuation |
| `project/scripts/core/game_settings.gd` | Difficulty, master volume, persisted settings |
| **Unit Classes** ||
| `project/scripts/units/unit_base.gd` | Base class for all units; Area2D range detection, attack-move, stuck detection, body animation |
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
| `project/scripts/units/transport_ship.gd` | Naval troop transport, garrison 10 units |
| `project/scripts/units/war_galley.gd` | Feudal Age combat ship |
| **Unique Units (8 civs)** ||
| `project/scripts/units/menceyes_guard.gd` | Guanches infantry: Rage Aura at HP < 50% |
| `project/scripts/units/ravine_archer.gd` | Canarii archer: Ambush Shot (×2 first shot when stationary) |
| `project/scripts/units/sand_raider.gd` | Mahos cavalry: Hit & Run (retreat after attack) |
| `project/scripts/units/chevalier_normand.gd` | Franks cavalry: Lance Charge (×2.5 after 80 px movement) |
| `project/scripts/units/longbowman.gd` | Britons archer: Armour Piercing (+4 vs cavalry) |
| `project/scripts/units/conquistador.gd` | Castellanos infantry: Salvo Fire (3 rapid shots, 12 s CD) |
| `project/scripts/units/tidecaller.gd` | Atlantes amphibious: Tidal Pulse (2 splash damage) |
| `project/scripts/units/trireme.gd` | Fenicios ship: Ram (×2 vs ships, 40 px knockback) |
| **Building Classes** ||
| `project/scripts/buildings/building_base.gd` | Base class for all buildings; outward spiral spawn positioning, rally points |
| `project/scripts/buildings/town_center.gd` | Main TC: trains villagers, hero respawn, drop-off |
| `project/scripts/buildings/town_center_buildable.gd` | Castle Age player-built TC (275 wood) |
| `project/scripts/buildings/barracks.gd` | Trains infantry (Militia/Archer/Man-at-Arms/Pikeman/Long Swordsman/unique units) |
| `project/scripts/buildings/archery_range.gd` | Feudal Age: trains Archer |
| `project/scripts/buildings/stable.gd` | Trains cavalry (Scout/Heavy Scout/Knight/unique cavalry) |
| `project/scripts/buildings/siege_workshop.gd` | Castle Age: trains siege (BatteringRam/Mangonel/Trebuchet) |
| `project/scripts/buildings/dock.gd` | Naval: trains ships (FishingBoat/TransportShip/WarGalley/Trireme) |
| `project/scripts/buildings/blacksmith.gd` | Research weapon/armour upgrades (9 techs) |
| `project/scripts/buildings/university.gd` | Castle Age: research advanced techs (Ballistics/Chemistry/Siege Engineering) |
| `project/scripts/buildings/temple.gd` | Castle Age: research morale/HP buffs (Fervor/Sanctity/Atonement) |
| `project/scripts/buildings/market.gd` | Resource trading with dynamic rates, mercenary hiring |
| `project/scripts/buildings/wonder.gd` | Imperial Age: Wonder victory condition |
| `project/scripts/buildings/watch_tower.gd` | Defensive tower with auto-attack |
| `project/scripts/buildings/wall_segment.gd` | Defensive wall |
| `project/scripts/buildings/gate.gd` | Wall gate (opens for allies) |
| `project/scripts/buildings/house.gd` | +5 population cap |
| `project/scripts/buildings/farm.gd` | Renewable food source |
| `project/scripts/buildings/fish_trap.gd` | Naval renewable food source |
| `project/scripts/buildings/lumber_camp.gd` | Wood drop-off |
| `project/scripts/buildings/mining_camp.gd` | Gold/stone drop-off |
| **AI Systems** ||
| `project/scripts/ai/ai_player.gd` | AI coordinator: EventBus wiring, TC rebuild, elimination logic |
| `project/scripts/ai/ai_economy.gd` | Villager spawning/assignment, resource targets per age, age-advance trigger |
| `project/scripts/ai/ai_construction.gd` | Building placement, placement-failure cooldowns, population-house management |
| `project/scripts/ai/ai_military.gd` | Military training, research priority, combat targeting, base defense, aggression escalation |
| `project/scripts/ai/ai_naval.gd` | Naval training, galley patrol/retreat, transport assault, fish-trap construction |
| **UI Systems** ||
| `project/scripts/ui/hud_manager.gd` | CanvasLayer controller: action menu, selection panel, timer bars, tutorial; composes the HUD child components below |
| `project/scripts/ui/hud/hud_weather.gd` | `HudWeather` — weather announcement banner + countdown pill (self-wires to WeatherManager) |
| `project/scripts/ui/hud/hud_match_stats.gd` | `HudMatchStats` — match clock, per-player/rival stat counters, timeline snapshots, game-over + charts overlays |
| `project/scripts/ui/hud/hud_menus.gd` | `HudMenus` — in-game pause menu, settings panel, save-slot picker, surrender flow |
| `project/scripts/ui/hud/hud_controls.gd` | `HudControls` — game-speed buttons, camera dpad (with panning), idle-villager/idle-military cycle buttons |
| `project/scripts/ui/hud/hud_style.gd` | `HudStyle` — shared StyleBoxFlat panel/button factory used by HUD components |
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

Uses [GUT](https://github.com/bitwes/Gut) addon. Tests live in `tests/unit/` and `tests/integration/`.
Run from the GUT panel inside Godot editor, or headlessly via CI.

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
- Atlantes: Ship attack speed bonus, amphibious unique unit
- Fenicios: Ship cost reduction, ramming naval unique unit

**Weather System:**
- 5 procedural weather types (Calima, Atlantic Storm, Sea Fog, Trade Winds, Volcanic Ash)
- Stat modifiers: vision, movement speed, gather rate, projectile drift, building damage
- Weather-based cloaking (Sea Fog coastal stealth)
- Visual effects overlay (rain, dust, ash, fog vignette)
- Lobby-configurable frequency (Off/Normal/Frequent/Extreme)

**Combat:**
- Melee and ranged damage calculation with armour types (melee/pierce)
- Projectile system with flight time and drift (weather-affected)
- Area-of-effect splash damage (Mangonel 72 px, Trebuchet 48 px)
- Attack-ground command for ranged/siege units
- Cover Fire button (move into range then attack)
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
- Minimap with right-click move orders, resource/unit/building icons
- Weather banner and countdown pill
- In-game pause menu (Resume, Settings, Surrender, Exit)
- Game-over screen with victory/defeat message
- Match lobby with civ selection, map type, resource mode, victory mode, weather settings
- Tooltips for all buttons (buildings, units, technologies)
- Camera follow selected units
- Control groups (Ctrl+1..9)

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
- Hero ring (gold circle) visual
- Rally point markers for production buildings
- Health bars for units/buildings (hidden when full HP)
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
- Custom terrain tiles in progress (malpaís, dune, risco, laurisilva)
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
