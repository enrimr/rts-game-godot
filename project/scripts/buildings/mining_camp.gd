extends BuildingBase

class_name MiningCamp

## Caldera claim (Volcanic Coast): a Mining Camp raised in a caldera's shadow
## taps the volcanic rock — a slow stone trickle for its owner. This is the
## "+stone for controller" the CALDERA terrain always promised.
const CALDERA_CLAIM_RADIUS: float = 800.0
const CALDERA_STONE_INTERVAL: float = 8.0
const CALDERA_STONE_AMOUNT: int = 1

var _caldera_claim: bool = false
var _caldera_timer: float = 0.0

func _ready() -> void:
	super._ready()
	construction_complete.connect(_on_construction_complete)
	if state == BuildingState.COMPLETE:
		_register_drop_off()
		_caldera_claim = _near_caldera()

func _on_construction_complete() -> void:
	_register_drop_off()
	_caldera_claim = _near_caldera()

func _register_drop_off() -> void:
	var drop_off := DropOffBuilding.new()
	drop_off.player_id = player_id
	add_child(drop_off)

func _near_caldera() -> bool:
	for z: Dictionary in TerrainManager.get_zones():
		if (z["type"] as TerrainManager.TerrainType) != TerrainManager.TerrainType.CALDERA:
			continue
		if global_position.distance_to(z["center"] as Vector2) \
				<= (z["radius"] as float) + CALDERA_CLAIM_RADIUS:
			return true
	return false

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# The authority trickles; client mirrors receive stockpiles via meta.
	if not _caldera_claim or NetworkSession.is_client():
		return
	_caldera_timer += delta
	if _caldera_timer >= CALDERA_STONE_INTERVAL:
		_caldera_timer -= CALDERA_STONE_INTERVAL
		ResourceManager.add_resource(player_id, "stone", CALDERA_STONE_AMOUNT)
