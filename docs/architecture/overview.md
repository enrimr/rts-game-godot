# Architecture Overview

## High-Level Design

Calima Kingdoms: Flames of the Atlantic is a 2D real-time strategy game built in Godot 4 inspired by Age of Empires II. It follows a data-driven, signal-based architecture to keep systems loosely coupled.

## Core Systems

| System | Script | Responsibility |
|---|---|---|
| GameManager | `scripts/core/game_manager.gd` | Global game state, tick loop |
| EventBus | `scripts/core/event_bus.gd` | Decoupled signal dispatch |
| ResourceManager | `scripts/core/resource_manager.gd` | Per-player resource stockpiles |
| SelectionManager | `scripts/core/selection_manager.gd` | Unit/building selection |
| CivBonusManager | `scripts/core/civ_bonus_manager.gd` | Per-player multipliers for unit stats, gather rates, age-up costs |
| TechManager | `scripts/core/tech_manager.gd` | Research queue, applies technology effects |
| MapManager | `scripts/map/map_manager.gd` | Tile map, fog of war, pathfinding |
| TerrainManager | `scripts/map/terrain_manager.gd` | Impassability queries and nearest-passable search for all units |
| HUD | `scripts/ui/hud_manager.gd` | In-game overlay: resources, selection panel, age label, game clock, pause overlay (scene: `scenes/ui/hud/hud.tscn`) |
| Dock | `scripts/buildings/dock.gd` | Coastal building that trains naval units and accepts fish drop-offs (scene: `scenes/buildings/dock.tscn`) |
| ShipBase | `scripts/units/ship_base.gd` | Base class for all naval units; marks ocean as passable via `civ_id` |
| Fishing Boat | `scripts/units/fishing_boat.gd` | Gathers FOOD_FISH from ocean nodes, returns to Dock |
| Transport Ship | `scripts/units/transport_ship.gd` | Ocean movement unit (garrison milestone) |
| War Galley | `scripts/units/war_galley.gd` | Ranged naval combat unit |

## Autoloads (Singletons)

The following nodes are registered as autoloads in `project.godot`:

- `GameManager` → `scripts/core/game_manager.gd`
- `EventBus` → `scripts/core/event_bus.gd`
- `ResourceManager` → `scripts/core/resource_manager.gd`
- `SelectionManager` → `scripts/core/selection_manager.gd`
- `CivBonusManager` → `scripts/core/civ_bonus_manager.gd`
- `TechManager` → `scripts/core/tech_manager.gd`
- `TerrainManager` → `scripts/map/terrain_manager.gd`

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
