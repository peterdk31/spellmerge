extends "res://tests/support/suite.gd"
## A live replay (netcode spike S1, docs/milestones/netcode-spike.md; core/sim/frames.gd,
## `play_live`, fed by a `LiveFeed`): a replay that grows while it plays, as the online client plays
## the host's run. On its own bus and input manager, stepped by hand as the Tick does
## (`begin_step`, then that many `tick`s): it waits for a tick not there yet instead of ending,
## catches up as the feed paces it, plays the frames it is fed, sends the local seat's frame every
## step (its commands and presses, also while it waits), seats only as the replay says, and ends
## once closed and played out.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const FramesScript := preload("res://core/sim/frames.gd")

const DT: float = 1.0 / 60.0
## The seat whose input is this machine's in these tests (the online client's).
const LOCAL: int = 1

var _bus: EventsScript
var _input: InputManagerScript
var _frames: FramesScript
## What the listeners heard: [command, args...], and the seats' joins and leaves: [+seat] / [-seat].
var _heard: Array = []
var _seats: Array = []
## The host's run: a replay of seats 0 and 1.
var _host: Replay
## The live replay's feed.
var _feed: Feed


## The feed of these tests: lets `let_through` of the host's ticks in at its next pump, and keeps
## every frame sent as [tick, seat, frame bytes].
class Feed:
	extends LiveFeed
	var host: Replay
	var fed: int = 0
	var let_through: int = 0
	var pumps: int = 0
	var sent: Array = []
	var problems: PackedStringArray = PackedStringArray()
	## Called in `pump` or `send` instead, when valid (a test's own).
	var on_pump: Callable = Callable()
	var on_send: Callable = Callable()
	## When above 0: the ticks it asks for, whatever is there.
	var asks: int = 0

	func pump() -> void:
		pumps += 1
		if on_pump.is_valid():
			on_pump.call()
			return
		while let_through > 0 and fed < host.tick_count():
			var problem: String = replay.add_tick_bytes(host.tick_bytes(fed))
			if problem != "":
				problems.append("tick %d: %s" % [fed, problem])
			fed += 1
			let_through -= 1

	func send(tick: int, frame: InputFrame) -> void:
		sent.append([tick, frame.seat, frame.to_bytes()])
		if on_send.is_valid():
			on_send.call()

	func ticks_to_run(ahead: int) -> int:
		return asks if asks > 0 else super(ahead)


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
	_bus.listen(&"staff_change_requested", func(seat: int, staff: int, slot: int, card: StringName) -> void: _heard.append([&"staff_change_requested", seat, staff, slot, card]))
	_bus.seat_joined.connect(func(seat: int) -> void: _seats.append(seat + 1))
	_bus.seat_left.connect(func(seat: int) -> void: _seats.append(-seat - 1))
	_host = _hosts_run(30)
	_new_feed()


func after_each() -> void:
	_frames.stop_recording()
	_frames.stop_playing()


func _new_feed(cushion: int = 2) -> void:
	_feed = Feed.new(1 << LOCAL, cushion)
	_feed.host = _host
	_feed.replay = Replay.from_bytes(_host.header_bytes())


## A run of `ticks` ticks of seats 0 and 1: seat 0 walks a turning way and presses a staff now and
## then; at tick 4 it changes a staff (a command), at tick 9 seat 1 (the client's) does, at tick
## 12 seat 2 joins and at tick 14 seat 1 leaves.
func _hosts_run(ticks: int) -> Replay:
	var replay := Replay.new()
	replay.build = Replay.build_of()
	replay.content = Replay.content_of(_frames.registry)
	replay.run_seed = 77
	replay.seats = 0b0011
	var frames: Array[InputFrame] = []
	for seat in 4:
		var frame := InputFrame.new()
		frame.seat = seat
		frames.append(frame)
	var seats: int = 0b0011
	for tick in ticks:
		for frame in frames:
			frame.clear()
		frames[0].set_move(Vector2.RIGHT.rotated(tick * 0.3))
		if tick % 5 == 1:
			frames[0].press(tick % 4)
		if tick == 4:
			frames[0].add_command(&"staff_change_requested", [1, 2, &"frost"])
		if tick == 9:
			frames[1].add_command(&"staff_change_requested", [0, 0, &"bolt"])
		if tick == 12:
			frames[2].add_command(InputFrame.JOIN, [])
			seats |= 0b0100
		var mask: int = seats
		if tick == 14:
			frames[1].add_command(InputFrame.LEAVE, [])
			seats &= ~0b0010
		replay.add_tick(frames, mask)
	return replay


## Plays the feed's replay with seat LOCAL this machine's (its virtual device joined first, as the client's
## own device is).
func _play() -> bool:
	_input.add_virtual_device(LOCAL)
	_seats.clear()
	return _frames.play_live(_feed)


## One physics step as the Tick runs it: the ticks the frames service says. Returns how many ran.
func _step() -> int:
	var due: int = _frames.begin_step(DT)
	for i in due:
		_frames.tick(DT)
	return due


func _sent_frame(at: int) -> InputFrame:
	var frame := InputFrame.new()
	check_equal(frame.decode(_feed.sent[at][2]), "", "sent frame %d is whole" % at)
	return frame


func test_it_waits_for_a_tick_not_there_yet_instead_of_ending() -> void:
	check(_play(), "it plays")
	check(_frames.is_live() and _frames.is_playing(), "live")
	for i in 5:
		check_equal(_step(), 0, "step %d: no tick while none has arrived" % i)
	check_equal(_feed.pumps, 5, "the feed is pumped every step")
	check(_frames.is_playing(), "still playing: a live replay out of ticks waits")
	check_equal(_frames.ticks, 0, "and no tick ran")
	_feed.let_through = 1
	check_equal(_step(), 1, "a tick arrives: it runs")
	check_equal(_step(), 0, "then it waits again")
	check_equal(_frames.play_tick(), 1, "one tick played")


func test_ticks_held_back_are_caught_up_as_the_feed_paces() -> void:
	check(_play(), "it plays")
	_feed.let_through = 12
	var ran: Array[int] = []
	for i in 6:
		ran.append(_step())
	check_equal(ran, [3, 3, 3, 1, 1, 1] as Array[int], "the default pace: up to three a step while more than its cushion are ahead, then one")
	check_equal(_feed.replay.tick_count() - _frames.play_tick(), 0, "all played")
	for i in 4:
		_feed.let_through = 1
		check_equal(_step(), 1, "one arriving a step: one a step")
	_feed.let_through = 3
	check_equal(_step(), 1, "within the cushion it does not hurry")
	_feed.asks = 99
	check_equal(_step(), 2, "a feed asking for more than is there runs what is there")
	check_equal(_step(), 0, "then waits")


func test_it_plays_the_frames_it_is_fed() -> void:
	check(_play(), "it plays")
	var expected: Array[InputFrame] = []
	for seat in 4:
		expected.append(InputFrame.new())
	_feed.let_through = _host.tick_count()
	_feed.asks = 1
	for tick in _host.tick_count():
		check_equal(_step(), 1, "tick %d runs" % tick)
		_host.read_tick(tick, expected)
		for seat in 4:
			check_equal(_frames.frame_of(seat).to_bytes(), expected[seat].to_bytes(), "tick %d seat %d: the host's frame" % [tick, seat])
	check_equal(_heard, [[&"staff_change_requested", 0, 1, 2, &"frost"], [&"staff_change_requested", 1, 0, 0, &"bolt"]], "the host's commands apply at their ticks, the local seat's among them as the host ordered it")
	check(_feed.problems.is_empty(), "every tick taken: %s" % ", ".join(_feed.problems))


## The view's question (whose wizards this machine's camera holds): a live replay's local seats.
func test_the_seats_here_are_the_live_replays_local_seats() -> void:
	check(_play(), "it plays")
	check_equal(_frames.seats_here(), _feed.local_seats, "the feed's local seats, whatever devices sit here")
	check(_feed.local_seats != 0, "and there is one")


func test_the_local_seats_frame_is_sent_every_step() -> void:
	check(_play(), "it plays")
	_input.send_virtual(LOCAL, &"move_left", 1.0)
	_input.send_virtual(LOCAL, &"staff_2", 1.0)
	_bus.staff_change_requested.emit(LOCAL, 3, 1, &"fire")
	_bus.staff_change_requested.emit(0, 0, 0, &"fire")
	check_equal(_step(), 0, "no tick there")
	check_equal(_feed.sent.size(), 1, "a frame all the same: one a step, while it waits too")
	if _feed.sent.size() != 1:
		return
	check_equal([_feed.sent[0][0], _feed.sent[0][1]], [0, LOCAL], "the local seat's, with the replay's next tick")
	var frame: InputFrame = _sent_frame(0)
	check_equal(frame.move_vector(), Vector2.LEFT, "the device's walk")
	check(frame.is_pressed(1) and frame.is_held(1), "its press")
	check_equal(frame.commands, [[&"staff_change_requested", 3, 1, &"fire"]], "the local seat's command goes out in its frame")
	check(_heard.is_empty(), "and nothing applies here: a command comes back in the host's frames; another seat's is dropped")
	_feed.let_through = 3
	_feed.asks = 3
	check_equal(_step(), 3, "three ticks in one step")
	check_equal(_feed.sent.size(), 2, "still one frame for the step")
	if _feed.sent.size() != 2:
		return
	frame = _sent_frame(1)
	check_equal(_feed.sent[1][0], 0, "sent before the step's ticks: the next is tick 0")
	check(not frame.is_pressed(1) and frame.is_held(1) and frame.commands.is_empty(), "pressed once, held on, its command sent once")
	_step()
	check_equal(_feed.sent[2][0], 3, "the next step's frame: tick 3 next")
	check(_frames.frame_of(LOCAL).move == Vector2i.ZERO, "the game's frame for the seat is the host's, not the device's")


func test_a_press_made_while_no_tick_runs_goes_out_at_the_next_step() -> void:
	check(_play(), "it plays")
	check_equal(_step(), 0, "waiting")
	_input.send_virtual(LOCAL, &"staff_1", 1.0)
	_input.send_virtual(LOCAL, &"staff_1", 0.0)
	_bus.staff_change_requested.emit(LOCAL, 2, 0, &"bolt")
	check_equal(_step(), 0, "still waiting")
	check_equal(_feed.sent.size(), 2, "a frame each step")
	if _feed.sent.size() != 2:
		return
	var frame: InputFrame = _sent_frame(1)
	check(frame.is_pressed(0) and not frame.is_held(0), "the tap made while it waited, in the next step's frame")
	check_equal(frame.commands, [[&"staff_change_requested", 2, 0, &"bolt"]], "and the command")
	check(not _sent_frame(0).is_pressed(0), "not in the frame before")


## The seats are the replay's while it plays: a pad joining here seats nobody, the replay's join and
## leave seat at their ticks, and the replay's leave of the local seat never sends this machine's
## own device away.
func test_the_seats_are_the_replays_not_this_machines_devices() -> void:
	check(_play(), "it plays")
	check_equal(_seats, [1], "seat 0 is seated by the header (seat 1 was joined here already)")
	_seats.clear()
	check_equal(_frames.joined_seats(), [0, 1] as Array[int], "the header's seats")
	_input.add_virtual_device(3)
	check(_seats.is_empty(), "a device joining a seat the replay does not hold seats nobody")
	check_equal(_frames.joined_seats(), [0, 1] as Array[int], "the seats stay the replay's")
	_input.leave(LOCAL)
	check(_seats.is_empty(), "the local device leaving leaves no seat here")
	_feed.let_through = 1
	_step()
	check(_frame_has(_sent_frame(0), InputFrame.LEAVE), "its leave goes to the host in its frame")
	_input.add_virtual_device(LOCAL)
	_feed.let_through = _host.tick_count()
	_feed.asks = 1
	while _frames.play_tick() < 13:
		_step()
	check_equal(_seats, [3], "the replay's join of seat 2 seats it at its tick")
	check_equal(_frames.joined_seats(), [0, 1, 2] as Array[int], "and the seats follow")
	check(_input.is_joined(2), "with a virtual device, for the HUD")
	while _frames.play_tick() < 15:
		_step()
	check_equal(_seats, [3, -2], "the replay's leave of the local seat at its tick")
	check_equal(_frames.joined_seats(), [0, 2] as Array[int], "it plays no more")
	check(_input.is_joined(LOCAL), "the replay's leave of the local seat leaves this machine's device be")
	check(_input.is_joined(3), "and the device on seat 3, which the replay never seated, stays")
	_seats.clear()
	_frames.stop_playing()
	check_equal(_frames.joined_seats(), [1, 3] as Array[int], "once the replay ends, the seats are this machine's devices again")
	check_equal(_seats, [-1, -3, 2, 4], "and say so: the replay's seats leave, this machine's join")
	check(not _input.is_joined(0) and not _input.is_joined(2), "the virtual devices the replay was given are given back")


## A replay file too: a device joining while it plays seats nobody until it ends.
func test_a_device_joining_while_a_file_plays_seats_nobody_until_it_ends() -> void:
	check(_frames.play(_host), "a file plays")
	_seats.clear()
	_input.add_virtual_device(3)
	check(_seats.is_empty(), "no seat")
	_frames.tick(DT)
	check(not _frames.joined_seats().has(3), "the replay's seats")
	_frames.stop_playing()
	check_equal(_seats, [-1, -2, 4], "once the replay ends its seats leave and the device's is seated")
	check(not _input.is_joined(0) and not _input.is_joined(1) and _input.is_joined(3), "the replay's devices are given back, the other stays")


func test_it_ends_once_closed_and_played_out() -> void:
	check(_play(), "it plays")
	_feed.let_through = 2
	_step()
	_step()
	check(_frames.is_playing(), "out of ticks and open: it waits")
	_feed.let_through = 1
	_feed.closed = true
	check_equal(_step(), 1, "closed with a tick left: it runs")
	check(_frames.is_playing(), "and the replay plays through that tick (its seats are the tick's)")
	check_equal(_step(), 1, "at the next step it ends, and the step is the game's own: one tick")
	check(not _frames.is_playing() and not _frames.is_live(), "ended")
	check_equal(_feed.pumps, 4, "the feed pumped once a step while it played")
	_step()
	check_equal(_feed.pumps, 4, "and no more")


## Whoever plays it may stop it from inside its feed (a link that closes while it reads or sends):
## the step then is the game's own, and nothing breaks.
func test_it_may_be_stopped_from_its_own_feed() -> void:
	_feed.on_send = func() -> void: _frames.stop_playing()
	check(_play(), "it plays")
	_feed.let_through = 3
	check_equal(_step(), 1, "stopped from `send`: a step of the game's own")
	check(not _frames.is_playing(), "stopped")
	_new_feed()
	_feed.on_pump = func() -> void: _frames.stop_playing()
	check(_frames.play_live(_feed), "it plays again")
	check_equal(_frames.begin_step(DT), 1, "stopped from its pump: a step of the game's own")
	check(not _frames.is_playing(), "stopped")


func test_a_replay_of_another_build_or_content_is_refused() -> void:
	var good: Replay = _feed.replay
	var other_build: Replay = Replay.from_bytes(_host.header_bytes())
	other_build.build = "other 0123"
	_feed.replay = other_build
	check(not _frames.play_live(_feed), "another build: refused (online it would part)")
	var other_content: Replay = Replay.from_bytes(_host.header_bytes())
	other_content.content += 1
	_feed.replay = other_content
	check(not _frames.play_live(_feed), "other content: refused")
	_feed.replay = null
	check(not _frames.play_live(_feed) and not _frames.play_live(null), "no replay or no feed: refused")
	check(not _frames.is_playing(), "nothing plays")
	check(_frames.play(other_build), "a replay file of another build still plays (with a warning)")
	_frames.stop_playing()
	_feed.replay = good
	check(_frames.play_live(_feed), "the good one plays")


func test_commands_are_heard_offline_and_from_local_seats_live() -> void:
	check(_frames.hears_commands(0) and _frames.hears_commands(LOCAL), "offline, every seat")
	check(_play(), "live")
	check(_frames.hears_commands(LOCAL), "a live replay hears its local seat")
	check(not _frames.hears_commands(0), "not the others: their frames are the host's")
	_frames.stop_playing()
	check(_frames.play(_host), "a file plays")
	check(not _frames.hears_commands(LOCAL), "a file's frames say all")
	check_equal(_frames.begin_step(DT), 1, "and it runs a tick every step")


func _frame_has(frame: InputFrame, command: StringName) -> bool:
	for entry: Array in frame.commands:
		if entry[0] == command:
			return true
	return false


# --- A run begun anew by the game (`restart`; online lobby) ----------------------

## Every `hub_requested` heard on the bus (the seat it was for).
func _hear_starts() -> Array[int]:
	var heard: Array[int] = []
	_bus.hub_requested.connect(func(seat: int) -> void: heard.append(seat))
	return heard


func test_a_run_the_game_asks_for_starts_as_the_next_step_does_never_inside_a_tick() -> void:
	var heard: Array[int] = _hear_starts()
	_frames.tick(DT)
	_frames.restart(&"hub_requested", 2)
	check_equal(heard, [] as Array[int], "asked for inside a tick: nothing starts there")
	_frames.begin_step(DT)
	check_equal(heard, [2] as Array[int], "it starts as the next step does, for the seat that asked")
	_frames.begin_step(DT)
	check_equal(heard, [2] as Array[int], "once")
	_frames.restart(&"hub_requested", 0)
	_frames.tick(DT)
	check_equal(heard, [2, 0] as Array[int], "whoever ticks by hand, with no step's start: at the tick's start")


func test_a_run_recorded_begins_a_new_recording_there() -> void:
	var heard: Array[int] = _hear_starts()
	var anew: Array[Replay] = []
	_frames.recorded_anew.connect(func(replay: Replay) -> void: anew.append(replay))
	_input.add_virtual_device(0)
	var first: Replay = _frames.record(&"sandbox_requested", 0, 5)
	for i in 7:
		_step()
	_frames.restart(&"hub_requested", 0)
	check(_frames.recorded() == first and anew.is_empty(), "asked for: the recording goes on until the step's end")
	_step()
	check_equal([anew.size(), heard], [1, [0] as Array[int]], "a new recording began as the next step did, and the start was sent")
	var second: Replay = anew[0]
	check(second != first and _frames.recorded() == second, "the frames service records into it")
	check_equal([first.tick_count(), second.tick_count()], [7, 1], "the one before ended with the tick it was asked in; the new one holds the step's own tick")
	check_equal([second.start, second.starter, second.seats], [&"hub_requested", 0, 0b0001], "its header: the start asked for, the seats joined now")
	check(second.run_seed != 0 and second.build == first.build, "a seed of its own, the same build")
	_frames.stop_recording()


func test_a_replay_from_a_file_ends_there_and_the_game_goes_on() -> void:
	var heard: Array[int] = _hear_starts()
	check(_frames.play(_host), "a replay plays")
	for i in 5:
		_step()
	_frames.restart(&"hub_requested", 1)
	_step()
	check(not _frames.is_playing(), "the replay ends where the game began a run anew: a recording is one stretch")
	check_equal(heard, [1] as Array[int], "and the start is sent, so the game goes on by itself")


func test_a_live_replay_waits_for_its_feed_to_bring_the_next_recording() -> void:
	var heard: Array[int] = _hear_starts()
	check(_play(), "the live replay plays")
	_feed.let_through = 6
	_feed.asks = 6
	_step()
	check_equal(_frames.play_tick(), 6, "it played what the host sent")
	_frames.restart(&"hub_requested", 0)
	check_equal(_step(), 0, "the game asked for a run anew: no tick runs, the picture holds")
	check(_frames.is_live() and heard.is_empty(), "the replay still plays, and nothing started: the next recording is the feed's to bring")
	# The feed brings the next recording in its pump (the host's new header arrived).
	var next: Replay = _hosts_run(4)
	next.start = &"hub_requested"
	var from: Feed = _feed
	from.on_pump = func() -> void:
		if from.replay.start != &"hub_requested":
			from.host = next
			from.fed = 0
			from.replay = Replay.from_bytes(next.header_bytes())
			_frames.play_live(from)
		while from.fed < next.tick_count():
			from.replay.add_tick_bytes(next.tick_bytes(from.fed))
			from.fed += 1
	from.asks = 0
	# This machine's player leaves in the very step the next recording begins: still its to send.
	from.sent.clear()
	_input.leave(LOCAL)
	var ran: int = _step()
	check(not from.sent.is_empty() and _frame_has(_sent_frame(0), InputFrame.LEAVE), "a leave pressed in between goes out in the seat's next frame")
	check_equal(heard, [0] as Array[int], "the next recording's start is sent as it begins")
	check(ran >= 1 and _frames.is_live(), "and it is played in the same step, with no tick asked of a replay that has none (%d)" % ran)
	check_equal(_frames.play_tick(), ran, "from its first tick")
	# The feed's own callback holds the feed: let go, or neither is ever freed.
	from.on_pump = Callable()


func test_a_live_replay_whose_feed_goes_before_the_next_recording_leaves_the_game_running() -> void:
	var heard: Array[int] = _hear_starts()
	check(_play(), "the live replay plays")
	_feed.let_through = 6
	_feed.asks = 6
	_step()
	_frames.restart(&"hub_requested", 0)
	_step()
	check(_frames.is_live() and heard.is_empty(), "it waits for the next recording")
	# The host is gone before its next header came.
	_feed.closed = true
	_step()
	_step()
	check(not _frames.is_playing(), "the replay ends")
	check_equal(heard, [0] as Array[int], "and the run the game asked for starts here all the same: nobody is left in an empty game")
	_step()
	check_equal(heard, [0] as Array[int], "once")

