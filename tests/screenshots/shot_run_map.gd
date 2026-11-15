extends "res://tests/support/screenshot.gd"
## The run's map on the pause menu's Map page (run generation RG8, hud/widgets/run_map_view.gd):
## the generated crypt run just begun (`run_map_first_room`: the party framed in gold in the first
## room, every room in reach), then the party a way on (`run_map_a_way_on`: the run area told the
## way taken, so the rooms behind it and on the other branch dim; the run's seed may have made a map
## of one room a row), and a made-up map of the crypt's widest shape told to the map itself
## (`run_map_branches`: three rooms a row, the party on the right branch). Each at 3x, round the
## screen's middle, and the whole screen once (`run_map_screen`).

## The made-up map: each room's row, kind and links, and where the party is.
const ROWS: Array[int] = [0, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4, 5]
const KINDS: Array[StringName] = [&"fight", &"fight", &"fight", &"fight", &"fight", &"fight", &"fight", &"fight", &"fight", &"fight", &"fight", &"boss"]
const LINKS: Array = [[1, 2], [3, 4], [4, 5], [6], [6, 7], [7], [8, 9], [9, 10], [11], [11], [11], []]
const AT: int = 5
const HALF := Vector2i(80, 110)


func _init() -> void:
	pin_room = false


func take() -> void:
	if not need(["PlayerInput", "Hud", "Flow", "Events", "UIFocus", "Run"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var hud: Node = root.get_node("Hud")
	var ui_focus: Node = root.get_node("UIFocus")
	input.call("add_virtual_device", 0)
	if not flow.call("start_run", 0) or not await wait_for(func() -> bool: return flow.call("get_wizard", 0) != null):
		fail("the crypt run did not start")
		return
	await settle()
	tap(0, &"pause")
	await settle()
	var pause_menu: Node = hud.call("get_pause_menu")
	var row: Node = pause_menu.call("button", "Map")
	if not pause_menu.call("is_open") or row == null or not (row as Control).visible:
		fail("the pause menu is not open with its Map row")
		return
	ui_focus.call("focus", 0, row)
	tap(0, &"accept")
	await settle()
	var view: Node = pause_menu.call("map_view")
	if not (view as Control).is_visible_in_tree() or not view.call("has_map"):
		fail("the Map page does not show the run's map")
		return
	await shot("run_map_screen")
	await snap(Vector2(320.0, 180.0), "run_map_first_room", HALF, 3)
	# The run area moves on through the map as the party takes a way (Flow is not asking, so the
	# room on screen stays: only the map moves on, which is all this picture shows).
	root.get_node("Events").emit_signal("run_way_taken", 0)
	await settle()
	if int(view.get("at")) <= 0:
		fail("the map did not move on")
		return
	await snap(Vector2(320.0, 180.0), "run_map_a_way_on", HALF, 3)
	var links: Array[PackedInt32Array] = []
	for room: Array in LINKS:
		links.append(PackedInt32Array(room))
	view.call("show_map", PackedInt32Array(ROWS), KINDS, links, AT)
	await settle()
	await snap(Vector2(320.0, 180.0), "run_map_branches", HALF, 3)
