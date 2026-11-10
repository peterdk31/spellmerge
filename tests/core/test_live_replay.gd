extends "res://tests/support/suite.gd"
## A live replay (netcode spike S1, docs/milestones/netcode-spike.md; core/sim/frames.gd,
## `play_live`): a replay that grows while it plays, as the online client plays the host's run. On
## its own bus and input manager, ticked by hand as the Tick does (`ticks_due`, then that many
## `tick`s): it waits for a tick not there yet instead of ending, catches up a few a step, plays
## the frames it is fed, hands the local seat's frames out with their tick (their commands and their
## presses, also one made while no tick ran), and ends once closed and played out.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const FramesScript := preload("res://core/sim/frames.gd")

const DT: float = 1.0 / 60.0
## The seat whose input is this machine's in these tests (the online client's).
const LOCAL: int = 1

var _bus: EventsScript
var _input: InputManagerScript
var _frames: FramesScript
## What the listeners heard: [command, args...].
var _heard: Array = []
## The host's run: a replay of seat 0's frames.
var _host: Replay
## The live replay played, and how many of the host's ticks have been fed to it.
var _live: Replay
var _fed: int = 0
## The ticks the pump lets through at its next call.
var _let_through: int = 0
## The pump's calls, and every frame handed out: [tick, seat, frame bytes].
var _pumps: int = 0
var _sent: Array = []


func before_each() -> void:
	_heard.clear()
	_sent.clear()
	_fed = 0
	_let_through = 0
	_pumps = 0
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
	_host = _hosts_run(30)
	_live = Replay.from_bytes(_host.header_bytes())


func after_each() -> void:
	_frames.stop_recording()
	_frames.stop_playing()


## A run of `ticks` ticks: seat 0 walks a turning way and presses a staff now and then; at tick 4 it
## changes a staff (a command), and at tick 9 seat 1 (the client's) does.
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
		replay.add_tick(frames, 0b0011)
	return replay


## Plays `_live` with seat LOCAL this machine's (its virtual device joined first, as the client's
## own device is), its pump feeding the host's ticks as `_let_through` says.
func _play(cushion: int = 2) -> bool:
	_input.add_virtual_device(LOCAL)
	return _frames.play_live(_live, 1 << LOCAL, _pump, _on_sent, cushion)


func _pump() -> void:
	_pumps += 1
	while _let_through > 0 and _fed < _host.tick_count():
		check_equal(_live.add_tick_bytes(_host.tick_bytes(_fed)), "", "tick %d is taken" % _fed)
		_fed += 1
		_let_through -= 1


func _on_sent(tick: int, frame: InputFrame) -> void:
	_sent.append([tick, frame.seat, frame.to_bytes()])


## One physics step as the Tick runs it: the ticks the frames service says. Returns how many ran.
func _step() -> int:
	var due: int = _frames.ticks_due()
	for i in due:
		_frames.tick(DT)
	return due


func test_it_waits_for_a_tick_not_there_yet_instead_of_ending() -> void:
	check(_play(), "it plays")
	check(_frames.is_live() and _frames.is_playing(), "live")
	for i in 5:
		check_equal(_step(), 0, "step %d: no tick while none has arrived" % i)
	check_equal(_pumps, 5, "the pump is called every step, before the ticks are counted")
	check(_frames.is_playing(), "still playing: a live replay out of ticks waits")
	check_equal(_frames.ticks, 0, "and no tick ran")
	_let_through = 1
	check_equal(_step(), 1, "a tick arrives: it runs")
	check_equal(_step(), 0, "then it waits again")
	check_equal(_frames.play_tick(), 1, "one tick played")


func test_ticks_held_back_are_caught_up_within_the_cushion() -> void:
	check(_play(2), "it plays")
	_let_through = 12
	var ran: Array[int] = []
	for i in 6:
		ran.append(_step())
	check_equal(ran, [3, 3, 3, 1, 1, 1] as Array[int], "up to three a step while it holds more than its cushion, then one")
	check_equal(_live.tick_count() - _frames.play_tick(), 0, "all played")
	for i in 4:
		_let_through = 1
		check_equal(_step(), 1, "one arriving a step: one a step")
	_let_through = 3
	check_equal(_step(), 1, "within the cushion it does not hurry")
	check_equal(_step(), 1, "nor with one ahead")
	check_equal(_step(), 1, "the last")
	check_equal(_step(), 0, "then waits")


func test_it_plays_the_frames_it_is_fed() -> void:
	check(_play(), "it plays")
	var expected: Array[InputFrame] = []
	for seat in 4:
		expected.append(InputFrame.new())
	_let_through = _host.tick_count()
	var played: int = 0
	while played < _host.tick_count():
		var before: int = _frames.play_tick()
		var ran: int = _step()
		check(ran > 0, "it runs while ticks are there")
		if ran == 0:
			break
		# Only the last tick of the step is left to look at.
		_host.read_tick(before + ran - 1, expected)
		for seat in 4:
			check_equal(_frames.frame_of(seat).to_bytes(), expected[seat].to_bytes(), "tick %d seat %d: the host's frame" % [before + ran - 1, seat])
		played += ran
	check_equal(_heard, [[&"staff_change_requested", 0, 1, 2, &"frost"], [&"staff_change_requested", 1, 0, 0, &"bolt"]], "the host's commands apply at their ticks, the local seat's among them as the host ordered it")


func test_the_local_seats_frames_are_handed_out_with_their_tick() -> void:
	# No cushion: the three ticks run in one step.
	check(_play(0), "it plays")
	_let_through = 3
	_input.send_virtual(LOCAL, &"move_left", 1.0)
	_input.send_virtual(LOCAL, &"staff_2", 1.0)
	_bus.staff_change_requested.emit(LOCAL, 3, 1, &"fire")
	_bus.staff_change_requested.emit(0, 0, 0, &"fire")
	_step()
	check_equal(_sent.size(), 3, "one frame a tick run, of the local seat only")
	if _sent.size() != 3:
		return
	var frame := InputFrame.new()
	check_equal(frame.decode(_sent[0][2]), "", "a whole frame")
	check_equal([_sent[0][0], _sent[0][1]], [0, LOCAL], "built in tick 0, for the local seat")
	check_equal(frame.move_vector(), Vector2.LEFT, "the device's walk")
	check(frame.is_pressed(1) and frame.is_held(1), "its press")
	check_equal(frame.commands, [[&"staff_change_requested", 3, 1, &"fire"]], "the local seat's command goes out in its frame")
	check(not _heard.has([&"staff_change_requested", LOCAL, 3, 1, &"fire"]), "and is not applied here: it comes back in the host's frames")
	check(not _heard.has([&"staff_change_requested", 0, 0, 0, &"fire"]), "another seat's command is dropped")
	frame.decode(_sent[1][2])
	check_equal(_sent[1][0], 1, "the next built in tick 1")
	check(not frame.is_pressed(1) and frame.is_held(1) and frame.commands.is_empty(), "pressed once, held on, its command sent once")
	check_equal(_sent[2][0], 2, "and tick 2")
	check(_frames.frame_of(LOCAL).move == Vector2i.ZERO, "the game's frame for the seat is the host's, not the device's")


func test_a_press_made_while_no_tick_runs_reaches_the_next_frame() -> void:
	check(_play(), "it plays")
	check_equal(_step(), 0, "waiting")
	_input.send_virtual(LOCAL, &"staff_1", 1.0)
	_input.send_virtual(LOCAL, &"staff_1", 0.0)
	_bus.staff_change_requested.emit(LOCAL, 2, 0, &"bolt")
	check_equal(_step(), 0, "still waiting")
	check(_sent.is_empty(), "no frame is built while no tick runs")
	_let_through = 1
	check_equal(_step(), 1, "a tick")
	check_equal(_sent.size(), 1, "its frame")
	if _sent.is_empty():
		return
	var frame := InputFrame.new()
	frame.decode(_sent[0][2])
	check(frame.is_pressed(0) and not frame.is_held(0), "the tap made while it waited")
	check_equal(frame.commands, [[&"staff_change_requested", 2, 0, &"bolt"]], "and the command")


func test_it_ends_once_closed_and_played_out() -> void:
	check(_play(), "it plays")
	_let_through = 2
	_step()
	_step()
	check(_frames.is_playing(), "out of ticks and open: it waits")
	_let_through = 1
	_frames.close_live()
	check(_frames.is_playing(), "closed with a tick left: it plays on")
	check_equal(_step(), 1, "the tick left runs")
	check(not _frames.is_playing() and not _frames.is_live(), "then it ends")
	check_equal(_pumps, 3, "the pump called once a step")
	check_equal(_step(), 1, "and a step is the game's own again: one tick")
	check_equal(_pumps, 3, "with no pump")


## Whoever plays it may stop it from inside its callables (a link that closes while it reads or
## sends): the tick in progress then runs on no replay, and nothing breaks.
func test_it_may_be_stopped_from_its_own_callables() -> void:
	_input.add_virtual_device(LOCAL)
	var stop_in_sent := func(_tick: int, _frame: InputFrame) -> void: _frames.stop_playing()
	check(_frames.play_live(_live, 1 << LOCAL, _pump, stop_in_sent, 0), "it plays")
	_let_through = 3
	check_equal(_step(), 3, "three ticks due")
	check(not _frames.is_playing(), "stopped from `sent`")
	check(_frames.frame_of(0).move == Vector2i.ZERO, "the tick ran on no replay")
	_live = Replay.from_bytes(_host.header_bytes())
	_fed = 0
	var stop_in_pump := func() -> void: _frames.stop_playing()
	check(_frames.play_live(_live, 1 << LOCAL, stop_in_pump, _on_sent), "it plays again")
	check_equal(_frames.ticks_due(), 1, "stopped from its pump: a step of the game's own")
	check(not _frames.is_playing(), "stopped")


func test_a_replay_of_another_build_or_content_is_refused() -> void:
	var other_build: Replay = Replay.from_bytes(_host.header_bytes())
	other_build.build = "other 0123"
	check(not _frames.play_live(other_build, 1 << LOCAL, _pump, _on_sent), "another build: refused (online it would part)")
	var other_content: Replay = Replay.from_bytes(_host.header_bytes())
	other_content.content += 1
	check(not _frames.play_live(other_content, 1 << LOCAL, _pump, _on_sent), "other content: refused")
	check(not _frames.is_playing(), "nothing plays")
	check(_frames.play(other_build), "a replay file of another build still plays (with a warning)")


func test_commands_are_heard_offline_and_live_but_not_while_a_file_plays() -> void:
	check(_frames.hears_commands(), "offline")
	check(_play(), "live")
	check(_frames.hears_commands(), "a live replay hears its local seats")
	_frames.stop_playing()
	check(_frames.play(_host), "a file plays")
	check(not _frames.hears_commands(), "a file's frames say all")
	check_equal(_frames.ticks_due(), 1, "and it runs a tick every step")
