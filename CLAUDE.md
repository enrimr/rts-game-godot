# Age of Kingdoms — CLAUDE.md

## Project Overview

An Age of Empires II inspired 2D real-time strategy game built in **Godot 4** with GDScript.

- **Engine**: Godot 4.3+
- **Language**: GDScript (no C#)
- **Genre**: 2D real-time strategy (top-down isometric-style)
- **Scope**: Single-player skirmish vs AI, 5 civilizations, multiplayer planned later

## Repository Layout

```
project/          ← Open this in Godot editor (contains project.godot)
  assets/         ← Art, audio, fonts, shaders
  scenes/         ← .tscn scene files
  scripts/        ← .gd source files
    core/         ← Singletons: GameManager, EventBus, ResourceManager, SelectionManager
    units/        ← UnitBase, Villager, military unit classes
    buildings/    ← BuildingBase and specific building scripts
    economy/      ← ResourceNode, drop-off logic
    map/          ← MapManager (tilemap, fog of war, pathfinding)
    combat/       ← Projectiles, damage calculation
    ai/           ← AIPlayer state machine
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
3. **Autoloads (singletons)**: `GameManager`, `EventBus`, `ResourceManager`, `SelectionManager` — access these by name anywhere.
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

**M1** — Playable map with villagers that gather resources and return to a drop-off building.

## Sub-agents

Four specialized agents live in `.claude/agents/`. Invoke them by name with `@agent-name` or via the Claude Code agent system.

| Agent | File | When to invoke |
|---|---|---|
| `developer` | `.claude/agents/developer.md` | Implementing features, fixing bugs, any coding task |
| `tester` | `.claude/agents/tester.md` | Writing GUT tests, expanding coverage, investigating test failures |
| `code-reviewer` | `.claude/agents/code-reviewer.md` | Before merging a branch, after a large refactor |
| `docs-keeper` | `.claude/agents/docs-keeper.md` | After any `.gd`/`.tscn`/`.tres` change to sync documentation |

### Recommended workflow

```
developer  →  code-reviewer  →  tester  →  docs-keeper
```

1. `developer` implements the feature
2. `code-reviewer` reviews the diff — blockers must be fixed before proceeding
3. `tester` writes or updates GUT tests for the changed code
4. `docs-keeper` updates `docs/` and `CLAUDE.md` to reflect the new state
