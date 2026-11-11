extends "res://tests/support/suite.gd"
## What a run's start takes along (core/sim/run_carry.gd, online lobby): each seat's staffs, as the
## card ids in their slots. It comes back from its bytes slot for slot, a copy stands apart, what is
## not an id or past a limit is left out when it is made, and the decoder refuses anything else.

const FramesScript := preload("res://core/sim/frames.gd")


func _carry() -> RunCarry:
	return RunCarry.of_kept([[[&"bolt", &"", &"dash"], [], [&"fire"]], [], [], [[&"possess"]]])


func test_it_comes_back_from_its_bytes_slot_for_slot() -> void:
	var carry: RunCarry = _carry()
	var bytes := PackedByteArray([7])
	carry.encode_into(bytes)
	bytes.append(9)
	var back := RunCarry.new()
	check_equal(back.decode_at(bytes, 1), "", "read")
	check_equal(back.read_to, bytes.size() - 1, "up to its end, not past it")
	check_equal(back.as_kept(), [[[&"bolt", &"", &"dash"], [], [&"fire"]], [], [], [[&"possess"]]], "every seat's staffs, an empty slot and an empty staff kept")
	check(back.equals(carry), "the same")
	check_equal(back.seats(), 0b1001, "seats 0 and 3 take something along")
	var none := RunCarry.new()
	var empty := PackedByteArray()
	none.encode_into(empty)
	check_equal(empty, PackedByteArray([0]), "nothing taken along is one byte")
	check(none.is_empty() and none.as_kept() == [[], [], [], []], "and nothing for every seat")


func test_a_copy_stands_apart() -> void:
	var carry: RunCarry = _carry()
	var copy: RunCarry = carry.copy()
	check(copy.equals(carry), "a copy is the same")
	copy.set_staffs(0, [[&"dash"]])
	(carry.staffs_of(3)[0] as Array).append(&"bolt")
	check_equal(carry.staffs_of(0)[0], [&"bolt", &"", &"dash"] as Array[StringName], "changing the copy leaves the first")
	check_equal(carry.staffs_of(3), [[&"possess"]], "and what it hands out is a copy too")


func test_what_is_not_an_id_or_past_a_limit_is_left_out() -> void:
	var cards: Array = []
	for i in RunCarry.MAX_CARDS + 5:
		cards.append(&"bolt")
	var carry: RunCarry = RunCarry.of_kept([[[&"bolt", "res://x.gd", &"fire"], [], [], [], [&"fifth"]], [], [], [], [[&"seat_five"]]])
	check_equal(carry.staffs_of(0), [[&"bolt", &"", &"fire"], [], [], []], "a path is no id (an empty slot), and a fifth staff is none")
	check_equal(carry.seats(), 0b0001, "a fifth seat is none")
	carry.set_staffs(1, [cards])
	check_equal((carry.staffs_of(1)[0] as Array).size(), RunCarry.MAX_CARDS, "a staff holds as many cards as a staff has slots, at most")
	check(carry.staffs_of(-1).is_empty() and carry.staffs_of(4).is_empty(), "no seat outside the four")


func test_the_decoder_refuses_what_is_not_whole_and_in_bounds() -> void:
	var good := PackedByteArray()
	_carry().encode_into(good)
	# seat mask; seat 0: 3 staffs; staff 0: 3 cards; "bolt" (4, b, o, l, t) ...
	var cases: Dictionary = {}
	cases["nothing"] = PackedByteArray()
	cases["cut short"] = good.slice(0, good.size() - 1)
	var seats: PackedByteArray = good.duplicate()
	seats[0] = 0x10
	cases["a fifth seat"] = seats
	var no_staff: PackedByteArray = good.duplicate()
	no_staff[1] = 0
	cases["a seat with no staff"] = no_staff
	var five: PackedByteArray = good.duplicate()
	five[1] = 5
	cases["five staffs"] = five
	var many: PackedByteArray = good.duplicate()
	many[2] = RunCarry.MAX_CARDS + 1
	cases["more cards than a staff has slots"] = many
	var long: PackedByteArray = good.duplicate()
	long[3] = InputFrame.MAX_TEXT + 1
	cases["an id longer than an id"] = long
	var dot: PackedByteArray = good.duplicate()
	dot[5] = 0x2e
	cases["an id with a dot"] = dot
	var zero: PackedByteArray = good.duplicate()
	zero[5] = 0
	cases["an id with a zero byte"] = zero
	var high: PackedByteArray = good.duplicate()
	high[5] = 0xc3
	cases["an id with a byte past plain text"] = high
	for name: String in cases:
		var carry: RunCarry = _carry()
		var before: Array = carry.as_kept()
		check(carry.decode_at(cases[name], 0) != "", "%s is refused" % name)
		check_equal(carry.as_kept(), before, "%s changes nothing" % name)
	check_equal(RunCarry.new().decode_at(good, 0), "", "the good one is read")
	check(RunCarry.new().decode_at(good, -1) != "" and RunCarry.new().decode_at(good, good.size()) != "", "nothing is read from outside the bytes")


func test_random_bytes_never_break_the_decoder() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var good := PackedByteArray()
	_carry().encode_into(good)
	for i in 2000:
		var bytes: PackedByteArray = good.duplicate()
		bytes[rng.randi() % bytes.size()] = rng.randi() % 256
		var carry := RunCarry.new()
		if carry.decode_at(bytes, 0) == "":
			var again := PackedByteArray()
			carry.encode_into(again)
			check_equal(again, bytes.slice(0, carry.read_to), "what is read is exactly its bytes")


## The frames service: a run that starts takes what the game says it would take now, or the
## replay's on the deck (its header), always as a copy.
func test_a_run_takes_the_games_carry_or_the_replays() -> void:
	var frames: FramesScript = FramesScript.new()
	check(frames.next_run_carry().is_empty(), "nothing, with no game to ask")
	var game: RunCarry = _carry()
	frames.set_carry_source(func() -> RunCarry: return game)
	check(frames.next_run_carry().equals(game), "what the game says")
	frames.set_carry_source(func() -> RunCarry: return null)
	check(frames.next_run_carry().is_empty(), "a game that says nothing: nothing")
	frames.set_carry_source(func() -> RunCarry: return game)
	var replay := Replay.new()
	replay.carry = RunCarry.of_kept([[], [[&"dash"]]])
	frames.set(&"_tape", ReplayTape.playing(replay))
	var run: RunCarry = frames.next_run_carry()
	check_equal(run.as_kept(), [[], [[&"dash"]], [], []], "the replay's, not the game's")
	run.set_staffs(1, [[&"bolt"]])
	check_equal(replay.carry.staffs_of(1), [[&"dash"]], "a copy: the run's change is not the replay's")
	frames.free()
