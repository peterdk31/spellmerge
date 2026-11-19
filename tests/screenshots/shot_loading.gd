extends "res://tests/support/screenshot.gd"
## The loading screen before the first room (owner, 2026-10-29), half way through compiling the
## shaders: `loading_half`. The load is held still, so the shot does not depend on the frame
## rate. The shaders are not compiled first (`warm_first`), or there would be no load to show.
## Then the party's departure from the hub's lit stone (`run_departure_changed`): the screen half
## way down over the hub (`loading_departing_half`) and down, with no bar (`loading_departing`).
## Its frames are stepped by hand, so the shots do not depend on the frame rate either.


const ScreenScript := preload("res://hud/panels/loading/loading_screen.gd")


func _init() -> void:
	warm_first = false


func take() -> void:
	if not need(["PlayerInput", "Flow", "Events", "Loading"]):
		return
	var flow: Node = root.get_node("Flow")
	flow.set("loading_enabled", true)
	root.get_node("PlayerInput").call("add_virtual_device", 0)
	root.get_node("Events").emit_signal("play_requested", 0)
	var loading: Node = root.get_node("Loading")
	if not bool(loading.call("is_loading")):
		fail("the loading did not start")
		return
	loading.set_process(false)
	while true:
		loading.call("step")
		var now: Vector2i = loading.call("progress")
		if now.y > 0 and now.x >= now.y / 2:
			break
	await shot("loading_half")
	loading.set_process(true)
	if not await wait_for(func() -> bool: return not bool(loading.call("is_loading")), 2000):
		fail("the loading did not end")
		return
	await _departing(flow)


func _departing(flow: Node) -> void:
	flow.call("stop_run")
	root.get_node("Events").emit_signal("hub_requested", 0)
	if not await wait_for(func() -> bool: return flow.get("mode") == &"hub" and flow.call("get_wizard", 0) != null, 600):
		fail("the hub did not start after the load")
		return
	var screen: Node = root.get_node("Hud/Root/Loading")
	await wait_for(func() -> bool: return not bool(screen.get("visible")))
	var room: RoomBase = root.get_node("Registry").call("get_resource", &"rooms", &"hub") as RoomBase
	(flow.call("get_wizard", 0) as Node2D).global_position = HubRules.area_of(room.places(), HubRules.ROLE_RUN_START).get_center()
	await settle()
	# Only the screen hears it: the shot is of its look, and the hub stays as it is under it.
	root.get_node("Events").emit_signal("run_departure_changed", true)
	screen.set_process(false)
	for i in ScreenScript.COVER_FRAMES / 2:
		screen.call("advance")
	await shot("loading_departing_half")
	while not bool(screen.call("is_down")):
		screen.call("advance")
	await shot("loading_departing")
	root.get_node("Events").emit_signal("run_departure_changed", false)
	screen.set_process(true)
