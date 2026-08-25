# Architecture Overview

## High-Level Design

Calima: Flames of the Atlantic is a 2D real-time strategy game built in Godot 4 inspired by Age of Empires II. It follows a data-driven, signal-based architecture to keep systems loosely coupled.

## Core Systems

### Autoload Singletons

| System | Script | Responsibility |
|---|---|---|
| GameManager | `scripts/core/game_manager.gd` | Global game state, pause, game-over, victory conditions (Conquest/Regicide/Wonder) |
| EventBus | `scripts/core/event_bus.gd` | Decoupled signal dispatch for all cross-system communication |
| ResourceManager | `scripts/core/resource_manager.gd` | Per-player resource stockpiles (food/wood/gold/stone), spatial resource cache |
| SelectionManager | `scripts/core/selection_manager.gd` | Unit/building selection (40 max), control groups (1-9) |
| AgeManager | `scripts/core/age_manager.gd` | Per-player Age tracking (Dark/Feudal/Castle/Imperial), age-advance timers |
| PopulationManager | `scripts/core/population_manager.gd` | Per-player population current/cap tracking |
| CivBonusManager | `scripts/core/civ_bonus_manager.gd` | Per-player multipliers for unit stats (HP, attack, speed, armor), gather rates, age-up costs, attack speed, archer range bonuses per age |
| TechManager | `scripts/core/tech_manager.gd` | Research queue, applies 21 technology effects, instant tech grants (civ bonuses) |
| TerrainManager | `scripts/core/terrain_manager.gd` | Impassability queries, nearest-passable search, coastal zone detection |
| WeatherManager | `scripts/core/weather_manager.gd` | Procedural weather state machine (5 types); stat-modifier query API (vision, speed, gather, drift, damage) |
| AudioManager | `scripts/core/audio_manager.gd` | Spatial audio playback with distance attenuation |
| SaveManager | `scripts/core/save_manager.gd` | Complete game save/load, 99 JSON slots with metadata UI |
| GameSettings | `scripts/core/game_settings.gd` | Difficulty, master volume, persisted settings |
| MatchConfig | `scripts/core/match_config.gd` | Lobby settings (map size, resources, civs, victory mode, weather frequency) |

### Unit Classes (28 total)

| Unit | Script | Notes |
|---|---|---|
| UnitBase | `scripts/units/unit_base.gd` | Base class: Area2D range detection, attack-move, stuck detection, body animation |
| Villager | `scripts/units/villager.gd` | Gather, build, repair; work/walk animation differentiation |
| HeroUnit | `scripts/units/hero_unit.gd` | 8 unique hero abilities (extends Militia) |
| Militia | `scripts/units/militia.gd` | Dark Age infantry |
| ManAtArms | `scripts/units/man_at_arms.gd` | Feudal Age infantry upgrade |
| LongSwordsman | `scripts/units/long_swordsman.gd` | Castle Age infantry upgrade |
| Pikeman | `scripts/units/pikeman.gd` | Castle Age anti-cavalry spearman |
| Archer | `scripts/units/archer.gd` | Feudal Age ranged infantry; attack-ground, cover fire |
| Scout | `scripts/units/scout.gd` | Dark Age exploration cavalry; auto-explore ability (60 s) |
| HeavyScout | `scripts/units/heavy_scout.gd` | Feudal Age cavalry upgrade |
| Knight | `scripts/units/knight.gd` | Castle Age heavy cavalry |
| BatteringRam | `scripts/units/battering_ram.gd` | Castle Age melee siege; ×3 vs buildings, 0.2× vs units |
| Mangonel | `scripts/units/mangonel.gd` | Castle Age AoE siege; 72 px splash, minimum range |
| Trebuchet | `scripts/units/trebuchet.gd` | Imperial Age long-range siege; 48 px splash, deploy/undeploy (3 s) |
| FishingBoat | `scripts/units/fishing_boat.gd` | Naval food gatherer |
| TransportShip | `scripts/units/transport_ship.gd` | Naval troop transport (10 garrison) |
| WarGalley | `scripts/units/war_galley.gd` | Feudal Age combat ship |
| MenceyesGuard | `scripts/units/menceyes_guard.gd` | Guanches infantry: Rage Aura at HP < 50% |
| RavineArcher | `scripts/units/ravine_archer.gd` | Canarii archer: Ambush Shot (×2 first shot when stationary ≥1.5 s) |
| SandRaider | `scripts/units/sand_raider.gd` | Mahos cavalry: Hit & Run (retreat 90 px after attack) |
| ChevalierNormand | `scripts/units/chevalier_normand.gd` | Franks cavalry: Lance Charge (×2.5 after 80 px movement) |
| Longbowman | `scripts/units/longbowman.gd` | Britons archer: Armour Piercing (+4 vs cavalry), kiting AI |
| Conquistador | `scripts/units/conquistador.gd` | Castellanos infantry: Salvo Fire (3 rapid shots, 12 s CD) |
| Tidecaller | `scripts/units/tidecaller.gd` | Atlantes amphibious: Tidal Pulse (2 splash damage, 65 px) |
| Trireme | `scripts/units/trireme.gd` | Fenicios ship: Ram (×2 vs ships, 40 px knockback), passive gold income |
| Animal | `scripts/units/animal.gd` | Wildlife (deer, boar) |
| Sheep | `scripts/units/sheep.gd` | Convertible livestock |
| ShipBase | `scripts/units/ship_base.gd` | Base class for naval units; ocean passability via `civ_id` |

### Building Classes (22 total)

| Building | Script | Notes |
|---|---|---|
| BuildingBase | `scripts/buildings/building_base.gd` | Base class: outward spiral spawn, rally points, construction system |
| TownCenter | `scripts/buildings/town_center.gd` | Main TC: trains villagers (50 food), hero respawn, drop-off |
| TownCenterBuildable | `scripts/buildings/town_center_buildable.gd` | Castle Age player-built TC (275 wood) |
| Barracks | `scripts/buildings/barracks.gd` | Infantry (Militia/Archer/Man-at-Arms/Pikeman/Long Swordsman/unique) |
| ArcheryRange | `scripts/buildings/archery_range.gd` | Feudal Age: trains Archer |
| Stable | `scripts/buildings/stable.gd` | Cavalry (Scout/Heavy Scout/Knight/unique cavalry) |
| SiegeWorkshop | `scripts/buildings/siege_workshop.gd` | Castle Age: siege (BatteringRam/Mangonel/Trebuchet) |
| Dock | `scripts/buildings/dock.gd` | Naval: ships (FishingBoat/TransportShip/WarGalley/Trireme), fish drop-off |
| Blacksmith | `scripts/buildings/blacksmith.gd` | 9 weapon/armour technologies |
| University | `scripts/buildings/university.gd` | Castle Age: 3 advanced techs (Ballistics/Chemistry/Siege Engineering) |
| Temple | `scripts/buildings/temple.gd` | Castle Age: 3 morale/HP buffs (Fervor/Sanctity/Atonement) |
| Market | `scripts/buildings/market.gd` | Resource trading (dynamic rates), mercenary hiring |
| Wonder | `scripts/buildings/wonder.gd` | Imperial Age: Wonder victory condition |
| WatchTower | `scripts/buildings/watch_tower.gd` | Defensive tower with auto-attack, tall stone visual |
| WallSegment | `scripts/buildings/wall_segment.gd` | Defensive wall (5 stone) |
| Gate | `scripts/buildings/gate.gd` | Wall gate (opens for allies, 30 wood) |
| House | `scripts/buildings/house.gd` | +5 population cap (25 wood) |
| Farm | `scripts/buildings/farm.gd` | Renewable food source (60 wood) |
| FishTrap | `scripts/buildings/fish_trap.gd` | Naval renewable food source (75 wood) |
| LumberCamp | `scripts/buildings/lumber_camp.gd` | Wood drop-off (100 wood) |
| MiningCamp | `scripts/buildings/mining_camp.gd` | Gold/stone drop-off (100 wood) |

### AI Systems

| System | Script | Responsibility |
|---|---|---|
| AIPlayer | `scripts/ai/ai_player.gd` | AI coordinator: EventBus wiring, TC rebuild, elimination logic |
| AIEconomy | `scripts/ai/ai_economy.gd` | Villager spawning/assignment, resource targets per age, age-advance trigger |
| AIConstruction | `scripts/ai/ai_construction.gd` | Building placement, placement-failure cooldowns, population management |
| AIMilitary | `scripts/ai/ai_military.gd` | Military training, research priority, combat targeting, base defense, aggression escalation |
| AINaval | `scripts/ai/ai_naval.gd` | Naval training, galley patrol/retreat, transport assault, fish-trap construction |

### UI Systems

| System | Script | Responsibility |
|---|---|---|
| HUDManager | `scripts/ui/hud_manager.gd` | CanvasLayer controller: drives all HUD child nodes |
| ResourceDisplay | `scripts/ui/resource_display.gd` | HBoxContainer showing one resource icon + amount |
| UnitPortrait | `scripts/ui/unit_portrait.gd` | PanelContainer showing unit name + HP bar in selection grid |
| WeatherOverlay | `scripts/ui/weather_overlay.gd` | Screen-space visual effects (rain, dust, ash, fog) driven by WeatherManager |
| Minimap | `scripts/ui/minimap.gd` | Minimap with right-click move orders, resource/unit/building icons; entity content redraws on a 5 Hz tick, overlay (camera rect/flashes) only while changing |

## Autoloads Registration

The following 14 nodes are registered as autoloads in `project.godot`:

- `GameManager` → `scripts/core/game_manager.gd`
- `EventBus` → `scripts/core/event_bus.gd`
- `ResourceManager` → `scripts/core/resource_manager.gd`
- `SelectionManager` → `scripts/core/selection_manager.gd`
- `AgeManager` → `scripts/core/age_manager.gd`
- `PopulationManager` → `scripts/core/population_manager.gd`
- `CivBonusManager` → `scripts/core/civ_bonus_manager.gd`
- `TechManager` → `scripts/core/tech_manager.gd`
- `TerrainManager` → `scripts/map/terrain_manager.gd`
- `WeatherManager` → `scripts/core/weather_manager.gd`
- `AudioManager` → `scripts/core/audio_manager.gd`
- `SaveManager` → `scripts/core/save_manager.gd`
- `GameSettings` → `scripts/core/game_settings.gd`
- `MatchConfig` → `scripts/core/match_config.gd`

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
