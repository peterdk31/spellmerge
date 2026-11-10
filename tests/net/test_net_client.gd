extends "res://tests/support/suite.gd"
## The client's session (netcode spike S2, docs/milestones/netcode-spike.md; net/net_client.gd) on
## a bus, input manager and frames service of its own, the test playing the host by writing its
## messages into the link: the client pings, takes the host's header only of this build and
## content with a seat for it, plays the ticks as they arrive, sends its seat's frame every step
## for the host's tick `tick + delay`, works its delay out from its ping, times its presses,
## sends its checks, keeps a parting it is told of, ends when the host is gone, and
## closes the link on whatever a host must not send.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const FramesScript := preload("res://core/sim/frames.gd")

const DT: float = 1.0 / 60.0
const SEAT: int = 1


class Area:
	extends RefCounted
	var value: int = 0


var _bus: EventsScript
var _input: InputManagerScript
var _frames: FramesScript
var _client: NetClient
## The host's end of the link.
var _far: NetLoopback
var _areas: Dictionary = {}
var _now: float = 0.0
var _message: NetMessage = NetMessage.new()
## The host's run: its header, and the ticks it has made.
var _run: Replay
var _host_frames: Array[InputFrame] = []


func before_each() -> void:
	_now = 0.0
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
	_input.add_virtual_device(SEAT)
	_areas = {"one": Area.new(), "two": Area.new()}
	var ends: Array[NetLoopback] = NetLoopback.pair()
	_far = ends[1]
	_client = NetClient.new(_frames, ends[0], func() -> Dictionary: return _areas, SEAT, 2, 4)
	_client.clock = func() -> float: return _now
	_run = Replay.new()
	_run.build = Replay.build_of()
	_run.content = Replay.content_of(_frames.registry)
	_run.run_seed = 5
	_run.seats = 0b0011
	_host_frames.clear()
	for seat in 4:
		var frame := InputFrame.new()
		frame.seat = seat
		_host_frames.append(frame)


func after_each() -> void:
	_frames.stop_playing()


## One physics step as the game runs it. Returns the ticks run.
func _step() -> int:
	_now += 1000.0 / 60.0
	if not _client.started:
		_client.pump()
		return 0
	var due: int = _frames.begin_step(DT)
	for i in due:
		_frames.tick(DT)
		_client.after_tick()
	return due


## The host sends its header and the client takes it.
func _link_up() -> void:
	_far.send(NetMessage.of_header(_run.header_bytes()))
	_step()
	_drain()


## The host makes `count` more ticks (seat 1's frame pressing `pressed`) and sends them.
func _host_ticks(count: int, pressed: int = 0) -> void:
	for i in count:
		for frame in _host_frames:
			frame.clear()
		_host_frames[0].set_move(Vector2.RIGHT)
		_host_frames[SEAT].pressed_bits = pressed
		_run.add_tick(_host_frames, 0b0011)
		var tick: int = _run.tick_count() - 1
		_far.send(NetMessage.of_tick(tick, _run.tick_bytes(tick)))


## The next message the client sent of `kind` (others before it are dropped), or null.
func _next(kind: int) -> NetMessage:
	while true:
		var bytes: PackedByteArray = _far.read()
		if bytes.is_empty():
			return null
		check_equal(_message.decode(bytes), "", "what the client sends is a whole message")
		if _message.kind == kind:
			return _message
	return null


func _drain() -> void:
	while not _far.read().is_empty():
		pass


func test_it_pings_and_takes_the_hosts_header() -> void:
	_step()
	check(_next(NetMessage.PING) != null, "it pings while it waits")
	check(not _client.started and not _frames.is_playing(), "nothing plays before the header")
	_far.send(NetMessage.of_header(_run.header_bytes()))
	_step()
	check(_client.started and _client.is_playing() and _frames.is_live(), "the header starts the host's run, live")
	check_equal(_frames.joined_seats(), [0, 1] as Array[int], "with the host's seats")
	check_equal([_client.delay, _client.stats.delay], [4, 4], "the delay given")
	check_equal(_step(), 0, "no tick yet: it waits")
	_host_ticks(2)
	check_equal(_step(), 1, "ticks arrive: it plays")
	check_equal(_frames.frame_of(0).move_vector(), Vector2.RIGHT, "the host's frames")
	check_equal(_step(), 1, "one a step")
	check_equal(_step(), 0, "then it waits again")
	_step()
	check_equal(_client.stats.steps_waited, 2, "the steps it waited are counted")


func test_it_sends_its_frame_every_step_for_the_tick_and_its_delay() -> void:
	_link_up()
	_input.send_virtual(SEAT, &"move_left", 1.0)
	_step()
	var sent: NetMessage = _next(NetMessage.FRAME)
	check(sent != null, "a frame while it waits")
	if sent == null:
		return
	check_equal(sent.tick, 0 + 4, "for the next tick it plays and its delay")
	var frame := InputFrame.new()
	check_equal(frame.decode(sent.body), "", "a whole frame")
	check_equal([frame.seat, frame.move_vector()], [SEAT, Vector2.LEFT], "its seat's, from its device")
	_host_ticks(3)
	_step()
	_step()
	_drain()
	_step()
	sent = _next(NetMessage.FRAME)
	check(sent != null and sent.tick == 2 + 4, "two ticks played: for tick 2 and the delay")


func test_the_delay_comes_from_the_ping_when_none_is_given() -> void:
	var ends: Array[NetLoopback] = NetLoopback.pair()
	_far = ends[1]
	_client = NetClient.new(_frames, ends[0], Callable(), SEAT, 2)
	_client.clock = func() -> float: return _now
	_step()
	var ping: NetMessage = _next(NetMessage.PING)
	check(ping != null, "a ping")
	if ping == null:
		return
	# Six steps (100 ms) later the answer is there.
	for i in 5:
		_step()
	_far.send(NetMessage.of_pong(ping.stamp))
	_step()
	check(absf(_client.stats.rtt_ms - 100.0) <= 1.0, "the round trip measured (%.0f ms)" % _client.stats.rtt_ms)
	_far.send(NetMessage.of_header(_run.header_bytes()))
	_step()
	check_equal(_client.delay, 6 + 2 + 1, "the round trip in ticks, the cushion and one")
	# With no ping answered: the default.
	after_each()
	before_each()
	ends = NetLoopback.pair()
	_far = ends[1]
	_client = NetClient.new(_frames, ends[0], Callable(), SEAT, 2)
	_far.send(NetMessage.of_header(_run.header_bytes()))
	_step()
	check_equal(_client.delay, NetClient.DEFAULT_DELAY, "no ping answered: the default")


func test_a_header_of_another_game_is_refused() -> void:
	# How the header is changed, and a word of the reason it must be refused for.
	var cases: Dictionary[String, Array] = {
		"another build": ["other 0123", func(run: Replay) -> void: run.build = "other 0123"],
		"other content": ["not this game's", func(run: Replay) -> void: run.content += 1],
		"no seat for this machine": ["seated nobody", func(run: Replay) -> void: run.seats = 0b0001],
	}
	for what: String in cases:
		after_each()
		before_each()
		(cases[what][1] as Callable).call(_run)
		_far.send(NetMessage.of_header(_run.header_bytes()))
		_step()
		check(not _client.started and not _frames.is_playing(), "%s: nothing plays" % what)
		check(not _far.is_open() and _client.problem.contains(cases[what][0]), "%s: the link closes, for that (%s)" % [what, _client.problem])


func test_what_a_host_must_not_send_closes_the_link() -> void:
	var frame := InputFrame.new()
	frame.seat = SEAT
	var with_ticks := Replay.new()
	with_ticks.build = Replay.build_of()
	with_ticks.add_tick(_host_frames, 0)
	var none: Dictionary[String, int] = {}
	# What is sent, and a word of the reason it must be refused for.
	var cases: Dictionary[String, Array] = {
		"bytes that are no message": ["too short", PackedByteArray([1, 2, 3])],
		"a second header": ["second header", NetMessage.of_header(_run.header_bytes())],
		"a tick out of order": ["tick 3, not 0", NetMessage.of_tick(3, PackedByteArray([0]))],
		"a tick that is none": ["seats", NetMessage.of_tick(0, PackedByteArray([0x1f]))],
		"a tick with bytes left over": ["left over", NetMessage.of_tick(0, PackedByteArray([0, 0]))],
		"a client's kind (a frame)": ["not a host's", NetMessage.of_frame(1, frame.to_bytes())],
		"a ping": ["not a host's", NetMessage.of_ping(1)],
		"a check": ["not a host's", NetMessage.of_hashes(1, none)],
	}
	for what: String in cases:
		after_each()
		before_each()
		_link_up()
		_far.send(cases[what][1])
		_far.send(NetMessage.of_tick(0, PackedByteArray([0])))
		_step()
		check(not _far.is_open() and _client.problem.contains(cases[what][0]), "%s closes the link, for that (%s)" % [what, _client.problem])
		check_equal(_client.replay.tick_count(), 0, "%s: a tick behind it is not taken" % what)
		check(_client.feed.closed, "%s: no more ticks will come" % what)
		_step()
		check(not _frames.is_playing(), "%s: the run ends" % what)
	after_each()
	before_each()
	_far.send(NetMessage.of_header(PackedByteArray([1, 2, 3, 4])))
	_step()
	check(not _far.is_open() and not _client.started and _client.problem.contains("the header"), "a header that is none closes the link")
	after_each()
	before_each()
	_far.send(NetMessage.of_tick(0, PackedByteArray([0])))
	_step()
	check(not _far.is_open() and not _client.started, "a tick before the header closes the link")
	after_each()
	before_each()
	_far.send(NetMessage.of_header(with_ticks.to_bytes()))
	_step()
	check(not _far.is_open() and not _client.started, "a header with ticks in it closes the link")


func test_the_host_gone_the_run_ends_once_played_out() -> void:
	_link_up()
	_host_ticks(3)
	_far.close()
	check_equal(_step(), 1, "what arrived before the link closed is played")
	check(_client.feed.closed, "no more will come")
	_step()
	_step()
	check(_client.is_playing(), "to its last tick")
	_step()
	check(not _client.is_playing() and not _frames.is_playing(), "then the run ends")
	check_equal(_client.problem, "", "the host closed it, not this side")


func test_it_sends_a_check_of_every_window() -> void:
	_client.checks = NetChecks.new(4)
	var mine := NetChecks.new(4)
	_link_up()
	_host_ticks(9)
	var expected: Array = []
	for tick in 9:
		_client.feed.cushion = 100
		check_equal(_step(), 1, "tick %d" % tick)
		var check: Dictionary[String, int] = mine.add(tick, _areas)
		if not check.is_empty():
			expected.append([tick, check])
	var sent: Array = []
	while true:
		var message: NetMessage = _next(NetMessage.HASHES)
		if message == null:
			break
		sent.append([message.tick, message.hashes])
	check_equal(sent, expected, "a check after ticks 3 and 7, of the state hashed as the host hashes it")
	check_equal(_client.stats.checks, 2, "counted")


func test_a_parting_it_is_told_of_is_kept_once() -> void:
	_link_up()
	_host_ticks(3)
	_step()
	_far.send(NetMessage.of_parted(59, PackedStringArray(["Combat", "actor 4"])))
	_far.send(NetMessage.of_parted(119, PackedStringArray(["Spells"])))
	_step()
	check_equal([_client.parted_tick, _client.parted_areas], [59, PackedStringArray(["Combat", "actor 4"])], "the first parting: its tick and areas")
	check_equal(_client.replay.tick_count(), 3, "with the run it received so far, for whoever holds it to save")
	check(_far.is_open() and _client.is_playing(), "and it plays on")


func test_a_press_is_timed_until_it_comes_back() -> void:
	_link_up()
	_host_ticks(1)
	_step()
	_input.send_virtual(SEAT, &"staff_2", 1.0)
	_step()
	_input.send_virtual(SEAT, &"staff_2", 0.0)
	# The host's ticks go on without it for four steps, then one carries the press.
	for i in 4:
		_host_ticks(1)
		_step()
	check_equal(_client.stats.presses, 0, "not back yet")
	_host_ticks(1, 0b0010)
	_step()
	_step()
	check_equal(_client.stats.presses, 1, "the press came back in the host's tick")
	check_equal(_client.stats.press_steps, 5, "five steps after it was sent")
	_host_ticks(1, 0b0010)
	_step()
	_step()
	check_equal(_client.stats.presses, 1, "a press of the host's tick that this machine did not make is not timed")


func test_it_reads_a_set_number_of_messages_a_step() -> void:
	_link_up()
	_host_ticks(NetClient.MAX_READ + 50)
	_client.feed.cushion = 100000
	_step()
	check_equal(_client.replay.tick_count(), NetClient.MAX_READ, "no more than its limit in one step")
	_step()
	check_equal(_client.replay.tick_count(), NetClient.MAX_READ + 50, "the rest in the next")
