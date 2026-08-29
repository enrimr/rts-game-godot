# System Design Details

## Economy System

Resources: Food, Wood, Gold, Stone (matching AoE2 exactly).

Villagers gather from `ResourceNode` objects on the map. Each villager carries up to 10 units and returns to a drop-off building. `ResourceManager` is the single source of truth for stockpiles.

## Combat System

All damage flows through `unit.take_damage(amount, source)`. Armor reduces incoming damage. Range is checked via `attack_range` on `UnitResource`. Combat uses the AoE2 damage formula:

```
damage = max(1, attacker.attack - target.armor_melee)
```

## Pathfinding

Uses Godot's built-in `NavigationAgent2D` on each unit. Navigation regions are updated when buildings are placed or destroyed.

## Terrain Impassability

`TerrainManager` (autoload) is the single authority on whether a world position is passable for a given actor.

**Key API:**

| Method | Signature | Description |
|---|---|---|
| `is_impassable_for` | `(world_pos: Vector2, civ_id: String) -> bool` | Returns `true` if the tile at `world_pos` is impassable for the given civilization |
| `nearest_passable` | `(world_pos: Vector2, civ_id: String) -> Vector2` | Radial search (30 rings × 24 px step) returning the closest passable position |
| `nearest_ocean` | `(world_pos: Vector2) -> Vector2` | Spiral search returning the closest ocean tile — used to guarantee ship spawns land in water |
| `distance_to_coast` | `(world_pos: Vector2) -> float` | Distance to the nearest land/ocean boundary, `INF` on a landlocked map |
| `bake_minimap_texture` | `() -> ImageTexture` | Generates a 256×256 terrain texture used by the minimap renderer |

`distance_to_coast` is analytic — the closest point on every land outline segment
and on every OCEAN zone circle — and memoized per `COAST_CACHE_CELL` (24 px)
grid cell, evaluated at the **cell centre** so the answer never depends on which
query filled the cell first. The cache is dropped by `reset()`, `add_zone()` and
`set_land_polys()`; those three are therefore the only legal ways to mutate
terrain. The previous implementation was an outward ring search costing ~1.8 ms
per call: sea fog asks for the coastal distance once per unit and building
several times a second, which by itself exceeded the whole frame budget and made
the game crawl whenever Sea Fog rolled in. `_point_in_any_land` also
bounding-box rejects (`_land_bounds`) before running the polygon test.
Gated by `tests/unit/test_coast_distance.gd`.

**Integration points:**

- `UnitBase` carries a `civ_id: String = ""` property. Its `_safe_destination(destination: Vector2) -> Vector2` helper calls `TerrainManager.nearest_passable` before any nav agent assignment.
- `ShipBase` overrides `_safe_destination` to snap to `nearest_ocean` instead: ships
  masquerade as the amphibious `atlantes` civ, so `nearest_passable` considers land
  passable and would leave a nav target on the shore — off the ocean navmesh, where
  the agent reports "navigation finished" immediately and the ship never moves.
- All unit `order_move` implementations (`Militia`, `Archer`, `Pikeman`, `Scout`, `HeavyScout`, `Knight`) and `Villager._start_move_to` call `_safe_destination` before setting `nav_agent.target_position`.
- `Animal` nodes call `TerrainManager.nearest_passable(pos, "")` in `order_move`, `_pick_wander_target`, and `_start_flee` so fauna never path onto water or other impassable terrain.

## NavMesh Carving

`NavMeshBuilder.build(parent, map_half, land_polys)` runs at map generation time
(called from `MapGenerator._run`):

- Creates `NavigationObstacle2D` nodes for every malpaís, risco, and caldera zone, parented inside the scene's `NavigationRegion2D`.
- On **Islands** maps, the default nav polygon (which would span the full map area including ocean) is replaced with per-island land polygons so the baked mesh never covers ocean tiles.

This means ship units — whose `civ_id` resolves to a civ that has ocean marked as passable — navigate a separate logical layer, while land units are physically blocked by the nav mesh boundaries.

## Fog of War

Tracked per-player as a boolean grid. Revealed when any unit/building has line of sight of a cell. Stored in `MapManager._fog_revealed`.

## Tech Tree System

Technologies are defined as `TechnologyResource` `.tres` files under `resources/technologies/`. Seventeen technologies are currently implemented:

| Technology | Researched at | Effect |
|---|---|---|
| `loom` | Barracks | Villager HP / armor |
| `fletching` | Barracks | Archer attack / range |
| `scale_barding` | Barracks | Cavalry armor |
| `bodkin_arrow` | Barracks | Archer attack |
| `chain_barding` | Barracks | Cavalry armor |
| `blast_furnace` | Barracks | Infantry attack |
| `plate_barding` | Barracks | Cavalry armor |
| `shipwright` | Barracks | Ship speed / cost |
| `forging` | Blacksmith | Melee attack |
| `padded_archer_armor` | Blacksmith | Archer pierce armor |
| `iron_casting` | Blacksmith | Melee attack |
| `siege_engineering` | University | Siege weapon effectiveness |
| `ballistics` | University | Projectile accuracy |
| `chemistry` | University | Projectile attack bonus |
| `sanctity` | Temple | Monk HP |
| `fervor` | Temple | Monk move speed |
| `atonement` | Temple | Monks can convert buildings |

`TechManager` (autoload) owns the research queue and applies effects when research completes. `CivBonusManager` (autoload) stores per-player multipliers derived from civilization bonuses and applied techs.

When a `TechnologyResource` has non-empty `upgrade_from_unit_id` and `upgrade_to_unit_id` fields, `TechManager` treats it as a unit upgrade: on completion it immediately replaces all live units of type `upgrade_from_unit_id` with instances of `upgrade_to_unit_id` (HP scaled proportionally), and the source building switches its training queue to produce the new type going forward. Upgrade techs are researched at the same building that trains the unit (Barracks for infantry upgrades, Stable for cavalry upgrades).

## AI System

`AIPlayer` (`scripts/ai/ai_player.gd`, `extends Node`) is the coordinator. It owns `BUILDING_SCENES` and `VILLAGER_SCENE` constants, wires `EventBus` signals, and runs on a 2-second `TICK_INTERVAL` tick (plus a 3-second `THREAT_CHECK_INTERVAL` scan). All substantive logic is delegated to four `RefCounted` modules that are instantiated in `_ready()` via `ModuleClass.new()` then `.setup(self)`. Each module holds a typed back-reference `var _ai: AIPlayer` and accesses sibling modules through `_ai._module.method()`.

| Module | Class | File | Responsibilities |
|---|---|---|---|
| `_construction` | `AIConstruction` | `scripts/ai/ai_construction.gd` | Building placement; placement-failure cooldowns (`_build_fail_counts`, `_build_cooldowns`); population-house management; loads all building costs at startup via `BuildingResource.get_cost_dict()` |
| `_economy` | `AIEconomy` | `scripts/ai/ai_economy.gd` | Villager spawning and idle-villager assignment; per-age resource-type target fractions; age-advance trigger; `find_nearest_resource` / `find_nearest_drop_off` helpers |
| `_military` | `AIMilitary` | `scripts/ai/ai_military.gd` | `AggressionLevel` enum (PASSIVE / ALERTED / AGGRESSIVE) with decay timer; Barracks, Stable, and SiegeWorkshop training; tech research priority queue (`_TECH_PRIORITY`); multi-target attack dispatch; control-zone threat detection and base defense |
| `_naval` | `AINaval` | `scripts/ai/ai_naval.gd` | Naval unit training; galley patrol and HP-based retreat (`GALLEY_RETREAT_HP_RATIO = 0.30`); transport boarding and `order_move_then_unload` assault sequence; fish-trap construction; idle land-unit attack once units have crossed to the enemy island |

`AIPlayer` also contains TC-loss handling: on `EventBus.building_destroyed`, if the destroyed building is the AI's Town Center, a 0.5 s deferred call to `_attempt_tc_rebuild` finds the safest villager (maximally distant from the enemy center-of-mass) and places a new TC. If the AI has no units and no buildings it emits `EventBus.player_eliminated`.

On **Islands** maps (`MatchConfig.map_type == ISLANDS`) the `_run_tick` call also invokes all four naval methods; land-only maps skip the naval module entirely.

## UI / HUD System

The HUD is a `CanvasLayer` scene at `scenes/ui/hud/hud.tscn`, instanced as a child of `GameWorld` in `scenes/game/game_world.tscn`. The root node carries `hud_manager.gd`, which retains the core in-game UI (action menu, selection panel, timer bars, tutorial) and **composes** a set of focused child components, each a plain `Node` added in `_ready`:

| Component (`class_name`) | File | Responsibility |
|---|---|---|
| `HudResourceBar` | `scripts/ui/hud/hud_resource_bar.gd` | Top-bar resource counters + gatherer counts, population label (at-cap flash), age label; self-wires to EventBus |
| `HudWeather` | `scripts/ui/hud/hud_weather.gd` | Weather announcement banner + countdown pill; self-wires to `WeatherManager` |
| `HudMatchStats` | `scripts/ui/hud/hud_match_stats.gd` | Match clock, per-player/rival stat counters, timeline snapshots, game-over + charts overlays |
| `HudMenus` | `scripts/ui/hud/hud_menus.gd` | Pause menu, settings, save-slot picker, surrender (tutorial/dpad hooks injected as callables) |
| `HudControls` | `scripts/ui/hud/hud_controls.gd` | Game-speed buttons, camera dpad + panning, idle-villager/idle-military cycle buttons |
| `HudStyle` | `scripts/ui/hud/hud_style.gd` | Shared `StyleBoxFlat` panel/button factory |

The components self-wire to their own signals; `hud_manager` does not relay events to them. The split was incremental and behaviour-preserving — `hud_manager.gd` went from ~3300 to ~1900 lines. A headless load harness lives at `project/tools/check_hud.gd` (`godot --headless -s tools/check_hud.gd`).

**EventBus wiring** (`hud_manager._ready` connects the core panels; components connect their own):

| Signal | Handler | Effect |
|---|---|---|
| `EventBus.resource_changed` | `_on_resource_changed` | Updates the matching `ResourceDisplay` for the local player |
| `EventBus.unit_selected` | `_on_unit_selected` | Rebuilds the unit portraits grid and detail panel |
| `EventBus.age_advance_complete` | `_on_age_advance_complete` | Updates the age label for the local player |
| `EventBus.market_rate_changed` | `_on_market_rate_changed` | Refreshes the Market action panel with live rates if the changed market is currently selected |
| `GameManager.game_started` | `_on_game_started` | Resets game speed and refreshes age/resources (the clock is started by `HudMatchStats`) |
| `GameManager.game_paused` | `toggle_pause` | Shows/hides the full-screen pause overlay |
| `GameManager.game_over` | `HudMatchStats._on_game_over` | Stops the clock and builds the end-of-match summary + charts |

**Component breakdown**:

- **TopBar** (`PanelContainer`, anchored top): four `ResourceDisplay` nodes (Food, Wood, Gold, Stone), a population `Label`, an age `Label`, and a game-clock `Label`.
- **ResourceDisplay** (`class_name ResourceDisplay extends HBoxContainer`): two `Label` children — `IconLabel` for the resource name and `AmountLabel` for the count. Updated via `set_amount(value: int)`.
- **BottomBar** (`PanelContainer`, anchored bottom): a selection panel and a minimap panel.
  - **UnitPortraitsGrid** (`GridContainer`, 10 columns, max 40 portraits): populated dynamically by `HudManager.update_selection`. Each cell is a `UnitPortrait` instance.
  - **UnitDetailPanel**: shows the first selected unit's display name and HP bar.
  - **ActionButtonsGrid**: `GridContainer` with `ACTION_COLS = 5` columns and `ACTION_ROWS = 2` rows (10 slots per page). When the active action list exceeds 10 entries, the last two slots on the bottom row become ◀/▶ pagination buttons. `_render_action_page()` rebuilds the grid for the current `_action_page`.
  - **MinimapPanel**: hosts `MinimapRenderer` (`scripts/ui/minimap.gd`). Rendering is split across two child layers so the widget is not rebuilt every frame: **ContentLayer** (terrain texture, fog cells, resources, buildings, units — the expensive entity iteration) redraws on a decoupled tick every `CONTENT_REDRAW_INTERVAL` (0.2 s), while **OverlayLayer** (camera viewport rect, event flashes, border) is marked dirty only when the camera view actually changes or a flash is animating; an idle minimap issues no draw calls. Enemy buildings seen at least once are remembered at their last known position (`_known_enemy_buildings`, updated on the content tick) and drawn dimmed while their fog cell is EXPLORED — even if destroyed under fog, AoE2-style; a ghost is only forgotten when the player re-observes the spot and the building is gone.
- **PauseOverlay** (`ColorRect`, full-screen, 50 % black): visible only when the game is paused.

**UnitPortrait** (`class_name UnitPortrait extends PanelContainer`): built entirely in code (`_ready`). Displays a 6-character name abbreviation and a color-coded HP bar (green > 50 %, yellow > 25 %, red ≤ 25 %). Created and discarded each time the selection changes; no scene file.

**Building selection behaviour**:

- When a building with `state != BuildingState.COMPLETE` is selected, the HUD shows only the Destroy action button regardless of building type.
- When construction completes, `EventBus.building_construction_complete` fires `_on_building_construction_complete`, which re-calls `_on_building_selected` on the same building if it is still selected, replacing the Destroy-only panel with the building's full action set.
- Buildings that implement `is_respawning_hero()` (or are an instance of `TownCenterBuildable`) are treated as Town Centers: the HUD shows the Town Center action set and wires the training queue.

**Player filtering**: `HudManager.local_player_id` (default `0`) gates all resource and age callbacks so that only data belonging to the local player is displayed.

## Naval Units

All naval units extend `ShipBase` (`scripts/units/ship_base.gd`), which itself extends `UnitBase`. `ShipBase` sets `civ_id = "atlantes"` on `_ready` so that the ocean terrain is treated as passable by `TerrainManager` for every ship regardless of the owning player's civilization.

### Unit classes

| Unit | Script | Age | Cost | Notes |
|---|---|---|---|---|
| Fishing Boat | `scripts/units/fishing_boat.gd` | Dark | 75W | Gathers `FOOD_FISH` from ocean nodes; returns food to nearest friendly Dock |
| Transport Ship | `scripts/units/transport_ship.gd` | Feudal | 125W | No combat; capacity 8; boards military units (Militia, Archer, Pikeman, Scout, Hero) — Villagers cannot board; unloads units at nearest passable shore position via `TerrainManager.nearest_passable` |
| War Galley | `scripts/units/war_galley.gd` | Feudal | 75W + 35G | Ranged naval combat: 6 attack, 5.5 range, 120 HP |

### Dock building

`scripts/buildings/dock.gd` / `scenes/buildings/dock.tscn` / `resources/buildings/dock.tres`

- Cost: 150 Wood — HP: 1,800 — Build time: 45 s
- Placement is validated by `_is_coastal()` in `game_world.gd`; the building can only be placed on land tiles directly adjacent to water.
- Trains the three naval units above with a queue cap of 5.
- HUD hotkey: **D** in the build menu.

Fishing boats automatically return food to the nearest friendly Dock. Right-clicking a Dock while carrying fish triggers the drop-off.

`Dock.water_access_point()` is the dock's berth: the first hull-clear open-water
position off its seaward side (`WATER_CLEARANCE` = 56 px, direction averaged from
16 ocean probes), falling back to `TerrainManager.nearest_ocean`. It is resolved
once and cached — neither the dock nor the coastline moves, and returning boats ask
for it every physics frame. Everything that navigates *to* a dock must aim at the
berth rather than at the dock node: the dock's own origin sits on the shoreline,
normally on land and always off the ocean navmesh, so a boat sent there stalled with
a full hold forever. `FishingBoat._drop_off_position()` returns the berth (or the
drop-off node's origin for buildings without the method) and the `DROP_OFF_RANGE`
check measures against whichever of the two is nearer. New ships spawn at the berth
too, spiralled aside by `_free_water_near` so a training queue doesn't stack on one
pixel. Gated by `tests/unit/test_dock_ship_spawn.gd` and
`tests/unit/test_fishing_boat_drop_off.gd`.

Fishing boats can also construct a **Fish Trap** on ocean tiles. Fish Traps are ocean buildings that regenerate food over time, providing a passive food source that does not require the boat to travel to a resource node.

Map boundary walls (invisible `NavigationObstacle2D` nodes along the map edges) prevent ships from sailing outside the playable area.

## Production Buildings

### TownCenterBuildable

`scripts/buildings/town_center_buildable.gd` (`class_name TownCenterBuildable`) extends `BuildingBase`. Requires Castle Age (age 2). Cost: 275 Wood (defined in `resources/buildings/town_center.tres`; 2400 HP). Scene: `scenes/buildings/town_center.tscn` (80×80 collision).

The building goes through the standard `BuildingBase` construction state machine while villagers build it. Once `state == COMPLETE` it activates two subsystems:

**Villager training** — queue cap 5 (`MAX_QUEUE`), cost 50 food (`VILLAGER_COSTS`). Public API mirrors the Stable/Barracks pattern:

| Method | Description |
|---|---|
| `order_train() -> bool` | Enqueues a villager; deducts food; emits `EventBus.train_queue_changed` |
| `order_cancel_train(index: int)` | Refunds food; removes entry; emits `EventBus.train_queue_changed` |
| `get_queue() -> Array` | Returns a duplicate of the current training queue |
| `get_max_queue() -> int` | Returns `MAX_QUEUE` (5) |
| `get_train_progress() -> float` | Fraction 0–1 of current training progress |

**Hero respawn** — listens to `EventBus.hero_died`. If the signal fires for the same `player_id`, the TC starts a 120-second (`HERO_RESPAWN_TIME`) countdown and re-spawns the hero on expiry via `_do_respawn_hero`. The respawn logic is designed so only one TC handles a given death event (the main TC connects first in scene order).

| Method | Description |
|---|---|
| `is_respawning_hero() -> bool` | `true` while a hero respawn countdown is active |
| `get_hero_respawn_fraction() -> float` | Progress 0–1 of the respawn timer |
| `get_hero_respawn_remaining() -> int` | Seconds remaining, ceiled |

**Drop-off** — a `DropOffBuilding` child node named `DropOff` is included in the scene. On `_ready`, `player_id` is propagated to it via `call_deferred("_sync_drop_off_player_id")` so villagers can return resources to this TC.

**HUD integration** — `HudManager._on_building_selected` detects `is_respawning_hero()` or `building is TownCenterBuildable` and renders the standard Town Center action panel (train villager, age-advance, hero-respawn bar). HUD build key: **Y** (`min_age: 2`).

### Stable

`scripts/buildings/stable.gd` (`class_name Stable`) extends `BuildingBase`. Trains cavalry units with a queue cap of 5 (`MAX_QUEUE`). Available units are gated by `AgeManager.get_age(player_id)` and civ-gated via the unit's civilization field:

| Unit ID | Class | Age requirement | Cost source | Civ restriction |
|---|---|---|---|---|
| `heavy_scout` | `HeavyScout` | Feudal (1) | `resources/units/heavy_scout_data.tres` | All |
| `knight` | `Knight` | Castle (2) | `resources/units/knight_data.tres` | All |
| `sand_raider` | `SandRaider` | Feudal (1) | `resources/units/sand_raider_data.tres` | Mahos only |
| `chevalier_normand` | `ChevalierNormand` | Castle (2) | `resources/units/chevalier_normand_data.tres` | Franks only |

Training cost is read from `UnitResource` fields (`cost_food`, `cost_wood`, `cost_gold`) and modified by `CivBonusManager.get_unit_cost_multiplier`. Resources are refunded on `order_cancel_train`. The `EventBus.train_queue_changed` signal is emitted after every queue mutation. On spawn, `PopulationManager.add_unit` is called and `EventBus.unit_spawned` is emitted.

### Research-only buildings

`Blacksmith`, `University`, and `Temple` extend `BuildingBase` and add no new API beyond the base class. They exist as production-building nodes so that `TechManager` can gate technology research by building type.

### Market

`scripts/buildings/market.gd` (`class_name Market`) extends `BuildingBase`.

Exchange rates are **dynamic per player per resource** (all operations require `BuildingState.COMPLETE`). Base rates are `BASE_SELL_RATE = 15` (resources per 1 gold) and `BASE_BUY_RATE = 20` (resources per 1 gold spent). Each lot traded degrades the relevant rate by `DEGRADE_PER_LOT = 3` steps, bounded by `MAX_SELL_RATE = 30` and `MIN_BUY_RATE = 5`. Rates recover 1 step every `RECOVERY_INTERVAL = 30` seconds via `_process`. State is tracked in per-player, per-resource offset dictionaries (`_sell_offsets`, `_buy_offsets`, `_recovery_timers`).

| Method | Direction | Description |
|---|---|---|
| `get_sell_rate(pid, resource) -> int` | query | Current sell rate (resources per 1 gold); increases with use |
| `get_buy_rate(pid, resource) -> int` | query | Current buy rate (resources per 1 gold spent); decreases with use |
| `sell_resource(player_id, resource)` | resource → gold | Single-unit sell at current sell rate; degrades rate |
| `buy_resource(player_id, resource)` | gold → resource | Single-unit buy at current buy rate; degrades rate |
| `sell_lot(player_id, resource)` | 100 resource → gold | Bulk sell: 100 / current sell rate gold received; degrades rate; emits `EventBus.market_rate_changed` |
| `buy_lot(player_id, resource)` | 5 gold → resource | Bulk buy: 5 × current buy rate resources received; degrades rate; emits `EventBus.market_rate_changed` |

## Cavalry Units

`HeavyScout` (`scripts/units/heavy_scout.gd`) and `Knight` (`scripts/units/knight.gd`) both extend `UnitBase`. Their movement and attack FSM pattern matches `Militia`: `MOVING` / `ATTACKING` states, `order_move` / `order_attack` entry points, avoidance via `NavigationAgent2D.velocity_computed`. Stats are defined entirely in their respective `UnitResource` `.tres` files.

## Siege Units

Three siege unit classes extend `UnitBase` and are produced by `SiegeWorkshop`.

### SiegeWorkshop

`scripts/buildings/siege_workshop.gd` (`class_name SiegeWorkshop`) extends `BuildingBase`. Requires Castle Age (age 2). Queue cap 5 (`MAX_QUEUE`). Units available are gated by `AgeManager.get_age(player_id)`:

| Unit ID | Class | Age requirement | Cost |
|---|---|---|---|
| `battering_ram` | `BatteringRam` | Castle (2) | 160W |
| `mangonel` | `Mangonel` | Castle (2) | 160W + 135G |
| `trebuchet` | `Trebuchet` | Imperial (3) | 200W + 200G |

Training cost is read from `UnitResource` fields and resources are refunded on `order_cancel_train`. `EventBus.train_queue_changed` is emitted after every queue mutation.

### BatteringRam

`class_name BatteringRam`. Melee siege unit. Overrides `_on_enemy_entered_range` to skip auto-attack if the entering body does not have a `building_data` property — rams never chase units. `_get_effective_attack_vs` multiplies base attack by 3.0 against buildings (further scaled by `CivBonusManager.get_siege_attack_bonus`) and by 0.2 against units.

### Mangonel and AoE splash

`class_name Mangonel`. Ranged siege unit with `SPLASH_RADIUS = 72.0` px. On each attack tick, `_fire_at(target_pos)` creates a `PhysicsShapeQueryParameters2D` with a `CircleShape2D` of that radius, calls `PhysicsDirectSpaceState2D.intersect_shape(query, 32)` at the impact point, and applies damage to every resulting collider that belongs to an enemy. Armor is subtracted per-target with a floor of 1.

Minimum range: `MIN_RANGE_RATIO = 0.35`. During `_handle_attacking`, if `dist < reach * MIN_RANGE_RATIO` the unit actively moves away from the target by 120 px. During `_handle_movement` the transition to `ATTACKING` only triggers when the target is inside `[reach * MIN_RANGE_RATIO, reach]`.

### Trebuchet — deploy/undeploy mechanic

`class_name Trebuchet`. Same AoE splash implementation as Mangonel but with `SPLASH_RADIUS = 48.0` px and `MIN_RANGE_RATIO = 0.40`.

Trebuchet adds a two-state deploy system on top of the base FSM:

| Bool flag | Meaning |
|---|---|
| `is_deployed` | Unit is unpacked and can fire |
| `_deploying` | Transition to deployed in progress |
| `_undeploying` | Transition to packed in progress |

`DEPLOY_TIME = 3.0` seconds. While either `_deploying` or `_undeploying` is true, `_physics_process` routes to `_handle_deploy_animation(delta)` instead of the normal FSM. On completion of undeploying, if an `attack_target` is still valid the unit resumes movement toward it automatically.

`order_move` and `order_attack` both call `_start_undeploy()` if `is_deployed` is true before issuing a nav target, ensuring the trebuchet never moves while packed. `_handle_movement` calls `_start_deploy()` when the target enters the valid firing band, replacing the direct `ATTACKING` state transition used by other ranged units.

## CivBonusManager — Extended API

Two query methods were added to `CivBonusManager`:

| Method | Signature | Description |
|---|---|---|
| `get_archer_armor_pierce_bonus` | `(player_id: int) -> float` | Returns additive pierce-armor bonus for archers; backed by `archer_armor_pierce` key in `_ADDITIVE_KEYS` |
| `get_unit_move_speed_multiplier` | `(player_id: int) -> float` | Returns the `unit_move_speed` multiplier applied to every unit's nav velocity |

`get_attack_speed_multiplier` handles `unit_id == "archer"` by returning the `archer_attack_speed` multiplier. `SandRaider` calls `CivBonusManager.get_attack_speed_multiplier(player_id, unit_data.id)` to scale its attack timer.

`get_unit_hp_multiplier`: `"sand_raider"` is included in the cavalry HP branch alongside `"scout"`, `"heavy_scout"`, and `"knight"`, so the `cavalry_hp` multiplier (e.g. Franks +15%) applies to Sand Raiders.

`get_unit_speed_multiplier`: `"sand_raider"` is included in the `scout_speed` branch, so the Mahos `scout_speed` bonus (+25%) applies to their unique unit.

`_ADDITIVE_KEYS` now includes `"archer_armor_pierce"` (alongside the existing `"unit_armor_melee"`). Additive keys accumulate flat points rather than multiplying.

`UnitBase._nav_velocity` multiplies movement speed by `CivBonusManager.get_unit_move_speed_multiplier(player_id)`. `Archer` attack speed is scaled by `CivBonusManager.get_attack_speed_multiplier(player_id, "archer")`.

## Age Advancement

Ages: Dark (0) → Feudal (1) → Castle (2) → Imperial (3). Advancing costs resources and takes time. Certain units, buildings, and technologies are locked behind age requirements.

## Weather System

`WeatherManager` (autoload, `scripts/core/weather_manager.gd`) drives a global procedural weather cycle. Weather affects all players equally and is controlled by two `MatchConfig` settings: `weather_enabled: bool` and `weather_frequency: int` (0=Off, 1=Normal, 2=Frequent, 3=Extreme). Both are exposed in the lobby as a single "Weather" option row.

### Weather types

| ID | `WeatherType` | Effect summary |
|---|---|---|
| `calima` | `CALIMA` | Saharan dust haze — land speed −15%, gather rate (food/wood) −20%, vision −40% |
| `atlantic_storm` | `ATLANTIC_STORM` | Rain & wind — naval speed −30%, fish gather −50%; projectile drift (crosswind) |
| `sea_fog` | `SEA_FOG` | Coastal fog (≤400 px from coast) — vision −60%, enemy units cloaked when intensity ≥ 0.5 (see the cloak rules below) |
| `trade_winds` | `TRADE_WINDS` | NE→SW wind — naval speed ±20% depending on heading; projectile drift along wind |
| `volcanic_ash` | `VOLCANIC_ASH` | Caldera zones (caldera radius + 800 px) — gather −30%, vision −50%, buildings drain 2 HP/s |

### Sea-fog cloak rules

`WeatherManager.is_unit_cloaked_by_weather(world_pos)` only answers the question
"is this position inside an active fog bank?". Two things break the cloak, and
`FogOfWar._apply_visibility` (the only caller with access to both sides) applies
them through `_breaks_fog_cloak`:

1. **Proximity.** An enemy within `WeatherManager.fog_spot_range(owner_id)` of any
   own unit or finished own building is visible anyway. The base range is
   `FOG_SPOT_RANGE` = 180 px, scaled by the owner civ's `fog_stealth` multiplier —
   the Atlantes ship 0.5, so they have to be found at 90 px.
2. **Attacking.** `UnitBase.is_revealed_by_combat()` stays true for
   `COMBAT_REVEAL_TIME` (3 s) after the unit's last strike (`_last_strike_msec`,
   stamped by the canonical machine in `_handle_attacking`). Firing gives your
   position away.

Without those rules the cloak hid *every* enemy inside the 400 px coastal band
regardless of line of sight — and on an Islands map the entire playable area is
inside that band, so whole armies became invisible while standing next to your
own units. Gated by `tests/unit/test_fog_cloak_reveal.gd`.

Map-type restrictions: `SEA_FOG` only spawns on ISLANDS / VOLCANIC_COAST / DESERT_COAST; `VOLCANIC_ASH` only on VOLCANIC_COAST (the only map type that generates calderas). `_in_volcanic_zone` checks the `TerrainManager` CALDERA zones; a map with no caldera (legacy save mid-event) falls back to whole-map coverage so an active event is never a no-op.

### Phase state machine

```
CLEAR ──(timer)──► RAMP_IN (10 s) ──► PEAK (variable) ──► RAMP_OUT (10 s) ──► CLEAR
```

`intensity` is a 0..1 float that smoothly ramps in/out. All stat-modifier calls multiply by `intensity` so effects fade gracefully.

### Stat-modifier query API

| Method | Consumers |
|---|---|
| `get_move_speed_multiplier(world_pos)` | `UnitBase._nav_velocity` |
| `get_naval_speed_multiplier(move_dir)` | `ShipBase._nav_velocity` |
| `get_gather_rate_multiplier(resource, world_pos)` | `Villager` gather loop |
| `get_vision_multiplier(world_pos)` | `FogOfWar._reveal_from_units/buildings` |
| `get_projectile_drift() → Vector2` | `Trebuchet._spawn_projectile`, `Mangonel._fire_at` |
| `is_unit_cloaked_by_weather(world_pos) → bool` | `FogOfWar._apply_visibility` |
| `fog_spot_range(player_id) → float` | `FogOfWar._breaks_fog_cloak` |
| `get_building_damage_rate(world_pos) → float` | `BuildingBase._process` |

### Visual overlay

`WeatherOverlay` (`scripts/ui/weather_overlay.gd`) is a `Node2D` child of `GameWorld` (z_index 15). It draws entirely in screen/viewport coordinates using `draw_set_transform_matrix(get_canvas_transform().affine_inverse())` at the start of `_draw()`, so the effect is camera-independent. Each weather type has dedicated particle arrays updated in `_process` and drawn in `_draw`:

| Weather | Visual |
|---|---|
| ATLANTIC_STORM | Falling rain lines (`_rain_particles`, 60) |
| TRADE_WINDS | Horizontal streak lines (`_wind_particles`, 30) |
| CALIMA | Drifting dust circles (`_dust_particles`, 80) |
| VOLCANIC_ASH | Falling ash circles (`_ash_particles`, 60) |
| SEA_FOG | Concentric vignette rects at screen edges |

All weather types also blend a full-screen color overlay that fades in/out with intensity.

### HUD notification

`GameWorld` listens to `WeatherManager.weather_changed` and `WeatherManager.weather_cleared` and calls `HudManager.show_weather(weather_id)` / `HudManager.hide_weather()`. The HUD creates a transient `Label` with the weather name that fades in over 0.8 s and fades out over 1.5 s.

### Conquest victory condition

Conquest mode (the default) no longer ends on Town Center destruction alone. A player is defeated only when they have **zero units AND zero buildings** remaining. When the AI's TC is destroyed, `AIPlayer` attempts to rebuild it using the safest available villager; if it has no villagers, no buildings, and no units it emits `EventBus.player_eliminated` and the match checks for an overall winner.
