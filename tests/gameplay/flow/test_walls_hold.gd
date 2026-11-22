extends "res://tests/support/suite.gd"
## Walls hold in the real room: four wizards started by Flow each walk and dodge into a different
## corner of arena_01 through the real input path (virtual devices) for four seconds of physics
## frames, and none ends up outside the walls. Regression test for the question "did the wizards
## walk through walls?" (the zoom-0.5 screenshot places them outside the room on purpose; this
## checks the game does not). One scenario, one test: the real game (Flow, PlayerInput, the room)
## is the point. It also checks that every wizard really walked away from its spawn, so the test
## is not passed by wizards that never moved.

const PinnedRun := preload("res://bench/pinned_run.gd")
const FlowScript := preload("res://gameplay/flow/flow.gd")
const ARENA: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")
## The room is 640x384; a wizard's centre must stay inside it and off its walls (a floating room's
## invisible edge since crypt rework CR3: wall cells of 8 px round its slab, wandering in and out).
const ROOM := Rect2(Vector2.ZERO, Vector2(640, 384))
const FRAMES: int = 240
const DIRECTIONS: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
const ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down", &"dodge"]

var flow: FlowScript
var input: Node
## The room's wall rectangles, read from its scene as the game reads them.
var walls: Array[Rect2] = []


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	input = root.get_node("PlayerInput")
	# A run of arena_01 alone (the crypt run's first room is any of its fight rooms, RG3b).
	flow.run_id_to_play = PinnedRun.pin(root.get_node("Registry"), ARENA)
	walls = RoomPlaces.wall_rects(own(ARENA.scene.instantiate()) as Node)
	for index in 4:
		input.call("add_virtual_device", index)


func after_each() -> void:
	flow.stop_run()
	flow.run_id_to_play = FlowScript.DEFAULT_RUN_ID
	for index in 4:
		for action: StringName in ACTIONS:
			input.call("send_virtual", index, action, 0.0)
		input.call("leave", index)


func test_four_wizards_walking_and_dodging_into_the_corners_stay_inside_the_room() -> void:
	check(flow.start_run(0), "Flow starts a run with four players")
	var starts: Array[Vector2] = []
	for index in 4:
		var wizard: Node2D = flow.get_wizard(index) as Node2D
		check(wizard != null, "wizard %d exists" % [index + 1])
		starts.append(wizard.global_position if wizard != null else Vector2.ZERO)
	var left: Array[bool] = [false, false, false, false]
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
			var wizard: Node2D = flow.get_wizard(index) as Node2D
			if wizard != null and not left[index] and not _inside(wizard.global_position):
				left[index] = true
				check(false, "wizard %d left the room at %s (frame %d)" % [index + 1, wizard.global_position, frame])
	for index in 4:
		var wizard: Node2D = flow.get_wizard(index) as Node2D
		# It really walked (pillars may stop it before its corner): the test is not vacuous.
		if wizard != null:
			check(wizard.global_position.distance_to(starts[index]) > 64.0,
				"wizard %d walked away from its spawn (%s to %s)" % [index + 1, starts[index], wizard.global_position])


## True when `point` is in the room and on no wall.
func _inside(point: Vector2) -> bool:
	return ROOM.has_point(point) and not walls.any(func(wall: Rect2) -> bool: return wall.has_point(point))
