extends SceneTree
## Walls hold in the real room: four wizards started by Flow each walk and dodge into
## a different corner of arena_01 through the real input path (virtual devices) for
## four seconds of physics frames, and none ends up outside the walls. Regression
## test for the question "did the wizards walk through walls?" (the zoom-0.5
## screenshot places them outside the room on purpose; this checks the game does not).
##
## godot --headless --path . --script res://tests/gameplay/flow/test_walls_hold.gd

## The room is 640x384 with a 32 px wall border; a wizard's centre must stay inside it.
const INSIDE := Rect2(Vector2(32, 32), Vector2(576, 320))
const FRAMES: int = 240
const DIRECTIONS: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]

var _failures: Array[String] = []


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	var input: Node = root.get_node_or_null("PlayerInput")
	var flow: Node = root.get_node_or_null("Flow")
	if input == null or flow == null:
		printerr("TEST FAILED: the PlayerInput and Flow autoloads must exist")
		quit(1)
		return
	for index in 4:
		input.call("add_virtual_device", index)
	_check(bool(flow.call("start_run", 0)), "Flow starts a run with four players")
	var starts: Array[Vector2] = []
	for index in 4:
		var wizard: Node2D = flow.call("get_wizard", index) as Node2D
		starts.append(wizard.global_position if wizard != null else Vector2.ZERO)
	for frame in FRAMES:
		for index in 4:
			var d: Vector2 = DIRECTIONS[index]
			input.call("send_virtual", index, &"move_left", 1.0 if d.x < 0 else 0.0)
			input.call("send_virtual", index, &"move_right", 1.0 if d.x > 0 else 0.0)
			input.call("send_virtual", index, &"move_up", 1.0 if d.y < 0 else 0.0)
			input.call("send_virtual", index, &"move_down", 1.0 if d.y > 0 else 0.0)
			# Tap dodge now and then: the fast dash is the likeliest way through a wall.
			input.call("send_virtual", index, &"dodge", 1.0 if frame % 20 == 0 else 0.0)
		await physics_frame
		for index in 4:
			var wizard: Node2D = flow.call("get_wizard", index) as Node2D
			if wizard != null and not INSIDE.has_point(wizard.global_position):
				_check(false, "wizard %d left the room at %s (frame %d)" % [index + 1, wizard.global_position, frame])
	for index in 4:
		var wizard: Node2D = flow.call("get_wizard", index) as Node2D
		_check(wizard != null, "wizard %d exists" % [index + 1])
		# It really walked (pillars may stop it before its corner): the test is not vacuous.
		if wizard != null:
			_check(wizard.global_position.distance_to(starts[index]) > 64.0,
				"wizard %d walked away from its spawn (%s to %s)" % [index + 1, starts[index], wizard.global_position])
		for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down", &"dodge"]:
			input.call("send_virtual", index, action, 0.0)
		input.call("leave", index)
	flow.call("stop_run")
	await create_timer(0.3).timeout
	if _failures.is_empty():
		print("TEST OK: gameplay/flow (walls hold four wizards walking and dodging into the corners)")
		quit(0)
	else:
		for failure in _failures.slice(0, 10):
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
