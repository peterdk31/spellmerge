extends Node
## Host and Join (netcode spike S4, docs/milestones/netcode-spike.md; the autoload "NetPlay"): what
## holds an online run together. It hears the main menu's requests on the bus, swaps the codes
## through a handshake (`NetHandshake`: WebRTC's, `NetRtc`), makes the session once the link is
## open (`NetHost` or `NetClient`), starts the run, and says where things stand on the bus. Nothing
## outside net/ calls it, and it calls nothing of the game but `core/`: the bus, the frames
## service (through the sessions), the input layer (which seats are this machine's) and the Tick's
## `ticked`.
##
## How it goes (`phase`, sent as `online_changed`):
##
## 1. **Host** (`online_host_requested`) or **Join** with the host's code
##    (`online_join_requested`): MAKING. This machine's seats are set (the host's: seat 0 alone;
##    the joining machine's: the client's seat alone, so its keyboard or first gamepad is that
##    seat in the builder, the pause menu and the frames it sends) and its keyboard joins if
##    nothing has. Nothing connects anywhere before this.
## 2. **This machine's code is made:** CODE, with the code for the other player. The host then
##    gives the code that came back (`online_answer_requested`): LINKING. A code refused (not a
##    code, the wrong side's) leaves things as they are and says why; the player may give another.
## 3. **The link is open:** LINKED. Each machine first does what must be ready before a room
##    (`play_load_requested`: Flow's loading screen), since a load takes each its own time and the
##    run must start on the same tick on both. Only then is its session pumped: the client pings
##    (and measures its ping, from which its input delay is set), and the host, which hears from
##    its pings that the client is ready, starts the run once READY_PINGS came and it is loaded
##    itself: a sandbox, recorded: PLAYING. The client is PLAYING once the host's header has
##    started its live replay.
## 4. **While it plays** the frames service drives the sessions; this only calls their `after_tick`
##    on the Tick's `ticked`, sends the counters' line about once a second (`online_line_changed`)
##    and logs them (`NetLog`), and when a hash check fails says so once and has this side's run
##    saved as a replay (`Frames.save_run`; the tools of core/sim find who differs, offline).
## 5. **The other machine gone:** ENDED. The host's run plays on without the client's seat (it
##    leaves, as an unplugged gamepad's does); the client's replay ends once played out and its
##    game goes on alone. All four seats are the machine's own again, its device staying on the
##    seat it plays on. Nothing more is heard after ENDED: that run may still play, and no new
##    one starts under it. **Given up** before the run (`online_leave_requested`) or failed: OFF
##    or FAILED, with this machine's seats its own again.
##
## It steps in its own `_physics_process` (never the simulation's: it reads the link and the
## engine's clock, and writes nothing the simulation reads but through the frames service). Tests
## set the services and `handshake_maker` before adding the node, and may step it by hand
## (`step`).
##
## No `class_name` (it would hide the autoload).

const EventsScript := preload("res://core/events/events.gd")
const FramesScript := preload("res://core/sim/frames.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const TickScript := preload("res://core/sim/tick.gd")

## The phases, the bus's names for them (`online_changed`).
const OFF: StringName = EventsScript.ONLINE_OFF
const MAKING: StringName = EventsScript.ONLINE_MAKING
const CODE: StringName = EventsScript.ONLINE_CODE
const LINKING: StringName = EventsScript.ONLINE_LINKING
const LINKED: StringName = EventsScript.ONLINE_LINKED
const PLAYING: StringName = EventsScript.ONLINE_PLAYING
const ENDED: StringName = EventsScript.ONLINE_ENDED
const FAILED: StringName = EventsScript.ONLINE_FAILED

## How the run starts (one of `Replay.STARTS`): a sandbox, for its storms.
const START: StringName = &"sandbox_requested"
## The client's pings the host hears before it starts the run: the client is loaded and has
## measured its ping (it pings twice a second).
const READY_PINGS: int = 3
## The counters' line is sent, and their row logged, every this many physics steps of a run.
const LINE_EVERY: int = 60
const LOG_EVERY: int = 600

## The services. Only tests set these, before adding the node; otherwise the autoloads are used.
var events: EventsScript = null
var frames: FramesScript = null
var input: InputManagerScript = null
var tick: TickScript = null
## Makes the handshake (a `NetHandshake`); invalid: WebRTC's (`NetRtc`). Tests give their own.
var handshake_maker: Callable = Callable()
## The game's areas by name, for the hash checks; invalid: the Tick's (`state_areas`).
var areas: Callable = Callable()

## Where things stand (see the top), with this machine's code and the note last sent. Read only.
var phase: StringName = OFF
var code: String = ""
var note: String = ""
## The session, from LINKED until the other machine is gone: the host's (`NetHost`, with the one
## guest machine) or the client's (`NetClient`). Read only.
var session: RefCounted:
	get:
		return _host if _host != null else _client

var _host: NetHost = null
var _client: NetClient = null

var _hosting: bool = false
var _handshake: NetHandshake = null
## True while the loading screen is up (`loading_started` to `loading_finished`).
var _loading: bool = false
## Physics steps of the run played.
var _steps: int = 0
var _parting_told: bool = false
var _log: NetLog = NetLog.new()


func _init() -> void:
	# The link is read and the codes are swapped under a pause too.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	if events == null:
		events = get_node_or_null(^"/root/Events") as EventsScript
	if frames == null:
		frames = get_node_or_null(^"/root/Frames") as FramesScript
	if input == null:
		input = get_node_or_null(^"/root/PlayerInput") as InputManagerScript
	if tick == null:
		tick = get_node_or_null(^"/root/Tick") as TickScript
	if tick != null:
		tick.ticked.connect(after_tick)
		if not areas.is_valid():
			areas = tick.state_areas
	if events == null or frames == null or input == null:
		push_warning("NetPlay: the Events, Frames or PlayerInput autoload is missing, so Host and Join do nothing.")
		return
	events.online_host_requested.connect(_on_host_requested)
	events.online_join_requested.connect(_on_join_requested)
	events.online_answer_requested.connect(_on_answer_requested)
	events.online_leave_requested.connect(_on_leave_requested)
	events.loading_started.connect(func() -> void: _loading = true)
	events.loading_finished.connect(func() -> void: _loading = false)


func _physics_process(_delta: float) -> void:
	step()


## One physics step: the handshake moves on, the session is pumped until its run starts, and a
## run that plays is watched (see the top).
func step() -> void:
	if _handshake != null:
		_step_handshake()
	elif session != null and phase == LINKED:
		_step_before_run()
	elif session != null and phase == PLAYING:
		_step_run()


## A tick has stepped (the Tick's `ticked`; a test's own loop): the session sends and hashes.
func after_tick() -> void:
	if phase != PLAYING:
		return
	if _host != null:
		_host.after_tick()
	elif _client != null:
		_client.after_tick()


func is_hosting() -> bool:
	return _hosting


func _on_host_requested(_player: int) -> void:
	_begin(true, "")


func _on_join_requested(_player: int, host_code: String) -> void:
	_begin(false, host_code)


## Host or Join was asked for: the handshake begins, and this machine's seats are set.
func _begin(hosting: bool, host_code: String) -> void:
	# Not after a run either (ENDED): that run may still play here, and no new one starts under it.
	if phase != OFF and phase != FAILED:
		return
	_hosting = hosting
	_handshake = handshake_maker.call() as NetHandshake if handshake_maker.is_valid() else NetRtc.new()
	var why: String = _handshake.offer() if hosting else _handshake.take(host_code)
	if why != "":
		_fail(why)
		return
	var seat: int = 0 if hosting else NetHost.SEAT
	# In the menu nobody plays yet: every device takes the place it would have joining now.
	input.set_own_seats(seat, 1, true)
	# The menu may be worked with the mouse by nobody who has joined: the keyboard plays, until a
	# gamepad wants the seat.
	if not input.is_joined(seat):
		input.join(InputManagerScript.KEYBOARD, true)
	_show(MAKING)


func _on_answer_requested(_player: int, answer: String) -> void:
	if not _hosting or phase != CODE or _handshake == null:
		return
	var why: String = _handshake.take(answer)
	if _handshake.problem() != "":
		# WebRTC itself refused it: this machine's own code is spent too.
		_fail(_handshake.problem())
	elif why != "":
		_show(CODE, "That code was not taken: %s." % why)
	else:
		_show(LINKING)


func _on_leave_requested(_player: int) -> void:
	if phase == PLAYING or phase == ENDED or phase == OFF:
		return
	_let_go()
	code = ""
	_show(OFF)


func _step_handshake() -> void:
	_handshake.poll()
	if _handshake.problem() != "":
		_fail(_handshake.problem())
		return
	if phase == MAKING and _handshake.code() != "":
		code = _handshake.code()
		_show(CODE)
	var link: NetLink = _handshake.link()
	if link == null:
		return
	_handshake = null
	if _hosting:
		_host = NetHost.new(frames, input, areas)
		_host.add_guest(link, 1 << NetHost.SEAT)
	else:
		_client = NetClient.new(frames, link, areas)
	_show(LINKED)
	# Whatever must load before a room loads now, not at the run's start.
	events.play_load_requested.emit()


func _step_before_run() -> void:
	# Not while this machine loads: the other hears nothing from it until it is ready.
	if _loading:
		return
	if _hosting:
		_host.pump()
		var guest: NetGuest = _host.guests[0]
		if guest.problem != "":
			_fail("the link was closed: %s" % guest.problem)
			return
		# Before the run a client sends only pings.
		if guest.stats.read < READY_PINGS and guest.link.is_open():
			return
		if _host.start(START, 0) == null:
			_fail("the other player left" if not guest.link.is_open() else "seat %d is held by a device of this machine" % (NetHost.SEAT + 1))
			return
	else:
		_client.pump()
		# A client whose run has started is playing, whatever came after the header (a link refused
		# then ends the run as any closed link does).
		if _client.problem != "" and not _client.started:
			_fail("the link was closed: %s" % _client.problem)
			return
		if not _client.started:
			if not _client.link.is_open():
				_fail("the host left")
			return
	_steps = 0
	_parting_told = false
	_log.open(_hosting)
	_show(PLAYING)


func _step_run() -> void:
	_steps += 1
	if _parted_tick() >= 0 and not _parting_told:
		_parting_told = true
		_tell_parting()
	var over: bool = not _host.hears_guests() if _hosting else not _client.is_playing()
	if over or _steps % LOG_EVERY == 0:
		_log.row(_stats().row())
	if over:
		_end()
	elif _steps % LINE_EVERY == 0:
		events.online_line_changed.emit(_line())


## The first hash check that failed: said once, and this side's run saved for the tools (the
## frames service holds the run and writes the file; a client whose replay ended in this very
## step has none on the deck any more, and the row then names no file).
func _tell_parting() -> void:
	var saved_as: String = "online_host_parted" if _hosting else "online_client_parted"
	var saved: bool = frames.save_run(saved_as) == OK
	var row: Dictionary = {"parted_tick": _parted_tick(), "parted_areas": _parted_areas(), "replay": saved_as if saved else ""}
	_log.row(row)
	print("NetPlay: the two machines parted at tick %d in %s%s" % [_parted_tick(), ", ".join(_parted_areas()), "; this side's run is saved as the replay %s" % saved_as if saved else ""])


func _line() -> String:
	var line: String = _stats().line()
	if _parted_tick() >= 0:
		line = "PARTED at tick %d (%s). %s" % [_parted_tick(), ", ".join(_parted_areas()), line]
	return line


## The session's counters: the client's, or the host's with its guests' added up.
func _stats() -> NetStats:
	return _host.totals() if _host != null else _client.stats


func _parted_tick() -> int:
	return _host.parted_tick if _host != null else _client.parted_tick


func _parted_areas() -> PackedStringArray:
	return _host.parted_areas if _host != null else _client.parted_areas


## The other machine is gone from a run that played.
func _end() -> void:
	var why: String = _host.guests[0].problem if _host != null else _client.problem
	if _host != null:
		# The client's seat leaves and the recording ends; the run plays on.
		_host.stop()
	# All four seats are this machine's again; its device keeps the seat it plays on.
	input.set_own_seats()
	_log.close()
	_host = null
	_client = null
	var gone: String = "The other player left; the run plays on here." if _hosting else "The host left; the run plays on here, alone."
	_show(ENDED, gone if why == "" else "%s (The link was closed: %s.)" % [gone, why])


func _fail(why: String) -> void:
	_let_go()
	code = ""
	_show(FAILED, why.substr(0, 1).to_upper() + why.substr(1) + ".")


## The handshake and a session whose run never began are closed, and this machine's seats are its
## own again.
func _let_go() -> void:
	if _handshake != null:
		_handshake.close()
		_handshake = null
	if _host != null:
		_host.stop()
		_host = null
	if _client != null:
		_client.link.close()
		_client = null
	# No run plays: every device takes the place it would have joining now.
	input.set_own_seats(0, InputManagerScript.MAX_PLAYERS, true)


func _show(now: StringName, with_note: String = "") -> void:
	phase = now
	note = with_note
	events.online_changed.emit(phase, code, note)
