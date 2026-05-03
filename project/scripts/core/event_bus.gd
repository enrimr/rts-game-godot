extends Node

## EventBus — global signal dispatcher to decouple systems.
## Emit signals here instead of coupling nodes directly.

# Economy
signal resource_changed(player_id: int, resource: String, amount: int)
signal resource_depleted(player_id: int, resource: String)

# Units
signal unit_spawned(unit: Node, player_id: int)
signal unit_died(unit: Node, player_id: int)
signal unit_selected(units: Array)
signal unit_command_issued(units: Array, command: Dictionary)

# Population
signal population_changed(player_id: int, current: int, cap: int)
signal population_cap_changed(player_id: int, cap: int)

# Buildings
signal train_queue_changed(building: Node, queue: Array, max_queue: int)
signal building_placed(building: Node, player_id: int)
signal building_destroyed(building: Node, player_id: int)
signal building_construction_complete(building: Node)
signal building_selected(building: Node)

# Research
signal technology_researched(player_id: int, tech_id: String)
signal age_advance_started(player_id: int, target_age: int)
signal age_advance_complete(player_id: int, new_age: int)

# Combat
signal unit_attacked(attacker: Node, target: Node)
signal damage_dealt(target: Node, amount: float, attacker: Node)

# Map
signal fog_of_war_updated(player_id: int, revealed_cells: Array)
