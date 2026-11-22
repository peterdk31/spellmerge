extends SceneTree
## Every shader compiled by the renderer it is started with (D1, 2026-11-22: the desktop builds draw
## with Vulkan or Direct 3D 12, the web with OpenGL, and a shader must compile on both): Play's own
## warm-up (`tests/support/warm_up.gd`, `core/projectiles/shader_warmup.gd`, which draws every
## shader once) behind the loading screen, then a pinned one-room run is started and drawn for a
## second (the light, the shadows, the mist, the motes, the floor's bake: what the warm-up draws
## with no room). Fails (`RENDERER SHADERS FAILED`, exit 1) on any error logged, a shader that does
## not compile among them (the mote shader's 33 varyings did not on Vulkan, which has 32); else
## `RENDERER SHADERS OK`. Needs a display (a headless run compiles nothing):
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-method mobile --script res://tests/smoke/renderer_shaders.gd -- --expect=mobile
##   ... --rendering-method gl_compatibility ... -- --expect=gl_compatibility   the web's renderer

const WarmUp := preload("res://tests/support/warm_up.gd")
const ErrorLogScript := preload("res://bench/error_log.gd")
const PinnedRun := preload("res://bench/pinned_run.gd")
const ROOM: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")
## Frames the room is drawn for.
const ROOM_FRAMES: int = 60


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	var error_log: Logger = ErrorLogScript.new()
	OS.add_logger(error_log)
	var failed: Array[String] = []
	var method: String = RenderingServer.get_current_rendering_method()
	print("RENDERER SHADERS: %s, %s" % [method, RenderingServer.get_current_rendering_driver_name()])
	# `-- --expect=mobile`: the renderer it must be drawing with (a GPU with no Vulkan falls back to
	# OpenGL with only a warning, which would check the other renderer twice).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--expect=") and arg.trim_prefix("--expect=") != method:
			failed.append("drawing with %s, not %s (no driver for it?)" % [method, arg.trim_prefix("--expect=")])
	if not await WarmUp.run(root):
		failed.append("the warm-up did not finish")
	var flow: Node = root.get_node_or_null("Flow")
	var input: Node = root.get_node_or_null("PlayerInput")
	if flow != null and input != null:
		input.call("add_virtual_device", 0)
		flow.set(&"run_id_to_play", PinnedRun.pin(root.get_node("Registry"), ROOM))
		flow.call("start_run", 0)
		for i in ROOM_FRAMES:
			await process_frame
		flow.call("stop_run")
	else:
		failed.append("the Flow and PlayerInput autoloads must exist")
	for i in 5:
		await process_frame
	OS.remove_logger(error_log)
	for line: String in error_log.call(&"get_lines"):
		failed.append("logged: " + line)
	if failed.is_empty():
		print("RENDERER SHADERS OK")
		quit(0)
	else:
		for reason in failed:
			printerr("RENDERER SHADERS FAILED: %s" % reason)
		quit(1)
