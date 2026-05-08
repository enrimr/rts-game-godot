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
- All unit `order_move` implementations (`Militia`, `Archer`, `Pikeman`, `Scout`) and `Villager._start_move_to` call `_safe_destination` before setting `nav_agent.target_position`.
- `Animal` nodes call `TerrainManager.nearest_passable(pos, "")` in `order_move`, `_pick_wander_target`, and `_start_flee` so fauna never path onto water or other impassable terrain.

## NavMesh Carving

`MapGenerator._add_nav_obstacles(parent)` runs at map generation time:

- Creates `NavigationObstacle2D` nodes for every malpaís, risco, and caldera zone, parented inside the scene's `NavigationRegion2D`.
- On **Islands** maps, the default nav polygon (which would span the full map area including ocean) is replaced with per-island land polygons so the baked mesh never covers ocean tiles.

This means ship units — whose `civ_id` resolves to a civ that has ocean marked as passable — navigate a separate logical layer, while land units are physically blocked by the nav mesh boundaries.

## Fog of War

Tracked per-player as a boolean grid. Revealed when any unit/building has line of sight of a cell. Stored in `MapManager._fog_revealed`.

## Tech Tree System

Technologies are defined as `TechnologyResource` `.tres` files under `resources/technologies/`. Eight technologies are currently implemented:

| Technology | Researched at | Cost | Effect |
|---|---|---|---|
| `loom` | Barracks | Food | Villager HP / armor |
| `fletching` | Barracks | Food / Gold | Archer attack / range |
| `scale_barding` | Barracks | Food / Gold | Cavalry armor |
| `bodkin_arrow` | Barracks | Food / Gold | Archer attack |
| `chain_barding` | Barracks | Food / Gold | Cavalry armor |
| `blast_furnace` | Barracks | Food / Gold | Infantry attack |
| `plate_barding` | Barracks | Food / Gold | Cavalry armor |
| `shipwright` | Barracks | Food / Gold | Ship speed / cost |

`TechManager` (autoload) owns the research queue and applies effects when research completes. `CivBonusManager` (autoload) stores per-player multipliers derived from civilization bonuses and applied techs.

## AI System

`AIPlayer` runs on a 1-second tick rather than every frame. Strategy enum controls economic vs. military priorities. Difficulty scales timings and reaction windows.

The AI builds lumber camps, mining camps, farms, and multiple barracks as its economy grows. On **Islands** maps the AI also builds a Dock, trains fishing boats, war galleys, and a transport ship. The naval assault sequence boards military units onto the transport ship and sails to the enemy shore. The AI attacks the nearest enemy building rather than always targeting the Town Center.

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
| Transport Ship | `scripts/units/transport_ship.gd` | Feudal | 125W | No combat; boards military units (Militia, Archer, Pikeman, Scout, Hero) — Villagers cannot board |
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

## Age Advancement

Ages: Dark (0) → Feudal (1) → Castle (2) → Imperial (3). Advancing costs resources and takes time. Certain units, buildings, and technologies are locked behind age requirements.
