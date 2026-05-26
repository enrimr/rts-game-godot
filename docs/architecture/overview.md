# Architecture Overview

## High-Level Design

Calima: Flames of the Atlantic is a 2D real-time strategy game built in Godot 4 inspired by Age of Empires II. It follows a data-driven, signal-based architecture to keep systems loosely coupled.

## Core Systems

| System | Script | Responsibility |
|---|---|---|
| GameManager | `scripts/core/game_manager.gd` | Global game state, tick loop |
| EventBus | `scripts/core/event_bus.gd` | Decoupled signal dispatch |
| ResourceManager | `scripts/core/resource_manager.gd` | Per-player resource stockpiles |
| SelectionManager | `scripts/core/selection_manager.gd` | Unit/building selection |
| CivBonusManager | `scripts/core/civ_bonus_manager.gd` | Per-player multipliers for unit stats (HP, attack, speed, armor), gather rates, age-up costs, attack speed, and move speed; `sand_raider` participates in cavalry HP and scout speed branches |
| TechManager | `scripts/core/tech_manager.gd` | Research queue, applies technology effects |
| MapManager | `scripts/map/map_manager.gd` | Tile map, fog of war, pathfinding |
| TerrainManager | `scripts/map/terrain_manager.gd` | Impassability queries and nearest-passable search for all units |
| WeatherManager | `scripts/core/weather_manager.gd` | Procedural weather state machine; provides stat-modifier query API to all systems |
| HUD | `scripts/ui/hud_manager.gd` | In-game overlay: resources, selection panel, age label, game clock, pause overlay (scene: `scenes/ui/hud/hud.tscn`) |
| Dock | `scripts/buildings/dock.gd` | Coastal building that trains naval units and accepts fish drop-offs (scene: `scenes/buildings/dock.tscn`) |
| Blacksmith | `scripts/buildings/blacksmith.gd` | Research-only building; hosts BLACKSMITH-category technologies (`forging`, `padded_archer_armor`, `iron_casting`) |
| University | `scripts/buildings/university.gd` | Research-only building; hosts UNIVERSITY-category technologies (`siege_engineering`, `ballistics`, `chemistry`) |
| Temple | `scripts/buildings/temple.gd` | Research-only building; hosts MONASTERY-category technologies (`sanctity`, `fervor`, `atonement`) |
| Market | `scripts/buildings/market.gd` | Resource trading: `sell_resource` / `buy_resource` (1-unit) and `sell_lot` / `buy_lot` (100-unit lots); dynamic per-player per-resource rates that degrade with use and recover over time; exposes `get_sell_rate` / `get_buy_rate` query API; emits `EventBus.market_rate_changed` |
| Stable | `scripts/buildings/stable.gd` | Trains cavalry units; queue cap 5; produces `HeavyScout` (Feudal Age) and `Knight` (Castle Age) |
| HeavyScout | `scripts/units/heavy_scout.gd` | Feudal Age cavalry unit trained at Stable; melee attack, move/attack FSM mirrors Militia |
| Knight | `scripts/units/knight.gd` | Castle Age heavy cavalry trained at Stable; higher stats than HeavyScout; same FSM pattern |
| SiegeWorkshop | `scripts/buildings/siege_workshop.gd` | Trains siege units; queue cap 5; available from Castle Age; produces `BatteringRam` and `Mangonel` (Castle Age), `Trebuchet` (Imperial Age) |
| BatteringRam | `scripts/units/battering_ram.gd` | Melee siege unit; x3 damage vs buildings, 0.2x vs units; overrides `_on_enemy_entered_range` to only auto-attack buildings |
| Mangonel | `scripts/units/mangonel.gd` | AoE ranged siege; 72 px splash radius; minimum range = 35 % of max range; backed off when target is too close |
| Trebuchet | `scripts/units/trebuchet.gd` | Long-range AoE siege; 48 px splash radius; minimum range = 40 % of max range; requires deploy/undeploy (3 s each); auto-undeploys on any move or attack order |
| ShipBase | `scripts/units/ship_base.gd` | Base class for all naval units; marks ocean as passable via `civ_id` |
| Fishing Boat | `scripts/units/fishing_boat.gd` | Gathers FOOD_FISH from ocean nodes, returns to Dock |
| Transport Ship | `scripts/units/transport_ship.gd` | Carries up to 8 military units across water; unloads them at the nearest passable shore position |
| War Galley | `scripts/units/war_galley.gd` | Ranged naval combat unit |
| AIPlayer | `scripts/ai/ai_player.gd` | AI coordinator; delegates to AIConstruction, AIEconomy, AIMilitary, AINaval |
| AIConstruction | `scripts/ai/ai_construction.gd` | AI building placement and failure-cooldown tracking |
| AIEconomy | `scripts/ai/ai_economy.gd` | AI villager management, resource assignment, age-advance |
| AIMilitary | `scripts/ai/ai_military.gd` | AI aggression state, military training, research, combat |
| AINaval | `scripts/ai/ai_naval.gd` | AI naval training, galley patrol, transport assault, fish traps |

## Autoloads (Singletons)

The following nodes are registered as autoloads in `project.godot`:

- `GameManager` → `scripts/core/game_manager.gd`
- `EventBus` → `scripts/core/event_bus.gd`
- `ResourceManager` → `scripts/core/resource_manager.gd`
- `SelectionManager` → `scripts/core/selection_manager.gd`
- `CivBonusManager` → `scripts/core/civ_bonus_manager.gd`
- `TechManager` → `scripts/core/tech_manager.gd`
- `TerrainManager` → `scripts/map/terrain_manager.gd`
- `WeatherManager` → `scripts/core/weather_manager.gd`

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
