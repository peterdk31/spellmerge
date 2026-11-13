extends Node
## The input frames (online-ready N2, docs/milestones/online-ready.md; the autoload "Frames"): the
## one input path. At the start of every tick it hands each seat 0-3 its `InputFrame`, and the
## simulation takes input from nothing else: a `PlayerController` builds its actor's intent from
## `frame_of(seat)`. Devices, bots and replays all produce frames, and later the network will;
## the game never knows which.
##
## - **The tick's start:** the Tick autoload (core/sim/tick.gd) calls `tick` first in every tick,
##   also while the game is stopped or held (a command still arrives then).
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
##   seat by seat, in the order they were sent (`EventsScript.apply_command`).
## - **Seats** (who plays: `seat_joined`, `seat_left`, heard by Coop; `joined_seats`, read by Flow
##   at a run's start): the simulation's, sent from here only, never from a device. Offline a seat
##   joins and leaves as its device does (and the frame tells a recording when); while a replay
##   plays, as the replay's frames say, at their tick's start, whatever this machine's devices do
##   meanwhile (a pad plugged in during a replay, or an online client's own seat leaving and
##   joining again, changes nothing until the replay says so). A replay's seats get virtual
##   devices for the HUD (given back when it ends), but a live replay's local seats keep this
##   machine's own. A source never seats: a JOIN or LEAVE it writes is dropped (`FrameSource`).
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
## - **A live replay** (`play_live`; netcode spike S1, docs/milestones/netcode-spike.md): a replay
##   that grows while it plays, the online client's, fed by a `LiveFeed` (core/sim/live_feed.gd).
##   The Tick calls `begin_step` first in every physics step: the feed's `pump` adds the ticks that
##   arrived, the seats whose input is this machine's (the feed's `local_seats`) build their frame
##   from their source or device, with their commands, and hand it to the feed's `send` (one a
##   step, also while the replay waits: the other machine hears this one at its own pace), and the
##   step runs as many ticks as the feed paces (none while no tick is there: the picture holds).
##   The replay's frames are the game's: a local seat's frame is never used here. It ends once its
##   feed is closed and it is played out. Frames knows no network.
## - **A replay's end:** at the start of the step (or tick) after its last tick, so its last tick
##   steps with the replay's seats as every tick before.
## - **A run's start** (`next_run_seed`, `next_run_rules`; the Tick asks at `begin_run`): the seed
##   and rules of the replay on the deck, else a random seed and this machine's rules
##   (`SessionRules.machine()`, changed by the "Max shots" setting, `projectile_cap_changed`). Online
##   (later), the host's come in here too, beside its inputs. What the run takes along from the play
##   before it (`next_run_carry`, core/sim/run_carry.gd: each seat's staffs) is the same: the
##   replay's, else what the game says it would take now (`set_carry_source`); a recording begun
##   writes the game's into its header, so the machines that play it start with what only this one had.
##
## - **A run begun anew by the game** (`restart`; online lobby, docs/milestones/online-lobby.md): the
##   game itself asks for a run's start (a party back in its hub after a run). It is sent at the
##   start of the next physics step, never inside a tick, so every machine starts it between the
##   same two ticks. With a run being recorded, a new recording begins there (`recorded_anew`):
##   a recording is one stretch from a run's start, and whoever sends it on (net/) sends the new
##   one. A replay played from a file ends there and the game goes on by itself; a live replay
##   waits for its feed to bring the next recording (`play_live` again, which `begin_step` takes
##   in its stride).
## - **Back to the main menu** (`main_menu_requested`): this machine's own leaving, never a command.
##   What is recorded or played ends there, and a run asked for by `restart` is forgotten.
##
## Nothing here allocates per tick, but a command (an array) and a recorded tick (its bytes).

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const SEATS: int = 4

## The run that is recorded began anew (`restart`): `replay` is the recording it goes into now.
signal recorded_anew(replay: Replay)

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
## While a live replay plays: the frames this machine's seats built this physics step, by seat
## (four, reused), handed to its feed.
var _built: Array[InputFrame] = []
## Per seat: the local input layer over its device.
var _local: Array[LocalInput] = []
## Per seat: what fills its frame instead of its device, or null.
var _sources: Array[FrameSource] = [null, null, null, null]
## Per seat: the commands sent since the last tick's start, each `[name, args...]`.
var _pending: Array[Array] = [[], [], [], []]
## The replay being recorded or played, or null.
var _tape: ReplayTape = null
## While a replay plays: the seats whose virtual device it added (a bit each), to give back.
var _mirrored: int = 0
## Per seat: where the seat aims from (`set_aim_pivot`: a world point, INF for none), or invalid.
var _pivots: Array[Callable] = [Callable(), Callable(), Callable(), Callable()]
## The frame a source watching a replay fills, dropped.
var _watched: InputFrame = InputFrame.new()
## Per seat: the presses of the ticks that stood still since the last tick that stepped (`stood`).
var _carried: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## A run's start the game asked for (`restart`), sent at the next step's start: the start and
## the seat it is for (empty: none).
var _restart: Array = []
## Says what a run that starts now takes along (`set_carry_source`: returns a RunCarry), or invalid:
## nothing.
var _carry_source: Callable = Callable()


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for seat in SEATS:
		var frame := InputFrame.new()
		frame.seat = seat
		_frames.append(frame)
		var built := InputFrame.new()
		built.seat = seat
		_built.append(built)
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
	events.main_menu_requested.connect(_on_main_menu_requested)


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


## What a run that starts now takes along from the play before it, as the game says it
## (`source()` returns a RunCarry; Flow gives it): read when a recording begins (its header) and by
## `next_run_carry` with no replay on the deck. An invalid Callable: nothing.
func set_carry_source(source: Callable) -> void:
	_carry_source = source


## What the run that starts next takes along (a copy): the replay's on the deck (its header), else
## what the game says it would take now.
func next_run_carry() -> RunCarry:
	if _tape != null:
		return _tape.replay.carry.copy()
	return _carry_now()


func _carry_now() -> RunCarry:
	var made: RunCarry = _carry_source.call() as RunCarry if _carry_source.is_valid() else null
	return made if made != null else RunCarry.new()


## A tick starts: every seat's frame is built (or read from the replay played), recorded, and its
## commands applied. `delta` is the tick's length in seconds.
func tick(delta: float) -> void:
	# Whoever ticks by hand, with no `begin_step`: the run the game asked for starts here.
	if not _restart.is_empty():
		_begin_anew()
	ticks += 1
	# A replay played out ended with its last tick: this one is the game's own.
	if is_playing() and _tape.is_done():
		stop_playing()
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


## A physics step starts (the Tick, before any of its ticks; `delta` is a step's length): returns
## how many ticks it runs. 1, but while a live replay plays its feed is pumped, this machine's
## seats' frames are built and sent, and then none runs while no tick is there and the feed paces
## the rest (see the class doc). A replay played out (a live one: and closed) ends here. Call it
## once a step: it reads the feed.
func begin_step(delta: float) -> int:
	if not _restart.is_empty():
		_begin_anew()
	if not is_live():
		if is_playing() and _tape.is_done():
			stop_playing()
		return 1
	var tape: ReplayTape = _tape
	tape.feed.pump()
	if tape != _tape:
		# The feed stopped it (a link that closed), or began the next recording (the host's run
		# began anew): that one is played from here.
		if not is_live():
			return 1
		tape = _tape
	if tape.is_done():
		stop_playing()
		return 1
	for seat in SEATS:
		if tape.is_local(seat):
			_build_seat(seat, _built[seat], delta)
			tape.feed.send(tape.at, _built[seat])
			if tape != _tape:
				return 1
	return tape.ticks_due()


## This machine leaves what it plays for the main menu (`main_menu_requested`): what it records or
## plays ends, and a run the game asked for and not yet begun (`restart`) never begins. The seats'
## commands still waiting are kept: the pause menu's own closing is one, and the game must not stay
## stopped under the menu.
func _on_main_menu_requested(_player: int) -> void:
	_restart = []
	stop_recording()
	stop_playing()


## The game asks for a run's start itself (one of `Replay.STARTS`, for seat `starter`): sent at
## the start of the next physics step (see the top, "A run begun anew by the game"). Whoever asks
## has ended its run first (it is idle until then).
func restart(start: StringName, starter: int) -> void:
	_restart = [start, starter]


## The run the game asked for (`restart`) starts: recorded anew, after a replay from a file, or
## plainly; a live replay's next recording is its feed's to bring.
func _begin_anew() -> void:
	# A live replay's next recording is its feed's to bring (`play_live` then takes this start's
	# place). Kept meanwhile: with the feed gone before it came, the replay ends and the game
	# starts the run itself, as after any replay.
	if is_live():
		return
	var start: StringName = _restart[0]
	var starter: int = _restart[1]
	_restart = []
	if is_playing():
		stop_playing()
		_send_start(start, starter)
	elif is_recording():
		recorded_anew.emit(record(start, starter))
	else:
		_send_start(start, starter)


## The tick just started stands still (the Tick, N4): its frames' presses wait for the next tick
## that steps.
func stood() -> void:
	for seat in SEATS:
		_carried[seat] |= _frames[seat].pressed_bits


## Start a run by `start` (one of `Replay.STARTS`) for seat `starter` and record it from its first
## tick. Returns the replay it records into (it grows each tick until `stop_recording`). The run's
## seed is `run_seed`, or a random one when it is 0 (the platform runs, N2b, pick theirs, so every
## platform plays the same run).
func record(start: StringName, starter: int, run_seed: int = 0) -> Replay:
	stop_playing()
	var replay := Replay.new()
	replay.build = Replay.build_of()
	replay.content = Replay.content_of(registry)
	replay.run_seed = run_seed if run_seed != 0 else SimSeed.pick()
	replay.start = start
	replay.starter = starter
	replay.seats = _device_seats()
	replay.rules = SessionRules.machine().copy()
	replay.carry = _carry_now()
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


## The replay being recorded into now, or null with none.
func recorded() -> Replay:
	return _tape.replay if is_recording() else null


## Save the run on the deck (the one recorded, or played, so far) as the replay file
## `user://replays/<name>.replay` (`Replay.save`: `name` of letters, digits and `_`). ERR_UNAVAILABLE
## with no run on the deck.
func save_run(name: String) -> Error:
	if _tape == null:
		return ERR_UNAVAILABLE
	return _tape.replay.save(name)


## Play `replay` from its first tick: its seats are seated (with virtual devices, where free), its
## run starts the way it started, and every tick takes its frames until they run out. False, and
## nothing happens, for a replay of other content.
func play(replay: Replay) -> bool:
	if replay == null or not _play(ReplayTape.playing(replay)):
		return false
	if replay.build != Replay.build_of():
		push_warning("Frames: the replay was recorded by %s, this is %s; it may play differently." % [replay.build, Replay.build_of()])
	return true


## Play `feed`'s replay live, as the feed adds its ticks (the online client; see the class doc): it
## starts as `play` does. The feed's local seats are this machine's: their frames are built each
## physics step and sent to the feed, and their commands are heard. False, and nothing happens, for
## no feed or replay, or a replay of another build or other content (online they would part).
func play_live(feed: LiveFeed) -> bool:
	if feed == null or feed.replay == null:
		return false
	if feed.replay.build != Replay.build_of():
		push_warning("Frames: the live replay is of build %s, this is %s, so it is not played." % [feed.replay.build, Replay.build_of()])
		return false
	return _play(ReplayTape.playing(feed.replay, feed))


## True while a live replay plays.
func is_live() -> bool:
	return is_playing() and _tape.is_live()


## Whether a command seat `seat` sends now reaches the game (in its frame): always but while a
## replay plays, whose frames say all (the pause menu then only stands the picture still), and
## then for a live replay's local seats (their commands come back in the replay's frames).
func hears_commands(seat: int) -> bool:
	return _builds(seat)


## A bit per seat played on this machine now, for the view only (whose wizards its camera holds,
## gameplay/feel/party_camera.gd; the game never asks): the seats a real device holds here, or a
## live replay's local seats (the online client's). Another machine's seat is a virtual device
## here, as a bot's is, so those are not this machine's; 0 while a recording plays.
func seats_here() -> int:
	var mask: int = 0
	for seat in SEATS:
		if is_playing():
			if _tape.is_local(seat):
				mask |= 1 << seat
		elif input != null and input.is_joined(seat) and not InputManagerScript.is_virtual(input.device_of(seat)):
			mask |= 1 << seat
	return mask


func _play(tape: ReplayTape) -> bool:
	var replay: Replay = tape.replay
	var here: int = Replay.content_of(registry)
	if replay.content != here:
		push_warning("Frames: the replay is of other content (%d, here %d), so it is not played." % [replay.content, here])
		return false
	stop_recording()
	var seated_before: int = _seated_now()
	# The feed of a live replay playing the next recording of its run: its local seats' commands
	# sent in between (a leave pressed just then) are still theirs to send.
	var kept: int = tape.feed.local_seats if tape.feed != null and _tape != null and _tape.feed == tape.feed else 0
	# One playing before it gives its devices back first.
	_release_devices()
	_tape = tape
	# The run the game asked for, if it did, is this one.
	_restart = []
	_carried.fill(0)
	_mirror_devices(tape.seated)
	# The joins just made are the replay's own (a live replay's local seats hear them).
	for seat in SEATS:
		if kept & (1 << seat) == 0:
			_pending[seat].clear()
	_seat_changes(seated_before, tape.seated)
	_send_start(replay.start, replay.starter)
	return true


## The replay played goes on from its tick `tick` (a snapshot of that tick restored: a player
## joining a run, a replay sought; online-ready N10). False, and nothing changes, when no replay
## plays or it has no such tick. Presses carried through ticks that stood still are dropped: they
## are input, which no snapshot holds (a snapshot taken while the game stands loses them).
func seek(tick: int) -> bool:
	if not is_playing() or tick < 0 or tick > _tape.replay.tick_count():
		return false
	_tape.at = tick
	# The snapshot restored the game's own seats (Coop's); these are the replay's at that tick.
	_tape.seated = _tape.replay.seats_at(tick)
	_mirror_devices(_tape.seated)
	_carried.fill(0)
	for seat in SEATS:
		_pending[seat].clear()
	return true


## Stop playing (by itself at the step after its last tick): the replay's virtual devices are given
## back, and the seats take their own input again, seated as their devices are.
func stop_playing() -> void:
	if not is_playing():
		return
	var seated_before: int = _tape.seated
	_release_devices()
	_tape = null
	_seat_changes(seated_before, _device_seats())


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
		_build_seat(seat, _frames[seat], delta)


## Seat `seat`'s frame for a tick of `delta` seconds into `frame`: from its source, else its device
## (else nothing), with the commands sent since its last frame.
func _build_seat(seat: int, frame: InputFrame, delta: float) -> void:
	frame.clear()
	var source: FrameSource = _sources[seat]
	if source != null:
		source.fill_frame(frame, delta)
		_drop_seating(frame)
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
		return
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
## pause menu) runs no tick, so the replay waits. A live replay's local seats built their frames
## at the step's start (`begin_step`); a live replay is ticked only for a tick it holds.
func _read_replay(delta: float) -> void:
	for seat in SEATS:
		if _sources[seat] != null and not _tape.is_local(seat):
			_watched.seat = seat
			_watched.clear()
			_sources[seat].fill_frame(_watched, delta)
	if _tape.has_tick():
		_read_tick()
		_apply()
		return
	if _tape.is_live():
		push_error("Frames: a live replay was ticked with no tick to play (tick %d); the Tick runs only what begin_step says." % _tape.at)
	for seat in SEATS:
		_frames[seat].clear()


## The next tick read, and its seats' joins and leaves made (before any command applies, as offline
## a device joins between ticks).
func _read_tick() -> void:
	_tape.read_tick(_frames)
	var seated_before: int = _tape.seated
	for seat in SEATS:
		for command: Array in _frames[seat].commands:
			if command[0] == InputFrame.JOIN:
				_tape.seated |= 1 << seat
			elif command[0] == InputFrame.LEAVE:
				_tape.seated &= ~(1 << seat)
	if _tape.seated != seated_before:
		_mirror_devices(_tape.seated)
		_seat_changes(seated_before, _tape.seated)


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
## devices). While a replay plays, the replay's.
func joined_seats() -> Array[int]:
	var out: Array[int] = []
	var mask: int = _seated_now()
	for seat in SEATS:
		if mask & (1 << seat) != 0:
			out.append(seat)
	return out


## A bit per seat seated now: the replay's while one plays, else each whose device is joined.
func _seated_now() -> int:
	return _tape.seated if is_playing() else _device_seats()


## A bit per seat whose device is joined now.
func _device_seats() -> int:
	var mask: int = 0
	if input != null:
		for seat in SEATS:
			if input.is_joined(seat):
				mask |= 1 << seat
	return mask


## The seats a recorded tick keeps: the joined ones and any with a command (a leave).
func _recorded_seats() -> int:
	var mask: int = _device_seats()
	for seat in SEATS:
		if not _frames[seat].commands.is_empty():
			mask |= 1 << seat
	return mask


## A command was sent (core/events): into its seat's next frame. Dropped while a replay plays, but
## a live replay's local seats' (they go into the frames handed to its `sent`).
func _on_command(command: StringName, args: Array) -> void:
	if args.is_empty() or typeof(args[0]) != TYPE_INT or int(args[0]) < 0 or int(args[0]) >= SEATS:
		if not is_playing():
			push_warning("Frames: %s for no seat is dropped." % command)
		return
	if not _builds(int(args[0])):
		return
	var entry: Array = [command]
	entry.append_array(args.slice(1))
	_pending[int(args[0])].append(entry)


## A device joined seat `player`: in its next frame, and offline the seat is seated at once.
func _on_device_joined(player: int, _device: int) -> void:
	if player < 0 or player >= SEATS or not _builds(player):
		return
	_pending[player].append([InputFrame.JOIN])
	if not is_playing() and events != null:
		events.seat_joined.emit(player)


## A device left seat `player`: in its next frame, and offline the seat leaves at once.
func _on_device_left(player: int, _device: int) -> void:
	if player < 0 or player >= SEATS or not _builds(player):
		return
	_pending[player].append([InputFrame.LEAVE])
	if not is_playing() and events != null:
		events.seat_left.emit(player)


## The seats `from` became `to` (a bit each): each seat left, then each joined, sent.
func _seat_changes(from: int, to: int) -> void:
	if events == null or from == to:
		return
	for seat in SEATS:
		if from & (1 << seat) != 0 and to & (1 << seat) == 0:
			events.seat_left.emit(seat)
	for seat in SEATS:
		if from & (1 << seat) == 0 and to & (1 << seat) != 0:
			events.seat_joined.emit(seat)


## A source's frame seats nobody (core/sim/frame_source.gd): a JOIN or LEAVE it wrote is dropped.
func _drop_seating(frame: InputFrame) -> void:
	for at in range(frame.commands.size() - 1, -1, -1):
		var command: StringName = frame.commands[at][0]
		if command == InputFrame.JOIN or command == InputFrame.LEAVE:
			push_warning("Frames: seat %d's source wrote %s, which only the input layer does; it is dropped." % [frame.seat, command])
			frame.commands.remove_at(at)


## While a replay plays: each seat it seats gets a virtual device where it has none, and each it
## does not loses the one given it here, so the HUD shows the replay's players. Only the devices
## added here (`_mirrored`) are ever sent away: never a real one, a bot's, or a live replay's local
## seat's. The devices' join and leave events are dropped (a replay plays).
func _mirror_devices(seats: int) -> void:
	if input == null:
		return
	for seat in SEATS:
		if _tape.is_local(seat):
			continue
		var bit: int = 1 << seat
		if seats & bit != 0 and not input.is_joined(seat):
			input.add_virtual_device(seat)
			_mirrored |= bit
		elif seats & bit == 0 and _mirrored & bit != 0:
			input.leave(seat)
			_mirrored &= ~bit


## The virtual devices the replay played was given leave (while it still plays, so they seat and
## record nothing).
func _release_devices() -> void:
	if input != null:
		for seat in SEATS:
			if _mirrored & (1 << seat) != 0 and input.is_joined(seat):
				input.leave(seat)
	_mirrored = 0


## Whether seat `seat`'s frames are built here now (from its source or device): always but while a
## replay plays, and then only a live replay's local seats.
func _builds(seat: int) -> bool:
	return not is_playing() or _tape.is_local(seat)


## This machine's "Max shots" changed (the pause menu's setting, or the saved one loaded): the cap
## of the runs that start from now on with this machine's rules. A run playing now changes only by
## the command (`shot_cap_requested`).
func _on_machine_cap(cap: int) -> void:
	SessionRules.machine().shot_cap = cap
