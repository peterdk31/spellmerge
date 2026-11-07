extends "res://tests/support/suite.gd"
## The frames service (core/sim/frames.gd, online-ready N2) on its own bus and input manager,
## ticked by hand: a device's input becomes its seat's frame (the local input layer), a source
## fills a seat instead, a command applies at the next tick's start (not when it is sent) and goes
## into its seat's frame, a recorded run plays back frame for frame with its commands at the same
## ticks, and a wizard's controller builds its intent from its seat's frame.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const FramesScript := preload("res://core/sim/frames.gd")
const WizardFixture := preload("res://tests/gameplay/player/wizard_fixture.gd")

const DT: float = 1.0 / 60.0

var _bus: EventsScript
var _input: InputManagerScript
var _frames: FramesScript
## What the listeners heard: [command, args...].
var _heard: Array = []


## A source that walks right and holds staff 1, and presses staff 0 on its first frame.
class Walker:
	extends FrameSource
	var filled: int = 0

	func fill_frame(frame: InputFrame, _delta: float) -> void:
		frame.set_move(Vector2.RIGHT)
		frame.hold(1, true)
		if filled == 0:
			frame.press(0)
		filled += 1


func before_each() -> void:
	_heard.clear()
	_bus = own(EventsScript.new()) as EventsScript
	_input = own(InputManagerScript.new()) as InputManagerScript
	_input.events = _bus
	_frames = own(FramesScript.new()) as FramesScript
	_frames.events = _bus
	_frames.input = _input
	_frames.auto_tick = false
	root.add_child(_bus)
	root.add_child(_input)
	root.add_child(_frames)
	_bus.listen(&"staff_change_requested", func(seat: int, staff: int, slot: int, card: StringName) -> void: _heard.append([&"staff_change_requested", seat, staff, slot, card]))
	_bus.listen(&"staff_cards_requested", func(seat: int, staff: int, cards: Array[StringName]) -> void: _heard.append([&"staff_cards_requested", seat, staff, cards]))


func after_each() -> void:
	_frames.stop_recording()
	_frames.stop_playing()


func test_every_command_is_an_event_of_its_shape() -> void:
	var bus := own(EventsScript.new()) as EventsScript
	var types: Dictionary = {"i": TYPE_INT, "s": TYPE_STRING_NAME, "S": TYPE_ARRAY}
	for kind in InputFrame.COMMAND_NAMES.size():
		var command: StringName = InputFrame.COMMAND_NAMES[kind]
		if command == InputFrame.JOIN or command == InputFrame.LEAVE:
			check(not bus.has_signal(command), "%s is no event" % command)
			continue
		check(bus.has_signal(command), "%s is an event" % command)
		var args: Array = []
		for signal_info: Dictionary in bus.get_signal_list():
			if signal_info["name"] == command:
				args = signal_info["args"]
		var shape: String = InputFrame.COMMAND_SHAPES[kind]
		check_equal(args.size(), shape.length() + 1, "%s: the seat, then its shape's arguments" % command)
		if args.size() != shape.length() + 1:
			continue
		check_equal(int(args[0]["type"]), TYPE_INT, "%s: the seat first" % command)
		for at in shape.length():
			check_equal(int(args[at + 1]["type"]), types[shape[at]], "%s: argument %d" % [command, at + 1])


func test_a_command_applies_at_the_next_tick_start() -> void:
	_bus.staff_change_requested.emit(2, 1, 0, &"fire")
	check(_heard.is_empty(), "not when it is sent")
	_frames.tick(DT)
	check_equal(_heard, [[&"staff_change_requested", 2, 1, 0, &"fire"]], "at the next tick's start, the seat first")
	check_equal(_frames.frame_of(2).commands, [[&"staff_change_requested", 1, 0, &"fire"]], "in its seat's frame")
	check(_frames.frame_of(0).commands.is_empty(), "and no other seat's")
	_frames.tick(DT)
	check_equal(_heard.size(), 1, "once")
	check(_frames.frame_of(2).commands.is_empty(), "the next frame has none")


func test_commands_keep_their_order_and_types() -> void:
	var cards: Array[StringName] = [&"split", &"", &"nova"]
	_bus.staff_cards_requested.emit(0, 2, cards)
	_bus.staff_change_requested.emit(0, 1, 3, &"")
	_bus.staff_change_requested.emit(1, 0, 0, &"bolt")
	_frames.tick(DT)
	check_equal(_heard.size(), 3, "all three")
	if _heard.size() == 3:
		check_equal(_heard[0][0], &"staff_cards_requested", "seat 0's first, as sent")
		check_equal(_heard[1], [&"staff_change_requested", 0, 1, 3, &""], "then its second")
		check_equal(_heard[2], [&"staff_change_requested", 1, 0, 0, &"bolt"], "then seat 1's")
		check(_heard[0][3] is Array[StringName], "a list arrives typed as the event's")


func test_without_a_sink_a_command_applies_as_sent() -> void:
	var bus := own(EventsScript.new()) as EventsScript
	var heard: Array = []
	bus.listen(&"horde_pick_requested", func(seat: int, choice: int) -> void: heard.append([seat, choice]))
	bus.horde_pick_requested.emit(3, 1)
	check_equal(heard, [[3, 1]], "a test's own bus applies at once")


func test_a_bad_command_never_reaches_the_game() -> void:
	_bus.staff_change_requested.emit(7, 1, 0, &"fire")
	_bus.staff_change_requested.emit(0, 1, 0, &"../fire")
	_frames.tick(DT)
	check(_heard.is_empty(), "no seat 7, no path for an id")


func test_a_device_becomes_its_seats_frame() -> void:
	_input.add_virtual_device(1)
	_frames.tick(DT)
	_input.send_virtual(1, &"move_right", 1.0)
	_input.send_virtual_aim(1, Vector2(0.0, 1.0))
	_input.send_virtual(1, &"staff_3", 1.0)
	_frames.tick(DT)
	var frame: InputFrame = _frames.frame_of(1)
	check_equal(frame.move_vector(), Vector2.RIGHT, "the walk")
	check_equal(frame.aim, 16384, "the stick's aim, down")
	check(frame.is_pressed(2) and frame.is_held(2), "a fresh press, held")
	_frames.tick(DT)
	check(not frame.is_pressed(2) and frame.is_held(2), "pressed one tick only, held on")
	_input.send_virtual(1, &"staff_1", 1.0)
	_input.send_virtual(1, &"staff_1", 0.0)
	_frames.tick(DT)
	check(frame.is_pressed(0) and not frame.is_held(0), "a tap let go before the tick still presses")
	_input.set_captured(1, true)
	_input.send_virtual(1, &"staff_1", 1.0)
	_frames.tick(DT)
	check(frame.captured and frame.move == Vector2i.ZERO and frame.held_bits == 0 and frame.pressed_bits == 0, "captured: nothing but the flag")
	_input.set_captured(1, false)
	_frames.tick(DT)
	check(not frame.is_pressed(0), "a press made while captured never counts later")
	check(_frames.frame_of(0).move == Vector2i.ZERO, "a seat with no device has an empty frame")


func test_the_stick_aim_holds_then_follows_the_walk() -> void:
	_input.add_virtual_device(0)
	_input.send_virtual_aim(0, Vector2.UP)
	_input.send_virtual(0, &"move_left", 1.0)
	_frames.tick(DT)
	_input.send_virtual_aim(0, Vector2.ZERO)
	_frames.tick(DT)
	check_equal(_frames.frame_of(0).aim, InputFrame.AIM_KEEP, "a let-go stick keeps the aim it gave, not the walk's")
	for i in int(LocalInput.AIM_HOLD_TIME / DT) + 1:
		_frames.tick(DT)
	check(_frames.frame_of(0).aim_vector().is_equal_approx(Vector2.LEFT), "then the walk's way")


func test_a_source_fills_its_seat_instead_of_the_device() -> void:
	_input.add_virtual_device(0)
	_input.send_virtual(0, &"move_left", 1.0)
	var walker := Walker.new()
	_frames.set_source(0, walker)
	_frames.tick(DT)
	var frame: InputFrame = _frames.frame_of(0)
	check_equal(frame.move_vector(), Vector2.RIGHT, "the source's walk, not the device's")
	check(frame.is_pressed(0) and frame.is_held(1), "and its buttons")
	_input.set_captured(0, true)
	_frames.tick(DT)
	check(frame.captured and frame.move == Vector2i.ZERO, "a captured seat holds still, also from a source")
	_input.set_captured(0, false)
	_frames.set_source(0, null)
	_frames.tick(DT)
	check_equal(frame.move_vector(), Vector2.LEFT, "the device again")


func test_a_recorded_run_plays_back_frame_for_frame() -> void:
	var walker := Walker.new()
	_input.add_virtual_device(0)
	_input.add_virtual_device(2)
	_frames.set_source(2, walker)
	_frames.tick(DT)
	var starts: Array = []
	_bus.sandbox_requested.connect(func(seat: int) -> void: starts.append(seat))
	var replay: Replay = _frames.record(&"sandbox_requested", 0)
	check_equal(starts, [0], "recording starts the run")
	check(_frames.is_recording(), "and records it")
	var first_seed: int = _frames.next_run_seed()
	var recorded: Array[PackedByteArray] = []
	for i in 12:
		if i == 3:
			_input.send_virtual(0, &"staff_2", 1.0)
		if i == 5:
			_bus.staff_change_requested.emit(0, 1, 2, &"frost")
		if i == 7:
			_input.add_virtual_device(1)
		_frames.tick(DT)
		recorded.append(_frames_bytes())
	check(_frames.stop_recording() == replay and not _frames.is_recording(), "stopping hands the replay over")
	check_equal(replay.tick_count(), 12, "a tick a tick")
	check_equal(replay.seats, 0b101, "the seats joined at the start")
	var heard_live: Array = _heard.duplicate()
	# Played back on a fresh input manager, through the replay's bytes.
	_heard.clear()
	_frames.set_source(2, null)
	for seat in 4:
		_input.leave(seat)
	_frames.tick(DT)
	var again: Replay = Replay.from_bytes(replay.to_bytes())
	check(_frames.play(again), "it plays")
	check_equal(starts, [0, 0], "its run starts the same way")
	check_equal(_frames.next_run_seed(), first_seed, "with the same seeds")
	check(_input.is_joined(0) and _input.is_joined(2) and not _input.is_joined(1), "its seats join")
	for i in 12:
		if i == 2:
			_bus.staff_change_requested.emit(3, 0, 0, &"bolt")
		_frames.tick(DT)
		check_equal(_frames_bytes(), recorded[i], "tick %d: the same frames" % i)
		if i == 7:
			check(_input.is_joined(1), "a seat that joined mid-run joins at the same tick")
	check_equal(_heard, heard_live, "the same commands; live ones are dropped while it plays")
	_frames.tick(DT)
	check(not _frames.is_playing(), "it stops when its frames run out")


## A replay plays one recorded tick each tick (online-ready N4): where the game stood stopped or
## held when it was recorded, it stands so again from its own state, so nothing is skipped.
func test_a_replay_plays_a_recorded_tick_each_tick() -> void:
	_input.add_virtual_device(0)
	var replay: Replay = _frames.record(&"sandbox_requested", 0)
	_input.send_virtual(0, &"move_right", 1.0)
	_frames.tick(DT)
	_bus.staff_change_requested.emit(0, 1, 0, &"fire")
	_frames.tick(DT)
	_input.send_virtual(0, &"move_right", 0.0)
	_input.send_virtual(0, &"move_left", 1.0)
	_frames.tick(DT)
	_frames.stop_recording()
	check_equal(_heard.size(), 1, "the command applied")
	_heard.clear()
	_input.leave(0)
	check(_frames.play(replay), "it plays")
	_frames.tick(DT)
	check_equal(_frames.frame_of(0).move_vector(), Vector2.RIGHT, "the first tick")
	check(_heard.is_empty(), "no command yet")
	_frames.tick(DT)
	check_equal(_heard.size(), 1, "the second tick's command")
	_frames.tick(DT)
	check_equal(_frames.frame_of(0).move_vector(), Vector2.LEFT, "the third tick")
	_frames.tick(DT)
	check(not _frames.is_playing(), "done")


## A tick that stands still (the Tick calls `stood`) keeps its presses for the next tick that
## steps, so a tap during a downed wizard's stop is not lost; the press is spent there, once.
func test_a_press_in_a_tick_that_stood_still_carries_to_the_next() -> void:
	_frames.tick(DT)
	_frames.frame_of(0).press(2)
	_frames.stood()
	_frames.tick(DT)
	_frames.stood()
	_frames.tick(DT)
	check(_frames.frame_of(0).is_pressed(2), "the press reaches the tick that steps, through two that stood")
	_frames.tick(DT)
	check(not _frames.frame_of(0).is_pressed(2), "and only that one")

func test_a_wizard_takes_its_intent_from_its_seats_frame() -> void:
	var world := WizardFixture.new(root, true)
	var body: Actor = world.wizard(1, Vector2.ZERO, [[&"bolt"], [], [], []], null, false)
	var controller: PlayerController = WizardFixture.controller(body)
	controller.input = null
	controller.frames = _frames
	world.add(body)
	world.input.add_virtual_device(1)
	_frames.set_source(1, Walker.new())
	_frames.tick(DT)
	body.step(DT)
	check_equal(body.intent.move, Vector2.RIGHT, "the frame's walk")
	check(body.intent.is_held(1), "its buttons")
	check(body.intent.is_pressed(0), "and its press")
	_frames.set_source(1, null)
	_frames.tick(DT)
	body.step(DT)
	check_equal(body.intent.move, Vector2.ZERO, "an empty frame stands")
	check(not body.intent.is_held(1), "and holds nothing")
	world.free_all()


## Every seat's frame of the tick, as bytes.
func _frames_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	for seat in 4:
		_frames.frame_of(seat).encode_into(out)
	return out
