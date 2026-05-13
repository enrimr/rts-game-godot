extends BuildingBase

class_name Wonder

func _ready() -> void:
	super._ready()
	if building_data == null:
		max_health = 5000.0
		health = 5000.0
		var hbar: ProgressBar = get_node_or_null("HealthBar") as ProgressBar
		if is_instance_valid(hbar):
			hbar.max_value = max_health
			hbar.value = health
