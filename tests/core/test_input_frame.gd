extends "res://tests/support/suite.gd"
## The input frame (core/sim/input_frame.gd, online-ready N2): the move and aim quantised, the
## buttons, the commands, the bytes there and back, and the strict decoder rejecting what is not
## a whole valid frame.


func _full() -> InputFrame:
	var frame := InputFrame.new()
	frame.seat = 2
	frame.set_move(Vector2(0.5, -1.0))
	frame.set_aim(Vector2(0.0, 3.0))
	frame.press(0)
	frame.hold(0, true)
	frame.hold(3, true)
	frame.captured = true
	check(frame.add_command(&"staff_change_requested", [1, 4, &"fire"]), "a staff change is a command")
	check(frame.add_command(&"staff_cards_requested", [2, [&"split", &"", &"nova"] as Array[StringName]]), "a whole staff is a command")
	check(frame.add_command(&"card_move_requested", [-1, 3, 0, 2]), "a card move is a command")
	check(frame.add_command(InputFrame.JOIN), "a join is a command")
	return frame


func test_the_move_is_a_byte_per_axis() -> void:
	var frame := InputFrame.new()
	frame.set_move(Vector2(1.0, -1.0))
	check_equal(frame.move, Vector2i(127, -127), "full tilt is 127")
	frame.set_move(Vector2(0.5, 0.0))
	check_equal(frame.move, Vector2i(64, 0), "half tilt rounds to a byte")
	frame.set_move(Vector2(3.0, NAN))
	check_equal(frame.move, Vector2i(127, 0), "out of range is clamped, NaN is still")
	frame.set_move(Vector2(1.0, 1.0).limit_length(1.0))
	check(frame.move_vector().length() <= 1.0, "a diagonal is never faster than 1: %s" % frame.move_vector().length())
	frame.set_move(Vector2.RIGHT)
	check_equal(frame.move_vector(), Vector2.RIGHT, "a full walk comes back exactly")


func test_the_aim_is_a_16_bit_angle_or_keep() -> void:
	var frame := InputFrame.new()
	check_equal(frame.aim, InputFrame.AIM_KEEP, "a new frame keeps the aim")
	check_equal(frame.aim_vector(), Vector2.ZERO, "keep is ZERO for the intent")
	frame.set_aim(Vector2(0.0, 5.0))
	check_equal(frame.aim, 16384, "down is a quarter turn")
	frame.set_aim(Vector2(-1.0, -0.0001))
	check(frame.aim >= 0 and frame.aim < InputFrame.AIM_STEPS, "the angle wraps into 0-65535: %d" % frame.aim)
	frame.set_aim(Vector2(3.0, 4.0))
	check(frame.aim_vector().distance_to(Vector2(0.6, 0.8)) < 0.0001, "the aim comes back within a step: %s" % frame.aim_vector())
	check(is_equal_approx(frame.aim_vector().length(), 1.0), "as a unit vector")
	frame.set_aim(Vector2.ZERO)
	check_equal(frame.aim, InputFrame.AIM_KEEP, "ZERO keeps the aim")
	frame.set_aim(Vector2(INF, 0.0))
	check_equal(frame.aim, InputFrame.AIM_KEEP, "a direction that is not finite keeps the aim")


func test_a_frame_comes_back_from_its_bytes() -> void:
	var frame := _full()
	var bytes: PackedByteArray = frame.to_bytes()
	var back: InputFrame = InputFrame.from_bytes(bytes)
	check(back != null, "the bytes are a valid frame")
	if back == null:
		return
	check_equal(back.seat, 2, "the seat")
	check_equal(back.move, frame.move, "the move")
	check_equal(back.aim, frame.aim, "the aim")
	check(back.is_pressed(0) and back.is_held(0) and back.is_held(3) and not back.is_held(1), "the buttons")
	check(back.captured, "captured")
	check_equal(back.commands.size(), 4, "every command")
	check_equal(back.commands[0], [&"staff_change_requested", 1, 4, &"fire"], "a staff change with its arguments")
	check_equal(back.commands[2], [&"card_move_requested", -1, 3, 0, 2], "a card move from the bag")
	var cards: Array = back.commands[1][2]
	check_equal(cards, [&"split", &"", &"nova"], "a list of ids, an empty one too")
	check(back.commands[1][2] is Array[StringName], "the list is typed as the event's")
	check_equal(back.to_bytes(), bytes, "the same bytes again")
	var empty := InputFrame.new()
	check_equal(empty.to_bytes().size(), InputFrame.HEAD_BYTES, "an empty frame is its head only")


func test_add_command_refuses_what_the_decoder_would() -> void:
	var frame := InputFrame.new()
	check(not frame.add_command(&"play_requested", []), "no such command")
	check(not frame.add_command(&"staff_change_requested", [1, 2]), "too few arguments")
	check(not frame.add_command(&"staff_change_requested", [1, 2.0, &"fire"]), "a float for an int")
	check(not frame.add_command(&"staff_change_requested", [1, 2, &"../x"]), "a path for an id")
	check(not frame.add_command(&"sandbox_spawn_requested", [&"imp", 1 << 40]), "an int past 32 bits")
	check(frame.commands.is_empty(), "nothing was added")
	for i in InputFrame.MAX_COMMANDS:
		frame.add_command(&"reward_pick_requested", [0])
	check(not frame.add_command(&"reward_pick_requested", [0]), "a full frame takes no more")


func test_the_decoder_rejects_bad_frames() -> void:
	var good: PackedByteArray = _full().to_bytes()
	var cases: Dictionary = {}
	cases["empty"] = PackedByteArray()
	cases["cut short"] = good.slice(0, good.size() - 1)
	var longer: PackedByteArray = good.duplicate()
	longer.append(0)
	cases["a byte left over"] = longer
	var version: PackedByteArray = good.duplicate()
	version[0] = 9
	cases["another version"] = version
	var seat: PackedByteArray = good.duplicate()
	seat[1] = 4
	cases["seat 4"] = seat
	var flags: PackedByteArray = good.duplicate()
	flags[2] = 0x80
	cases["unknown flags"] = flags
	var move: PackedByteArray = good.duplicate()
	move[4] = 0x80
	cases["move -128"] = move
	var count: PackedByteArray = good.duplicate()
	count[8] = InputFrame.MAX_COMMANDS + 1
	cases["too many commands"] = count
	var kind: PackedByteArray = good.duplicate()
	kind[InputFrame.HEAD_BYTES] = 200
	cases["unknown command"] = kind
	var keep := InputFrame.new()
	var aimed: PackedByteArray = keep.to_bytes()
	aimed.encode_u16(6, 5)
	cases["an aim beside keep"] = aimed
	var frame := InputFrame.new()
	frame.add_command(&"sandbox_action_requested", [&"reset"])
	var text: PackedByteArray = frame.to_bytes()
	text[InputFrame.HEAD_BYTES + 2] = 47
	cases["a slash in an id"] = text
	var long: PackedByteArray = frame.to_bytes()
	long[InputFrame.HEAD_BYTES + 1] = 200
	cases["an id longer than the frame"] = long
	for name: String in cases:
		var reader := InputFrame.new()
		var problem: String = reader.decode(cases[name])
		check(problem != "", "%s is rejected" % name)
		check(reader.commands.is_empty() and reader.held_bits == 0, "%s leaves the frame cleared" % name)
	check(InputFrame.from_bytes(PackedByteArray([1, 0, 0, 0, 0, 0, 0, 0])) == null, "from_bytes gives null for a bad frame")


func test_random_bytes_never_break_the_decoder() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var good: PackedByteArray = _full().to_bytes()
	var accepted: int = 0
	for i in 2000:
		var bytes: PackedByteArray = good.duplicate()
		for flip in 1 + rng.randi() % 3:
			bytes[rng.randi() % bytes.size()] = rng.randi() % 256
		var frame := InputFrame.new()
		if frame.decode(bytes) == "":
			accepted += 1
			check_equal(frame.to_bytes(), bytes, "an accepted frame is exactly its bytes")
	check(accepted < 2000, "most changed frames are rejected (%d accepted)" % accepted)


func test_copy_from() -> void:
	var frame := _full()
	var copy := InputFrame.new()
	copy.copy_from(frame)
	check_equal(copy.to_bytes(), frame.to_bytes(), "a copy is the same frame")
	copy.commands[0][3] = &"frost"
	check_equal(frame.commands[0][3], &"fire", "and its commands are its own")
	copy.clear()
	check(copy.commands.is_empty() and copy.aim == InputFrame.AIM_KEEP and copy.seat == 2, "clear keeps the seat only")
