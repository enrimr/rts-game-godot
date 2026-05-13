extends Node

## EventBus — global signal dispatcher to decouple systems.
## Emit signals here instead of coupling nodes directly.

# Economy
signal resource_changed(player_id: int, resource: String, amount: int)
signal resource_depleted(player_id: int, resource: String)

# Units
signal unit_spawned(unit: Node, player_id: int)
signal unit_died(unit: Node, player_id: int)
signal hero_died(player_id: int, hero_data: UnitResource)
signal hero_respawned(player_id: int)
signal garrison_changed(ship: Node, current: int, capacity: int)
signal unit_selected(units: Array)
signal unit_command_issued(units: Array, command: Dictionary)
signal animal_selected(animal: Node)

# Population
signal population_changed(player_id: int, current: int, cap: int)
signal population_cap_changed(player_id: int, cap: int)

# Resources
signal resource_node_selected(node: Node)

# Buildings
signal train_queue_changed(building: Node, queue: Array, max_queue: int)
signal building_placed(building: Node, player_id: int)
signal building_destroyed(building: Node, player_id: int)
signal building_construction_complete(building: Node)
signal building_selected(building: Node)
signal wonder_built(player_id: int)
signal wonder_destroyed(player_id: int)

# Research
signal technology_researched(player_id: int, tech_id: String)
signal age_advance_started(player_id: int, target_age: int)
signal age_advance_complete(player_id: int, new_age: int)

# Combat
signal unit_attacked(attacker: Node, target: Node)
signal hero_ability_used(player_id: int)
signal damage_dealt(target: Node, amount: float, attacker: Node)
signal ai_unit_under_attack(player_id: int)

# Map
signal fog_of_war_updated(player_id: int, revealed_cells: Array)
signal minimap_move_order(world_pos: Vector2)
signal camera_follow_cancelled()
signal camera_moved()
