extends "res://tests/support/suite.gd"
## The messages on the wire (netcode spike S2, docs/milestones/netcode-spike.md; net/net_message.gd):
## each kind comes back as it was written, and the decoder refuses everything else: a message cut
## short, one too long for its kind, an unknown kind, a wrong length, a name that is no name, bytes
## left over, and random bytes.

var _message: NetMessage


func before_each() -> void:
	_message = NetMessage.new()


func _frame_bytes() -> PackedByteArray:
	var frame := InputFrame.new()
	frame.seat = 1
	frame.set_move(Vector2(0.5, -1.0))
	frame.press(2)
	frame.add_command(&"staff_change_requested", [2, 0, &"fire"])
	return frame.to_bytes()


## One valid message of every kind.
func _valid() -> Array[PackedByteArray]:
	var replay := Replay.new()
	replay.build = "test 0123"
	return [
		NetMessage.of_header(replay.header_bytes()),
		NetMessage.of_tick(7, PackedByteArray([0])),
		NetMessage.of_frame(19, _frame_bytes()),
		NetMessage.of_hashes(59, {"Combat": 5, "actor 7": -9} as Dictionary[String, int]),
		NetMessage.of_parted(59, PackedStringArray(["Combat", "actor 7"])),
		NetMessage.of_ping(1234),
		NetMessage.of_pong(1234),
		NetMessage.of_seat_ask(2),
		NetMessage.of_run(2),
		NetMessage.of_lobby(7, PackedByteArray([NetMessage.NOBODY, 0, NetMessage.NOBODY, 3])),
	]


func test_every_kind_comes_back_as_written() -> void:
	var replay := Replay.new()
	replay.build = "test 0123"
	check_equal(_message.decode(NetMessage.of_header(replay.header_bytes())), "", "a header")
	check_equal([_message.kind, _message.body], [NetMessage.HEADER, replay.header_bytes()], "its bytes")
	check_equal(_message.decode(NetMessage.of_tick(7, PackedByteArray([3, 1, 2]))), "", "a tick")
	check_equal([_message.kind, _message.tick, _message.body], [NetMessage.TICK, 7, PackedByteArray([3, 1, 2])], "its number and bytes")
	check_equal(_message.decode(NetMessage.of_frame(19, _frame_bytes())), "", "a frame")
	check_equal([_message.kind, _message.tick, _message.body], [NetMessage.FRAME, 19, _frame_bytes()], "its tick and bytes")
	var hashes: Dictionary[String, int] = {"Combat": 5, "actor 7": -9, "Sim": 0x7fffffffffffffff}
	check_equal(_message.decode(NetMessage.of_hashes(59, hashes)), "", "a check")
	check_equal([_message.kind, _message.tick, _message.hashes], [NetMessage.HASHES, 59, hashes], "its tick and every area's hash")
	check_equal(_message.decode(NetMessage.of_hashes(59, {} as Dictionary[String, int])), "", "a check of no areas")
	check_equal(_message.decode(NetMessage.of_parted(59, PackedStringArray(["Combat", "actor 7"]))), "", "a parting")
	check_equal([_message.kind, _message.tick, _message.names], [NetMessage.PARTED, 59, PackedStringArray(["Combat", "actor 7"])], "its tick and areas")
	check_equal(_message.decode(NetMessage.of_ping(0xfffffffe)), "", "a ping")
	check_equal([_message.kind, _message.stamp], [NetMessage.PING, 0xfffffffe], "its stamp, 32 bits")
	check_equal(_message.decode(NetMessage.of_pong(77)), "", "a pong")
	check_equal([_message.kind, _message.stamp], [NetMessage.PONG, 77], "its stamp")
	check_equal(_message.decode(NetMessage.of_seat_ask(3)), "", "an ask for a seat")
	check_equal([_message.kind, _message.local], [NetMessage.SEAT_ASK, 3], "its player")
	var holders := PackedByteArray([NetMessage.NOBODY, 1, 0, NetMessage.NOBODY])
	check_equal(_message.decode(NetMessage.of_lobby(300, holders)), "", "a lobby")
	check_equal([_message.kind, _message.answered, _message.holders], [NetMessage.LOBBY, 300 & 0xff, holders], "the asks answered (a byte) and each seat's holder")


func test_the_recording_a_client_plays_is_said_by_its_number() -> void:
	check_equal(_message.decode(NetMessage.of_run(3)), "", "the client plays the host's third recording")
	check_equal([_message.kind, _message.run], [NetMessage.RUN, 3], "its number")
	check_equal(_message.decode(NetMessage.of_run(256 + 7)), "", "past 255 the number goes round again")
	check_equal(_message.run, 7, "a byte of it")
	var long: PackedByteArray = NetMessage.of_run(2)
	long.append(0)
	long.encode_u32(1, 2)
	check(_message.decode(long) != "", "a number of two bytes is refused")


func test_a_seat_is_asked_for_and_given_only_within_the_four() -> void:
	var ask: PackedByteArray = NetMessage.of_seat_ask(1)
	ask[NetMessage.HEAD_BYTES] = 4
	check(_message.decode(ask) != "", "a fifth player is refused")
	ask[NetMessage.HEAD_BYTES] = 255
	check(_message.decode(ask) != "", "and no player")
	check_equal(NetMessage.of_seat_ask(9), NetMessage.of_seat_ask(3), "an ask is never written for more than the fourth")
	var lobby: PackedByteArray = NetMessage.of_lobby(0, PackedByteArray([0, 1, 2, 3]))
	check_equal(_message.decode(lobby), "", "four players on four seats")
	lobby[NetMessage.HEAD_BYTES + 2] = 4
	check(_message.decode(lobby).contains("held by player 4"), "a seat held by a fifth player is refused")
	lobby[NetMessage.HEAD_BYTES + 2] = 0
	check(_message.decode(lobby).contains("two seats"), "a player on two seats is refused")
	check_equal(_message.holders, PackedByteArray(), "and nothing of it is kept")
	var short: PackedByteArray = NetMessage.of_lobby(0, PackedByteArray([0]))
	check_equal(_message.decode(short), "", "holders left out are nobody")
	check_equal(_message.holders, PackedByteArray([0, NetMessage.NOBODY, NetMessage.NOBODY, NetMessage.NOBODY]), "so the lobby is whole")
	check_equal(NetMessage.of_lobby(0, PackedByteArray([9, 0, 0, 0])).slice(NetMessage.HEAD_BYTES + 1, NetMessage.HEAD_BYTES + 2), PackedByteArray([NetMessage.NOBODY]), "a holder that is no player is written as nobody")


func test_a_parting_names_at_most_its_limit_and_only_names() -> void:
	var many := PackedStringArray()
	for i in NetMessage.MAX_PARTED + 5:
		many.append("actor %d" % i)
	check_equal(_message.decode(NetMessage.of_parted(3, many)), "", "more areas than fit")
	check_equal(_message.names.size(), NetMessage.MAX_PARTED, "the first of them")
	check_equal(_message.decode(NetMessage.of_parted(3, PackedStringArray(["", "a\nb", "ok", "x".repeat(65)]))), "", "names that are none")
	check_equal(_message.names, PackedStringArray(["ok"]), "are left out")
	check_equal(_message.decode(NetMessage.of_hashes(3, {"bad\tname": 1, "ok": 2} as Dictionary[String, int])), "", "a check too")
	check_equal(_message.hashes, {"ok": 2} as Dictionary[String, int], "only the names")


func test_a_message_cut_short_is_refused() -> void:
	for bytes in _valid():
		for size in bytes.size():
			check(_message.decode(bytes.slice(0, size)) != "", "kind %d cut to %d bytes" % [bytes[0], size])
			check_equal(_message.kind, 0, "and it is left empty")


func test_bytes_left_over_are_refused() -> void:
	for bytes in _valid():
		var more: PackedByteArray = bytes.duplicate()
		more.append(0)
		check(_message.decode(more) != "", "kind %d with a byte after it" % bytes[0])
		# The same with the length saying so: the kind's own bytes must use it all.
		more.encode_u32(1, more.size() - NetMessage.HEAD_BYTES)
		if bytes[0] != NetMessage.HEADER and bytes[0] != NetMessage.TICK and bytes[0] != NetMessage.FRAME:
			check(_message.decode(more) != "", "kind %d with a byte too many inside" % bytes[0])


func test_an_unknown_kind_is_refused() -> void:
	for kind: int in [0, 8, 100, 255]:
		var bytes: PackedByteArray = NetMessage.of_ping(1)
		bytes[0] = kind
		check(_message.decode(bytes) != "", "kind %d" % kind)


## A header carries every seat's player loadout (core/sim/party_loadout.gd): each filled until it
## takes no more (staffs of the longest ids full of the longest cards, then stacks, then single
## copies), with the longest build, it is no more than the most a header takes, and that crosses as
## a message.
func test_the_fullest_header_crosses() -> void:
	var replay := Replay.new()
	replay.build = "b".repeat(Replay.MAX_BUILD)
	var longest := StringName("c".repeat(InputFrame.MAX_TEXT))
	var staff: Array[StringName] = []
	for i in PlayerLoadout.MAX_CARDS:
		staff.append(longest)
	var loadout := PlayerLoadout.new()
	var number: int = 0
	while loadout.add_staff(number, longest, staff):
		number += 1
	while loadout.add_stack(longest, longest, PlayerLoadout.MAX_COPIES):
		pass
	while loadout.add_stack(&"b", &"c", 1):
		pass
	check(number > 0 and loadout.size() > PlayerLoadout.MAX_BYTES - 4 and loadout.size() <= PlayerLoadout.MAX_BYTES, "a loadout filled to its limit (%d bytes)" % loadout.size())
	for seat in PartyLoadout.SEATS:
		replay.party.put(seat, loadout)
	var header: PackedByteArray = replay.header_bytes()
	check(header.size() <= Replay.MAX_HEADER_BYTES and header.size() > Replay.MAX_HEADER_BYTES - 16, "the fullest header is no more than a header takes (%d of %d)" % [header.size(), Replay.MAX_HEADER_BYTES])
	check(NetMessage.MAX_HEADER <= NetMessage.MAX_BYTES, "and no more than a message may be")
	check_equal(_message.decode(NetMessage.of_header(header)), "", "it crosses")
	var back := Replay.new()
	check_equal(back.decode(_message.body), "", "and reads back as a replay")
	check(back.party.equals(replay.party), "with every seat's loadout")


func test_a_message_too_long_for_its_kind_is_refused() -> void:
	var big := PackedByteArray()
	big.resize(NetMessage.MAX_HEADER + 1)
	check(_message.decode(NetMessage.of_header(big)) != "", "a header past its limit")
	big.resize(NetMessage.MAX_TICK_BYTES + 1)
	check(_message.decode(NetMessage.of_tick(1, big)) != "", "a tick past its limit")
	big.resize(InputFrame.MAX_BYTES + 1)
	check(_message.decode(NetMessage.of_frame(1, big)) != "", "a frame past its limit")
	big.resize(NetMessage.MAX_BYTES + 1)
	big[0] = NetMessage.HASHES
	big.encode_u32(1, big.size() - NetMessage.HEAD_BYTES)
	check(_message.decode(big) != "", "anything past the longest message")
	var ping: PackedByteArray = NetMessage.of_ping(1)
	ping.append_array(PackedByteArray([0, 0]))
	ping.encode_u32(1, 6)
	check(_message.decode(ping) != "", "a stamp of six bytes")


func test_numbers_out_of_range_are_refused() -> void:
	check(_message.decode(NetMessage.of_tick(NetMessage.MAX_TICK + 1, PackedByteArray([0]))) != "", "a tick past the last")
	check(_message.decode(NetMessage.of_frame(0xffffffff, _frame_bytes())) != "", "a frame for a tick past the last")
	check_equal(_message.decode(NetMessage.of_tick(NetMessage.MAX_TICK, PackedByteArray([0]))), "", "the last tick is one")
	var check_bytes: PackedByteArray = NetMessage.of_hashes(1, {"a": 1} as Dictionary[String, int])
	check_bytes.encode_u16(NetMessage.HEAD_BYTES + 4, 2)
	check(_message.decode(check_bytes) != "", "a check that says more areas than it holds")
	check_bytes.encode_u16(NetMessage.HEAD_BYTES + 4, NetMessage.MAX_AREAS + 1)
	check(_message.decode(check_bytes) != "", "a check of too many areas")
	var twice: PackedByteArray = NetMessage.of_hashes(1, {"a": 1, "b": 2} as Dictionary[String, int])
	twice[NetMessage.HEAD_BYTES + 6 + 1 + 1 + 8 + 1] = 97
	check(_message.decode(twice) != "", "an area named twice")
	var named: PackedByteArray = NetMessage.of_parted(1, PackedStringArray(["ab"]))
	named[named.size() - 1] = 10
	check(_message.decode(named) != "", "a name with a line break")
	named = NetMessage.of_parted(1, PackedStringArray(["ab"]))
	named[NetMessage.HEAD_BYTES + 5] = 0
	check(_message.decode(named) != "", "an empty name")
	named = NetMessage.of_parted(1, PackedStringArray(["ab"]))
	named[NetMessage.HEAD_BYTES + 4] = NetMessage.MAX_PARTED + 1
	check(_message.decode(named) != "", "too many areas parted")


## Random bytes, and valid messages with bytes changed: the decoder answers every one (a problem,
## or a message whose own limits hold) and never fails.
func test_random_bytes_are_refused_or_read_whole() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5eed
	var valid: Array[PackedByteArray] = _valid()
	var refused: int = 0
	var taken: int = 0
	for i in 6000:
		var bytes: PackedByteArray
		if i % 3 == 0:
			bytes = PackedByteArray()
			bytes.resize(rng.randi_range(0, 80))
			for at in bytes.size():
				bytes[at] = rng.randi_range(0, 255)
			if i % 6 == 0 and bytes.size() >= NetMessage.HEAD_BYTES:
				# A true envelope round random bytes, so the kinds' own readers are reached.
				bytes[0] = rng.randi_range(1, 7)
				bytes.encode_u32(1, bytes.size() - NetMessage.HEAD_BYTES)
		else:
			bytes = valid[rng.randi_range(0, valid.size() - 1)].duplicate()
			for change in rng.randi_range(1, 3):
				bytes[rng.randi_range(0, bytes.size() - 1)] = rng.randi_range(0, 255)
		var problem: String = _message.decode(bytes)
		if problem != "":
			refused += 1
			check_equal(_message.kind, 0, "a refused message is left empty")
			continue
		taken += 1
		check(_message.kind >= NetMessage.HEADER and _message.kind <= NetMessage.RUN, "a known kind")
		check(_message.tick >= 0 and _message.tick <= NetMessage.MAX_TICK, "a tick in range")
		check(_message.hashes.size() <= NetMessage.MAX_AREAS and _message.names.size() <= NetMessage.MAX_PARTED, "within its limits")
		for name: String in _message.hashes:
			check(name.length() >= 1 and name.length() <= NetMessage.MAX_NAME, "a name")
	check(refused > 2000, "most are refused (%d)" % refused)
	check(taken > 100, "and a change that keeps a message whole is read (%d)" % taken)


## A check holds every area of a full actor table: a body an actor, an actor's part of each area
## kept by actor id (BY_ACTOR, props W3: "Spells 7"), and the services. A second area that lists
## BY_ACTOR adds a part an actor: this fails until MAX_AREAS grows with it (an area past it is left
## out of the check, and the other machine reports it as differing).
func test_a_check_holds_a_full_table_of_bodies_and_parts() -> void:
	var by_actor: int = 0
	for entry in preload("res://tests/support/sim_source.gd").scripts():
		if StateWalk.has_by_actor(entry["script"] as Script):
			by_actor += 1
	check(by_actor >= 1, "Spells keeps state by actor id")
	var actors: int = preload("res://core/actors/actors.gd").ACTORS
	check(NetMessage.MAX_AREAS >= (1 + by_actor) * actors + 64, "%d areas hold %d bodies, %d parts each and the services" % [NetMessage.MAX_AREAS, actors, by_actor])
