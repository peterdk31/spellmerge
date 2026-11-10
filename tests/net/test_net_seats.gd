extends "res://tests/support/suite.gd"
## The joining machine's seats (online lobby L2, docs/milestones/online-lobby.md;
## net/net_client.gd with an input layer) on a bus, input manager and frames service of its own,
## the test playing the host by writing its messages into the link. The machine's devices are
## asked for by a number of its own and seated where the host's lobby says; a seat is the
## machine's while its device sits on it; a player the host gives no seat may ask again; a player
## who leaves is taken off by the host; a seat somebody still sits on here is taken once it is
## free; the session over, devices seat themselves again; and a machine far behind a run runs
## more ticks a step until it has caught up.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const FramesScript := preload("res://core/sim/frames.gd")

const DT: float = 1.0 / 60.0
const KEYBOARD: int = InputManagerScript.KEYBOARD
const NOBODY: int = NetMessage.NOBODY
const PAD: int = 5

var _bus: EventsScript
var _input: InputManagerScript
var _frames: FramesScript
var _client: NetClient
## The host's end of the link.
var _far: NetLoopback
var _now: float = 0.0
var _message: NetMessage = NetMessage.new()
var _run: Replay
var _host_frames: Array[InputFrame] = []
## Every seat_joined (seat + 1) and seat_left (-seat - 1).
var _seats: Array = []


func before_each() -> void:
	_now = 0.0
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
	_bus.seat_joined.connect(func(seat: int) -> void: _seats.append(seat + 1))
	_bus.seat_left.connect(func(seat: int) -> void: _seats.append(-seat - 1))
	var ends: Array[NetLoopback] = NetLoopback.pair()
	_far = ends[1]
	_client = NetClient.new(_frames, ends[0], Callable(), NetHost.SEAT, 2, 4, _input)
	_client.clock = func() -> float: return _now
	_run = Replay.new()
	_run.build = Replay.build_of()
	_run.content = Replay.content_of(_frames.registry)
	_run.run_seed = 5
	_run.seats = 0b0001
	_host_frames.clear()
	for seat in 4:
		var frame := InputFrame.new()
		frame.seat = seat
		_host_frames.append(frame)


func after_each() -> void:
	_client.release_devices()
	_frames.stop_playing()


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


func _pad_joins(device: int = PAD) -> void:
	var press := InputEventJoypadButton.new()
	press.device = device
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	_input.handle_event(press)


## The host's lobby: `answered` asks, and the seats' holders.
func _lobby(answered: int, holders: Array) -> void:
	_far.send(NetMessage.of_lobby(answered, PackedByteArray(holders)))


## The host makes `count` ticks, seats `seats` in them, `commands` (by seat) in the first.
func _host_ticks(count: int, seats: int = 0b0001, commands: Dictionary = {}) -> void:
	for i in count:
		for frame in _host_frames:
			frame.clear()
		if i == 0:
			for seat: int in commands:
				_host_frames[seat].add_command(commands[seat], [])
		var kept: int = seats
		for seat: int in commands:
			kept |= 1 << seat
		_run.add_tick(_host_frames, kept if i == 0 else seats)
		var tick: int = _run.tick_count() - 1
		_far.send(NetMessage.of_tick(tick, _run.tick_bytes(tick)))


## The asks the client sent since the last look (each one's player), and how many frames by seat.
func _sent() -> Dictionary:
	var asks: Array[int] = []
	var frames: Dictionary[int, int] = {}
	var commands: Array = []
	while true:
		var bytes: PackedByteArray = _far.read()
		if bytes.is_empty():
			break
		check_equal(_message.decode(bytes), "", "what the client sends is a whole message")
		if _message.kind == NetMessage.SEAT_ASK:
			asks.append(_message.local)
		elif _message.kind == NetMessage.FRAME:
			var frame := InputFrame.new()
			frame.decode(_message.body)
			frames[frame.seat] = int(frames.get(frame.seat, 0)) + 1
			for command: Array in frame.commands:
				commands.append([frame.seat, command[0]])
	return {"asks": asks, "frames": frames, "commands": commands}


func _start_run() -> void:
	_far.send(NetMessage.of_header(_run.header_bytes()))
	_step()


func test_devices_that_sat_in_the_menu_are_asked_for_by_number_and_seated_where_the_host_says() -> void:
	_pad_joins()
	_pad_joins(PAD + 1)
	check_equal([_input.device_of(0), _input.device_of(1)], [PAD, PAD + 1], "in the menu they sit as they joined")
	_client.seat_devices()
	check_equal(_input.joined_count(), 0, "the host seats them: they leave their seats")
	check_equal(_sent()["asks"], [0, 1] as Array[int], "and each is asked for by a number of this machine's, never its device")
	check_equal(_client.feed.local_seats, 0, "no seat is this machine's yet")
	_lobby(2, [NOBODY, NOBODY, 1, 0])
	_step()
	check_equal([_input.device_of(3), _input.device_of(2)], [PAD, PAD + 1], "each is seated where the host said: the first pad on P4, the second on P3")
	check_equal(_client.feed.local_seats, 0b1100, "and those seats are this machine's")
	check_equal(_client.seats, 0b1100, "as the session says")
	_start_run()
	_host_ticks(3)
	_step()
	var sent: Dictionary = _sent()
	check_equal([int(sent["frames"].get(2, 0)) > 0, int(sent["frames"].get(3, 0)) > 0, sent["frames"].has(0)], [true, true, false], "it sends a frame for each of its seats, none for the host's")
	check(InputManagerScript.is_virtual(_input.device_of(0)), "the host's seat is a stand-in device here")


func test_with_nobody_seated_the_keyboard_is_asked_for() -> void:
	_client.seat_devices()
	check_equal(_sent()["asks"], [0] as Array[int], "one ask")
	_lobby(1, [NOBODY, 0, NOBODY, NOBODY])
	_step()
	check_equal(_input.device_of(1), KEYBOARD, "the keyboard plays the seat the host gave")
	_client.seat_devices()
	check_equal(_sent()["asks"], [] as Array[int], "asked for once")


func test_a_device_that_joins_later_is_asked_for_and_one_given_no_seat_may_ask_again() -> void:
	_client.seat_devices()
	_lobby(1, [NOBODY, 0, NOBODY, NOBODY])
	_step()
	_sent()
	_pad_joins()
	check_equal([_input.player_of(PAD), _sent()["asks"]], [InputManagerScript.NO_PLAYER, [1] as Array[int]], "a pad that presses join is asked for, not seated here")
	_pad_joins()
	check_equal(_sent()["asks"], [] as Array[int], "while its ask is out it asks no more")
	# An older lobby (it does not count this ask yet) changes nothing for it.
	_lobby(1, [NOBODY, 0, NOBODY, NOBODY])
	_step()
	_pad_joins()
	check_equal(_sent()["asks"], [] as Array[int], "a lobby from before its ask is not its answer")
	# The host has no seat free: the ask is answered with none.
	_lobby(2, [NOBODY, 0, NOBODY, NOBODY])
	_step()
	check_equal(_input.player_of(PAD), InputManagerScript.NO_PLAYER, "answered with no seat, it is not seated")
	_pad_joins()
	check_equal(_sent()["asks"], [1] as Array[int], "and may ask again")
	_lobby(3, [NOBODY, 0, 1, NOBODY])
	_step()
	check_equal([_input.device_of(2), _client.feed.local_seats], [PAD, 0b0110], "given a seat, it plays it")


func test_a_player_who_leaves_says_so_in_its_frame_and_the_host_frees_the_seat() -> void:
	_client.seat_devices()
	_pad_joins()
	_lobby(2, [NOBODY, 0, 1, NOBODY])
	_step()
	_start_run()
	_host_ticks(4, 0b0111)
	_step()
	_sent()
	_input.leave(2)
	_step()
	var sent: Dictionary = _sent()
	check(sent["commands"].has([2, InputFrame.LEAVE]), "the leave goes to the host in the seat's frame (%s)" % [sent["commands"]])
	check_equal(_client.feed.local_seats, 0b0110, "the seat is this machine's until the host says otherwise")
	_pad_joins()
	check_equal(_sent()["asks"], [] as Array[int], "its player's number is not free yet")
	_lobby(2, [NOBODY, 0, NOBODY, NOBODY])
	_step()
	check_equal(_client.feed.local_seats, 0b0010, "the host freed it: the seat is not this machine's")
	_pad_joins()
	check_equal(_sent()["asks"], [1] as Array[int], "and the pad may ask again")


func test_a_seat_somebody_still_sits_on_here_is_taken_once_it_is_free() -> void:
	# This machine is behind the host: on the host seat 1's player left a while ago, here the
	# run still has it seated.
	_client.seat_devices()
	_run.seats = 0b0011
	_start_run()
	_host_ticks(2, 0b0011)
	_step()
	check(InputManagerScript.is_virtual(_input.device_of(1)), "seat 1 is somebody else's here")
	_lobby(1, [NOBODY, 0, NOBODY, NOBODY])
	_step()
	check_equal([_input.player_of(KEYBOARD), _client.feed.local_seats], [InputManagerScript.NO_PLAYER, 0], "given that seat, this machine waits: it is not its own while another sits on it")
	_host_ticks(1, 0b0001, {1: InputFrame.LEAVE})
	_host_ticks(2, 0b0001)
	for i in 4:
		_step()
	check_equal([_input.device_of(1), _client.feed.local_seats], [KEYBOARD, 0b0010], "once the run here has them gone, its device takes the seat")
	_host_ticks(1, 0b0001, {1: InputFrame.JOIN})
	_host_ticks(2, 0b0011)
	_seats.clear()
	for i in 4:
		_step()
	check_equal(_seats, [2], "and its wizard comes when the host's tick says so")
	check_equal(_input.device_of(1), KEYBOARD, "its own device still on it")


func test_the_session_over_devices_seat_themselves_again() -> void:
	_input.join(KEYBOARD)
	_client.seat_devices()
	_client.release_devices(true)
	check_equal(_input.device_of(0), KEYBOARD, "no run came of it: the keyboard sits where it sat")
	_pad_joins()
	check_equal(_input.device_of(1), PAD, "and a pad seats itself, as ever")
	check_equal(_sent()["asks"], [0] as Array[int], "only the first was ever asked for")


func test_a_link_refused_leaves_the_seating_to_be_given_back_by_its_holder() -> void:
	_input.join(KEYBOARD)
	_client.seat_devices()
	_far.send(PackedByteArray([99, 0, 0, 0, 0]))
	_step()
	check(_client.problem != "", "refused (%s)" % _client.problem)
	check_equal(_input.joined_count(), 0, "the session does not give the seating back by itself: whoever holds it does, once")
	_client.release_devices(true)
	check_equal(_input.device_of(0), KEYBOARD, "given back by its holder: the device it took off its seat sits again")
	_pad_joins()
	check_equal(_input.device_of(1), PAD, "and devices seat themselves again")


func test_a_machine_far_behind_runs_more_ticks_a_step_until_it_has_caught_up() -> void:
	_client.seat_devices()
	_lobby(1, [NOBODY, 0, NOBODY, NOBODY])
	_start_run()
	var behind: int = 2000
	# However slow the machine the test runs on: a step's time is never short.
	_client.burst_usec = 1 << 40
	_host_ticks(behind)
	check(not _client.is_catching_up(), "not before it knows")
	var most: int = 0
	var steps: int = 0
	while _frames.play_tick() < behind - NetClient.FAR and steps < 600:
		most = maxi(most, _step())
		steps += 1
		if steps == 3:
			check(_client.is_catching_up(), "far behind: it catches up")
	check(most > LiveFeed.CATCH_UP, "it ran more ticks a step than the usual three (%d)" % most)
	check(steps < behind / LiveFeed.CATCH_UP / 2, "and was there far sooner than three a step would be (%d steps)" % steps)
	for i in 120:
		_step()
	check_equal(_frames.play_tick(), behind, "it played every tick")
	check(not _client.is_catching_up(), "and paces as ever once it is near")


func test_catching_up_runs_fewer_ticks_a_step_when_they_take_too_long() -> void:
	_client.seat_devices()
	_start_run()
	_host_ticks(3000)
	_client.burst_usec = 1 << 40
	var fast: int = 0
	for i in 5:
		fast = _step()
	check(fast > NetClient.BURST_START, "ticks that are done early: more the next step (%d)" % fast)
	# From here every step's ticks take far longer than a step has.
	_client.burst_usec = 0
	var slow: int = fast
	for i in 12:
		slow = _step()
	check(slow < fast and slow >= 1, "ticks that take too long: fewer, never none (%d)" % slow)

