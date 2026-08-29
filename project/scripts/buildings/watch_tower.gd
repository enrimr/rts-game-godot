extends BuildingBase

class_name WatchTower

## Defensive tower: always fires one arrow at the nearest enemy in range, and
## every garrisoned unit adds another arrow to the volley (AoE2-style). The
## attack machinery lives in BuildingBase (_ranged_attack_* overrides); the
## garrison rules in BuildingBase.can_garrison_unit.

const GARRISON_CAPACITY: int = 5

func garrison_capacity() -> int:
	return GARRISON_CAPACITY

func _ranged_attack_arrows() -> int:
	return 1 + _garrison.size()
