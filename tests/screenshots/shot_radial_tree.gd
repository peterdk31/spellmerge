extends "res://tests/support/screenshot.gd"
## Screenshots of the radial builder's tree view (owner, 2026-10-31, docs/milestones/
## M2-builder-tree.md, part T5), in the sandbox with the radial builder picked: one player with a
## nested staff (a held decoy whose timer fires a fire bolt, whose on expire fires a frost nova,
## and whose on hurt fires a last bolt) and the marker on a card deep in it (radial_tree), then
## all four players with their trees open at once (radial_tree_four_players).

const NESTED: Array[StringName] = [&"timer", &"on_hurt", &"hold", &"decoy", &"on_expire", &"fire", &"bolt", &"blast", &"frost", &"nova", &"bolt"]
const OTHERS: Array = [
	[&"on_hit", &"on_expire", &"bolt", &"fire", &"nova", &"frost", &"nova"],
	[&"double", &"bolt", &"on_hit", &"orbit", &"lightning", &"nova"],
	[&"homing", &"bolt", &"split", &"bolt", &"on_wall", &"bolt", &"rune"],
]

var _input: Node = null
var _hud: Node = null


func take() -> void:
	if not need(["PlayerInput", "Hud", "Flow", "Events"]):
		return
	_input = root.get_node("PlayerInput")
	_hud = root.get_node("Hud")
	var flow: Node = root.get_node("Flow")
	var events: Node = root.get_node("Events")
	for index in 4:
		_input.call("add_virtual_device", index)
	events.emit_signal("sandbox_requested", 0)
	if not await wait_for(func() -> bool: return flow.call("get_wizard", 3) != null):
		fail("the sandbox did not start with four wizards")
		return
	_hud.call("_on_builder_options_changed", true, 0, true)
	events.emit_signal("staff_cards_requested", 0, 1, _typed(NESTED))
	for index in 3:
		events.emit_signal("staff_cards_requested", index + 1, 1, _typed(OTHERS[index]))
	if not await _open([0]):
		return
	tap(0, &"extra")
	await settle(8)
	_hud.call("get_radial", 0).call("mark_slot", 8)
	await settle(8)
	await shot("radial_tree")
	if not await _open([1, 2, 3]):
		return
	for index in [1, 2, 3]:
		tap(index, &"extra")
	await settle(8)
	await shot("radial_tree_four_players")
	for index in 4:
		tap(index, &"back")
	await settle(8)
	flow.call("stop_run")
	await create_timer(0.3).timeout


func _typed(cards: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for card: Variant in cards:
		out.append(StringName(card))
	return out


## B for each of `players`, as a person opens the radial; fails unless every one opened.
func _open(players: Array[int]) -> bool:
	for player in players:
		tap(player, &"back")
	var opened: bool = await wait_for(func() -> bool: return players.all(func(player: int) -> bool: return _hud.call("get_radial", player).call("is_open")))
	if not opened:
		fail("the radial builders of players %s did not all open" % str(players.map(func(player: int) -> int: return player + 1)))
	return opened
