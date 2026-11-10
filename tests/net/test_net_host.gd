extends "res://tests/support/suite.gd"
## The host's session (netcode spike S2, docs/milestones/netcode-spike.md; net/net_host.gd) on a
## bus, input manager and frames service of its own, the test playing the client by writing its
## messages into the link: the client is seated through the input layer, the header and every tick
## go out, a client frame is used at its tick, a frame that has not arrived is stood in for by the
## last without its presses and commands (and the late one's come with the next), the client's
## leave and join seat through the input layer, a check that differs is kept and told, and
## whatever a client must not send closes the link while the host plays on.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const FramesScript := preload("res://core/sim/frames.gd")

const DT: float = 1.0 / 60.0
const SEAT: int = NetHost.SEAT


## An area of two numbers, for the checks.
class Area:
	extends RefCounted
	var value: int = 0
	var other: int = 7


var _bus: EventsScript
var _input: InputManagerScript
var _frames: FramesScript
var _host: NetHost
## The one guest machine, on seat SEAT.
var _guest: NetGuest
## The client's end of the link.
var _far: NetLoopback
var _heard: Array = []
var _seats: Array = []
var _areas: Dictionary = {}
var _read: Array[InputFrame] = []
var _message: NetMessage = NetMessage.new()


func before_each() -> void:
	_heard.clear()
	_seats.clear()
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
	_bus.listen(&"staff_change_requested", func(seat: int, staff: int, slot: int, card: StringName) -> void: _heard.append([seat, staff, slot, card]))
	_bus.seat_joined.connect(func(seat: int) -> void: _seats.append(seat + 1))
	_bus.seat_left.connect(func(seat: int) -> void: _seats.append(-seat - 1))
	_input.add_virtual_device(0)
	_areas = {"one": Area.new(), "two": Area.new()}
	var ends: Array[NetLoopback] = NetLoopback.pair()
	_far = ends[1]
	_host = NetHost.new(_frames, _input, func() -> Dictionary: return _areas)
	_guest = _host.add_guest(ends[0], 1 << SEAT)
	_read.clear()
	for seat in 4:
		_read.append(InputFrame.new())


func after_each() -> void:
	_host.stop()
	_frames.stop_recording()


func _start() -> Replay:
	var replay: Replay = _host.start(&"sandbox_requested", 0, 99)
	_seats.clear()
	return replay


## One tick as the game runs it.
func _tick() -> void:
	for i in _frames.begin_step(DT):
		_frames.tick(DT)
		_host.after_tick()


## The next message the host sent, decoded (kind 0 when none waits).
func _next() -> NetMessage:
	var bytes: PackedByteArray = _far.read()
	if bytes.is_empty():
		_message.decode(PackedByteArray())
	else:
		check_equal(_message.decode(bytes), "", "what the host sends is a whole message")
	return _message


## Every message waiting, dropped.
func _drain() -> void:
	while not _far.read().is_empty():
		pass


## The client's frame for tick `for_tick`: held and pressed staffs as bits, a walk, commands.
func _frame(held: int = 0, pressed: int = 0, move: Vector2 = Vector2.ZERO, commands: Array = []) -> InputFrame:
	var frame := InputFrame.new()
	frame.seat = SEAT
	frame.held_bits = held
	frame.pressed_bits = pressed
	frame.set_move(move)
	for command: Array in commands:
		frame.add_command(command[0], command.slice(1))
	return frame


func _send(for_tick: int, frame: InputFrame) -> void:
	_far.send(NetMessage.of_frame(for_tick, frame.to_bytes()))


## The recorded frame of the client's seat at `tick`.
func _recorded(tick: int) -> InputFrame:
	_host.replay.read_tick(tick, _read)
	return _read[SEAT]


func test_start_seats_the_client_and_sends_the_header() -> void:
	check(not _input.is_joined(SEAT), "the client's seat is free")
	_seats.clear()
	var replay: Replay = _host.start(&"sandbox_requested", 0, 99)
	check(replay != null and _host.is_running(), "it starts")
	check(_input.is_joined(SEAT) and InputManagerScript.is_virtual(_input.device_of(SEAT)), "the client's seat holds a virtual device")
	check_equal(_seats, [SEAT + 1], "seated by the frames service, as a pad's")
	check(_frames.is_recording(), "the run is recorded")
	var message: NetMessage = _next()
	check_equal(message.kind, NetMessage.HEADER, "the header goes out first")
	var header: Replay = Replay.from_bytes(message.body)
	check(header != null and header.tick_count() == 0, "a replay's header, no ticks")
	if header != null:
		check_equal([header.seats, header.run_seed, header.start, header.build], [0b0011, 99, &"sandbox_requested", Replay.build_of()], "both seats, the seed, the start, this build")
	check(_host.start(&"sandbox_requested", 0) == null, "it starts once")


func test_it_does_not_start_over_a_closed_link_or_a_seat_held_here() -> void:
	_input.join(3)
	check_equal(_input.player_of(3), SEAT, "a pad of this machine holds the client's seat")
	check(_host.start(&"sandbox_requested", 0) == null and not _frames.is_recording(), "no start: the spike seats one client, on that seat")
	_input.leave(SEAT)
	_far.close()
	check(_host.start(&"sandbox_requested", 0) == null, "no start over a closed link")


func test_every_tick_goes_out_after_it() -> void:
	var replay: Replay = _start()
	_drain()
	for tick in 5:
		_tick()
		var message: NetMessage = _next()
		check_equal([message.kind, message.tick], [NetMessage.TICK, tick], "tick %d, in the step it was made" % tick)
		check_equal(message.body, replay.tick_bytes(tick), "its recorded bytes")
		check_equal(_next().kind, 0, "and nothing else")
	check_equal(_host.stats.ticks, 5, "counted")


func test_a_frame_is_used_at_its_tick_and_stood_in_for_when_late() -> void:
	_start()
	_send(1, _frame(0b0001, 0b0001, Vector2.RIGHT))
	_tick()
	check(_recorded(0).move == Vector2i.ZERO and _recorded(0).held_bits == 0, "a frame for tick 1 is not used at tick 0")
	_tick()
	var used: InputFrame = _recorded(1)
	check(used.is_held(0) and used.is_pressed(0) and used.move_vector() == Vector2.RIGHT, "at tick 1 it is: the walk, the button held, the press")
	# Tick 2's frame does not arrive: the last stands in, without its press.
	_tick()
	var stood: InputFrame = _recorded(2)
	check(stood.is_held(0) and stood.move_vector() == Vector2.RIGHT, "tick 2, no frame: the last stands in, the button still held")
	check(not stood.is_pressed(0), "but not pressed again")
	check_equal(_guest.stats.stood_in, 1, "counted")
	# It arrives two ticks late, with a press of another staff and a command.
	_send(2, _frame(0b0011, 0b0010, Vector2.LEFT, [[&"staff_change_requested", 1, 0, &"frost"]]))
	_tick()
	var late: InputFrame = _recorded(3)
	check(late.is_pressed(1) and late.is_held(1) and late.move_vector() == Vector2.LEFT, "the late frame's press comes with the next tick")
	check_equal(late.commands, [[&"staff_change_requested", 1, 0, &"frost"]], "and its command")
	check_equal(_heard, [[SEAT, 1, 0, &"frost"]], "applied once, as the client's seat's")
	check_equal(_guest.stats.late_frames, 1, "counted as late")
	_tick()
	check(not _recorded(4).is_pressed(1) and _recorded(4).commands.is_empty(), "a tick later neither comes again")
	check_equal(_heard.size(), 1, "the command applied once")


func test_frames_for_one_tick_are_used_together() -> void:
	_start()
	_tick()
	_send(1, _frame(0b0001, 0b0001, Vector2.UP, [[&"staff_change_requested", 0, 0, &"bolt"]]))
	_send(1, _frame(0b0000, 0b0100, Vector2.DOWN, [[&"staff_change_requested", 0, 1, &"fire"]]))
	_send(5, _frame(0b1000, 0b1000))
	_tick()
	var used: InputFrame = _recorded(1)
	check(used.move_vector() == Vector2.DOWN and used.held_bits == 0, "the walk and the held buttons are the newest's")
	check_equal(used.pressed_bits, 0b0101, "the presses are both's (a tap between two ticks is not lost)")
	check_equal(used.commands, [[&"staff_change_requested", 0, 0, &"bolt"], [&"staff_change_requested", 0, 1, &"fire"]], "the commands both's, in order")
	check_equal(_recorded(1).pressed_bits & 0b1000, 0, "a frame for a later tick waits")
	for i in 4:
		_tick()
	check(_recorded(5).is_pressed(3) and not _recorded(4).is_pressed(3), "and is used at its own")


func test_more_commands_than_a_frame_holds_wait_for_the_next() -> void:
	_start()
	_tick()
	for i in 3:
		var commands: Array = []
		for slot in 6:
			commands.append([&"staff_change_requested", i, slot, &"bolt"])
		_send(1, _frame(0, 0, Vector2.ZERO, commands))
	_tick()
	check_equal(_recorded(1).commands.size(), InputFrame.MAX_COMMANDS, "a full frame")
	_tick()
	check_equal(_recorded(2).commands.size(), 18 - InputFrame.MAX_COMMANDS, "the rest in the next")
	check_equal(_heard.size(), 18, "every one applied")
	check_equal(_heard[17], [SEAT, 2, 5, &"bolt"], "in order")


func test_a_clients_leave_and_join_seat_through_the_input_layer() -> void:
	_start()
	_tick()
	_send(1, _frame(0, 0, Vector2.ZERO, [[InputFrame.LEAVE]]))
	_tick()
	check(not _input.is_joined(SEAT), "the client's device left: its virtual device leaves here")
	check_equal(_seats, [-SEAT - 1], "and the seat, by the frames service")
	check_equal(_recorded(1).commands, [[InputFrame.LEAVE]], "the recording says so at that tick, once")
	_send(2, _frame(0b0001, 0, Vector2.ZERO, [[InputFrame.JOIN]]))
	_tick()
	check(_input.is_joined(SEAT), "it joins again")
	check_equal(_seats, [-SEAT - 1, SEAT + 1], "seated again")
	check_equal(_recorded(2).commands, [[InputFrame.JOIN]], "recorded once")
	check(_recorded(2).is_held(0), "with the frame's input")


func test_the_client_gone_its_seat_leaves_and_the_host_plays_on() -> void:
	_start()
	_send(0, _frame(0b0001, 0b0001, Vector2.RIGHT))
	_send(1, _frame(0b0001, 0, Vector2.RIGHT))
	_far.close()
	_tick()
	_tick()
	check(_recorded(1).is_held(0), "what arrived before it closed is used")
	check(_input.is_joined(SEAT), "the seat plays while what it sent lasts")
	_tick()
	check(not _input.is_joined(SEAT), "then its seat leaves, as a pad pulled out would")
	check_equal([_recorded(2).commands, _recorded(2).held_bits], [[[InputFrame.LEAVE]], 0], "in the seat's own frame of that tick, which holds nothing")
	check_equal(_seats, [-SEAT - 1], "the frames service says so")
	_tick()
	check_equal(_host.replay.tick_count(), 4, "and the host ran every tick")
	check_equal(_guest.stats.stood_in, 0, "a seat that is gone is not stood in for")
	check(_host.is_running() and _guest.is_gone() and not _host.hears_guests(), "the run goes on, the guest gone")


func test_a_ping_is_answered_before_the_run_and_in_it() -> void:
	_far.send(NetMessage.of_ping(41))
	_host.pump()
	var message: NetMessage = _next()
	check_equal([message.kind, message.stamp], [NetMessage.PONG, 41], "before the run, when pumped")
	_start()
	_drain()
	_far.send(NetMessage.of_ping(42))
	_tick()
	message = _next()
	check_equal([message.kind, message.stamp], [NetMessage.PONG, 42], "in the run, as the seat's frame is built")


func test_what_a_client_must_not_send_closes_the_link() -> void:
	var garbage := PackedByteArray([9, 9, 9])
	var frame_bytes: PackedByteArray = _frame().to_bytes()
	var other_seat := InputFrame.new()
	other_seat.seat = 0
	var bad_frame: PackedByteArray = frame_bytes.duplicate()
	bad_frame[0] = 99
	var none: Dictionary[String, int] = {}
	# What is sent, and a word of the reason it must be refused for.
	var cases: Dictionary[String, Array] = {
		"bytes that are no message": ["too short", garbage],
		"a host's kind (a tick)": ["not a guest's", NetMessage.of_tick(0, PackedByteArray([0]))],
		"a header": ["not a guest's", NetMessage.of_header(Replay.new().header_bytes())],
		"a pong": ["not a guest's", NetMessage.of_pong(1)],
		"a frame of another seat": ["seat 0", NetMessage.of_frame(1, other_seat.to_bytes())],
		"a frame that is no frame": ["version", NetMessage.of_frame(1, bad_frame)],
		"a frame for an earlier tick than the last": ["after one for 5", NetMessage.of_frame(5, frame_bytes), NetMessage.of_frame(4, frame_bytes)],
		"a frame far ahead": ["at tick", NetMessage.of_frame(NetGuest.MAX_AHEAD + 10, frame_bytes)],
		"a check of a tick not played": ["not played yet", NetMessage.of_hashes(500, none)],
		"a check of a tick that ends no check": ["after one of", NetMessage.of_hashes(0, none)],
	}
	for what: String in cases:
		after_each()
		before_each()
		_start()
		_tick()
		var sent: Array = cases[what]
		for at in range(1, sent.size()):
			_far.send(sent[at])
		_tick()
		check(not _far.is_open() and _guest.problem.contains(sent[0]), "%s closes the link, for that (%s)" % [what, _guest.problem])
		_tick()
		check_equal(_host.replay.tick_count(), 3, "%s: the host plays on" % what)


func test_a_frame_before_the_run_closes_the_link() -> void:
	_send(1, _frame())
	_host.pump()
	check(not _far.is_open(), "closed")
	check(_host.start(&"sandbox_requested", 0) == null, "and no run starts over it")


func test_it_reads_a_set_number_of_messages_a_tick() -> void:
	_start()
	_drain()
	for i in NetGuest.MAX_READ + 20:
		_far.send(NetMessage.of_ping(i))
	_tick()
	var pongs: int = 0
	while _next().kind != 0:
		pongs += 1 if _message.kind == NetMessage.PONG else 0
	check_equal(pongs, NetGuest.MAX_READ, "no more than its limit in one tick")
	_tick()
	pongs = 0
	while _next().kind != 0:
		pongs += 1 if _message.kind == NetMessage.PONG else 0
	check_equal(pongs, 20, "the rest in the next")


func test_too_many_frames_waiting_close_the_link() -> void:
	_start()
	for round in 12:
		for i in NetGuest.MAX_READ:
			_send(NetGuest.MAX_AHEAD, _frame())
		_tick()
	check(not _far.is_open(), "closed: %s" % _guest.problem)
	check(_host.replay.tick_count() == 12, "the host played on")


func test_a_refused_client_is_not_read_or_used_again() -> void:
	_start()
	_tick()
	# A bad message, with good ones behind it that arrived before the link closed.
	_far.send(NetMessage.of_pong(1))
	_send(2, _frame(0b0001, 0b0001, Vector2.RIGHT, [[&"staff_change_requested", 0, 0, &"bolt"]]))
	_far.send(NetMessage.of_ping(5))
	_tick()
	check(_guest.problem != "" and not _guest.hears(), "refused")
	_drain()
	_tick()
	_tick()
	check(_recorded(2).held_bits == 0 and _recorded(2).commands.is_empty() and _heard.is_empty(), "the frame behind the bad message is never used")
	var answered: bool = false
	while _next().kind != 0:
		answered = answered or _message.kind == NetMessage.PONG
	check(not answered, "nor its ping answered")
	check_equal(_guest.stats.read, 1, "nothing was read after the refusal")


func test_frames_queued_before_a_refusal_are_dropped() -> void:
	_start()
	_send(3, _frame(0b0001, 0b0001, Vector2.RIGHT))
	_tick()
	_far.send(NetMessage.of_pong(1))
	_tick()
	check(_guest.problem != "", "refused")
	_tick()
	_tick()
	check(_recorded(3).held_bits == 0 and not _recorded(3).is_pressed(0), "a frame that waited for its tick is not used once the client is refused")


func test_a_flood_of_commands_closes_the_link() -> void:
	_start()
	_tick()
	var commands: Array = []
	for slot in InputFrame.MAX_COMMANDS:
		commands.append([&"staff_change_requested", 0, slot, &"bolt"])
	for i in 6:
		_send(1, _frame(0, 0, Vector2.ZERO, commands))
	_tick()
	check(_guest.problem.contains("commands waiting"), "more commands waiting than its limit: refused (%s)" % _guest.problem)
	check_equal(_recorded(1).commands, [[InputFrame.LEAVE]], "and none of them is passed on: its seat leaves")
	_tick()
	check_equal(_host.replay.tick_count(), 3, "the host plays on")


func test_frames_used_together_never_make_a_frame_past_its_limit() -> void:
	_start()
	_tick()
	# Each command a list of 64 long ids: about 4 kB, twelve of them far past a frame's 16 kB.
	var ids: Array[StringName] = []
	for i in InputFrame.MAX_LIST:
		ids.append(StringName("c".repeat(InputFrame.MAX_TEXT - 2) + "%02d" % i))
	for staff in 12:
		_send(1, _frame(0, 0, Vector2.ZERO, [[&"staff_cards_requested", staff % 4, ids]]))
	var heard: Array = []
	_bus.listen(&"staff_cards_requested", func(seat: int, staff: int, cards: Array) -> void: heard.append([seat, staff, cards.size()]))
	for tick in 6:
		_tick()
		check(_recorded(tick + 1).to_bytes().size() <= InputFrame.MAX_BYTES, "tick %d's frame is within a frame's limit (%d bytes)" % [tick + 1, _recorded(tick + 1).to_bytes().size()])
	check_equal(heard.size(), 12, "every command applied, over as many ticks as it took")
	check(_recorded(1).commands.size() < 12 and _recorded(1).commands.size() >= 1, "some in the first tick, the rest after")
	check_equal(_guest.problem, "", "nothing refused: these are a client's to send")
	check(Replay.from_bytes(_host.replay.to_bytes()) != null, "and the recording still decodes")


func test_a_leave_behind_a_full_frame_waits_for_the_next_tick() -> void:
	_start()
	_tick()
	var commands: Array = []
	for slot in InputFrame.MAX_COMMANDS:
		commands.append([&"staff_change_requested", 0, slot, &"bolt"])
	_send(1, _frame(0, 0, Vector2.ZERO, commands))
	_send(1, _frame(0, 0, Vector2.ZERO, [[InputFrame.LEAVE]]))
	_tick()
	check(_input.is_joined(SEAT) and _seats.is_empty(), "the frame is full: the seat does not leave yet")
	_tick()
	check(_recorded(2).commands.has([InputFrame.LEAVE]), "the leave is recorded in the tick the seat left")
	check(not _input.is_joined(SEAT), "the tick after, it does")
	check_equal(_seats, [-SEAT - 1], "and the seat left once")
	check_equal(_heard.size(), InputFrame.MAX_COMMANDS, "every command before it applied")


func test_a_leave_takes_a_place_in_the_frame_it_is_recorded_in() -> void:
	_start()
	_tick()
	var commands: Array = []
	for slot in InputFrame.MAX_COMMANDS - 1:
		commands.append([&"staff_change_requested", 0, slot, &"bolt"])
	commands.append([InputFrame.LEAVE])
	_send(1, _frame(0, 0, Vector2.ZERO, commands))
	_send(1, _frame(0, 0, Vector2.ZERO, [[&"staff_change_requested", 3, 0, &"fire"]]))
	_tick()
	check_equal(_recorded(1).commands.size(), InputFrame.MAX_COMMANDS, "fifteen commands and the leave fill the frame")
	check(_recorded(1).commands.has([InputFrame.LEAVE]), "the leave is recorded, not dropped for want of room")
	_tick()
	check_equal(_recorded(2).commands, [[&"staff_change_requested", 3, 0, &"fire"]], "the command behind them waits for the next tick")


func test_checks_are_taken_one_a_window_in_order() -> void:
	_host.checks = NetChecks.new(2)
	_start()
	for i in 8:
		_tick()
	var none: Dictionary[String, int] = {}
	_far.send(NetMessage.of_hashes(3, none))
	_tick()
	check(_far.is_open(), "a check of a window's last tick is taken")
	_far.send(NetMessage.of_hashes(3, none))
	_tick()
	check(_guest.problem.contains("after one of 3"), "the same check again is refused (%s)" % _guest.problem)


## The client's check of the ticks up to `tick`, hashed as the host hashes (the same areas).
func _client_check(checks: NetChecks, tick: int) -> Dictionary[String, int]:
	return checks.add(tick, _areas)


func test_a_check_that_agrees_passes_and_one_that_differs_is_kept_and_told() -> void:
	_host.checks = NetChecks.new(4)
	var mine := NetChecks.new(4)
	_start()
	_drain()
	var checks: Array = []
	for tick in 8:
		_tick()
		var check: Dictionary[String, int] = _client_check(mine, tick)
		if not check.is_empty():
			checks.append([tick, check])
	check_equal(checks.size(), 2, "a check every four ticks")
	_drain()
	_far.send(NetMessage.of_hashes(checks[0][0], checks[0][1]))
	_tick()
	check_equal([_guest.stats.checks, _guest.stats.mismatches, _host.parted_tick], [1, 0, -1], "the first agrees")
	# The client's game parted in one area: its hash of it is another.
	var theirs: Dictionary[String, int] = checks[1][1]
	theirs["two"] = theirs["two"] + 1
	_far.send(NetMessage.of_hashes(checks[1][0], theirs))
	_tick()
	check_equal([_guest.stats.checks, _guest.stats.mismatches], [2, 1], "the second differs")
	check_equal(_host.parted_tick, 7, "the tick is kept")
	check_equal(_host.parted_areas, PackedStringArray(["two"]), "and the area that differs")
	var told: NetMessage = null
	while _next().kind != 0:
		if _message.kind == NetMessage.PARTED:
			told = _message
			break
	check(told != null, "the client is told")
	if told != null:
		check_equal([told.tick, told.names], [7, PackedStringArray(["two"])], "the tick and the area")
	check(_far.is_open(), "the link stays open: the spike does not mend it")


func test_a_check_the_host_no_longer_keeps_is_counted_not_refused() -> void:
	_host.checks = NetChecks.new(1)
	_start()
	for i in NetHost.MAX_CHECKS_KEPT + 4:
		_tick()
	check_equal(_guest.stats.unchecked, 4, "the oldest checks go once too many wait for the client's")
	_far.send(NetMessage.of_hashes(0, {"one": 1} as Dictionary[String, int]))
	_tick()
	check_equal(_guest.stats.unchecked, 6, "the client's check of one of them is counted (and this tick's oldest went)")
	check(_far.is_open() and _host.parted_tick < 0, "and nothing else: no parting, the link open")


func test_stop_gives_the_seat_back_and_hands_the_run() -> void:
	var replay: Replay = _start()
	_tick()
	_tick()
	check(_host.stop() == replay, "the run recorded")
	check_equal(replay.tick_count(), 2, "its ticks")
	check(not _input.is_joined(SEAT) and _frames.source_of(SEAT) == null, "the client's seat is free again")
	check(not _frames.is_recording() and not _far.is_open(), "the recording stopped, the link closed")


## Several guest machines (online lobby L3): each on seats of its own, the header and every tick
## to each, each one's frames used for its own seats only.
func test_guests_take_seats_of_their_own_up_to_three() -> void:
	var host := NetHost.new(_frames, _input)
	var links: Array[NetLink] = []
	for i in 5:
		links.append(NetLoopback.pair()[0])
	check(host.add_guest(links[0], 1 << 0) == null, "seat 0 is the host's")
	check(host.add_guest(links[0], 0) == null, "a guest plays a seat")
	check(host.add_guest(links[0], 1 << 4) == null, "one of the four")
	check(host.add_guest(links[0], (1 << 1) | (1 << 2)) != null, "a guest on seats 2 and 3")
	check(host.add_guest(links[1], 1 << 2) == null, "a seat another guest plays")
	check(host.add_guest(links[1], 1 << 3) != null and host.guests.size() == 2, "a second guest on seat 4")
	check(host.add_guest(links[2], 1 << 3) == null, "taken")
	check_equal(host.guest_seats(), 0b1110, "the guests' seats")
	var full := NetHost.new(_frames, _input)
	for seat in [1, 2, 3]:
		full.add_guest(NetLoopback.pair()[0], 1 << seat)
	check_equal(full.guests.size(), NetHost.GUESTS, "three guests, one a seat")


## Two guest machines, one on seats 1 and 2, one on seat 3, with the test playing both.
func _two_guests() -> Array[NetLoopback]:
	_host.stop()
	_host = NetHost.new(_frames, _input, func() -> Dictionary: return _areas)
	var a: Array[NetLoopback] = NetLoopback.pair()
	var b: Array[NetLoopback] = NetLoopback.pair()
	_guest = _host.add_guest(a[0], (1 << 1) | (1 << 2))
	_host.add_guest(b[0], 1 << 3)
	return [a[1], b[1]]


func _frame_of(seat: int, held: int, move: Vector2) -> PackedByteArray:
	var frame := InputFrame.new()
	frame.seat = seat
	frame.held_bits = held
	frame.set_move(move)
	return frame.to_bytes()


func test_every_guest_gets_the_header_and_every_tick() -> void:
	var far: Array[NetLoopback] = _two_guests()
	check(_host.start(&"sandbox_requested", 0, 99) != null, "it starts")
	check(_input.is_joined(1) and _input.is_joined(2) and _input.is_joined(3), "every guest's seats seated")
	_tick()
	_tick()
	for i in 2:
		var kinds: Array = []
		var bytes: PackedByteArray = far[i].read()
		while not bytes.is_empty():
			_message.decode(bytes)
			kinds.append([_message.kind, _message.tick])
			bytes = far[i].read()
		check_equal(kinds, [[NetMessage.HEADER, 0], [NetMessage.TICK, 0], [NetMessage.TICK, 1]], "guest %d: the header, then each tick" % i)
	var header: Replay = Replay.new()
	check_equal(header.decode(_host.replay.header_bytes()), "", "the header")
	check_equal(header.seats, 0b1111, "seats every machine's seats")
	check_equal(_host.stats.ticks, 2, "the host's ticks counted")


func test_each_guest_plays_its_own_seats() -> void:
	var far: Array[NetLoopback] = _two_guests()
	_host.start(&"sandbox_requested", 0, 99)
	far[0].send(NetMessage.of_frame(0, _frame_of(1, 0b0001, Vector2.LEFT)))
	far[0].send(NetMessage.of_frame(0, _frame_of(2, 0b0010, Vector2.UP)))
	far[1].send(NetMessage.of_frame(0, _frame_of(3, 0b0100, Vector2.RIGHT)))
	_tick()
	_host.replay.read_tick(0, _read)
	check_equal([_read[1].held_bits, _read[1].move_vector()], [0b0001, Vector2.LEFT], "seat 2 from the first guest")
	check_equal([_read[2].held_bits, _read[2].move_vector()], [0b0010, Vector2.UP], "seat 3 from the first guest too")
	check_equal([_read[3].held_bits, _read[3].move_vector()], [0b0100, Vector2.RIGHT], "seat 4 from the second")


func test_a_guest_that_sends_another_guests_seat_is_closed_alone() -> void:
	var far: Array[NetLoopback] = _two_guests()
	_host.start(&"sandbox_requested", 0, 99)
	_tick()
	far[0].send(NetMessage.of_frame(1, _frame_of(3, 0b0001, Vector2.LEFT)))
	far[1].send(NetMessage.of_frame(1, _frame_of(3, 0b0100, Vector2.RIGHT)))
	_tick()
	var second: NetGuest = _host.guests[1]
	check(_guest.problem.contains("a frame of seat 3") and not far[0].is_open(), "the first guest is closed (%s)" % _guest.problem)
	check(second.hears() and second.problem == "", "the second plays on")
	_tick()
	_tick()
	check(not _input.is_joined(1) and not _input.is_joined(2), "the first guest's seats left")
	check(_input.is_joined(3), "the second's stays")
	_host.replay.read_tick(1, _read)
	check_equal(_read[3].held_bits, 0b0100, "seat 4 is the second guest's own frame, never the first's")
	check(_host.is_running() and _host.hears_guests(), "the run goes on")


func test_each_guests_checks_are_its_own() -> void:
	var far: Array[NetLoopback] = _two_guests()
	_host.checks = NetChecks.new(2)
	_host.start(&"sandbox_requested", 0, 99)
	var theirs := NetChecks.new(2)
	var mine: Dictionary[String, int] = {}
	for tick in 2:
		_tick()
		mine = _client_check(theirs, tick)
	var other: Dictionary[String, int] = mine.duplicate()
	other["two"] = other["two"] + 1
	far[0].send(NetMessage.of_hashes(1, mine))
	far[1].send(NetMessage.of_hashes(1, other))
	_tick()
	var second: NetGuest = _host.guests[1]
	check_equal([_guest.stats.checks, _guest.stats.mismatches, _guest.parted_tick], [1, 0, -1], "the first agrees")
	check_equal([second.stats.checks, second.stats.mismatches, second.parted_tick], [1, 1, 1], "the second parted at tick 1")
	check_equal([_host.parted_tick, _host.parted_areas], [1, PackedStringArray(["two"])], "the host knows the first parting")
	var told: Array = [false, false]
	for i in 2:
		var bytes: PackedByteArray = far[i].read()
		while not bytes.is_empty():
			_message.decode(bytes)
			told[i] = told[i] or _message.kind == NetMessage.PARTED
			bytes = far[i].read()
	check_equal(told, [false, true], "only the guest that parted is told")
	check_equal(_host.totals().checks, 2, "the totals add the guests' up")


## A guest gone while one of its seats still had a frame for the tick: each seat leaves at the tick
## its own LEAVE is recorded in (the seat seen gone this tick; the other, built before that was
## seen, the next), never off the host's game a tick before the recording says so.
func test_a_gone_guests_seats_leave_each_in_its_own_frame() -> void:
	var far: Array[NetLoopback] = _two_guests()
	_host.start(&"sandbox_requested", 0, 99)
	_tick()
	far[0].send(NetMessage.of_frame(1, _frame_of(1, 0b0001, Vector2.LEFT)))
	far[0].close()
	var joined: Array = []
	for i in 3:
		_tick()
		joined.append([_input.is_joined(1), _input.is_joined(2)])
	check_equal(joined, [[true, false], [false, false], [false, false]], "seat 3 (no frame) leaves at once, seat 2 (its frame used) a tick later")
	check_equal([_left_in(1), _left_in(2)], [2, 1], "each in the tick its device left in")
	check(_input.is_joined(3), "the other guest's seat stays")


## The tick of the host's recording whose frame of `seat` holds a LEAVE, or -1.
func _left_in(seat: int) -> int:
	for tick in _host.replay.tick_count():
		_host.replay.read_tick(tick, _read)
		if _read[seat].commands.has([InputFrame.LEAVE]):
			return tick
	return -1


## A guest of several seats holds no more frames waiting than one of one seat: the limit is the
## guest's, all its seats together.
func test_a_guest_of_two_seats_shares_one_limit_of_frames_waiting() -> void:
	var far: Array[NetLoopback] = _two_guests()
	_host.start(&"sandbox_requested", 0, 99)
	var half: int = NetGuest.MAX_QUEUED / 2
	var sent: int = 0
	while sent <= half:
		for i in mini(NetGuest.MAX_READ / 2, half + 1 - sent):
			far[0].send(NetMessage.of_frame(NetGuest.MAX_AHEAD, _frame_of(1, 0, Vector2.ZERO)))
			far[0].send(NetMessage.of_frame(NetGuest.MAX_AHEAD, _frame_of(2, 0, Vector2.ZERO)))
			sent += 1
		_tick()
	check(_guest.problem.contains("frames waiting"), "more than its limit over its two seats: refused (%s)" % _guest.problem)
	check(_host.guests[1].hears(), "the other guest plays on")
