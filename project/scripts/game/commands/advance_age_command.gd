class_name AdvanceAgeCommand extends GameCommand

## Starts the player's age advance (cost and current-age validation live in
## AgeManager.start_advance).

static func make(p_player: int) -> AdvanceAgeCommand:
	var cmd: AdvanceAgeCommand = AdvanceAgeCommand.new()
	cmd.player_id = p_player
	return cmd

func kind() -> String:
	return "advance_age"

func execute(_world: Node2D) -> void:
	AgeManager.start_advance(player_id)
