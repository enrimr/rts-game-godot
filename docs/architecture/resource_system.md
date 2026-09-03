# Resource System

Food, wood, gold, and stone flow through three layers: storage (`ResourceManager`), gathering (`Villager` + `ResourceNode`), and display (`HudManager` + `ResourceDisplay`).

---

## Storage — `ResourceManager`

Autoload singleton. Stores resources per player in a nested dictionary:

```gdscript
_player_resources[player_id] = { food: 200, wood: 75, gold: 50, stone: 0 }
```

Starting amounts when a match begins: `food=200, wood=75, gold=50, stone=0`.

Values are stored as `float` to allow fractional accumulation (e.g. farms trickle-feed continuously).

### Key functions

| Function | Behaviour |
|---|---|
| `init_player(player_id, starting_resources)` | Initialise a player's stockpile |
| `add_resource(player_id, resource, amount)` | Add amount, emit signals |
| `spend_resource(player_id, costs)` | Deduct if affordable, return `bool` |
| `can_afford(player_id, costs)` | Validate without deducting |
| `register_node(node)` | Add a `ResourceNode` to the spatial cache |
| `get_nearest_resource(resource_name, from, max_range, exclude)` | Pathfinding helper for villagers |

After every `add_resource` or `spend_resource` call two signals fire:
1. `EventBus.resource_changed(player_id, resource, new_amount)`
2. `ResourceManager.resources_updated(player_id, resources)` (full dict, used for stats)

---

## Resource nodes — `ResourceNode`

Scene node placed on the map. Tracks how much is left and handles depletion.

```
ResourceType enum: WOOD | GOLD | STONE | FOOD_HUNT | FOOD_FISH | FOOD_BERRY | OLIVINA
```

All three food variants map to the `"food"` string for `ResourceManager`. `OLIVINA` is a game-specific resource.

`gather(amount) -> float` — deducts from `remaining_amount`, emits `depleted` when empty and calls `queue_free()`.

On `_ready` each node registers itself with `ResourceManager.register_node(self)`, so the spatial cache is always up to date. The `depleted` signal is connected to `ResourceManager._on_node_depleted()` which removes the node from the cache.

---

## Gathering loop — `Villager`

```
Every gather_interval (default 1 s):
  ResourceNode.gather(gather_rate)
    → apply CivBonusManager multiplier
    → apply WeatherManager multiplier
    → accumulate carried_amount (cap: carry_capacity = 10
      × CivBonusManager.get_carry_capacity_multiplier — the Blacksmith
      carreta_canaria / carreton_isleno techs each add +25%)

When carried_amount == carry_capacity (or node depleted):
  order_drop_off() → move to nearest DropOffBuilding

On arrival at drop-off:
  ResourceManager.add_resource(player_id, carried_resource, carried_amount)
  carried_amount = 0
  resume gathering
```

**Range constants:**

| Constant | Value |
|---|---|
| `GATHER_RANGE` | 48 px |
| `DROP_OFF_RANGE` | 72 px |
| `FALLBACK_RESOURCE_RANGE` | 400 px |
| `BLOCKED_RESOURCE_RANGE` | 180 px |

If the gather target becomes invalid or unreachable (blocked 3 times), the villager searches for the nearest node of the same resource type within `FALLBACK_RESOURCE_RANGE`, then falls back to any resource within `BLOCKED_RESOURCE_RANGE`.

Drop-off buildings are found via the `"drop_off_buildings"` group (town center, lumber camp, mining camp, mill, farm). The `DropOffBuilding` node in each scene adds itself to that group on `_ready` (the Mill registers its node programmatically on construction complete).

---

## Spending resources

Any system that trains units or constructs buildings calls:

```gdscript
if ResourceManager.can_afford(player_id, costs):
    ResourceManager.spend_resource(player_id, costs)
```

`costs` is a plain dictionary, e.g. `{ "food": 60, "gold": 75 }`.

### Example costs

| Action | Cost |
|---|---|
| Train villager | `{ food: 50 }` |
| Build house | `{ wood: 25 }` |
| Build barracks | `{ wood: 175 }` |
| Train knight | `{ food: 60, gold: 75 }` |
| Train war galley | `{ wood: 75, gold: 35 }` |
| Build wonder | `{ wood: 2500, food: 2500, stone: 2500, gold: 5000 }` |

---

## HUD display — `HudManager` + `ResourceDisplay`

`HudManager` holds four `ResourceDisplay` child nodes (`%FoodDisplay`, `%WoodDisplay`, `%GoldDisplay`, `%StoneDisplay`), one per resource.

`ResourceDisplay` is a plain `HBoxContainer` with an icon label and an amount label. `set_amount(value: int)` is the only public method.

On `_ready`, `HudManager` connects:

```gdscript
EventBus.resource_changed.connect(_on_resource_changed)
```

Handler (filtered to `local_player_id`):

```gdscript
func _on_resource_changed(player_id, resource, amount):
    if player_id != local_player_id:
        return
    match resource:
        "food":  _food_display.set_amount(amount)
        "wood":  _wood_display.set_amount(amount)
        "gold":  _gold_display.set_amount(amount)
        "stone": _stone_display.set_amount(amount)
    _refresh_button_states()  # enable/disable action buttons by affordability
```

`_refresh_button_states()` re-checks every visible action button against `ResourceManager.can_afford()` so buttons grey out when funds are insufficient.

---

## Full data flow

```
ResourceNode.gather(rate)
  └─ Villager._handle_gathering()
       accumulates carried_amount
       when full → _handle_returning()
         └─ ResourceManager.add_resource(player_id, resource, amount)
              ├─ EventBus.resource_changed  →  HudManager._on_resource_changed()
              │                                  └─ ResourceDisplay.set_amount()
              └─ ResourceManager.resources_updated  →  stat tracking

Training / construction
  └─ ResourceManager.spend_resource(player_id, costs)
       ├─ EventBus.resource_changed  →  HudManager (same path as above)
       └─ _refresh_button_states()
```

---

## Related files

| File | Role |
|---|---|
| `project/scripts/core/resource_manager.gd` | Storage, spatial cache, signals |
| `project/scripts/economy/resource_node.gd` | Map resource node, depletion |
| `project/scripts/economy/drop_off_building.gd` | Drop-off point marker |
| `project/scripts/units/villager.gd` | Gathering and returning logic |
| `project/scripts/ui/hud_manager.gd` | Signal wiring, button state refresh |
| `project/scripts/ui/resource_display.gd` | Single-resource HUD widget |
| `project/scripts/core/event_bus.gd` | `resource_changed`, `resource_depleted` signals |
| `project/scripts/core/civ_bonus_manager.gd` | Gather rate multipliers per civilisation |
| `project/scripts/core/weather_manager.gd` | Weather-based gather rate multipliers |
