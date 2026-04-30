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

## Fog of War

Tracked per-player as a boolean grid. Revealed when any unit/building has line of sight of a cell. Stored in `MapManager._fog_revealed`.

## AI System

`AIPlayer` runs on a 1-second tick rather than every frame. Strategy enum controls economic vs. military priorities. Difficulty scales timings and reaction windows.

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

## Age Advancement

Ages: Dark (0) → Feudal (1) → Castle (2) → Imperial (3). Advancing costs resources and takes time. Certain units, buildings, and technologies are locked behind age requirements.
