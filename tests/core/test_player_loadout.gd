extends "res://tests/support/suite.gd"
## The player loadout (core/sim/player_loadout.gd, items I4) and the party's (party_loadout.gd): what
## a run's start takes along, each seat's bags, staffs by number and hands. It comes back from its
## bytes as it was, a copy stands apart, a writer refuses what is no id or past a limit, and the
## decoder refuses every cut, count, number and id out of range and a section it does not know,
## changing nothing.

const FramesScript := preload("res://core/sim/frames.gd")

const NONE: int = PlayerLoadout.NO_STAFF


func _ids(words: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for word in words.split(" ", false):
		out.append(StringName(word) if word != "-" else &"")
	return out


## A player: bolts and a fire in the card bag, a relic, `curl` on RB, `star` in the staff bag and
## `dev` on LB.
func _player() -> PlayerLoadout:
	var made := PlayerLoadout.new()
	made.add_stack(&"cards", &"bolt", 19)
	made.add_stack(&"cards", &"fire", 1)
	made.add_stack(&"relics", &"lamp", 1)
	made.add_staff(0, &"curl", _ids("bolt - dash"))
	made.add_staff(7, &"star", _ids(""))
	made.add_staff(2, &"dev", _ids("fire"))
	made.set_hands(PackedInt32Array([0, NONE, 2, NONE]))
	return made


func _bytes(loadout: PlayerLoadout) -> PackedByteArray:
	var out := PackedByteArray()
	loadout.encode_into(out)
	return out


func test_it_comes_back_from_its_bytes_as_it_was() -> void:
	var loadout: PlayerLoadout = _player()
	var bytes := PackedByteArray([7])
	loadout.encode_into(bytes)
	check_equal(bytes.size() - 1, loadout.size(), "it takes `size()` bytes")
	bytes.append(9)
	var back := PlayerLoadout.new()
	check_equal(back.decode_at(bytes, 1), "", "read")
	check_equal(back.read_to, bytes.size() - 1, "up to its end, not past it")
	check(back.equals(loadout), "the same")
	check_equal(back.bags(), [&"cards", &"relics"] as Array[StringName], "the bags, in order")
	check_equal(back.stack_ids(&"cards"), _ids("bolt fire"), "a bag's stacks")
	check_equal(back.stack_counts(&"cards"), PackedInt32Array([19, 1]), "and their copies")
	check_equal(back.staff_numbers(), PackedInt32Array([0, 7, 2]), "the staffs by number, in the order written")
	check_equal(back.staff_id(7), &"star", "each the staff it is")
	check_equal(back.staff_cards(0), _ids("bolt - dash"), "with its cards slot by slot, an empty slot kept")
	check_equal(back.staff_cards(7), _ids(""), "a staff of no cards")
	check_equal(back.hands(), PackedInt32Array([0, NONE, 2, NONE]), "the hands, an empty one too")
	check_equal([back.hand_of(2), back.hand_of(7), back.hand_of(NONE)], [2, -1, -1], "a staff's hand, none for one in the bag")
	check(back.stack_ids(&"potions").is_empty() and back.staff_id(5) == &"" and back.staff_cards(5).is_empty(), "nothing for a bag or a number it has not")
	var none := PlayerLoadout.new()
	check(none.is_empty() and not loadout.is_empty(), "a new one holds nothing")
	check_equal(_bytes(none).size(), none.size(), "and its bytes are its size")
	check_equal(PlayerLoadout.new().decode_at(_bytes(none), 0), "", "an empty loadout is one: a player with nothing")


func test_a_copy_stands_apart() -> void:
	var loadout: PlayerLoadout = _player()
	var copy: PlayerLoadout = loadout.copy()
	check(copy.equals(loadout) and copy.size() == loadout.size(), "a copy is the same")
	copy.add_stack(&"cards", &"nova", 2)
	copy.add_staff(9, &"moon", _ids("bolt"))
	copy.set_hands(PackedInt32Array([9]))
	loadout.staff_cards(0).append(&"nova")
	loadout.stack_ids(&"cards").append(&"nova")
	check(loadout.equals(_player()), "changing the copy, or what it hands out, leaves the first")
	check(not copy.equals(loadout) and not loadout.equals(null), "and they are no longer the same")
	var other: PlayerLoadout = _player()
	other.set_hands(PackedInt32Array([0, 2, NONE, NONE]))
	check(not other.equals(loadout), "the same things on other hands are not the same player")


func test_a_writer_refuses_what_is_no_id_or_past_a_limit() -> void:
	var loadout: PlayerLoadout = _player()
	var before: PackedByteArray = _bytes(loadout)
	check(not loadout.add_stack(&"", &"bolt", 1) and not loadout.add_stack(&"cards", &"", 1), "a bag or an item with no name")
	check(not loadout.add_stack(&"cards", &"res://x.gd", 1) and not loadout.add_stack(&"a/b", &"bolt", 1), "a path is no id")
	check(not loadout.add_stack(&"cards", &"bolt", 0) and not loadout.add_stack(&"cards", &"bolt", PlayerLoadout.MAX_COPIES + 1), "no copies, or more than a stack holds")
	check(not loadout.add_staff(0, &"moon", _ids("")), "a number taken")
	check(not loadout.add_staff(-1, &"moon", _ids("")) and not loadout.add_staff(PlayerLoadout.MAX_NUMBER + 1, &"moon", _ids("")), "a number out of range")
	check(not loadout.add_staff(3, &"", _ids("")) and not loadout.add_staff(3, &"moon", [&"a.b"] as Array[StringName]), "a staff with no id, or a card that is none")
	var many: Array[StringName] = []
	many.resize(PlayerLoadout.MAX_CARDS + 1)
	check(not loadout.add_staff(3, &"moon", many), "more cards than a staff has slots")
	check(not loadout.set_hands(PackedInt32Array([5])), "a hand holding a staff it does not own")
	check(not loadout.set_hands(PackedInt32Array([0, 0])), "one staff on two hands")
	var hands := PackedInt32Array()
	hands.resize(PlayerLoadout.MAX_HANDS + 1)
	hands.fill(NONE)
	check(not loadout.set_hands(hands), "more hands than there may be")
	check_equal(_bytes(loadout), before, "every refusal changes nothing")
	# The counts' limits.
	var full := PlayerLoadout.new()
	for i in PlayerLoadout.MAX_BAGS:
		check(full.add_stack(StringName("bag%d" % i), &"x", 1), "bag %d" % i)
	check(not full.add_stack(&"one_more", &"x", 1), "no more bags than MAX_BAGS")
	for i in PlayerLoadout.MAX_STACKS - PlayerLoadout.MAX_BAGS:
		full.add_stack(&"bag0", &"x", 1)
	check(not full.add_stack(&"bag0", &"x", 1), "no more stacks than MAX_STACKS")
	for i in PlayerLoadout.MAX_STAFFS:
		check(full.add_staff(i, &"s", _ids("")), "staff %d" % i)
	check(not full.add_staff(PlayerLoadout.MAX_STAFFS, &"s", _ids("")), "no more staffs than MAX_STAFFS")
	check_equal(PlayerLoadout.new().decode_at(_bytes(full), 0), "", "one at its counts is read")
	# The bytes' limit: staffs full of the longest cards.
	var longest := StringName("c".repeat(InputFrame.MAX_TEXT))
	var staff: Array[StringName] = []
	for i in PlayerLoadout.MAX_CARDS:
		staff.append(longest)
	var big := PlayerLoadout.new()
	var number: int = 0
	while big.add_staff(number, longest, staff):
		number += 1
	check(number > 0 and number < PlayerLoadout.MAX_STAFFS, "a staff that would pass MAX_BYTES is refused (after %d)" % number)
	check(big.size() <= PlayerLoadout.MAX_BYTES and _bytes(big).size() == big.size(), "so it never takes more")
	check_equal(PlayerLoadout.new().decode_at(_bytes(big), 0), "", "and is read back")


## Where the sections start in `_player()`'s bytes: [BAGS, STAFFS, HANDS], each at its tag.
func _sections(bytes: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	var at: int = 1
	for tag in PlayerLoadout.SECTIONS:
		out.append(at)
		at += 3 + bytes.decode_u16(at + 1)
	return out


func test_the_decoder_refuses_what_is_not_whole_and_in_bounds() -> void:
	var good: PackedByteArray = _bytes(_player())
	var at: PackedInt32Array = _sections(good)
	var bags: int = at[0]
	var staffs: int = at[1]
	var hands: int = at[2]
	var cases: Dictionary = {}
	cases["nothing"] = PackedByteArray()
	# Every cut: a loadout never reads from fewer bytes than its own.
	for size in good.size():
		cases["cut to %d bytes" % size] = good.slice(0, size)
	var change: Callable = func(name: String, index: int, value: int) -> void:
		var bytes: PackedByteArray = good.duplicate()
		bytes[index] = value
		cases[name] = bytes
	change.call("two sections", 0, 2)
	change.call("four sections", 0, 4)
	change.call("a section it does not know", bags, 9)
	change.call("a section out of its place", bags, PlayerLoadout.STAFFS)
	change.call("a later section it does not know", hands, 4)
	change.call("a section longer than its payload", bags + 1, good[bags + 1] + 1)
	change.call("a section shorter than its payload", bags + 1, good[bags + 1] - 1)
	# BAGS: count, then "cards" (5, c a r d s), its stacks (2 bytes), "bolt" (4, b o l t), 19 (2 bytes).
	change.call("more bags than it holds", bags + 3, 3)
	change.call("fewer bags than it holds", bags + 3, 1)
	change.call("a bag with no name", bags + 4, 0)
	change.call("a bag's name longer than an id", bags + 4, InputFrame.MAX_TEXT + 1)
	change.call("a bag's name with a dot", bags + 5, 0x2e)
	change.call("a bag's name with a zero byte", bags + 5, 0)
	change.call("a bag's name with a byte past plain text", bags + 5, 0xc3)
	change.call("more stacks than the bag holds", bags + 10, 3)
	change.call("an item with no name", bags + 12, 0)
	change.call("an item with a slash", bags + 13, 0x2f)
	change.call("a stack of no copies", bags + 17, 0)
	var twice := PlayerLoadout.new()
	twice.add_stack(&"cards", &"bolt", 1)
	twice.add_stack(&"cardz", &"bolt", 1)
	var twice_bytes: PackedByteArray = _bytes(twice)
	twice_bytes[1 + 3 + 1 + 1 + 5 + 2 + 5 + 2 + 5] = 0x73
	cases["a bag twice"] = twice_bytes
	# By hand: the bag "cards" with a stack count of 0, then no staffs and no hands.
	var no_stacks := PackedByteArray([3, PlayerLoadout.BAGS, 9, 0, 1, 5])
	no_stacks.append_array("cards".to_ascii_buffer())
	no_stacks.append_array(PackedByteArray([0, 0, PlayerLoadout.STAFFS, 1, 0, 0, PlayerLoadout.HANDS, 1, 0, 0]))
	cases["a bag that holds nothing"] = no_stacks
	# STAFFS: count, then number 0 (2 bytes), "curl" (4, c u r l), 3 cards: "bolt", "", "dash".
	change.call("more staffs than it holds", staffs + 3, 4)
	change.call("a number twice", staffs + 3 + 1 + 2 + 5 + 1 + 5 + 1 + 5, 0)
	change.call("a staff with no id", staffs + 6, 0)
	change.call("a staff's id with a dot", staffs + 7, 0x2e)
	change.call("more cards than the staff holds", staffs + 11, 4)
	change.call("more cards than a staff has slots", staffs + 11, PlayerLoadout.MAX_CARDS + 1)
	change.call("a card that is no id", staffs + 13, 0x2d)
	change.call("a card longer than an id", staffs + 12, InputFrame.MAX_TEXT + 1)
	var numbered: PackedByteArray = good.duplicate()
	numbered.encode_u16(staffs + 4, 0xffff)
	cases["a staff numbered as no staff is"] = numbered
	# HANDS: count, then each hand's number (2 bytes).
	change.call("more hands than it holds", hands + 3, 5)
	change.call("more hands than there may be", hands + 3, PlayerLoadout.MAX_HANDS + 1)
	change.call("a hand holding a staff it does not own", hands + 4, 5)
	change.call("one staff on two hands", hands + 6, 0)
	change.call("the same staff on two hands (the second byte)", hands + 7, 0)
	var left_over: PackedByteArray = good.duplicate()
	left_over.encode_u16(hands + 1, left_over.decode_u16(hands + 1) + 1)
	left_over.append(0)
	cases["a byte left over in a section"] = left_over
	for name: String in cases:
		var loadout: PlayerLoadout = _player()
		check(loadout.decode_at(cases[name], 0) != "", "%s is refused" % name)
		check(loadout.equals(_player()), "%s changes nothing" % name)
	check_equal(PlayerLoadout.new().decode_at(good, 0), "", "the good one is read")
	check(PlayerLoadout.new().decode_at(no_stacks, 0).contains("holds nothing"), "the empty bag for being empty")
	check(PlayerLoadout.new().decode_at(twice_bytes, 0).contains("twice"), "the bag twice for being twice")
	check(PlayerLoadout.new().decode_at(cases["a section it does not know"], 0).contains("does not know"), "the unknown section for being unknown")
	check(PlayerLoadout.new().decode_at(good, -1) != "" and PlayerLoadout.new().decode_at(good, good.size()) != "", "nothing is read from outside the bytes")


func test_random_bytes_never_break_the_decoder() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var good: PackedByteArray = _bytes(_player())
	var read: int = 0
	for i in 4000:
		var bytes: PackedByteArray = good.duplicate()
		bytes[rng.randi() % bytes.size()] = rng.randi() % 256
		if i % 4 == 0:
			bytes[rng.randi() % bytes.size()] = rng.randi() % 256
		var loadout := PlayerLoadout.new()
		if loadout.decode_at(bytes, 0) == "":
			read += 1
			check_equal(_bytes(loadout), bytes.slice(0, loadout.read_to), "what is read is exactly its bytes")
			check_equal(loadout.size(), loadout.read_to, "and its size")
	check(read > 0, "some changed loadouts are still loadouts (%d)" % read)


## The party's loadout: a byte of seats, then each of those seats' loadout.
func test_the_partys_record_comes_back_and_bad_ones_are_refused() -> void:
	var party := PartyLoadout.new()
	check(party.is_empty() and party.of(0) == null, "nobody takes anything along at first")
	check_equal(_party_bytes(party), PackedByteArray([0]), "which is one byte")
	party.put(0, _player())
	party.put(3, PlayerLoadout.new())
	party.put(4, _player())
	party.put(-1, _player())
	check_equal(party.seats(), 0b1001, "seats 0 and 3; a seat outside the four is none")
	check(party.of(3) != null and party.of(3).is_empty(), "an empty loadout is a player with nothing, not no loadout")
	party.of(0).add_stack(&"cards", &"nova", 1)
	check(party.of(0).equals(_player()), "what it hands out is a copy")
	var bytes := PackedByteArray([7])
	party.encode_into(bytes)
	check(bytes.size() - 1 <= PartyLoadout.MAX_BYTES, "within its most")
	bytes.append(9)
	var back := PartyLoadout.new()
	check_equal(back.decode_at(bytes, 1), "", "read")
	check_equal(back.read_to, bytes.size() - 1, "to its end")
	check(back.equals(party) and party.copy().equals(party) and not party.equals(null), "the same, and a copy too")
	var other: PartyLoadout = party.copy()
	other.put(3, null)
	check(not other.equals(party) and party.seats() == 0b1001, "a copy stands apart")
	other.put(3, _player())
	check(not other.equals(party), "another loadout for a seat is not the same")
	var good: PackedByteArray = _party_bytes(party)
	var cases: Dictionary = {"nothing": PackedByteArray(), "cut short": good.slice(0, good.size() - 1), "only the seats": good.slice(0, 1)}
	var fifth: PackedByteArray = good.duplicate()
	fifth[0] = 0x19
	cases["a fifth seat"] = fifth
	var more: PackedByteArray = good.duplicate()
	more[0] = 0b1011
	cases["a seat more than it holds"] = more
	var bad: PackedByteArray = good.duplicate()
	bad[1] = 9
	cases["a loadout that is none"] = bad
	for name: String in cases:
		var kept: PartyLoadout = party.copy()
		check(kept.decode_at(cases[name], 0) != "", "%s is refused" % name)
		check(kept.equals(party), "%s changes nothing" % name)


func _party_bytes(party: PartyLoadout) -> PackedByteArray:
	var out := PackedByteArray()
	party.encode_into(out)
	return out


## The frames service: a run that starts takes what the game says it would take now, or the
## replay's on the deck (its header), always as a copy.
func test_a_run_takes_the_games_party_or_the_replays() -> void:
	var frames: FramesScript = FramesScript.new()
	check(frames.next_run_party().is_empty(), "nothing, with no game to ask")
	var game := PartyLoadout.new()
	game.put(0, _player())
	frames.set_party_source(func() -> PartyLoadout: return game)
	check(frames.next_run_party().equals(game), "what the game says")
	frames.set_party_source(func() -> PartyLoadout: return null)
	check(frames.next_run_party().is_empty(), "a game that says nothing: nothing")
	frames.set_party_source(func() -> PartyLoadout: return game)
	var replay := Replay.new()
	replay.party.put(1, PlayerLoadout.new())
	frames.set(&"_tape", ReplayTape.playing(replay))
	var run: PartyLoadout = frames.next_run_party()
	check_equal(run.seats(), 0b0010, "the replay's, not the game's")
	run.put(1, null)
	check_equal(replay.party.seats(), 0b0010, "a copy: the run's change is not the replay's")
	frames.free()
