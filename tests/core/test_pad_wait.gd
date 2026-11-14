extends "res://tests/support/suite.gd"
## An unplugged gamepad on the real game (owner, 2026-11-13): the seat keeps its wizard, the game
## stops for everyone until that seat has a gamepad again, and a recording of it plays the same.
## Before, the input layer made the seat leave and its wizard went.
##
## Two gamepads play the sandbox. Seat 1's is pulled out while it walks, seat 0's while the game
## waits for seat 1's; seat 1's comes back under its own id, and another gamepad takes seat 0 with
## its `join`. The run is recorded (Frames) and its replay must give the same state hash at every
## tick (tests/support/replay_run.gd).
##
## godot --headless --path . --script res://tests/core/test_pad_wait.gd

const ReplayRun := preload("res://tests/support/replay_run.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const CoopScript := preload("res://gameplay/coop/coop.gd")
const TickScript := preload("res://core/sim/tick.gd")
const FramesScript := preload("res://core/sim/frames.gd")

const TICKS: int = 110
const RUN_SEED: int = 77
## The script, by physics step.
const WALK_AT: int = 8
const GONE_1_AT: int = 20
const GONE_0_AT: int = 30
const BACK_1_AT: int = 45
const TAKEN_0_AT: int = 60
## The pad that takes seat 0's place.
const OTHER_PAD: int = 5

var _run: ReplayRun


func before_each() -> void:
	_run = ReplayRun.new(self)


func after_each() -> void:
	await _run.fresh()


func test_an_unplugged_pad_stops_the_game_and_its_replay_plays_the_same() -> void:
	await _run.fresh()
	var input: InputManagerScript = root.get_node("PlayerInput") as InputManagerScript
	var frames: FramesScript = root.get_node("Frames") as FramesScript
	var flow: Node = root.get_node("Flow")
	var coop: CoopScript = root.get_node("Coop") as CoopScript
	var game: Sim = (root.get_node("Tick") as TickScript).sim
	var line: Label = _pad_line()
	input.handle_event(_button(0, JOY_BUTTON_A))
	input.handle_event(_button(1, JOY_BUTTON_A))
	check(input.player_of(0) == 0 and input.player_of(1) == 1, "two gamepads joined")
	await physics_frame
	var recorded := Desync.new()
	var replay: Replay = frames.record(&"sandbox_requested", 0, RUN_SEED)
	var stood_at: Vector2 = Vector2.INF
	var back_at: Vector2 = Vector2.INF
	for i in TICKS:
		await physics_frame
		recorded.capture(_run.areas())
		var wizard: Node2D = flow.call("get_wizard", 1) as Node2D
		match i:
			WALK_AT:
				input.handle_event(_axis(1, JOY_AXIS_LEFT_X, 1.0))
			GONE_1_AT:
				check(frames.frame_of(1).move.x > 0, "seat 1 walks before its gamepad goes")
				input._on_joy_connection_changed(1, false)
			GONE_0_AT:
				input._on_joy_connection_changed(0, false)
			BACK_1_AT:
				input._on_joy_connection_changed(1, true)
			TAKEN_0_AT:
				input.handle_event(_button(OTHER_PAD, JOY_BUTTON_A))
				input.handle_event(_axis(1, JOY_AXIS_LEFT_X, 1.0))
		if i == GONE_1_AT + 3:
			check(game.stopped_for(CoopScript.PAD_OF[1]) and paused, "the game stops for seat 1's gamepad, and the picture with it")
			check(coop.is_joined(1) and wizard != null and input.is_joined(1), "the seat and its wizard are kept")
			check(frames.frame_of(1).move == Vector2i.ZERO and frames.frame_of(1).held_bits == 0, "its frames hold no input")
			check(line != null and line.visible and line.text.contains("P2"), "the HUD says whose controller is gone")
			stood_at = wizard.global_position if wizard != null else Vector2.INF
		if i == GONE_0_AT + 3:
			check(CoopScript.pad_waits(game) == 3, "a second gamepad gone while waiting: both seats wait")
		if i == BACK_1_AT + 3:
			check(CoopScript.pad_waits(game) == 1 and game.is_stopped(), "seat 1's gamepad back: the game still waits for seat 0's")
			check(wizard != null and wizard.global_position == stood_at, "nobody moved while the game waited")
		if i == TAKEN_0_AT + 3:
			check(not game.is_stopped() and not paused, "another gamepad took seat 0: the game goes on")
			check(input.device_of(0) == OTHER_PAD and input.device_of(1) == 1, "each seat has a gamepad, seat 1 its own")
			check(coop.is_joined(0) and coop.is_joined(1) and flow.call("get_wizard", 0) != null, "on the same seats, with their wizards")
			check(line != null and not line.visible, "the line is gone")
			back_at = wizard.global_position if wizard != null else Vector2.INF
	var walked: Node2D = flow.call("get_wizard", 1) as Node2D
	check(walked != null and walked.global_position.x > back_at.x, "seat 1 walks again on its gamepad")
	replay = frames.stop_recording()
	check(replay != null and replay.tick_count() == TICKS, "the run was recorded")
	if replay == null:
		return
	check(ReplayRun.has_command(replay, &"pad_wait_requested"), "the waits are in the recording")
	check(not ReplayRun.has_command(replay, InputFrame.LEAVE), "and no seat left in it")
	var again: Replay = Replay.from_bytes(replay.to_bytes())
	check(again != null, "the replay reads back from its bytes")
	if again == null:
		return
	var played := Desync.new()
	await _run.play(again, 0, played)
	for problem in _run.problems:
		check(false, problem)
	check_equal(played.hashes.size(), TICKS, "the replay played every tick")
	check(Desync.first_parting(recorded, played) < 0, "the replay plays the same: %s" % Desync.compare(recorded, played))


func _pad_line() -> Label:
	var hud: Node = root.get_node_or_null("Hud")
	return hud.call("get_pad_line") as Label if hud != null and hud.has_method(&"get_pad_line") else null


func _button(device: int, button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = true
	return event


func _axis(device: int, axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	return event
