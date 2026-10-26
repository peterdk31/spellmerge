extends "res://tests/support/suite.gd"
## The main menu's Sandbox button (staffs B7): shown and focused in `dev` and `preview` builds,
## hidden in the others, and it only sends `sandbox_requested(0)` (flow starts the sandbox).

const MenuScene: PackedScene = preload("res://hud/menus/main_menu/main_menu.tscn")
const EventsScript := preload("res://core/events/events.gd")

var requests: Array[int] = []
var plays: Array[int] = []


func _menu(channel: String) -> Control:
	var bus := own(EventsScript.new()) as EventsScript
	bus.sandbox_requested.connect(func(player: int) -> void: requests.append(player))
	bus.play_requested.connect(func(player: int) -> void: plays.append(player))
	var menu := MenuScene.instantiate() as Control
	menu.set("events", bus)
	menu.set("channel", channel)
	root.add_child(own(menu))
	return menu


func before_each() -> void:
	requests.clear()
	plays.clear()


func test_dev_and_preview_show_it_with_the_focus() -> void:
	for channel: String in ["dev", "preview"]:
		var menu := _menu(channel)
		var sandbox := menu.get_node("%Sandbox") as Button
		check(sandbox.visible, "%s: the Sandbox button shows" % channel)
		check(sandbox.has_focus(), "%s: it has the focus, so one press starts the sandbox" % channel)
		check((menu.get_node("%Play") as Button).visible, "%s: Play is still there" % channel)


func test_nightly_and_stable_hide_it() -> void:
	for channel: String in ["nightly", "stable"]:
		var menu := _menu(channel)
		check(not (menu.get_node("%Sandbox") as Button).visible, "%s: no Sandbox button" % channel)
		check((menu.get_node("%Play") as Button).has_focus(), "%s: Play has the focus" % channel)


func test_it_sends_only_sandbox_requested() -> void:
	var menu := _menu("preview")
	(menu.get_node("%Sandbox") as Button).pressed.emit()
	check_equal(requests, [0] as Array[int], "sandbox_requested(0)")
	check_equal(plays, [] as Array[int], "not play_requested")
	(menu.get_node("%Play") as Button).pressed.emit()
	check_equal(plays, [0] as Array[int], "Play still starts the normal game")
