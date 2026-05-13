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
| Blacksmith | `scripts/buildings/blacksmith.gd` | Research-only building; hosts BLACKSMITH-category technologies (`forging`, `padded_archer_armor`, `iron_casting`) |
| University | `scripts/buildings/university.gd` | Research-only building; hosts UNIVERSITY-category technologies (`siege_engineering`, `ballistics`, `chemistry`) |
| Temple | `scripts/buildings/temple.gd` | Research-only building; hosts MONASTERY-category technologies (`sanctity`, `fervor`, `atonement`) |
| Market | `scripts/buildings/market.gd` | Resource trading: `sell_resource` / `buy_resource` (1-unit increments) and `sell_lot` / `buy_lot` (100-unit lots); converts food/wood/stone ↔ gold at fixed rates |
| Stable | `scripts/buildings/stable.gd` | Trains cavalry units; queue cap 5; produces `HeavyScout` (Feudal Age) and `Knight` (Castle Age) |
| HeavyScout | `scripts/units/heavy_scout.gd` | Feudal Age cavalry unit trained at Stable; melee attack, move/attack FSM mirrors Militia |
| Knight | `scripts/units/knight.gd` | Castle Age heavy cavalry trained at Stable; higher stats than HeavyScout; same FSM pattern |
| ShipBase | `scripts/units/ship_base.gd` | Base class for all naval units; marks ocean as passable via `civ_id` |
| Fishing Boat | `scripts/units/fishing_boat.gd` | Gathers FOOD_FISH from ocean nodes, returns to Dock |
| Transport Ship | `scripts/units/transport_ship.gd` | Carries up to 8 military units across water; unloads them at the nearest passable shore position |
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
