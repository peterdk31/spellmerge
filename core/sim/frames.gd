extends Node
## The input frames (online-ready N2, docs/milestones/online-ready.md; the autoload "Frames"): the
## one input path. At the start of every tick it hands each seat 0-3 its `InputFrame`, and the
## simulation takes input from nothing else: a `PlayerController` builds its actor's intent from
## `frame_of(seat)`. Devices, bots and replays all produce frames, and later the network will;
## the game never knows which.
##
## - **The tick's start:** the Tick autoload (core/sim/tick.gd) calls `tick` first in every tick,
##   also while the game is stopped or held (the horde's level-up break takes its picks then).
## - **A tick that stands still** (online-ready N4: the game stopped or held; the Tick calls
##   `stood`): its presses carry to the next tick that steps, ORed into its frames, so a tap during a
##   downed wizard's stop is not lost. The recording keeps each tick's own frames; a replay carries
##   them the same way, its stops being the game's state.
## - **Where a frame comes from**, per seat: the replay being played (`play`); else the seat's
##   source (`set_source`: a bot, a `FrameSource`); else its device through the local input layer
##   (`LocalInput`: the walk, the aim with the mouse turned into a direction from the seat's aim
##   pivot, the buttons, captured); else nothing (a cleared frame). The pivot (the hand the seat's
##   wizard aims from) is told by whoever drives the seat (`set_aim_pivot`: its PlayerController),
##   so the input layer knows no body.
## - **Commands:** the HUD's requests (core/events, `command_sink`) and the seat's device joining
##   or leaving go into the seat's next frame, and the frame's commands apply when its tick starts,
##   seat by seat, in the order they were sent (`EventsScript.apply_command`). Joins and leaves
##   happen as the device joins and leaves (Flow and Coop read the joined seats at a run's start);
##   the frame tells a replay when, and a replay played joins and leaves its seats then.
## - **Replays:** `record(start, starter)` starts a run and records every tick's frames (the seats
##   joined, or with a command) into a `Replay`, `stop_recording` hands it over; `play(replay)`
##   joins its seats, starts its run the same way and feeds its frames, one a tick, until they run
##   out (live input and commands are dropped meanwhile): the game's stops are part of its state
##   (N4), so it stands still where the recording did. The replay on the deck is a `ReplayTape`
##   (core/sim/replay_tape.gd). A source set while a replay plays is still asked each tick
##   and its frame dropped: a bot reads the game through queries that fill the services' caches
##   (the projectile manager's threat grid and target table), which count as state and change the
##   next step, so a bot's run replays exactly only with the bot watching again (docs/DECISIONS.md,
##   2026-11-05). A person's input reads nothing of the game but where the hand is.
## - **A run's start** (`next_run_seed`, `next_run_rules`; the Tick asks at `begin_run`): the seed
##   and rules of the replay on the deck, else a random seed and this machine's rules
##   (`SessionRules.machine()`, changed by the "Max shots" setting, `projectile_cap_changed`). Online
##   (later), the host's come in here too, beside its inputs.
##
## Nothing here allocates per tick, but a command (an array) and a recorded tick (its bytes).

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const SEATS: int = 4

## The services. Only tests set these, before adding the node; otherwise the autoloads are used.
var events: EventsScript = null
var input: InputManagerScript = null
var registry: RegistryScript = null
## Whether the Tick starts its tick (the game). A test that ticks it by hand (`tick`) turns it off.
var auto_tick: bool = true
## Ticks started since the game began.
var ticks: int = 0
## Only tests set this: the mouse's point in the world, instead of the viewport's (INF: the viewport's).
var mouse_world_override: Vector2 = Vector2.INF

## The frames of the tick in progress, by seat (four, reused).
var _frames: Array[InputFrame] = []
## Per seat: the local input layer over its device.
var _local: Array[LocalInput] = []
## Per seat: what fills its frame instead of its device, or null.
var _sources: Array[FrameSource] = [null, null, null, null]
## Per seat: the commands sent since the last tick's start, each `[name, args...]`.
var _pending: Array[Array] = [[], [], [], []]
## The replay being recorded or played, or null.
var _tape: ReplayTape = null
## Per seat: where the seat aims from (`set_aim_pivot`: a world point, INF for none), or invalid.
var _pivots: Array[Callable] = [Callable(), Callable(), Callable(), Callable()]
## The frame a source watching a replay fills, dropped.
var _watched: InputFrame = InputFrame.new()
## Per seat: the presses of the ticks that stood still since the last tick that stepped (`stood`).
var _carried: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])


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
	if registry == null:
		registry = get_node_or_null("/root/Registry") as RegistryScript
	if events == null:
		push_warning("Frames: the Events autoload is missing, so commands apply as they are sent.")
		return
	events.command_sink = _on_command
	events.device_joined.connect(_on_device_joined)
	events.device_left.connect(_on_device_left)
	events.projectile_cap_changed.connect(_on_machine_cap)


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


## Seat `seat` aims its mouse from `pivot()` (a world point; INF for none): its wizard's hand. An
## invalid Callable: from nowhere (the mouse gives no aim).
func set_aim_pivot(seat: int, pivot: Callable) -> void:
	if seat >= 0 and seat < SEATS:
		_pivots[seat] = pivot


## The seed of the run that starts next (the Tick's `begin_run`): the replay's on the deck, else
## random.
func next_run_seed() -> int:
	return _tape.next_run_seed() if _tape != null else SimSeed.fresh()


## The rules of the run that starts next: the replay's on the deck, else this machine's (a copy).
func next_run_rules() -> SessionRules:
	return _tape.run_rules() if _tape != null else SessionRules.machine().copy()


## A tick starts: every seat's frame is built (or read from the replay played), recorded, and its
## commands applied. `delta` is the tick's length in seconds.
func tick(delta: float) -> void:
	ticks += 1
	if is_playing():
		_read_replay(delta)
	else:
		_build(delta)
		if _tape != null:
			_tape.record_tick(_frames, _recorded_seats())
		_apply()
	for seat in SEATS:
		if _carried[seat] != 0:
			_frames[seat].pressed_bits |= _carried[seat]
			_carried[seat] = 0
	if is_playing() and not _tape.has_tick():
		stop_playing()


## The tick just started stands still (the Tick, N4): its frames' presses wait for the next tick
## that steps.
func stood() -> void:
	for seat in SEATS:
		_carried[seat] |= _frames[seat].pressed_bits


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
	replay.rules = SessionRules.machine().copy()
	_tape = ReplayTape.recording(replay)
	_carried.fill(0)
	_send_start(start, starter)
	return replay


## Stop recording; returns the replay (null when none was recorded).
func stop_recording() -> Replay:
	if not is_recording():
		return null
	var replay: Replay = _tape.replay
	_tape = null
	return replay


func is_recording() -> bool:
	return _tape != null and not _tape.plays


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
	_tape = ReplayTape.playing(replay)
	_carried.fill(0)
	for seat in SEATS:
		_pending[seat].clear()
		if replay.seats & (1 << seat) != 0 and input != null and not input.is_joined(seat):
			input.add_virtual_device(seat)
	_send_start(replay.start, replay.starter)
	return true


## Stop playing (by itself once the frames run out): the seats take their own input again.
func stop_playing() -> void:
	if is_playing():
		_tape = null


func is_playing() -> bool:
	return _tape != null and _tape.plays


## The tick of the replay played that comes next (0 before its first).
func play_tick() -> int:
	return _tape.at if is_playing() else 0


## Send the request `start` (one of `Replay.STARTS`, each an event with the seat that asks).
func _send_start(start: StringName, starter: int) -> void:
	if events == null:
		return
	if not Replay.STARTS.has(start):
		push_warning("Frames: %s does not start a run." % start)
		return
	events.emit_signal(start, starter)


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
			var hand: Vector2 = _pivot(seat)
			_local[seat].fill(frame, input, seat, delta, hand, _mouse_world() if hand != Vector2.INF else Vector2.INF)
		var pending: Array = _pending[seat]
		if pending.is_empty():
			continue
		for command: Array in pending:
			if not frame.add_command(command[0], command.slice(1)):
				push_warning("Frames: seat %d's %s does not fit a frame (its arguments, or too many commands), so it is dropped." % [seat, command[0]])
		pending.clear()


## Where seat `seat` aims its mouse from (its pivot's point), INF while it aims otherwise or has
## no pivot.
func _pivot(seat: int) -> Vector2:
	if not input.is_mouse_aiming(seat) or not _pivots[seat].is_valid():
		return Vector2.INF
	return _pivots[seat].call() as Vector2


## The mouse in the world: the viewport's mouse through its canvas transform (the world's camera).
func _mouse_world() -> Vector2:
	if mouse_world_override != Vector2.INF:
		return mouse_world_override
	if not is_inside_tree():
		return Vector2.INF
	var viewport: Viewport = get_viewport()
	return viewport.get_canvas_transform().affine_inverse() * viewport.get_mouse_position()


## The replay's next tick, read and applied: one a tick. Where the recording stood stopped or held,
## the game stands so too, its stops being state (N4); a pause of the player's while it plays (the
## pause menu) runs no tick, so the replay waits.
func _read_replay(delta: float) -> void:
	for seat in SEATS:
		if _sources[seat] != null:
			_watched.seat = seat
			_watched.clear()
			_sources[seat].fill_frame(_watched, delta)
	if _tape.has_tick():
		_read_tick()
		_apply()
		return
	for seat in SEATS:
		_frames[seat].clear()


func _read_tick() -> void:
	_tape.read_tick(_frames)
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


## The seats joined now, in order: who plays a run that starts (Flow reads them here, never the
## devices).
func joined_seats() -> Array[int]:
	var out: Array[int] = []
	var mask: int = _joined_seats()
	for seat in SEATS:
		if mask & (1 << seat) != 0:
			out.append(seat)
	return out


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
	if is_playing():
		return
	if args.is_empty() or typeof(args[0]) != TYPE_INT or int(args[0]) < 0 or int(args[0]) >= SEATS:
		push_warning("Frames: %s for no seat is dropped." % command)
		return
	var entry: Array = [command]
	entry.append_array(args.slice(1))
	_pending[int(args[0])].append(entry)


func _on_device_joined(player: int, _device: int) -> void:
	if player >= 0 and player < SEATS and not is_playing():
		_pending[player].append([InputFrame.JOIN])


func _on_device_left(player: int, _device: int) -> void:
	if player >= 0 and player < SEATS and not is_playing():
		_pending[player].append([InputFrame.LEAVE])


## This machine's "Max shots" changed (the pause menu's setting, or the saved one loaded): the cap
## of the runs that start from now on with this machine's rules. A run playing now changes only by
## the command (`shot_cap_requested`).
func _on_machine_cap(cap: int) -> void:
	SessionRules.machine().shot_cap = cap
