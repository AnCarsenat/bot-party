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
## True: the mode hands out the cards itself (process_pick), not first come first served.
var custom_pick := false
## True: the mode runs the party its own way: start_level() when an arena is
## loaded instead of the card box (see the Auction mod).
var custom_flow := false
## Standard rules ("target", "round_time", "coins", "surprises", "equal_odds")
## this mode doesn't use: Party > Rules doesn't show them.
var hidden_rules: Array = []


## The mode's own rules, shown in Party > Rules under the usual ones. Each:
## {key, name, info, default, min, max, step} for numbers, {key, name, info,
## default (true/false)} for on/off, or {key, name, info, default, choices:
## [[value, "Shown as"], ...]}. Add "when": {other_key: value} to show a rule
## only while another one has that value. Read them with Party.rule(key).
func rule_defs() -> Array:
	return []


## Other defaults for standard rules (like {"round_time": 40}).
func rule_defaults() -> Dictionary:
	return {}


## A new party (before its first scene): `session` can be changed (Party.session).
func party_started(_session: Dictionary) -> void:
	pass


## custom_flow: an arena is loaded and ready (instead of the card box). Use
## ctl.place_cards(), ctl.runners, ctl.start_countdown()...
func start_level(_ctl: Node) -> void:
	pass


## The scoreboard was shown. Return true to take it from there (next scene,
## end of the party...), false for the usual (winner check, next round).
func after_score(_ctl: Node) -> bool:
	return false


## The scoreboard's heading ("" for the usual "First to N points wins").
func goal_text() -> String:
	return ""


## The score the scoreboard's bars are drawn against (0: the winning score).
func score_goal() -> int:
	return 0


## The party starts (once, in the arena).
func setup(_ctl: Node) -> void:
	pass


## The box is filled (ctl.box: item ids), picking starts.
func pick_started(_ctl: Node) -> void:
	pass


## Every frame of picking, when custom_pick is true. Fill ctl.picks (slot -> index
## in ctl.box), use ctl.pressed(slot, "action_1"), ctl.cursors (slot -> card
## they stand on), ctl.update_box(), ctl.say() / ctl.note(), and call
## ctl.start_place() when done (players without a card place nothing).
func process_pick(_ctl: Node, _delta: float) -> void:
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
