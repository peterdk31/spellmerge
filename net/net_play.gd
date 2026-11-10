extends Node
## Playing online (netcode spike S4, docs/milestones/netcode-spike.md; the room and the seats,
## online lobby L2, docs/milestones/online-lobby.md; the autoload "NetPlay"): what holds an online
## run together. It hears the requests on the bus, has a handshake find the other machine
## (`NetHandshake`: it never knows which kind beyond choosing one by the way in, in
## `_handshake_for`, and never reads a code: each handshake says whether a typed text is its own),
## makes the session once a link is there (`NetHost`, with a `NetGuest` for each guest machine, or
## `NetClient`), and says where things stand on the bus.
## Nothing outside net/ calls it, and it calls nothing of the game but `core/`: the bus, the
## frames service (itself and through the sessions), the input layer (whose devices a client's
## session has seated by the host) and the Tick's `ticked`.
##
## Which way the machines find each other (the handshake) and what they then play (a party's
## hub that machines come to and go from, or one run of two) are two things, kept apart: a
## platform's own lobbies would be another way into the same party.
##
## - **A party opened** (the hub's altar, `online_open_requested`): this machine's party is opened
##   to other machines, through a room. MAKING, then CODE with the room's code, for the others
##   to type. The party
##   plays on as it was; nothing of the game changes until a machine joins. Asked again, the
##   code is said again (A is also a wizard's dash: a second press must not close the room).
## - **By hand** (the main menu's Host, `online_host_requested`): CODE with this machine's code;
##   the code that comes back is given with `online_answer_requested`: LINKING.
## - **Joining** (`online_join_requested` with what the player typed or pasted): the first way
##   in whose handshake takes the text (a machine's code, by hand: CODE; anything else is for
##   the room's to take or refuse).
##
## Then, for each (`phase`, sent as `online_changed`):
##
## 1. **A link is there:** LINKED. Each machine first does what must be ready before a room
##    (`play_load_requested`: Flow's loading screen), since a load takes each its own time and
##    no machine may load inside a run another one plays. Only then is its session pumped: the
##    joining machine has its devices seated by the host (`NetClient.seat_devices`) and pings;
##    the host hears from READY_PINGS pings that it is ready.
## 2. **The run:** PLAYING. By hand, the host starts a sandbox, recorded, both machines from its
##    first tick. In a room, the joining machine is put into the hub the host is in: the host
##    records its hub (a hub that is not recorded yet, or was for longer than MAX_CATCH_UP ticks,
##    starts anew, recorded), and the joining machine plays the recording from its first tick
##    until it has caught up, then on, live. From the hub into a run and back is the game's own
##    doing, inside that recording. A machine that comes while the party is out of the hub
##    (`start_stone_changed` says where it is) is turned away: joining is in the hub only.
## 3. **While it plays** the frames service drives the sessions; this only calls their
##    `after_tick` on the Tick's `ticked`, sends the counters' line about once a second
##    (`online_line_changed`) and logs them (`NetLog`), and when a hash check fails says so once
##    and has this side's run saved as a replay (`Frames.save_run`).
## 4. **A guest machine gone:** its seats leave, as unplugged pads' do, and the others play on.
##    With the last one gone a party's room stays open (CODE again; the recording ends, so the
##    next machine joins a hub begun anew); by hand it is ENDED. The joining machine's replay ends once played out and its game
##    goes on alone, its devices where they sat: ENDED. **Given up** before the run
##    (`online_leave_requested`) or failed: OFF or FAILED.
##
## **A party takes up to three guest machines** (`NetHost.GUESTS`; L3), each joined to the hub's
## recording when it is ready, the others playing on meanwhile; a link past that is closed. A
## machine that joins a recording others already play catches up on all of it (the recording
## cannot begin anew under them). By hand it is one guest machine.
##
## It steps in its own `_physics_process` (never the simulation's: it reads the link and the
## engine's clock, and writes nothing the simulation reads but through the frames service). Tests
## set the services and the handshake makers before adding the node, and may step it by hand
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

## How a run by hand starts (one of `Replay.STARTS`): a sandbox, for its storms.
const START: StringName = &"sandbox_requested"
## How a party's recording starts: the hub.
const ROOM_START: StringName = &"hub_requested"
## The ways machines find each other (`_handshake_for`).
const BY_HAND: StringName = &"hand"
const THROUGH_ROOM: StringName = &"room"
## The ways tried for what a joining player typed, in order; the last is given what no other takes
## (and says why it is not its own either).
const JOIN_WAYS: Array[StringName] = [BY_HAND, THROUGH_ROOM]
## The client's pings the host hears before it starts the run: the client is loaded and has
## measured its ping (it pings twice a second).
const READY_PINGS: int = 3
## A hub recorded for longer than this (ten minutes) starts anew when a machine joins, so
## catching up on it never takes long.
const MAX_CATCH_UP: int = 36000
## The counters' line is sent, and their row logged, every this many physics steps of a run.
const LINE_EVERY: int = 60
const LOG_EVERY: int = 600

## The services. Only tests set these, before adding the node; otherwise the autoloads are used.
var events: EventsScript = null
var frames: FramesScript = null
var input: InputManagerScript = null
var tick: TickScript = null
## Make the handshake by hand, and the one through a room (each a `NetHandshake`); invalid:
## WebRTC's by pasted codes (`NetRtc`), and through the room server (`NetSignalHandshake`). Tests
## give their own.
var handshake_maker: Callable = Callable()
var room_handshake_maker: Callable = Callable()
## The game's areas by name, for the hash checks; invalid: the Tick's (`state_areas`).
var areas: Callable = Callable()

## Where things stand (see the top), with this machine's code (a room's, or its own by hand) and
## the note last sent. Read only.
var phase: StringName = OFF
var code: String = ""
var note: String = ""
## The session, from the first link until the other machines are gone: the host's (`NetHost`,
## with its guest machines) or the client's (`NetClient`). Read only.
var session: RefCounted:
	get:
		return _host if _host != null else _client

var _host: NetHost = null
var _client: NetClient = null
var _hosting: bool = false
## The host's: true for a party (its hub, joined a while in, open for the next machine when one
## leaves), false for one run two machines start together (a sandbox). Whatever the way in.
var _party: bool = false
var _handshake: NetHandshake = null
## The host's: the seat that asked, and the run it records (null: none).
var _starter: int = 0
var _replay: Replay = null
## True while the party is in the hub (`start_stone_changed`): where a machine may join.
var _in_lobby: bool = false
## True while the loading screen is up (`loading_started` to `loading_finished`).
var _loading: bool = false
## The joining machine's devices were handed to the host's seating.
var _seated: bool = false
## Physics steps of the run played.
var _steps: int = 0
var _parting_told: bool = false
## Why the last guest machine let go of was gone ("": its link just closed).
var _last_problem: String = ""
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
		push_warning("NetPlay: the Events, Frames or PlayerInput autoload is missing, so playing online does nothing.")
		return
	events.online_host_requested.connect(_on_host_requested)
	events.online_open_requested.connect(_on_open_requested)
	events.online_join_requested.connect(_on_join_requested)
	events.online_answer_requested.connect(_on_answer_requested)
	events.online_leave_requested.connect(_on_leave_requested)
	events.loading_started.connect(func() -> void: _loading = true)
	events.loading_finished.connect(func() -> void: _loading = false)
	events.start_stone_changed.connect(func(_standing: int, wizards: int, _lit: bool) -> void: _in_lobby = wizards > 0)
	frames.recorded_anew.connect(_on_recorded_anew)


func _physics_process(_delta: float) -> void:
	step()


## One physics step: the handshake moves on, the machines not in the run yet are heard until
## they are, and a run that plays is watched (see the top).
func step() -> void:
	if _handshake != null:
		_step_handshake()
	if _host != null:
		_step_host()
	elif _client != null and phase == LINKED:
		_step_client_before_run()
	elif _client != null and phase == PLAYING:
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


## The one place a way to find the other machine becomes a handshake.
func _handshake_for(way: StringName) -> NetHandshake:
	var maker: Callable = room_handshake_maker if way == THROUGH_ROOM else handshake_maker
	if maker.is_valid():
		return maker.call() as NetHandshake
	if way == THROUGH_ROOM:
		return NetSignalHandshake.new()
	return NetRtc.new()


func _on_host_requested(_player: int) -> void:
	if phase == OFF or phase == FAILED:
		_begin(true, false, _handshake_for(BY_HAND), "")


## What the player typed or pasted is given to the first way in whose handshake takes it; the
## last way is given what no other does, and says why it is not its own.
func _on_join_requested(_player: int, typed: String) -> void:
	if phase != OFF and phase != FAILED:
		return
	var found: NetHandshake = null
	for way in JOIN_WAYS:
		found = _handshake_for(way)
		if found.takes(typed):
			break
	_begin(false, false, found, typed)


## The altar: this party's room is opened; asked again, its code is said again.
func _on_open_requested(player: int) -> void:
	if _hosting and _party and phase == CODE:
		_show(CODE)
		events.online_line_changed.emit(_room_line())
		return
	# Not under a replay (one played back, or another machine's run): that party is not this one's.
	if frames.is_playing():
		return
	if phase == ENDED:
		phase = OFF
	if phase != OFF and phase != FAILED:
		return
	_starter = player
	_begin(true, true, _handshake_for(THROUGH_ROOM), "")


## Hosting or joining was asked for, through `handshake`: it begins.
func _begin(hosting: bool, party: bool, handshake: NetHandshake, typed: String) -> void:
	# Not after a run by hand either (ENDED): that run may still play here, and no new one
	# starts under it.
	if phase != OFF and phase != FAILED:
		return
	_hosting = hosting
	_party = party
	_seated = false
	_replay = null
	_handshake = handshake
	var why: String = _handshake.offer() if hosting else _handshake.take(typed)
	if why != "":
		_fail(why)
		return
	# A menu may be worked with the mouse by nobody who has joined: the keyboard plays, until a
	# gamepad wants the seat. (A joining machine's devices are seated by the host, once linked.)
	if hosting and input.joined_count() == 0:
		input.join(InputManagerScript.KEYBOARD, true)
	_show(MAKING)


func _on_answer_requested(_player: int, answer: String) -> void:
	if not _hosting or _party or phase != CODE or _handshake == null:
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
		if _host != null and not _host.guests.is_empty():
			# A room that closed under a run: the run plays on, and nobody else joins.
			_handshake = null
			code = ""
		else:
			_fail(_handshake.problem())
		return
	if phase == MAKING and _handshake.code() != "":
		code = _handshake.code()
		_show(CODE)
		if _party:
			events.online_line_changed.emit(_room_line())
	var link: NetLink = _handshake.next_link()
	if link == null:
		return
	if _hosting:
		if _host == null:
			_host = NetHost.new(frames, input, areas)
		# By hand the other machine's first player has its seat beforehand; a party's are asked for.
		if _host.add_guest(link, 0 if _party else 1 << NetHost.SEAT) == null:
			# As many machines as the host takes.
			link.close()
			return
		if not _party:
			# Two machines found each other: that handshake is done. A party's goes on, for the next.
			_handshake = null
	else:
		_handshake = null
		_client = NetClient.new(frames, link, areas, 1 << NetHost.SEAT, 2, -1, input)
	if phase != PLAYING:
		_show(LINKED)
	# Whatever must load before a room loads now, not inside a run.
	events.play_load_requested.emit()


## The host's step: the guest machines not in the run yet are turned away, or heard until they
## are ready and then joined to it; the run that plays is watched.
func _step_host() -> void:
	# Not while this machine loads: the others hear nothing from it until it is ready.
	if _loading:
		return
	for guest: NetGuest in _host.guests.duplicate():
		# A machine that comes while the party is out of the hub is turned away before anything
		# of its is read: it is given no seat, even for a moment.
		if _host != null and not guest.admitted and _party and not _in_lobby:
			_turn_away(guest, "a machine came while the party was out of the hub; joining is in the hub only")
	if _host == null:
		return
	_host.pump()
	for guest: NetGuest in _host.guests.duplicate():
		if _host == null or guest.admitted:
			continue
		if guest.problem != "":
			_turn_away(guest, "the link was closed: %s" % guest.problem)
		elif not guest.link.is_open():
			_turn_away(guest, "the other player left")
		elif guest.pings_heard >= READY_PINGS:
			# Before the run a guest sends only pings and its asks for seats: it is loaded.
			_admit(guest)
	if _host != null and phase == PLAYING:
		_step_run()


## The run that is recorded began anew (the party is back in its hub; the frames service's
## `recorded_anew`): when it is the party's, every guest machine in it is sent the new recording.
func _on_recorded_anew(replay: Replay) -> void:
	if _host == null or not _party or _host.replay == null or _host.replay != _replay:
		return
	_replay = replay
	_host.rebegin(replay)


## The guest machine `guest` is ready: it is joined to the run (by hand: the run starts).
func _admit(guest: NetGuest) -> void:
	if not _party:
		_replay = _host.start(START, 0)
		if _replay == null:
			_fail("seat %d is held by a device of this machine" % (NetHost.SEAT + 1))
			return
	else:
		if _host.replay == null:
			if _replay == null or frames.recorded() != _replay or _replay.tick_count() > MAX_CATCH_UP:
				# The hub begins anew, recorded: what the joining machine catches up on.
				_replay = frames.record(ROOM_START, _starter)
			_host.begin(_replay, false)
		if not _host.admit(guest):
			_turn_away(guest, "the other player left")
			return
	if phase != PLAYING:
		_steps = 0
		_parting_told = false
		_log.open(true)
		_show(PLAYING)


## A guest machine that is not in the run is let go, with a word on why: a party waits for the
## next (or plays on with the others); by hand it failed.
func _turn_away(guest: NetGuest, why: String) -> void:
	if not _party:
		_fail(why)
		return
	_host.remove_guest(guest)
	var said: String = why.substr(0, 1).to_upper() + why.substr(1) + "."
	if phase == PLAYING:
		# The others play on.
		note = said
		return
	if _host.guests.is_empty():
		_host.stop(true)
		_host = null
	_show(CODE if _handshake != null else OFF, said)


## A joining machine before its run: its devices are handed to the host's seating, it pings, and
## plays once the host's header has started its live replay.
func _step_client_before_run() -> void:
	# Not while this machine loads: the host hears nothing from it until it is ready.
	if _loading:
		return
	if not _seated:
		_seated = true
		_client.seat_devices()
	_client.pump()
	# A client whose run has started is playing, whatever came after the header (a link refused
	# then ends the run as any closed link does).
	if _client.problem != "" and not _client.started:
		_fail("the link was closed: %s" % _client.problem)
		return
	if not _client.started:
		if not _client.link.is_open():
			_fail("the host left, or its party cannot be joined right now")
		return
	_steps = 0
	_parting_told = false
	_log.open(false)
	_show(PLAYING)


func _step_run() -> void:
	_steps += 1
	if _parted_tick() >= 0 and not _parting_told:
		_parting_told = true
		_tell_parting()
	var over: bool
	if _hosting:
		# A guest machine that is gone is let go (between ticks, as a pad is pulled out): its
		# seats leave. The others play on.
		for guest: NetGuest in _host.guests.duplicate():
			if guest.admitted and not guest.hears():
				_last_problem = guest.problem
				_host.remove_guest(guest)
		over = _admitted() == 0
	else:
		over = not _client.is_playing()
	if over or _steps % LOG_EVERY == 0:
		_log.row(_stats().row())
	if over:
		_end()
	elif _steps % LINE_EVERY == 0:
		events.online_line_changed.emit(_line())


## The guest machines in the run.
func _admitted() -> int:
	var count: int = 0
	for guest in _host.guests:
		count += 1 if guest.admitted else 0
	return count


## The session's counters: the client's, or the host's with its guests' added up.
func _stats() -> NetStats:
	return _host.totals() if _host != null else _client.stats


func _parted_tick() -> int:
	return _host.parted_tick if _host != null else _client.parted_tick


func _parted_areas() -> PackedStringArray:
	return _host.parted_areas if _host != null else _client.parted_areas


## The first hash check that failed: said once, and this side's run saved for the tools (the
## frames service holds the run and writes the file; a client whose replay ended in this very
## step has none on the deck any more, and the row then names no file).
func _tell_parting() -> void:
	var saved_as: String = "online_host_parted" if _hosting else "online_client_parted"
	var saved: bool = frames.save_run(saved_as) == OK
	var row: Dictionary = {"parted_tick": _parted_tick(), "parted_areas": _parted_areas(), "replay": saved_as if saved else ""}
	_log.row(row)
	print("NetPlay: the machines parted at tick %d in %s%s" % [_parted_tick(), ", ".join(_parted_areas()), "; this side's run is saved as the replay %s" % saved_as if saved else ""])


func _line() -> String:
	var line: String = _stats().line()
	if _parted_tick() >= 0:
		line = "PARTED at tick %d (%s). %s" % [_parted_tick(), ", ".join(_parted_areas()), line]
	if _client != null and _client.is_catching_up():
		line = "Catching up with the host. %s" % line
	if _hosting and _party and code != "":
		line = "Room %s, %d machine(s) joined. %s" % [code, _admitted(), line]
	return line


## What a room's host shows while nobody has joined.
func _room_line() -> String:
	return "Online room %s: the code other machines join by." % code


## The other machines are gone from a run that played.
func _end() -> void:
	var why: String = _client.problem if _client != null else _last_problem
	_last_problem = ""
	_log.close()
	if _hosting and _party:
		# Their seats left; the party plays on, unrecorded, and the next machine joins a hub begun anew.
		_host.stop(true)
		_host = null
		if _replay != null and frames.recorded() == _replay:
			frames.stop_recording()
		_replay = null
		if _handshake != null:
			_show(CODE, "The other machines left; the room is still open.")
			events.online_line_changed.emit(_room_line())
		else:
			code = ""
			_show(ENDED, "The other machines left, and the room is closed; the party plays on here.")
			events.online_line_changed.emit("")
		return
	if _hosting:
		# The client's seats leave and the recording ends; the run plays on.
		_host.stop()
		_host = null
		_replay = null
	else:
		# Its devices stay on the seats they play on, and seat themselves again from now on.
		_client.release_devices()
		_client = null
	var gone: String = "The other player left; the run plays on here." if _hosting else "The host left; the run plays on here, alone."
	_show(ENDED, gone if why == "" else "%s (The link was closed: %s.)" % [gone, why])


func _fail(why: String) -> void:
	if _hosting and _party and code != "":
		# The room's line goes with the room.
		events.online_line_changed.emit("")
	_let_go()
	code = ""
	_show(FAILED, why.substr(0, 1).to_upper() + why.substr(1) + ".")


## The handshake and a session whose run never began are closed, and a joining machine's devices
## seat themselves again.
func _let_go() -> void:
	if _handshake != null:
		_handshake.close()
		_handshake = null
	if _host != null:
		_host.stop(_party)
		_host = null
	if _client != null:
		_client.link.close()
		_client.release_devices(true)
		_client = null


func _show(now: StringName, with_note: String = "") -> void:
	phase = now
	note = with_note
	events.online_changed.emit(phase, code, note)
