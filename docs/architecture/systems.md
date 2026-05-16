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
  - **ActionButtonsGrid**: `GridContainer` placeholder for future action buttons; currently empty.
  - **MinimapPanel**: contains `MinimapPlaceholder` (`ColorRect`), a placeholder for a future minimap renderer.
- **PauseOverlay** (`ColorRect`, full-screen, 50 % black): visible only when the game is paused.

**UnitPortrait** (`class_name UnitPortrait extends PanelContainer`): built entirely in code (`_ready`). Displays a 6-character name abbreviation and a color-coded HP bar (green > 50 %, yellow > 25 %, red ≤ 25 %). Created and discarded each time the selection changes; no scene file.

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
