extends Node
## The input frames (online-ready N2, docs/milestones/online-ready.md; the autoload "Frames"): the
## one input path. At the start of every tick it hands each seat 0-3 its `InputFrame`, and the
## simulation takes input from nothing else: a `PlayerController` builds its actor's intent from
## `frame_of(seat)`. Devices, bots and replays all produce frames, and later the network will;
## the game never knows which.
##
## - **The tick's start:** the Tick autoload (core/sim/tick.gd) calls `tick` first in every tick,
##   also while the tree is paused (the horde's level-up break takes its picks then).
## - **Where a frame comes from**, per seat: the replay being played (`play`); else the seat's
##   source (`set_source`: a bot, a `FrameSource`); else its device through the local input layer
##   (`LocalInput`: the walk, the aim with the mouse turned into a direction from the hand of the
##   actor the seat drives, the buttons, captured); else nothing (a cleared frame).
## - **Commands:** the HUD's requests (core/events, `command_sink`) and the seat's device joining
##   or leaving go into the seat's next frame, and the frame's commands apply when its tick starts,
##   seat by seat, in the order they were sent (`EventsScript.apply_command`). Joins and leaves
##   happen as the device joins and leaves (Flow and Coop read the joined seats at a run's start);
##   the frame tells a replay when, and a replay played joins and leaves its seats then.
## - **Replays:** `record(start, starter)` starts a run and records every tick's frames (the seats
##   joined, or with a command) into a `Replay`, `stop_recording` hands it over; `play(replay)`
##   joins its seats, starts its run the same way and feeds its frames, one a tick, until they run
##   out (live input and commands are dropped meanwhile; each tick says whether the game stood
##   paused, `_read_replay`). Both deal the seeds nobody chose from the
##   replay's seed (`SimSeed.begin`). A source set while a replay plays is still asked each tick
##   and its frame dropped: a bot reads the game through queries that fill the services' caches
##   (the projectile manager's threat grid and target table), which count as state and change the
##   next step, so a bot's run replays exactly only with the bot watching again (docs/DECISIONS.md,
##   2026-11-05). A person's input reads nothing of the game but where the hand is.
##
## Nothing here allocates per tick, but a command (an array) and a recorded tick (its bytes).

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const SEATS: int = 4

## The services. Only tests set these, before adding the node; otherwise the autoloads are used.
var events: EventsScript = null
var input: InputManagerScript = null
var actors: ActorsScript = null
var registry: RegistryScript = null
## Whether the Tick starts its tick (the game). A test that ticks it by hand (`tick`) turns it off.
var auto_tick: bool = true
## Ticks started since the game began.
var ticks: int = 0

## The frames of the tick in progress, by seat (four, reused).
var _frames: Array[InputFrame] = []
## Per seat: the local input layer over its device.
var _local: Array[LocalInput] = []
## Per seat: what fills its frame instead of its device, or null.
var _sources: Array[FrameSource] = [null, null, null, null]
## Per seat: the commands sent since the last tick's start, each `[name, args...]`.
var _pending: Array[Array] = [[], [], [], []]
var _recording: Replay = null
var _playing: Replay = null
var _play_at: int = 0
## Where the seat's actor holds its staff and where the mouse is, for the local layer.
var _hand: Vector2 = Vector2.INF
var _mouse: Vector2 = Vector2.INF
## The frame a source watching a replay fills, dropped.
var _watched: InputFrame = InputFrame.new()


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for seat in SEATS:
		var frame := InputFrame.new()
		frame.seat = seat
		_frames.append(frame)
		_local.append(LocalInput.new())


func _ready() -> void:
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if input == null:
		input = get_node_or_null("/root/PlayerInput") as InputManagerScript
	if actors == null:
		actors = get_node_or_null("/root/Actors") as ActorsScript
	if registry == null:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if events == null:
		push_warning("Frames: the Events autoload is missing, so commands apply as they are sent.")
		return
	events.command_sink = _on_command
	events.device_joined.connect(_on_device_joined)
	events.device_left.connect(_on_device_left)


func _exit_tree() -> void:
	if events != null and is_instance_valid(events) and events.command_sink == Callable(self, &"_on_command"):
		events.command_sink = Callable()


## Seat `seat`'s frame for the tick in progress (null for a seat outside 0-3). Read only.
func frame_of(seat: int) -> InputFrame:
	return _frames[seat] if seat >= 0 and seat < SEATS else null


## Fill seat `seat`'s frames from `source` instead of its device (null: its device again).
func set_source(seat: int, source: FrameSource) -> void:
	if seat >= 0 and seat < SEATS:
		_sources[seat] = source


func source_of(seat: int) -> FrameSource:
	return _sources[seat] if seat >= 0 and seat < SEATS else null


## A tick starts: every seat's frame is built (or read from the replay played), recorded, and its
## commands applied. `delta` is the tick's length in seconds.
func tick(delta: float) -> void:
	ticks += 1
	if _playing != null:
		_read_replay(delta)
	else:
		_build(delta)
		if _recording != null:
			_recording.add_tick(_frames, _recorded_seats(), _paused())
		_apply()
	if _playing != null and _play_at >= _playing.tick_count():
		stop_playing()


## Start a run by `start` (one of `Replay.STARTS`) for seat `starter` and record it from its first
## tick. Returns the replay it records into (it grows each tick until `stop_recording`). The run's
## seed is `run_seed`, or a random one when it is 0 (the platform runs, N2b, pick theirs, so every
## platform plays the same horde).
func record(start: StringName, starter: int, run_seed: int = 0) -> Replay:
	stop_playing()
	var replay := Replay.new()
	replay.build = Replay.build_of()
	replay.content = Replay.content_of(registry)
	replay.run_seed = run_seed if run_seed != 0 else SimSeed.pick()
	replay.start = start
	replay.starter = starter
	replay.seats = _joined_seats()
	_recording = replay
	SimSeed.begin(replay.run_seed)
	_send_start(start, starter)
	return replay


## Stop recording; returns the replay (null when none was recorded).
func stop_recording() -> Replay:
	var replay: Replay = _recording
	if replay != null:
		_recording = null
		SimSeed.end()
	return replay


func is_recording() -> bool:
	return _recording != null


## Play `replay` from its first tick: its seats join (virtual devices, where free), its run starts
## the way it started, and every tick takes its frames until they run out. False, and nothing
## happens, for a replay of other content.
func play(replay: Replay) -> bool:
	if replay == null:
		return false
	var here: int = Replay.content_of(registry)
	if replay.content != here:
		push_warning("Frames: the replay is of other content (%d, here %d), so it is not played." % [replay.content, here])
		return false
	if replay.build != Replay.build_of():
		push_warning("Frames: the replay was recorded by %s, this is %s; it may play differently." % [replay.build, Replay.build_of()])
	stop_recording()
	_playing = replay
	_play_at = 0
	for seat in SEATS:
		_pending[seat].clear()
		if replay.seats & (1 << seat) != 0 and input != null and not input.is_joined(seat):
			input.add_virtual_device(seat)
	SimSeed.begin(replay.run_seed)
	_send_start(replay.start, replay.starter)
	return true


## Stop playing (by itself once the frames run out): the seats take their own input again.
func stop_playing() -> void:
	if _playing == null:
		return
	_playing = null
	_play_at = 0
	SimSeed.end()


func is_playing() -> bool:
	return _playing != null


## The tick of the replay played that comes next (0 before its first).
func play_tick() -> int:
	return _play_at


func _send_start(start: StringName, starter: int) -> void:
	if events == null:
		return
	match start:
		&"play_requested":
			events.play_requested.emit(starter)
		&"sandbox_requested":
			events.sandbox_requested.emit(starter)
		&"horde_requested":
			events.horde_requested.emit(starter)
		_:
			push_warning("Frames: %s does not start a run." % start)


func _build(delta: float) -> void:
	for seat in SEATS:
		var frame: InputFrame = _frames[seat]
		frame.clear()
		var source: FrameSource = _sources[seat]
		if source != null:
			source.fill_frame(frame, delta)
			if input != null and input.is_captured(seat):
				frame.move = Vector2i.ZERO
				frame.aim = InputFrame.AIM_KEEP
				frame.held_bits = 0
				frame.pressed_bits = 0
				frame.captured = true
		elif input != null and input.is_joined(seat):
			_find_hand(seat)
			_local[seat].fill(frame, input, seat, delta, _hand, _mouse)
		var pending: Array = _pending[seat]
		if pending.is_empty():
			continue
		for command: Array in pending:
			if not frame.add_command(command[0], command.slice(1)):
				push_warning("Frames: seat %d's %s does not fit a frame (its arguments, or too many commands), so it is dropped." % [seat, command[0]])
		pending.clear()


## Where the hand of the actor seat `seat` drives is, and the mouse in its world (INF for none), but
## only while the seat aims with the mouse.
func _find_hand(seat: int) -> void:
	_hand = Vector2.INF
	_mouse = Vector2.INF
	if actors == null or not input.is_mouse_aiming(seat):
		return
	var body := actors.node_of(actors.actor_of_seat(seat)) as Node2D
	if body == null or not body.is_inside_tree():
		return
	var offset: Variant = body.get(&"hand_offset")
	_hand = body.global_position + (offset as Vector2 if offset is Vector2 else Vector2.ZERO)
	_mouse = body.get_global_mouse_position()


## The replay's next tick, read and applied. A tick that stood paused is played while the game
## stands paused (the horde's break), and one that ran while it runs: a pause of the recording's
## own (the pause menu) is skipped through at once, its commands applied in order, and a pause of
## the player's waits (N4 makes a stop part of the game's state).
func _read_replay(delta: float) -> void:
	for seat in SEATS:
		if _sources[seat] != null:
			_watched.seat = seat
			_watched.clear()
			_sources[seat].fill_frame(_watched, delta)
	var paused: bool = _paused()
	while _play_at < _playing.tick_count():
		var stood: bool = _playing.is_paused_at(_play_at)
		if stood == paused:
			_read_tick()
			_apply()
			return
		if not stood:
			# Paused here, running in the recording: wait.
			for seat in SEATS:
				_frames[seat].clear()
			return
		_read_tick()
		_apply()
	for seat in SEATS:
		_frames[seat].clear()


func _read_tick() -> void:
	_playing.read_tick(_play_at, _frames)
	_play_at += 1
	for seat in SEATS:
		_pending[seat].clear()
		if input == null:
			continue
		for command: Array in _frames[seat].commands:
			if command[0] == InputFrame.JOIN and not input.is_joined(seat):
				input.add_virtual_device(seat)
			elif command[0] == InputFrame.LEAVE and input.is_joined(seat):
				input.leave(seat)
	# The joins just made sent their own; the replay's frames say all.
	for seat in SEATS:
		_pending[seat].clear()


## The tick's commands apply, seat by seat, each seat's in the order sent.
func _apply() -> void:
	if events == null:
		return
	for seat in SEATS:
		var commands: Array[Array] = _frames[seat].commands
		if commands.is_empty():
			continue
		for command: Array in commands:
			var command_name: StringName = command[0]
			if command_name == InputFrame.JOIN or command_name == InputFrame.LEAVE:
				continue
			var args: Array = [seat]
			args.append_array(command.slice(1))
			events.apply_command(command_name, args)


## True while the tree stands paused (the pause menu, the horde's level-up break).
func _paused() -> bool:
	return is_inside_tree() and get_tree().paused


## A bit per seat joined now.
func _joined_seats() -> int:
	var mask: int = 0
	if input != null:
		for seat in SEATS:
			if input.is_joined(seat):
				mask |= 1 << seat
	return mask


## The seats a recorded tick keeps: the joined ones and any with a command (a leave).
func _recorded_seats() -> int:
	var mask: int = _joined_seats()
	for seat in SEATS:
		if not _frames[seat].commands.is_empty():
			mask |= 1 << seat
	return mask


## A command was sent (core/events): into its seat's next frame. Dropped while a replay plays.
func _on_command(command: StringName, args: Array) -> void:
	if _playing != null:
		return
	if args.is_empty() or typeof(args[0]) != TYPE_INT or int(args[0]) < 0 or int(args[0]) >= SEATS:
		push_warning("Frames: %s for no seat is dropped." % command)
		return
	var entry: Array = [command]
	entry.append_array(args.slice(1))
	_pending[int(args[0])].append(entry)


func _on_device_joined(player: int, _device: int) -> void:
	if player >= 0 and player < SEATS and _playing == null:
		_pending[player].append([InputFrame.JOIN])


func _on_device_left(player: int, _device: int) -> void:
	if player >= 0 and player < SEATS and _playing == null:
		_pending[player].append([InputFrame.LEAVE])
