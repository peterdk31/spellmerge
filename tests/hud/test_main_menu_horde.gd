extends "res://tests/support/suite.gd"
## The main menu's Horde button (docs/milestones/horde.md, H2): shown in every build channel, it
## only sends `horde_requested(0)` (flow starts the horde run). The focus stays where it was:
## Sandbox in `dev` and `preview`, Play in the others.

const MenuScene: PackedScene = preload("res://hud/menus/main_menu/main_menu.tscn")
const EventsScript := preload("res://core/events/events.gd")

const CHANNELS: Array[String] = ["dev", "preview", "nightly", "stable"]

var hordes: Array[int] = []
var plays: Array[int] = []
var sandboxes: Array[int] = []


func _menu(channel: String) -> Control:
	var bus := own(EventsScript.new()) as EventsScript
	bus.horde_requested.connect(func(player: int) -> void: hordes.append(player))
	bus.play_requested.connect(func(player: int) -> void: plays.append(player))
	bus.sandbox_requested.connect(func(player: int) -> void: sandboxes.append(player))
	var menu := MenuScene.instantiate() as Control
	menu.set("events", bus)
	menu.set("channel", channel)
	root.add_child(own(menu))
	return menu


func before_each() -> void:
	hordes.clear()
	plays.clear()
	sandboxes.clear()


func test_every_channel_shows_it() -> void:
	for channel: String in CHANNELS:
		var menu := _menu(channel)
		var horde := menu.get_node("%Horde") as Button
		check(horde.visible, "%s: the Horde button shows" % channel)
		check_equal(horde.text, "Horde", "%s: it says Horde" % channel)


func test_the_focus_stays_on_sandbox_or_play() -> void:
	for channel: String in CHANNELS:
		var menu := _menu(channel)
		var focused: String = "Sandbox" if channel == "dev" or channel == "preview" else "Play"
		check((menu.get_node("%" + focused) as Button).has_focus(), "%s: %s has the focus" % [channel, focused])
		check(not (menu.get_node("%Horde") as Button).has_focus(), "%s: Horde does not take it" % channel)


func test_it_sends_only_horde_requested() -> void:
	for channel: String in CHANNELS:
		hordes.clear()
		plays.clear()
		sandboxes.clear()
		var menu := _menu(channel)
		(menu.get_node("%Horde") as Button).pressed.emit()
		check_equal(hordes, [0] as Array[int], "%s: horde_requested(0)" % channel)
		check_equal(plays, [] as Array[int], "%s: not play_requested" % channel)
		check_equal(sandboxes, [] as Array[int], "%s: not sandbox_requested" % channel)


func test_it_stands_below_play() -> void:
	var menu := _menu("stable")
	var play := menu.get_node("%Play") as Button
	var horde := menu.get_node("%Horde") as Button
	check(horde.get_parent() == play.get_parent(), "in the same column as Play")
	check_equal(horde.get_index(), play.get_index() + 1, "right below Play")
