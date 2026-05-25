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
3. **Autoloads (singletons)**: `GameManager`, `EventBus`, `ResourceManager`, `SelectionManager`, `CivBonusManager`, `TechManager`, `WeatherManager` — access these by name anywhere.
4. **Type hints everywhere** — every GDScript function must declare parameter types and return type.

## Key Files

| File | Purpose |
|---|---|
| `project/scripts/core/game_manager.gd` | Global game state, pause, game-over |
| `project/scripts/core/event_bus.gd` | All cross-system signals |
| `project/scripts/core/resource_manager.gd` | Per-player food/wood/gold/stone stockpiles |
| `project/scripts/core/selection_manager.gd` | Unit selection, control groups |
| `project/scripts/units/unit_base.gd` | Base class for all units |
| `project/scripts/units/villager.gd` | Gathering and building logic |
| `project/scripts/buildings/building_base.gd` | Base class for all buildings |
| `project/resources/units/unit_resource.gd` | Unit stat definition (Resource) |
| `project/resources/buildings/building_resource.gd` | Building stat definition |
| `project/resources/technologies/technology_resource.gd` | Tech effects |
| `project/resources/civilizations/civilization_resource.gd` | Civ bonuses |
| `project/scripts/ui/hud_manager.gd` | CanvasLayer controller: wires EventBus/GameManager signals, drives all HUD child nodes |
| `project/scripts/ui/resource_display.gd` | `ResourceDisplay` — HBoxContainer showing one resource icon + amount |
| `project/scripts/ui/unit_portrait.gd` | `UnitPortrait` — PanelContainer showing unit name abbreviation and HP bar in selection grid |
| `project/scripts/core/civ_bonus_manager.gd` | Per-player multipliers for unit stats, gather rates, age-up costs, move speed, and attack speed |
| `project/scripts/core/tech_manager.gd` | Research queue, applies technology effects to units |
| `project/scripts/buildings/blacksmith.gd` | `Blacksmith` — research-only building; hosts BLACKSMITH techs |
| `project/scripts/buildings/university.gd` | `University` — research-only building; hosts UNIVERSITY techs |
| `project/scripts/buildings/temple.gd` | `Temple` — research-only building; hosts MONASTERY techs |
| `project/scripts/buildings/market.gd` | `Market` — resource trading: `sell_lot` / `buy_lot` and single-unit variants |
| `project/scripts/buildings/stable.gd` | `Stable` — trains `HeavyScout` (Feudal) and `Knight` (Castle); queue cap 5 |
| `project/scripts/units/heavy_scout.gd` | `HeavyScout` — Feudal Age cavalry; trained at Stable |
| `project/scripts/units/knight.gd` | `Knight` — Castle Age heavy cavalry; trained at Stable |
| `project/scripts/units/man_at_arms.gd` | `ManAtArms` — Feudal Age infantry upgrade of Militia; trained at Barracks |
| `project/scripts/units/long_swordsman.gd` | `LongSwordsman` — Castle Age infantry upgrade of Man-at-Arms; trained at Barracks |
| `project/scripts/buildings/siege_workshop.gd` | `SiegeWorkshop` — trains `BatteringRam`/`Mangonel` (Castle), `Trebuchet` (Imperial); queue cap 5 |
| `project/scripts/units/battering_ram.gd` | `BatteringRam` — melee siege unit; x3 damage vs buildings, 0.2x vs units; only auto-attacks buildings |
| `project/scripts/units/mangonel.gd` | `Mangonel` — AoE ranged siege; 72 px splash via `PhysicsDirectSpaceState2D.intersect_shape`; minimum range mechanic |
| `project/scripts/units/trebuchet.gd` | `Trebuchet` — long-range AoE siege; 48 px splash; must deploy/undeploy (3 s) before firing; auto-undeploys when ordered to move |
| `project/scripts/buildings/town_center_buildable.gd` | `TownCenterBuildable` — player-built Town Center (Castle Age, 275 wood); trains villagers (50 food, queue 5); respawns hero; resource drop-off via `DropOff` child node; `is_respawning_hero()` lets HUD treat it identically to the main TC |
| `project/scripts/core/weather_manager.gd` | `WeatherManager` autoload — procedural weather state machine (Calima, Atlantic Storm, Sea Fog, Trade Winds, Volcanic Ash); provides stat-modifier query API consumed by units, buildings, fog-of-war, and projectiles |
| `project/scripts/ui/weather_overlay.gd` | `WeatherOverlay` — screen-space `Node2D` child of GameWorld that renders rain, dust, ash, wind and fog vignette visual effects; driven by WeatherManager |
| `project/scripts/core/match_config.gd` | `MatchConfig` — lobby settings (map size, resources, civs, weather frequency) written before loading game_world |
| `project/scripts/ai/ai_player.gd` | `AIPlayer` — coordinator (`extends Node`); holds `BUILDING_SCENES`/`VILLAGER_SCENE` consts, EventBus wiring, TC rebuild and elimination logic; delegates all per-domain work to the four modules below |
| `project/scripts/ai/ai_construction.gd` | `AIConstruction extends RefCounted` — building placement, placement-failure cooldowns, population-house management; loads costs via `BuildingResource.get_cost_dict()` |
| `project/scripts/ai/ai_economy.gd` | `AIEconomy extends RefCounted` — villager spawning and assignment, resource-type target fractions per age, age-advance trigger, nearest-resource / nearest-drop-off helpers |
| `project/scripts/ai/ai_military.gd` | `AIMilitary extends RefCounted` — `AggressionLevel` enum (PASSIVE/ALERTED/AGGRESSIVE), military training (Barracks/Stable/SiegeWorkshop), research priority queue, combat targeting, base defense |
| `project/scripts/ai/ai_naval.gd` | `AINaval extends RefCounted` — naval unit training, galley patrol/retreat, transport boarding and `order_move_then_unload` assault, fish-trap construction, idle land-unit attack on enemy island |

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

## Current Milestone

**M3** — Full tech tree, 8 civilizations with unique content, naval gameplay on Islands maps.

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
