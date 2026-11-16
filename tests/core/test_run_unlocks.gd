extends "res://tests/support/suite.gd"
## The save flags a run plays by (core/sim/run_unlocks.gd, run generation RG6): sorted and each
## once, there and back through bytes, the strict decoder refusing what is not a whole valid list;
## the frames service taking them from the game (this machine's) with no replay on the deck and from
## the replay's header while one is, a recording writing the game's into its header, and the Tick
## handing them to the run (`Sim.unlocks`).

const FramesScript := preload("res://core/sim/frames.gd")
const TickScript := preload("res://core/sim/tick.gd")

var _source_flags: Array[StringName] = []


func _source() -> RunUnlocks:
	return RunUnlocks.of(_source_flags)


func test_the_flags_are_sorted_and_each_once() -> void:
	var made := RunUnlocks.of([&"zeal", &"amber", &"zeal", &"m_2"] as Array[StringName])
	check_equal(made.flags, [&"amber", &"m_2", &"zeal"] as Array[StringName], "sorted, each once")
	check(made.has(&"zeal") and not made.has(&"other"), "has")
	check(not made.add(&""), "an empty flag is refused")
	check(not made.add(&"a/b"), "a flag that is no id is refused")
	check(not made.add(StringName("x".repeat(RunUnlocks.MAX_FLAG + 1))), "too long a flag is refused")
	check(made.add(StringName("x".repeat(RunUnlocks.MAX_FLAG))), "the longest is taken")
	var full := RunUnlocks.new()
	for i in RunUnlocks.MAX_FLAGS:
		full.add(StringName("f%03d" % i))
	check(not full.add(&"one_more"), "no more than MAX_FLAGS")
	var copy: RunUnlocks = made.copy()
	check(copy.equals(made), "a copy is equal")
	copy.add(&"new")
	check(not copy.equals(made) and not made.has(&"new"), "and stands apart")


func test_the_bytes_come_back_and_bad_ones_are_refused() -> void:
	var made := RunUnlocks.of([&"deeper", &"harder"] as Array[StringName])
	var bytes := PackedByteArray([9])
	made.encode_into(bytes)
	var back := RunUnlocks.new()
	check_equal(back.decode_at(bytes, 1), "", "read back")
	check(back.equals(made), "the same flags")
	check_equal(back.read_to, bytes.size(), "read to their end")
	var none := PackedByteArray()
	RunUnlocks.new().encode_into(none)
	check_equal(none, PackedByteArray([0]), "none: a byte of count")
	var cases: Dictionary = {}
	cases["cut short"] = bytes.slice(0, bytes.size() - 1)
	cases["nothing"] = PackedByteArray([9])
	var many: PackedByteArray = bytes.duplicate()
	many[1] = RunUnlocks.MAX_FLAGS + 1
	cases["more than MAX_FLAGS"] = many
	var empty_flag: PackedByteArray = bytes.duplicate()
	empty_flag[2] = 0
	cases["an empty flag"] = empty_flag
	var not_id: PackedByteArray = bytes.duplicate()
	not_id[3] = 0x2f
	cases["a flag that is no id (a slash)"] = not_id
	var high: PackedByteArray = bytes.duplicate()
	high[3] = 0xc3
	cases["a byte past plain text"] = high
	var order := PackedByteArray([9, 2, 1, 0x62, 1, 0x61])
	cases["out of order"] = order
	var twice := PackedByteArray([9, 2, 1, 0x61, 1, 0x61])
	cases["a flag twice"] = twice
	cases["a NUL in a flag (regression: it read back shorter)"] = PackedByteArray([9, 1, 2, 0x61, 0x00])
	for name: String in cases:
		var kept := RunUnlocks.of([&"kept"] as Array[StringName])
		check(kept.decode_at(cases[name], 1) != "", "%s is refused" % name)
		check_equal(kept.flags, [&"kept"] as Array[StringName], "%s changes nothing" % name)


func test_a_replay_carries_the_unlocks_in_its_header() -> void:
	var replay := Replay.new()
	replay.unlocks = RunUnlocks.of([&"deeper", &"harder"] as Array[StringName])
	var back: Replay = Replay.from_bytes(replay.to_bytes())
	check(back != null and back.unlocks.equals(replay.unlocks), "the header's unlocks come back")
	var header: Replay = Replay.from_bytes(replay.header_bytes())
	check(header != null and header.unlocks.equals(replay.unlocks), "and from the header alone (a live replay's)")
	var bad: PackedByteArray = replay.to_bytes()
	# The unlocks end the header, before its 4 bytes of tick count: the second flag's first letter.
	bad[bad.size() - 4 - 6] = 0x2f
	var refused := Replay.new()
	check(refused.decode(bad) != "" and refused.unlocks.is_empty(), "a bad unlock refuses the replay, and leaves it empty")
	check(Replay.new().unlocks.is_empty(), "a replay made has none")


func test_frames_take_the_game_s_unlocks_or_the_replay_s() -> void:
	var frames: FramesScript = FramesScript.new()
	check(frames.next_run_unlocks().is_empty(), "no source: none")
	_source_flags = [&"deeper"]
	frames.set_unlocks_source(_source)
	check_equal(frames.next_run_unlocks().flags, [&"deeper"] as Array[StringName], "this machine's, from the game")
	var first: RunUnlocks = frames.next_run_unlocks()
	first.add(&"more")
	check(not frames.next_run_unlocks().has(&"more"), "a copy each time")
	var replay := Replay.new()
	replay.unlocks = RunUnlocks.of([&"harder"] as Array[StringName])
	frames.set(&"_tape", ReplayTape.playing(replay))
	check_equal(frames.next_run_unlocks().flags, [&"harder"] as Array[StringName], "the replay's: the host's save, never this machine's")
	var played: RunUnlocks = frames.next_run_unlocks()
	played.add(&"more")
	check(not replay.unlocks.has(&"more"), "a copy of the header's")
	frames.set(&"_tape", ReplayTape.playing(Replay.new()))
	check(frames.next_run_unlocks().is_empty(), "a replay of none: none, whatever this machine's save holds")
	frames.free()


func test_a_recording_writes_the_game_s_unlocks_in_its_header() -> void:
	var frames: FramesScript = FramesScript.new()
	_source_flags = [&"harder", &"deeper"]
	frames.set_unlocks_source(_source)
	var replay: Replay = frames.record(&"hub_requested", 0, 77)
	check_equal(replay.unlocks.flags, [&"deeper", &"harder"] as Array[StringName], "a recording begun writes them in its header")
	_source_flags = []
	check_equal(frames.next_run_unlocks().flags, [&"deeper", &"harder"] as Array[StringName], "while it records, the header's, though the save changed")
	frames.stop_recording()
	check(frames.next_run_unlocks().is_empty(), "no replay: this machine's again")
	frames.free()


func test_the_tick_hands_the_run_its_unlocks() -> void:
	var frames: FramesScript = root.get_node("Frames") as FramesScript
	var tick: TickScript = root.get_node("Tick") as TickScript
	var source: Callable = frames.get(&"_unlocks_source")
	_source_flags = [&"deeper"]
	frames.set_unlocks_source(_source)
	tick.begin_run()
	check_equal(tick.sim.unlocks.flags, [&"deeper"] as Array[StringName], "a run's start takes this machine's")
	var replay := Replay.new()
	replay.unlocks = RunUnlocks.of([&"harder"] as Array[StringName])
	frames.set(&"_tape", ReplayTape.playing(replay))
	tick.begin_run()
	check_equal(tick.sim.unlocks.flags, [&"harder"] as Array[StringName], "a replay's start, the header's")
	frames.set(&"_tape", ReplayTape.playing(Replay.new()))
	tick.begin_run()
	check(tick.sim.unlocks.is_empty(), "a guest playing a host's run of none: none, though its own save holds a flag")
	frames.set(&"_tape", null)
	frames.set_unlocks_source(source)
	tick.begin_run()
