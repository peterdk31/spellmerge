extends "res://tests/support/screenshot.gd"
## The loading screen before the first room (owner, 2026-10-29), half way through compiling the
## shaders: `loading_half`. The load is held still, so the shot does not depend on the frame
## rate.


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
