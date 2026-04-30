# Architecture Overview

## High-Level Design

Age of Kingdoms is a 2D real-time strategy game built in Godot 4 inspired by Age of Empires II. It follows a data-driven, signal-based architecture to keep systems loosely coupled.

## Core Systems

| System | Script | Responsibility |
|---|---|---|
| GameManager | `scripts/core/game_manager.gd` | Global game state, tick loop |
| EventBus | `scripts/core/event_bus.gd` | Decoupled signal dispatch |
| ResourceManager | `scripts/core/resource_manager.gd` | Per-player resource stockpiles |
| SelectionManager | `scripts/core/selection_manager.gd` | Unit/building selection |
| MapManager | `scripts/map/map_manager.gd` | Tile map, fog of war, pathfinding |
| HUD | `scripts/ui/hud_manager.gd` | In-game overlay: resources, selection panel, age label, game clock, pause overlay (scene: `scenes/ui/hud/hud.tscn`) |

## Autoloads (Singletons)

The following nodes are registered as autoloads in `project.godot`:

- `GameManager` → `scripts/core/game_manager.gd`
- `EventBus` → `scripts/core/event_bus.gd`
- `ResourceManager` → `scripts/core/resource_manager.gd`
- `SelectionManager` → `scripts/core/selection_manager.gd`

## Data Layer

Game entities are defined as `Resource` subclasses under `resources/`:

- `CivilizationResource` — civ bonuses and unique units
- `UnitResource` — unit stats (shared across all instances)
- `BuildingResource` — building stats
- `TechnologyResource` — tech effects and prerequisites

## Signal Flow

```
User Input → SelectionManager / InputHandler
           → EventBus signals
           → Unit / Building / Economy handlers
           → HUD updates
```
