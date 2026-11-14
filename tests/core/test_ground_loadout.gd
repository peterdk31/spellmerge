extends "res://tests/support/suite.gd"
## Tests for what lies on the ground as a run's start takes it along (items I6,
## core/sim/ground_loadout.gd): it comes back from its bytes as it was, every place and mana to the
## bit; the writers refuse what the decoder would; the decoder refuses every cut, bad id, bad name
## and count out of range, changing nothing; a replay's header carries it (format 8), and the
## frames service gives the replay's on the deck, else the game's.
##
## godot --headless --path . --script res://tests/core/test_ground_loadout.gd

const FramesScript := preload("res://core/sim/frames.gd")


func _sample() -> GroundLoadout:
	var made := GroundLoadout.new()
	check(made.set_room(&"hub"), "a room")
	check(made.add_item(&"staff", &"star", "Wild star", 1, Vector2(448.25, 560.125), 87.123456789, [&"lightning", &"", &"split"] as Array[StringName]), "a staff")
	check(made.add_item(&"card", &"bolt", "", 1, Vector2(-3.5, 1e6), 0.0, [] as Array[StringName]), "a card")
	return made


func test_it_comes_back_from_its_bytes_as_it_was() -> void:
	var ground: GroundLoadout = _sample()
	var bytes := PackedByteArray()
	ground.encode_into(bytes)
	check_equal(bytes.size(), ground.size(), "its size is its bytes'")
	bytes.append(7)
	var read := GroundLoadout.new()
	check_equal(read.decode_at(bytes, 0), "", "read")
	check_equal(read.read_to, bytes.size() - 1, "to its end")
	check(read.equals(ground), "the same")
	check_equal(read.mana_of(0), 87.123456789, "the mana to the bit")
	check_equal(read.place_of(0), Vector2(448.25, 560.125), "the place to the bit")
	check_equal(read.cards_of(0), [&"lightning", &"", &"split"] as Array[StringName], "the cards, an empty slot too")
	check(ground.copy().equals(ground), "a copy is the same")
	var empty := GroundLoadout.new()
	var none := PackedByteArray()
	empty.encode_into(none)
	check_equal(none.size(), 3, "nothing lying is three bytes")


func test_the_writers_refuse_what_the_decoder_would() -> void:
	var ground := GroundLoadout.new()
	check(not ground.set_room(&"no room"), "a room that is no id")
	check(not ground.add_item(&"", &"bolt", "", 1, Vector2.ZERO, 0.0, []), "no kind")
	check(not ground.add_item(&"card", &"bo-lt", "", 1, Vector2.ZERO, 0.0, []), "an id that is no id")
	check(not ground.add_item(&"card", &"bolt", "é", 1, Vector2.ZERO, 0.0, []), "a name that is not plain text")
	check(not ground.add_item(&"card", &"bolt", "x".repeat(GroundLoadout.MAX_TITLE + 1), 1, Vector2.ZERO, 0.0, []), "a name too long")
	check(not ground.add_item(&"card", &"bolt", "", 0, Vector2.ZERO, 0.0, []), "no copies")
	check(not ground.add_item(&"card", &"bolt", "", 1, Vector2(NAN, 0.0), 0.0, []), "a place that is no number")
	check(not ground.add_item(&"card", &"bolt", "", 1, Vector2.ZERO, INF, []), "a mana that is no number")
	var many: Array[StringName] = []
	for i in GroundLoadout.MAX_CARDS + 1:
		many.append(&"bolt")
	check(not ground.add_item(&"staff", &"star", "", 1, Vector2.ZERO, 0.0, many), "too many cards")
	for i in GroundLoadout.MAX_ITEMS:
		ground.add_item(&"card", &"bolt", "", 1, Vector2.ZERO, 0.0, [])
	check(not ground.add_item(&"card", &"bolt", "", 1, Vector2.ZERO, 0.0, []), "past the most items")
	check_equal(ground.count(), GroundLoadout.MAX_ITEMS, "it holds the most")


func test_the_decoder_refuses_every_cut_and_changes_nothing() -> void:
	var bytes := PackedByteArray()
	_sample().encode_into(bytes)
	for cut in bytes.size():
		var read: GroundLoadout = _sample()
		check(read.decode_at(bytes.slice(0, cut), 0) != "", "cut at %d refused" % cut)
		check(read.equals(_sample()), "cut at %d changed nothing" % cut)
	var bad: PackedByteArray = bytes.duplicate()
	bad[1] = 45
	check(GroundLoadout.new().decode_at(bad, 0) != "", "a room id with a '-' refused")
	bad = bytes.duplicate()
	bad[4] = 0xff
	bad[5] = 0xff
	check(GroundLoadout.new().decode_at(bad, 0) != "", "too many items refused")
	# Random bytes never break it: each is refused or read whole.
	for n in 200:
		var noise := PackedByteArray()
		var state: int = n * 2654435761 + 1
		for i in 1 + n % 90:
			state = (state * 1103515245 + 12345) & 0x7fffffff
			noise.append(state & 0xff)
		var read := GroundLoadout.new()
		if read.decode_at(noise, 0) == "":
			check(read.read_to <= noise.size(), "noise %d read within its bytes" % n)


func test_a_replay_header_carries_it_and_the_frames_give_it() -> void:
	var replay := Replay.new()
	replay.ground = _sample()
	var back: Replay = Replay.from_bytes(replay.to_bytes())
	check(back != null, "the replay reads")
	check(back.ground.equals(_sample()), "its ground is the one written")
	check_equal(Replay.FORMAT, 8, "format 8")
	var frames := FramesScript.new()
	own(frames)
	check_equal(frames.next_run_ground().room, &"", "no source and no replay: nothing")
	frames.set_ground_source(func() -> GroundLoadout: return _sample())
	check(frames.next_run_ground().equals(_sample()), "the game's, with no replay on the deck")
