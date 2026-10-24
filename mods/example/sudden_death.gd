extends PartyMode
## Example game mode: the first robot to reach the flag ends the round and takes
## all the points. Everything not overridden here works like Classic.


func _init() -> void:
	name = "Sudden death"
	description = "First to the flag takes 15 points and ends the round. Nobody else scores."


func player_finished(ctl: Node, slot: int) -> void:
	ctl.say("%s takes it all!" % Party.label(slot))
	ctl.end_round()


func score_round(ctl: Node, gains: Dictionary) -> void:
	for s in gains:
		gains[s] = 0
	if not ctl.finished.is_empty():
		gains[ctl.finished[0]] = 15
