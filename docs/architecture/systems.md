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
| `bake_minimap_texture` | `() -> ImageTexture` | Generates a 256×256 terrain texture used by the minimap renderer |

**Integration points:**

- `UnitBase` carries a `civ_id: String = ""` property. Its `_safe_destination(destination: Vector2) -> Vector2` helper calls `TerrainManager.nearest_passable` before any nav agent assignment.
- All unit `order_move` implementations (`Militia`, `Archer`, `Pikeman`, `Scout`, `HeavyScout`, `Knight`) and `Villager._start_move_to` call `_safe_destination` before setting `nav_agent.target_position`.
- `Animal` nodes call `TerrainManager.nearest_passable(pos, "")` in `order_move`, `_pick_wander_target`, and `_start_flee` so fauna never path onto water or other impassable terrain.

## NavMesh Carving

`MapGenerator._add_nav_obstacles(parent)` runs at map generation time:

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

## AI System

`AIPlayer` runs on a 1-second tick rather than every frame. Strategy enum controls economic vs. military priorities. Difficulty scales timings and reaction windows.

The AI builds lumber camps, mining camps, farms, and multiple barracks as its economy grows. On **Islands** maps the AI also builds a Dock, trains fishing boats, war galleys, and a transport ship. The naval assault sequence boards idle military units onto the transport ship and calls `order_move_then_unload` toward the enemy TC; on arrival the ship positions each unit at the nearest passable land tile without issuing a move order. Every tick on naval maps, `_attack_with_idle_land_units()` scans for idle military units that are already on the enemy island (closer to the enemy TC than to the AI's own TC) and orders them to attack the nearest enemy building. The AI attacks the nearest enemy building rather than always targeting the Town Center.

## UI / HUD System

The HUD is a `CanvasLayer` scene at `scenes/ui/hud/hud.tscn`, instanced as a child of `GameWorld` in `scenes/game/game_world.tscn`. The root node carries `hud_manager.gd`, which owns all display logic.

**EventBus wiring** (`_ready` connects):

| Signal | Handler | Effect |
|---|---|---|
| `EventBus.resource_changed` | `_on_resource_changed` | Updates the matching `ResourceDisplay` for the local player |
| `EventBus.unit_selected` | `_on_unit_selected` | Rebuilds the unit portraits grid and detail panel |
| `EventBus.age_advance_complete` | `_on_age_advance_complete` | Updates the age label for the local player |
| `GameManager.game_started` | `_on_game_started` | Starts the in-game clock |
| `GameManager.game_paused` | `toggle_pause` | Shows/hides the full-screen pause overlay |

**Component breakdown**:

- **TopBar** (`PanelContainer`, anchored top): four `ResourceDisplay` nodes (Food, Wood, Gold, Stone), a population `Label`, an age `Label`, and a game-clock `Label`.
- **ResourceDisplay** (`class_name ResourceDisplay extends HBoxContainer`): two `Label` children — `IconLabel` for the resource name and `AmountLabel` for the count. Updated via `set_amount(value: int)`.
- **BottomBar** (`PanelContainer`, anchored bottom): a selection panel and a minimap panel.
  - **UnitPortraitsGrid** (`GridContainer`, 10 columns, max 40 portraits): populated dynamically by `HudManager.update_selection`. Each cell is a `UnitPortrait` instance.
  - **UnitDetailPanel**: shows the first selected unit's display name and HP bar.
  - **ActionButtonsGrid**: `GridContainer` with `ACTION_COLS = 5` columns and `ACTION_ROWS = 2` rows (10 slots per page). When the active action list exceeds 10 entries, the last two slots on the bottom row become ◀/▶ pagination buttons. `_render_action_page()` rebuilds the grid for the current `_action_page`.
  - **MinimapPanel**: contains `MinimapPlaceholder` (`ColorRect`), a placeholder for a future minimap renderer.
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

`scripts/buildings/stable.gd` (`class_name Stable`) extends `BuildingBase`. Trains cavalry units with a queue cap of 5 (`MAX_QUEUE`). Available units are gated by `AgeManager.get_age(player_id)`:

| Unit ID | Class | Age requirement | Cost source |
|---|---|---|---|
| `heavy_scout` | `HeavyScout` | Feudal (1) | `resources/units/heavy_scout_data.tres` |
| `knight` | `Knight` | Castle (2) | `resources/units/knight_data.tres` |

Training cost is read from `UnitResource` fields (`cost_food`, `cost_wood`, `cost_gold`) and modified by `CivBonusManager.get_unit_cost_multiplier`. Resources are refunded on `order_cancel_train`. The `EventBus.train_queue_changed` signal is emitted after every queue mutation. On spawn, `PopulationManager.add_unit` is called and `EventBus.unit_spawned` is emitted.

### Research-only buildings

`Blacksmith`, `University`, and `Temple` extend `BuildingBase` and add no new API beyond the base class. They exist as production-building nodes so that `TechManager` can gate technology research by building type.

### Market

`scripts/buildings/market.gd` (`class_name Market`) extends `BuildingBase`.

Exchange rates (all operations require `BuildingState.COMPLETE`):

| Method | Direction | Rate |
|---|---|---|
| `sell_resource(player_id, resource)` | resource → gold | 15 units of resource per 1 gold |
| `buy_resource(player_id, resource)` | gold → resource | 1 gold per 20 units of resource |
| `sell_lot(player_id, resource)` | 100 resource → gold | 100 / 15 ≈ 6 gold |
| `buy_lot(player_id, resource)` | 5 gold → resource | 5 × 20 = 100 units |

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

Two new query methods were added to `CivBonusManager`:

| Method | Signature | Description |
|---|---|---|
| `get_archer_armor_pierce_bonus` | `(player_id: int) -> float` | Returns additive pierce-armor bonus for archers; backed by `archer_armor_pierce` key in `_ADDITIVE_KEYS` |
| `get_unit_move_speed_multiplier` | `(player_id: int) -> float` | Returns the `unit_move_speed` multiplier applied to every unit's nav velocity |

`get_attack_speed_multiplier` now also handles `unit_id == "archer"` by returning the `archer_attack_speed` multiplier.

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
| `sea_fog` | `SEA_FOG` | Coastal fog (≤400 px from coast) — vision −60%, enemy units cloaked when intensity ≥ 0.5 |
| `trade_winds` | `TRADE_WINDS` | NE→SW wind — naval speed ±20% depending on heading; projectile drift along wind |
| `volcanic_ash` | `VOLCANIC_ASH` | Central zone (≤800 px from origin) — gather −30%, vision −50%, buildings drain 2 HP/s |

Map-type restrictions: `SEA_FOG` only spawns on ISLANDS / VOLCANIC_COAST / DESERT_COAST.

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
