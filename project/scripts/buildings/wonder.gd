extends BuildingBase

class_name Wonder

# One villager at build_rate=25 fills 100 pts → 4s normally.
# Scale factor 150 → 4 * 150 = 600s (10 min) solo; multiple villagers cut it down.
const BUILD_TIME_SCALE: float = 150.0

func _ready() -> void:
	super._ready()
	if building_data == null:
		max_health = 5000.0
		health = 5000.0
		var hbar: ProgressBar = get_node_or_null("HealthBar") as ProgressBar
		if is_instance_valid(hbar):
			hbar.max_value = max_health
			hbar.value = health

func add_construction(base_amount: float) -> void:
	super.add_construction(base_amount / BUILD_TIME_SCALE)
