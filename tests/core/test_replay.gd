extends "res://tests/support/suite.gd"
## The replay (core/sim/replay.gd, online-ready N2): its header (with the run's rules since N11) and
## ticks there and back through bytes and a file in user://replays/, and the strict decoder rejecting
## what is not a whole valid replay.


func _frames() -> Array[InputFrame]:
	var out: Array[InputFrame] = []
	for seat in 4:
		var frame := InputFrame.new()
		frame.seat = seat
		out.append(frame)
	return out


## A replay of three ticks: seats 0 and 2 walk and press, seat 2 sends a command on the second.
func _made() -> Replay:
	var replay := Replay.new()
	replay.build = "dev 0123abcd"
	replay.content = -42
	replay.run_seed = 0x1234_5678_9abc
	replay.start = &"horde_requested"
	replay.starter = 2
	replay.seats = 0b0101
	replay.rules.shot_cap = 750
	replay.rules.horde_alive = 150
	replay.rules.hit_work = 4000
	replay.rules.fire_shots = 0
	var frames: Array[InputFrame] = _frames()
	for tick in 3:
		frames[0].set_move(Vector2(1.0, 0.0).rotated(tick))
		frames[0].press(tick % 4)
		frames[2].clear()
		frames[2].set_aim(Vector2.UP)
		if tick == 1:
			frames[2].add_command(&"horde_pick_requested", [1])
		replay.add_tick(frames, 0b0101)
		frames[0].pressed_bits = 0
	return replay


func test_a_replay_comes_back_from_its_bytes() -> void:
	var replay := _made()
	var back: Replay = Replay.from_bytes(replay.to_bytes())
	check(back != null, "valid")
	if back == null:
		return
	check_equal(back.build, "dev 0123abcd", "the build")
	check_equal(back.content, -42, "the content")
	check_equal(back.run_seed, 0x1234_5678_9abc, "the seed")
	check_equal(back.start, &"horde_requested", "how it started")
	check_equal(back.starter, 2, "who started it")
	check_equal(back.seats, 0b0101, "the seats")
	check_equal(str(back.rules), str(replay.rules), "the run's rules")
	check(back.rules.equals(replay.rules), "every rule")
	check_equal(back.tick_count(), 3, "every tick")
	var a: Array[InputFrame] = _frames()
	var b: Array[InputFrame] = _frames()
	for tick in 3:
		check_equal(back.read_tick(tick, b), replay.read_tick(tick, a), "tick %d: the same seats" % tick)
		for seat in 4:
			check_equal(b[seat].to_bytes(), a[seat].to_bytes(), "tick %d seat %d: the same frame" % [tick, seat])
	back.read_tick(1, b)
	check_equal(b[2].commands, [[&"horde_pick_requested", 1]], "a command at its tick")
	check(b[1].move == Vector2i.ZERO and b[1].commands.is_empty(), "a seat with no frame reads cleared")
	check_equal(back.read_tick(3, b), -1, "no tick past the end")
	check_equal(back.to_bytes(), replay.to_bytes(), "the same bytes again")


func test_the_decoder_rejects_bad_replays() -> void:
	var good: PackedByteArray = _made().to_bytes()
	var cases: Dictionary = {}
	cases["empty"] = PackedByteArray()
	cases["cut short"] = good.slice(0, good.size() - 1)
	var longer: PackedByteArray = good.duplicate()
	longer.append(0)
	cases["a byte left over"] = longer
	var magic: PackedByteArray = good.duplicate()
	magic[0] = 0x58
	cases["not a replay"] = magic
	var format: PackedByteArray = good.duplicate()
	format[4] = 9
	cases["another format"] = format
	var older: PackedByteArray = good.duplicate()
	older[4] = 1
	cases["format 1 (before the rules)"] = older
	var build_end: int = 6 + good[5]
	var start: PackedByteArray = good.duplicate()
	start[build_end + 16] = 7
	cases["an unknown start"] = start
	var starter: PackedByteArray = good.duplicate()
	starter[build_end + 17] = 4
	cases["starter 4"] = starter
	# The rules: shot cap, horde cap, hit work, fire shots (four 32-bit numbers).
	var rules_at: int = build_end + 19
	var no_cap: PackedByteArray = good.duplicate()
	no_cap.encode_u32(rules_at, 0)
	cases["a shot cap of 0"] = no_cap
	var huge_cap: PackedByteArray = good.duplicate()
	huge_cap.encode_u32(rules_at, SessionRules.MAX_SHOT_CAP + 1)
	cases["a shot cap past the most"] = huge_cap
	var no_horde: PackedByteArray = good.duplicate()
	no_horde.encode_u32(rules_at + 4, 0)
	cases["a horde cap of 0"] = no_horde
	var no_work: PackedByteArray = good.duplicate()
	no_work.encode_u32(rules_at + 8, 0)
	cases["no hit work"] = no_work
	var fires: PackedByteArray = good.duplicate()
	fires.encode_u32(rules_at + 12, 0x8000_0000)
	cases["fire shots past the most"] = fires
	var ticks: PackedByteArray = good.duplicate()
	ticks.encode_u32(rules_at + SessionRules.BYTES, 4)
	cases["more ticks than it holds"] = ticks
	var frame_seat: PackedByteArray = good.duplicate()
	# The first tick: its seats byte, then seat 0's length (2 bytes) and frame; the frame's seat byte.
	var first: int = rules_at + SessionRules.BYTES + 4
	frame_seat[first + 3 + 1] = 1
	cases["a frame under another seat"] = frame_seat
	var frame_bad: PackedByteArray = good.duplicate()
	frame_bad[first + 3] = 9
	cases["a frame of another version"] = frame_bad
	var mask: PackedByteArray = good.duplicate()
	mask[first] = 0x20
	cases["an unknown bit in a tick"] = mask
	for name: String in cases:
		var replay := Replay.new()
		check(replay.decode(cases[name]) != "", "%s is rejected" % name)
		check(replay.tick_count() == 0 and replay.build == "" and replay.rules.equals(SessionRules.defaults()), "%s leaves it empty" % name)
	check(Replay.from_bytes(good) != null, "the good one is not")


func test_random_bytes_never_break_the_decoder() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var good: PackedByteArray = _made().to_bytes()
	for i in 1000:
		var bytes: PackedByteArray = good.duplicate()
		bytes[rng.randi() % bytes.size()] = rng.randi() % 256
		var replay := Replay.new()
		if replay.decode(bytes) == "":
			check_equal(replay.to_bytes(), bytes, "an accepted replay is exactly its bytes")


func test_a_replay_is_saved_and_opened_in_user_replays() -> void:
	var replay := _made()
	check_equal(replay.save("test_round_trip"), OK, "saved")
	check(FileAccess.file_exists("user://replays/test_round_trip.replay"), "under user://replays/")
	var back: Replay = Replay.open("test_round_trip")
	check(back != null and back.to_bytes() == replay.to_bytes(), "opened as it was")
	check(Replay.open("no_such_replay") == null, "a missing one is null")
	check_equal(replay.save("../escape"), ERR_INVALID_PARAMETER, "a name is an id, never a path")
	check_equal(replay.save(""), ERR_INVALID_PARAMETER, "and never empty")
	check(Replay.open("../test_round_trip") == null, "nor when opening")
	var file: FileAccess = FileAccess.open("user://replays/test_broken.replay", FileAccess.WRITE)
	file.store_buffer(PackedByteArray([1, 2, 3]))
	file.close()
	check(Replay.open("test_broken") == null, "a broken file is not a replay")
	DirAccess.remove_absolute("user://replays/test_round_trip.replay")
	DirAccess.remove_absolute("user://replays/test_broken.replay")


func test_the_content_hash_follows_the_ids() -> void:
	var registry: Node = root.get_node_or_null("Registry")
	check(registry != null, "the registry")
	if registry == null:
		return
	var here: int = Replay.content_of(registry)
	check(here != 0, "the content has a hash")
	check_equal(Replay.content_of(registry), here, "the same content, the same hash")
	check(Replay.build_of() != "", "the build names itself")


func test_the_run_seed_deals_the_same_seeds() -> void:
	var replay := Replay.new()
	replay.run_seed = 77
	var tape := ReplayTape.recording(replay)
	var first: Array[int] = [tape.next_run_seed(), tape.next_run_seed()]
	var again_tape := ReplayTape.playing(replay)
	var again: Array[int] = [again_tape.next_run_seed(), again_tape.next_run_seed()]
	check_equal(again, first, "the same seeds in the same order, recorded and played")
	check(first[0] != first[1], "each run its own")
	replay.rules.shot_cap = 321
	var rules: SessionRules = tape.run_rules()
	rules.shot_cap = 5
	check_equal(tape.run_rules().shot_cap, 321, "each run takes a copy of the replay's rules")

