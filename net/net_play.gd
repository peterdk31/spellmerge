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
##    (`hub_changed` says where it is) is turned away: joining is in the hub only.
## 3. **While it plays** the frames service drives the sessions; this only calls the run's
##    `after_tick` on the Tick's `ticked`, sends the line's facts and the counters about once a
##    second (`online_line_changed`) and logs them (`NetLog`), and when a hash check fails says so
##    once and has this side's run saved as a replay (`Frames.save_run`).
## 4. **A guest machine gone:** its seats leave, as unplugged pads' do, and the others play on.
##    With the last one gone a party's room stays open (CODE again; the recording ends, so the
##    next machine joins a hub begun anew); by hand it is ENDED. The joining machine's replay ends once played out and its game
##    goes on alone, its devices where they sat: ENDED. **Given up** before the run
##    (`online_leave_requested`) or failed: OFF or FAILED.
## 5. **Back to the main menu** (`main_menu_requested`, from any phase): everything is let go, as if
##    this machine had gone: OFF, ready to host or join again.
##
## **Why, never in words** (online lobby L5b): whatever did not work, or ended, leaves here as a
## name of `OnlineWhy` and its few facts (`online_changed`'s `reason` and `facts`; the line's facts),
## taken from the handshake (`NetWhy`) or the session (`NetSession.reason`) unread. The HUD words
## them; the words net/ has for the same (`NetWhy.text`, a session's `problem`) go to the output
## and the log only. **A machine that is linked and never ready** (it sends nothing, or the host
## never starts it) is let go after READY_S seconds of this machine's own stepping, loads not
## counted: NOT_READY.
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
## A machine that is linked is ready to play within this many seconds (the host: its pings heard;
## the joining machine: the host's run begun), or it is let go. Far longer than any load: the
## first room's shaders take a slow machine a quarter of a minute.
const READY_S: int = 90

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
## The physics steps a linked machine is given to be ready (READY_S of them; a test's own).
var ready_steps: int = READY_S * Engine.physics_ticks_per_second

## Where things stand (see the top), with this machine's code (a room's, or its own by hand) and
## why, as last said: a name of `OnlineWhy` (&"": nothing to say) and its facts. Read only.
var phase: StringName = OFF
var code: String = ""
var reason: StringName = &""
var facts: Dictionary = {}
## The session, from the first link until the other machines are gone: the host's (`NetHost`,
## with its guest machines) or the client's (`NetClient`). Read only.
var session: NetRun:
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
## True while the party is in the hub (`hub_changed`): where a machine may join.
var _in_lobby: bool = false
## True while the loading screen is up (`loading_started` to `loading_finished`).
var _loading: bool = false
## The joining machine's devices were handed to the host's seating.
var _seated: bool = false
## The joining machine: the physics steps it has waited, linked and loaded, for the host's run.
var _waited: int = 0
## Physics steps of the run played.
var _steps: int = 0
var _parting_told: bool = false
## Why the last guest machine let go of was gone (null: its link just closed).
var _last_why: NetWhy = null
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
	events.main_menu_requested.connect(_on_main_menu_requested)
	events.loading_started.connect(func() -> void: _loading = true)
	events.loading_finished.connect(func() -> void: _loading = false)
	events.hub_changed.connect(func(in_hub: bool) -> void: _in_lobby = in_hub)
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
	if phase == PLAYING and session != null:
		session.after_tick()


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
		_say_room()
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
	_waited = 0
	_replay = null
	_handshake = handshake
	var why: NetWhy = _handshake.offer() if hosting else _handshake.take(typed)
	if why != null:
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
	var why: NetWhy = _handshake.take(answer)
	if _handshake.problem() != null:
		# WebRTC itself refused it: this machine's own code is spent too.
		_fail(_handshake.problem())
	elif why != null:
		# That code was not taken; the player may give another.
		_show(CODE, why)
	else:
		_show(LINKING)


func _on_leave_requested(_player: int) -> void:
	if phase == PLAYING or phase == ENDED or phase == OFF:
		return
	_let_go()
	_show(OFF)


## This machine goes back to the main menu (`main_menu_requested`), whatever it plays: everything
## online is let go at once, so the other machines see it leave (its link closes: a guest's seats
## leave the host's game; a host's guests' replays end, and its room closes), and the machine may
## host or join again from the menu.
func _on_main_menu_requested(_player: int) -> void:
	if phase == OFF:
		return
	if phase == PLAYING and session != null:
		_log.row(session.counters().row())
	_log.close()
	_let_go()
	_last_why = null
	_say_line()
	_show(OFF)


func _step_handshake() -> void:
	_handshake.poll()
	if _handshake.problem() != null:
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
			_say_room()
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
			_turn_away(guest, NetWhy.new(OnlineWhy.OUT_OF_HUB, "a machine came while the party was out of the hub; joining is in the hub only"))
	if _host == null:
		return
	_host.pump()
	for guest: NetGuest in _host.guests.duplicate():
		if _host == null or guest.admitted:
			continue
		guest.waited += 1
		if guest.problem != "":
			_turn_away(guest, _why_closed(guest))
		elif not guest.link.is_open():
			_turn_away(guest, NetWhy.new(OnlineWhy.LEFT, "the other player left"))
		elif guest.pings_heard >= READY_PINGS:
			# Before the run a guest sends only pings and its asks for seats: it is loaded.
			_admit(guest)
		elif guest.waited >= ready_steps:
			_turn_away(guest, _not_ready("the other machine"))
	if _host != null and phase == PLAYING:
		_step_run()


## The run that is recorded began anew (the party is back in its hub; the frames service's
## `recorded_anew`): when it is the party's, every guest machine in it is sent the new recording.
func _on_recorded_anew(replay: Replay) -> void:
	if _host == null or not _party or _host.replay == null or _host.replay != _replay:
		return
	_replay = replay
	var before: Array[NetGuest] = _host.guests.duplicate()
	_host.rebegin(replay)
	for guest in before:
		if not _host.guests.has(guest) and guest.problem != "":
			# Let go by the host's session (too far behind the run before): kept here and told to
			# the output, as a machine turned away while the others play is.
			var why: NetWhy = _why_closed(guest)
			_tell(why)
			reason = why.name
			facts = why.facts


## The guest machine `guest` is ready: it is joined to the run (by hand: the run starts).
func _admit(guest: NetGuest) -> void:
	if not _party:
		_replay = _host.start(START, 0)
		if _replay == null:
			_fail(NetWhy.new(OnlineWhy.SEAT_HELD, "seat %d is held by a device of this machine" % (NetHost.SEAT + 1), {OnlineWhy.SEAT: NetHost.SEAT + 1}))
			return
	else:
		if _host.replay == null:
			if _replay == null or frames.recorded() != _replay or _replay.tick_count() > MAX_CATCH_UP:
				# The hub begins anew, recorded: what the joining machine catches up on.
				_replay = frames.record(ROOM_START, _starter)
			_host.begin(_replay, false)
		if not _host.admit(guest):
			_turn_away(guest, NetWhy.new(OnlineWhy.LEFT, "the other player left"))
			return
	if phase != PLAYING:
		_steps = 0
		_parting_told = false
		_log.open(true)
		_show(PLAYING)


## A guest machine that is not in the run is let go, and why is said: a party waits for the
## next (or plays on with the others); by hand it failed.
func _turn_away(guest: NetGuest, why: NetWhy) -> void:
	if not _party:
		_fail(why)
		return
	_host.remove_guest(guest)
	_tell(why)
	if phase == PLAYING:
		# The others play on, and nothing changed for them: it is only kept here.
		reason = why.name
		facts = why.facts
		return
	if _host.guests.is_empty():
		_host.stop(true)
		_host = null
	_show(CODE if _handshake != null else OFF, why)


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
	_waited += 1
	# A client whose run has started is playing, whatever came after the header (a link refused
	# then ends the run as any closed link does).
	if _client.problem != "" and not _client.started:
		_fail(_why_closed(_client))
		return
	if not _client.started:
		if not _client.link.is_open():
			_fail(NetWhy.new(OnlineWhy.TURNED_AWAY, "the host left, or its party cannot be joined right now"))
		elif _waited >= ready_steps:
			_fail(_not_ready("the host"))
		return
	_steps = 0
	_parting_told = false
	_log.open(false)
	_show(PLAYING)


func _step_run() -> void:
	_steps += 1
	if session.parted_at() >= 0 and not _parting_told:
		_parting_told = true
		_tell_parting()
	var over: bool
	if _hosting:
		# A guest machine that is gone is let go (between ticks, as a pad is pulled out): its
		# seats leave. The others play on.
		for guest: NetGuest in _host.guests.duplicate():
			if guest.admitted and not guest.hears():
				_last_why = _why_closed(guest)
				_host.remove_guest(guest)
		# Not while a machine still waits to be joined: it is joined to this run when ready.
		over = _host.guests.is_empty()
	else:
		over = not _client.is_playing()
	if over or _steps % LOG_EVERY == 0:
		_log.row(session.counters().row())
	if over:
		_end()
	elif _steps % LINE_EVERY == 0:
		_say_line(_line_facts(), session.counters().line())


## The guest machines in the run.
func _admitted() -> int:
	var count: int = 0
	for guest in _host.guests:
		count += 1 if guest.admitted else 0
	return count


## Why `of` closed its link, from what the session says (null: it did not; the link just closed).
func _why_closed(of: NetSession) -> NetWhy:
	if of.problem == "":
		return null
	var named: StringName = of.reason if of.reason != &"" else OnlineWhy.LINK_REFUSED
	var with: Dictionary = {OnlineWhy.SECONDS: NetSession.SILENT_MS / 1000} if named == OnlineWhy.SILENT else {}
	return NetWhy.new(named, "the link was closed: %s" % of.problem, with)


func _not_ready(who: String) -> NetWhy:
	return NetWhy.new(OnlineWhy.NOT_READY, "%s was not ready to play within %d seconds" % [who, READY_S], {OnlineWhy.SECONDS: READY_S})


## The first hash check that failed: said once, and this side's run saved for the tools (the
## frames service holds the run and writes the file; a client whose replay ended in this very
## step has none on the deck any more, and the row then names no file).
func _tell_parting() -> void:
	var saved_as: String = "online_host_parted" if _hosting else "online_client_parted"
	var saved: bool = frames.save_run(saved_as) == OK
	var row: Dictionary = {"parted_tick": session.parted_at(), "parted_areas": session.parted_in(), "replay": saved_as if saved else ""}
	_log.row(row)
	print("NetPlay: the machines parted at tick %d in %s%s" % [session.parted_at(), ", ".join(session.parted_in()), "; this side's run is saved as the replay %s" % saved_as if saved else ""])


## What the line says of the run beside its counters, as facts (`OnlineWhy`'s LINE_ keys).
func _line_facts() -> Dictionary:
	var said: Dictionary = {}
	if session.parted_at() >= 0:
		said[OnlineWhy.LINE_PARTED_TICK] = session.parted_at()
		if _hosting:
			# The host's names are its own. A joining machine's came off the wire (the host's
			# PARTED): they go to its log, never to its screen.
			said[OnlineWhy.LINE_PARTED_AREAS] = session.parted_in()
	if _client != null and _client.is_catching_up():
		said[OnlineWhy.LINE_CATCHING_UP] = true
	if _hosting and _party and code != "":
		said[OnlineWhy.LINE_ROOM] = code
		said[OnlineWhy.LINE_JOINED] = _admitted()
	return said


func _say_line(said: Dictionary = {}, counters: String = "") -> void:
	events.online_line_changed.emit(said, counters)


## What a room's host shows while nobody has joined: the room's code.
func _say_room() -> void:
	_say_line({OnlineWhy.LINE_ROOM: code})


## The other machines are gone from a run that played.
func _end() -> void:
	var after: NetWhy = _why_closed(_client) if _client != null else _last_why
	_last_why = null
	_log.close()
	if _hosting and _party:
		# Their seats left; the party plays on, unrecorded, and the next machine joins a hub begun anew.
		_host.stop(true)
		_host = null
		if _replay != null and frames.recorded() == _replay:
			frames.stop_recording()
		_replay = null
		if _handshake != null:
			_show(CODE, NetWhy.new(OnlineWhy.PARTY_LEFT_OPEN, "the other machines left; the room is still open"))
			_say_room()
		else:
			code = ""
			_show(ENDED, NetWhy.new(OnlineWhy.PARTY_LEFT_CLOSED, "the other machines left, and the room is closed"))
			_say_line()
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
	# The counters of a run that is over say nothing true any more.
	_say_line()
	# Why their link closed goes along, with its own facts.
	var with: Dictionary = {}
	if after != null:
		with = after.facts.duplicate()
		with[OnlineWhy.AFTER] = after.name
		_tell(after)
	_show(ENDED, NetWhy.new(OnlineWhy.GUEST_LEFT if _hosting else OnlineWhy.HOST_LEFT, "the other machine left", with))


func _fail(why: NetWhy) -> void:
	if _hosting and _party and code != "":
		# The room's line goes with the room.
		_say_line()
	_let_go()
	_tell(why)
	_show(FAILED, why)


## What net/ has in words for `why` goes to the output: never to the screen.
func _tell(why: NetWhy) -> void:
	print("NetPlay: %s (%s)" % [why.text, why.name])


## The handshake and the session are closed, the code and the run recorded forgotten, and a
## joining machine's devices seat themselves again.
func _let_go() -> void:
	code = ""
	_replay = null
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


## The phase is `now`, said on the bus with why (null: nothing to say).
func _show(now: StringName, why: NetWhy = null) -> void:
	phase = now
	reason = why.name if why != null else &""
	facts = why.facts if why != null else {}
	events.online_changed.emit(phase, code, reason, facts)
