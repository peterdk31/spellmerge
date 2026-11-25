extends "res://tests/support/screenshot.gd"
## The builder showing On Any Cast (docs/milestones/staff-language.md, L3, "Reading it in the
## builder"), in the hub with the radial builder picked: the echo chamber's familiar (frost bolts on
## any cast) and an answering rune (a fire blast), the marker on each On Any Cast in turn
## (`staff_any_cast_tree`, `staff_any_cast_tree_rune`).

const DevHub := preload("res://tests/support/dev_hub.gd")

const CARDS: Array[StringName] = [&"on_any_cast", &"familiar", &"frost", &"bolt", &"on_any_cast", &"rune", &"fire", &"blast", &"pulse"]

var _input: Node = null
var _hud: Node = null


func take() -> void:
	if not need(["PlayerInput", "Hud", "Flow", "Events"]):
		return
	_input = root.get_node("PlayerInput")
	_hud = root.get_node("Hud")
	var flow: Node = root.get_node("Flow")
	var events: Node = root.get_node("Events")
	_input.call("add_virtual_device", 0)
	if not DevHub.start(flow, root.get_node("Registry")):
		fail("the hub did not start")
		return
	if not await wait_for(func() -> bool: return flow.call("get_wizard", 0) != null):
		fail("the hub did not start with a wizard")
		return
	_hud.call("_on_builder_options_changed", 0, true)
	events.emit_signal("staff_cards_requested", 0, 1, CARDS, (flow.call("get_wizard", 0) as Actor).key())
	tap(0, &"back")
	if not await wait_for(func() -> bool: return _hud.call("get_radial", 0).call("is_open")):
		fail("the radial builder did not open")
		return
	tap(0, &"extra")
	await settle(8)
	_hud.call("get_radial", 0).call("mark_slot", 0)
	await settle(8)
	await shot("staff_any_cast_tree")
	_hud.call("get_radial", 0).call("mark_slot", 4)
	await settle(8)
	await shot("staff_any_cast_tree_rune")
	tap(0, &"back")
	await settle(8)
	flow.call("stop_run")
	await create_timer(0.3).timeout
