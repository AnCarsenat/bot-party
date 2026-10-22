class_name PartyMode
extends RefCounted
## A way of playing party mode. The usual one ("Classic") is this class as it is;
## mods make new ones by extending it and overriding the hooks they need
## (see MODDING.md and mods/example/sudden_death.gd).
##
## `ctl` is the party controller: ctl.slots (players), ctl.players (slot -> robot),
## ctl.finished (slots that reached the flag, in order), ctl.run_time,
## ctl.end_round() (stop the race now), ctl.say(text) (big message).

## Shown in Party > Rules.
var name := "Classic"
var description := "Reach the flag. Traps you placed score when they get someone."


## The party starts (once, in the arena).
func setup(_ctl: Node) -> void:
	pass


## "Go!": the race begins.
func round_started(_ctl: Node) -> void:
	pass


## Every frame of the race.
func process(_ctl: Node, _delta: float) -> void:
	pass


## A robot reached the flag (already in ctl.finished).
func player_finished(_ctl: Node, _slot: int) -> void:
	pass


## The round is over. `gains` (slot -> points) holds the usual points:
## change them as you like.
func score_round(_ctl: Node, _gains: Dictionary) -> void:
	pass
