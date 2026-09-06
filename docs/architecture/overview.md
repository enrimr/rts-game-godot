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
| TechManager | `scripts/core/tech_manager.gd` | Research queue (up to 5 in flight per building, paid at enqueue, refunded on cancel), applies 32 technology effects (loaded from `resources/technologies/`), instant tech grants (civ bonuses) |
| TerrainManager | `scripts/core/terrain_manager.gd` | Impassability queries, nearest-passable search, coastal zone detection |
| WeatherManager | `scripts/core/weather_manager.gd` | Procedural weather state machine (5 types); stat-modifier query API (vision, speed, gather, drift, damage) |
| AudioManager | `scripts/core/audio_manager.gd` | Spatial audio playback with distance attenuation; ALL audio (sfx, per-civ formant voices, music) is procedurally synthesized — see [audio_synthesis.md](audio_synthesis.md) |
| SaveManager | `scripts/core/save_manager.gd` | Complete game save/load, 99 JSON slots with metadata UI; schema v2 (read-enforced: newer refused, older defaulted) persists in-flight research, garrisons, unit stances and weather |
| GameSettings | `scripts/core/game_settings.gd` | Difficulty, master volume, persisted settings |
| MatchConfig | `scripts/core/match_config.gd` | Lobby settings (map size, resources, civs, victory mode, weather frequency, teams, hero gender, campaign mission, replay path) |
| EntityRegistry | `scripts/core/entity_registry.gd` | Stable per-match numeric IDs for units/buildings/resource nodes (`id_of`/`resolve`) |
| CommandBus | `scripts/core/command_bus.gd` | Single entry point for simulation-mutating intents; tick-stamped command log (replay/multiplayer foundation) |
| MatchRng | `scripts/core/match_rng.gd` | The single seeded RNG stream for all simulation randomness |
| NetworkSession | `scripts/multiplayer/network_session.gd` | Host-authoritative LAN/Internet session (ENet + Steam prototype): lobby roster, command pipe, reconnection, save/resume |
| CampaignManager | `scripts/campaign/campaign_manager.gd` | Campaign progress (chain-unlock, `user://campaign.cfg`), mission launch |

### Unit Classes (26 playable types + animals)

| Unit | Script | Notes |
|---|---|---|
| UnitBase | `scripts/units/unit_base.gd` | Base class: Area2D range detection, attack-move, stuck detection, body animation; `_step_enters_sea()` vetoes steps entering ocean at the off-mesh movement paths (RVO safe_velocity, combat gap-closer) |
| Villager | `scripts/units/villager.gd` | Gather, build, repair; work/walk animation differentiation |
| Harimaguada | `scripts/units/healer_unit.gd` | Priestess-healer trained at the Temple (Castle Age, 85F+25G); always female; never fights; follow-and-mend (5 HP/s) + idle auto-triage |
| PresaCanario | `scripts/units/presa_canario.gd` | Herding dog trained at the Mill (Dark Age, 30F+10G); `order_herd` fetches an animal and leads it to the nearest own drop-off (sheep convert on contact); each trip pays food for the net approach; guard dog (attack 3, DEFENSIVE) that never abandons a trip on its own |
| HeroUnit | `scripts/units/hero_unit.gd` | The hero class (extends Militia); 16 named heroes (2 per civ, `hero_*.tres`), each with a unique ability |
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
| TransportShip | `scripts/units/transport_ship.gd` | Naval troop transport (capacity 8, villagers may board) |
| WarGalley | `scripts/units/war_galley.gd` | Feudal Age combat ship |
| MenceyesGuard | `scripts/units/menceyes_guard.gd` | Guanches infantry: Rage Aura at HP < 50% |
| RavineArcher | `scripts/units/ravine_archer.gd` | Canarii archer: Ambush Shot (×2 first shot when stationary ≥1.5 s) |
| SandRaider | `scripts/units/sand_raider.gd` | Mahos cavalry: Hit & Run (retreat 90 px after attack) |
| ChevalierNormand | `scripts/units/chevalier_normand.gd` | Franks cavalry: Lance Charge (×2.5 after 80 px movement) |
| Longbowman | `scripts/units/longbowman.gd` | Britons archer: Armour Piercing (+4 vs cavalry), kiting AI |
| Conquistador | `scripts/units/conquistador.gd` | Castellanos infantry: Salvo Fire (3 rapid shots, 12 s CD) |
| Tidecaller | `scripts/units/tidecaller.gd` | Atlantes amphibious: Tidal Pulse (2 splash damage, 65 px); walks into the sea on navigation layer 4 |
| Trireme | `scripts/units/trireme.gd` | Fenicios ship: Ram (×2 vs ships, 40 px knockback), passive gold income |
| Animal | `scripts/units/animal.gd` | Wildlife (deer, boar) |
| Sheep | `scripts/units/sheep.gd` | Convertible livestock |
| ShipBase | `scripts/units/ship_base.gd` | Base class for naval units; ocean passability via `is_amphibious()`, hull painted per civ by `ShipDress` |

### Building Classes (20 building types)

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
| Temple | `scripts/buildings/temple.gd` | Castle Age: 3 morale/HP buffs (Fervor/Sanctity/Atonement); field hospital (garrisoned units heal 4 HP/s, heroes half rate); trains Harimaguada |
| Market | `scripts/buildings/market.gd` | Resource trading (dynamic rates), mercenary hiring |
| Wonder | `scripts/buildings/wonder.gd` | Imperial Age: Wonder victory condition |
| WatchTower | `scripts/buildings/watch_tower.gd` | Defensive tower with auto-attack, tall stone visual |
| WallSegment | `scripts/buildings/wall_segment.gd` | Defensive wall (5 stone) |
| Gate | `scripts/buildings/gate.gd` | Wall gate (opens for allies, 30 wood) |
| House | `scripts/buildings/house.gd` | +5 population cap (25 wood) |
| Farm | `scripts/buildings/farm.gd` | Renewable food source (60 wood) |
| FishTrap | `scripts/buildings/fish_trap.gd` | Naval renewable food source (75 wood) |
| LumberCamp | `scripts/buildings/lumber_camp.gd` | Wood drop-off (100 wood); researches the wood tech line (Double-Bit Axe → Bow Saw → Two-Man Saw) |
| MiningCamp | `scripts/buildings/mining_camp.gd` | Gold/stone drop-off (100 wood); researches the mining tech line (Reinforced Picks → Shaft Mining → Deep Galleries) |
| Mill | `scripts/buildings/mill.gd` | Food drop-off (100 wood, 600 HP); trains Presa Canario (queue cap 5); researches the food tech line (Horse Collar → Heavy Plow → Crop Rotation) |

### AI Systems

| System | Script | Responsibility |
|---|---|---|
| AIPlayer | `scripts/ai/ai_player.gd` | AI coordinator: EventBus wiring, TC rebuild, elimination logic |
| WorldQuery | `scripts/ai/world_query.gd` | Read-only query service over the unit/building layers; fog-honest sighting layer (`sighted_enemy_units` = seen now, `known_enemy_buildings` = seen or remembered, LOS from .tres × 64 px, throttled refresh) |
| AIEconomy | `scripts/ai/ai_economy.gd` | Villager spawning/assignment, resource targets per age, age-advance trigger; herding-dog management (up to 2 dogs) + single-in-flight sheep slaughter |
| AIConstruction | `scripts/ai/ai_construction.gd` | Building placement, placement-failure cooldowns, population management; Mill early, Watch Towers from Feudal |
| AIMilitary | `scripts/ai/ai_military.gd` | Military training, research priority, fog-honest combat targeting (sighted/known queries), base defense, aggression escalation |
| AINaval | `scripts/ai/ai_naval.gd` | Naval training, galley patrol/retreat (sighted ships only), transport assault, fish-trap construction |

### UI Systems

| System | Script | Responsibility |
|---|---|---|
| HUDManager | `scripts/ui/hud_manager.gd` | CanvasLayer controller: drives all HUD child nodes |
| ResourceDisplay | `scripts/ui/resource_display.gd` | HBoxContainer showing one resource icon + amount |
| UnitPortrait | `scripts/ui/unit_portrait.gd` | PanelContainer showing unit name + HP bar in selection grid |
| WeatherOverlay | `scripts/ui/weather_overlay.gd` | Screen-space visual effects (rain, dust, ash, fog) driven by WeatherManager |
| Minimap | `scripts/ui/minimap.gd` | Minimap with right-click move orders, resource/unit/building icons; entity content redraws on a 5 Hz tick, overlay (camera rect/flashes) only while changing |
| NotificationDisplay | `scripts/ui/notification_display.gd` | Stacking toasts with shortcut action buttons (jump to event, build house on pop-cap, locate hero) |
| HudActionMenu | `scripts/ui/hud/hud_action_menu.gd` | The command grid: per-selection button layouts, paging, stance/formation highlights; refuses orders in replays |
| HudActionDefs | `scripts/ui/hud/hud_action_defs.gd` | Static action tables + pure builders; costs always resolved from `.tres` data |
| HudTutorial | `scripts/ui/hud/hud_tutorial.gd` | Tutorial lesson driver; resource grants via `EventBus.tutorial_grant_resources` |
| HudReplayBar | `scripts/ui/hud/hud_replay_bar.gd` | Replay spectator controls: seekable timeline, speeds, reveal-all, cinematic mode, A/B clip markers |
| HudPlayersPanel | `scripts/ui/hud/hud_players_panel.gd` | AoE2-style players/score overlay docked on the minimap |
| CampaignScreen | `scripts/ui/campaign_screen.gd` | Mission selector + briefing panel |

### Multiplayer & Replay

| System | Script | Responsibility |
|---|---|---|
| NetworkSession | `scripts/multiplayer/network_session.gd` | Autoload — see the singleton table above |
| StateReplicator | `scripts/multiplayer/state_replicator.gd` | Host→client state replication at 15 Hz (puppet mirror worlds, interpolation); also the replay recorder and playback engine (`setup_playback`, `seek`); the sampler skips nodes without a `health` property (arrows fly inside the entity layers) |
| ReplayFile | `scripts/multiplayer/replay_file.gd` | Replay container: zstd-compressed snapshot stream (header + `{t, k, d}` packets), `user://replays/*.calrep` |

### Campaign

| System | Script | Responsibility |
|---|---|---|
| CampaignData | `scripts/campaign/campaign_data.gd` | Const mission table: tutorial prologue + 4 missions (seed, MatchConfig fields, objectives, waves, victory kind) |
| CampaignManager | `scripts/campaign/campaign_manager.gd` | Autoload — progress persistence, chain unlock, mission launch |
| MissionDirector | `scripts/campaign/mission_director.gd` | In-match objective tracking, scripted wave spawns, survive countdown, completion |

## Autoloads Registration

The following 19 nodes are registered as autoloads in `project.godot` (in registration order):

- `EventBus` → `scripts/core/event_bus.gd`
- `EntityRegistry` → `scripts/core/entity_registry.gd`
- `CommandBus` → `scripts/core/command_bus.gd`
- `MatchRng` → `scripts/core/match_rng.gd`
- `NetworkSession` → `scripts/multiplayer/network_session.gd`
- `GameManager` → `scripts/core/game_manager.gd`
- `ResourceManager` → `scripts/core/resource_manager.gd`
- `SelectionManager` → `scripts/core/selection_manager.gd`
- `PopulationManager` → `scripts/core/population_manager.gd`
- `AgeManager` → `scripts/core/age_manager.gd`
- `AudioManager` → `scripts/core/audio_manager.gd`
- `GameSettings` → `scripts/core/game_settings.gd`
- `MatchConfig` → `scripts/core/match_config.gd`
- `TerrainManager` → `scripts/core/terrain_manager.gd`
- `CivBonusManager` → `scripts/core/civ_bonus_manager.gd`
- `TechManager` → `scripts/core/tech_manager.gd`
- `SaveManager` → `scripts/core/save_manager.gd`
- `WeatherManager` → `scripts/core/weather_manager.gd`
- `CampaignManager` → `scripts/campaign/campaign_manager.gd`

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
