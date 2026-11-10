class_name NetHost
extends RefCounted
## The host's side of an online run (netcode spike S2; online lobby L2 and L3,
## docs/milestones/online-lobby.md): the host records its run and every recorded tick goes out to
## each guest machine; each guest's seats are virtual devices here whose frames come from that
## guest's link (`NetGuest`). The host never waits, for any of them.
##
## - **`add_guest`** takes a guest machine's link, before the run or in it: up to GUESTS machines.
##   Each guest is its own `NetGuest`, with its own seats, limits, checks and counters; a guest
##   never hears of another. Its seats are the host's to give: asked for by the guest and given
##   between ticks (`NetGuest`), or named beforehand (`seats`, before the run: Host and Join by
##   code), then seated when the run starts.
## - **`start`** starts a run recorded (`Frames.record`), with every guest's seats named
##   beforehand seated, and joins every guest to it. **`begin(run)`** takes a run that is recorded
##   already (a party's hub) and joins every guest to it; **`admit(guest)`** joins one that came
##   later. A guest joined to a run gets the lobby (its seats), the header, then every tick from
##   the first: what was recorded before at most SEND_A_TICK a tick, so its link never holds
##   more than it reads, then each new one as it is made.
## - **`after_tick`**, called after every tick has stepped, answers the guests' asks for seats
##   (between ticks, never while a tick's frames are built), sends the ticks not sent yet (the
##   newest tick's message made once for all) and hashes the tick's part of the state, once for
##   every guest; the host's checks are kept for the guests' to be compared with (`NetGuest`), up
##   to MAX_CHECKS_KEPT. A run joined in the middle of a check's window is checked from the next.
## - **`pump`**, called every physics step by whoever holds the host, reads the guests not joined
##   to the run yet (their pings, their asks) and answers their asks. A guest in the run is read
##   when its seats' frames are built, or after the tick with no seat. No `_process`, no thread.
## - **A guest gone** (its link closed, or refused): its seats leave and the others play on.
##   `remove_guest` lets it go for good. All gone, the run plays on here alone.
##
##     var host := NetHost.new(Frames, PlayerInput, Tick.state_areas)
##     var guest: NetGuest = host.add_guest(link)
##     host.begin(replay)    # the run Frames.record returned; or: host.start(&"sandbox_requested", 0)
##     ...  # every physics step: host.pump(); after every tick: host.after_tick()

const FramesScript := preload("res://core/sim/frames.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

## The guest's seat in Host and Join by code (one guest machine, one seat).
const SEAT: int = 1
## The most guest machines.
const GUESTS: int = 3
## The host's checks kept until the guests' arrive (they play behind the host).
const MAX_CHECKS_KEPT: int = 32
## The most ticks sent to a guest after one tick: one that joined a run under way is sent what
## was recorded before at this pace.
const SEND_A_TICK: int = 240


## A guest's seat's source: the host, held weakly (the frames service holds the source, the
## session holds the frames service), and the seat.
class Source:
	extends FrameSource
	var host: WeakRef = null
	var seat: int = 0

	func fill_frame(frame: InputFrame, _delta: float) -> void:
		var session: NetHost = host.get_ref() as NetHost if host != null else null
		if session != null:
			session.fill_seat(seat, frame)


var frames: FramesScript
var input: InputManagerScript
## The game's areas by name (`Tick.state_areas`), for the checks; invalid: no checks.
var areas: Callable
## The host's own work: the ticks recorded and the time hashing them. Each guest counts its own.
var stats: NetStats = NetStats.new()
var checks: NetChecks = NetChecks.new()
## The run recorded (null before the run).
var replay: Replay = null
## The guest machines, in the order they came. Read only.
var guests: Array[NetGuest] = []
## The first check of any guest that failed (the guests', in their order): its tick (-1: none) and
## the areas that differed.
var parted_tick: int:
	get:
		var parted: NetGuest = _parted()
		return parted.parted_tick if parted != null else -1
var parted_areas: PackedStringArray:
	get:
		var parted: NetGuest = _parted()
		return parted.parted_areas if parted != null else PackedStringArray()

var _sources: Array[Source] = []
## The host's own checks by tick, shared with every guest.
var _kept: Dictionary[int, Dictionary] = {}
## The first tick hashed for the checks (a whole window from there on).
var _check_from: int = 0
## The last tick's message made, and its tick (-1: none).
var _made: PackedByteArray = PackedByteArray()
var _made_tick: int = -1


func _init(frames_service: FramesScript, input_layer: InputManagerScript, state_areas: Callable = Callable()) -> void:
	frames = frames_service
	input = input_layer
	areas = state_areas
	for seat in Replay.SEATS:
		var source := Source.new()
		source.host = weakref(self)
		source.seat = seat
		_sources.append(source)


## A guest machine on `over`. `seats` (a bit each; before the run only): seats named beforehand
## for its first players, seated when the run starts. Returns its `NetGuest`, or null (and the
## link is left as it is) when there are GUESTS already, or `seats` are given in a run, name seat
## 0 (the host's) or a seat another guest was named.
func add_guest(over: NetLink, seats: int = 0) -> NetGuest:
	if guests.size() >= GUESTS:
		return null
	if seats != 0 and (replay != null or seats & ~0x0e != 0 or seats & guest_seats() != 0):
		return null
	var guest := NetGuest.new(frames, input, over, seats, areas)
	guest.checks = checks
	guest.kept = _kept
	guest.sources.assign(_sources)
	guests.append(guest)
	return guest


## Let `guest` go for good: its link closes and its seats leave. Call it between ticks.
func remove_guest(guest: NetGuest) -> void:
	if not guests.has(guest):
		return
	guest.link.close()
	for seat in Replay.SEATS:
		guest.take_back(seat)
	guests.erase(guest)


## The seats the guests play (a bit each).
func guest_seats() -> int:
	var mask: int = 0
	for guest in guests:
		mask |= guest.seats
	return mask


## Read what the guests not joined to the run yet sent (their pings, their asks for seats), and
## answer their asks. Whoever holds the host calls it every physics step, between ticks.
func pump() -> void:
	for guest in guests:
		if not guest.admitted:
			guest.pump()
			guest.answer_asks()


## Start the run by `start_by` (one of `Replay.STARTS`) for seat `starter`, recorded, with every
## guest's seats named beforehand seated, and join every guest to it. Returns the replay it
## records into, or null (and nothing starts) when a run was begun already, there is no guest, a
## guest cannot be heard, or a seat named for a guest is held by a device of this machine.
func start(start_by: StringName, starter: int = 0, run_seed: int = 0) -> Replay:
	if replay != null or guests.is_empty():
		return null
	for guest in guests:
		if not guest.hears():
			return null
		for seat in Replay.SEATS:
			if guest.owns(seat) and input.is_joined(seat) and not InputManagerScript.is_virtual(input.device_of(seat)):
				return null
	for guest in guests:
		for seat in Replay.SEATS:
			if guest.owns(seat):
				guest.seat_one(seat, true)
				frames.set_source(seat, _sources[seat])
	var run: Replay = frames.record(start_by, starter, run_seed)
	return run if begin(run) else null


## Take `run`, which the frames service records (from its first tick, or a while in), as this
## host's run, and join every guest there is to it (unless `admit_all` is false: whoever holds the
## host then admits each when it is ready). False, and nothing happens, when a run was begun
## already or `run` is none.
func begin(run: Replay, admit_all: bool = true) -> bool:
	if replay != null or run == null:
		return false
	replay = run
	stats.ticks = run.tick_count()
	_check_from = ceili(float(run.tick_count()) / checks.every) * checks.every
	if admit_all:
		for guest in guests:
			admit(guest)
	return true


## Join `guest` to the run: the lobby (its seats: it knows which are its own before the run
## seats anybody), the header, and from the next tick's end every tick from the first. False when
## there is no run, it is joined already, or it cannot be heard.
func admit(guest: NetGuest) -> bool:
	if replay == null or guest.admitted or not guests.has(guest) or not guest.hears():
		return false
	guest.replay = replay
	guest.checks = checks
	guest.check_from = _check_from
	guest.admitted = true
	guest.sent_ticks = 0
	guest.send_lobby()
	guest.send(NetMessage.of_header(replay.header_bytes()))
	return true


## End the session: every guest's seats leave, their links close. The recording stops too, unless
## `keep_recording` (a run that plays on, and may be joined again). Returns the run so far (null
## when none was begun).
func stop(keep_recording: bool = false) -> Replay:
	for guest in guests.duplicate():
		remove_guest(guest)
	if replay != null and not keep_recording and frames.is_recording():
		frames.stop_recording()
	return replay


## True while the run it began is recorded.
func is_running() -> bool:
	return replay != null and frames.is_recording()


## True while any guest can still be heard.
func hears_guests() -> bool:
	for guest in guests:
		if guest.hears():
			return true
	return false


## A guest's seat's frame for the tick being built (the frames service asks, through the seat's
## source; `frame` comes cleared).
func fill_seat(seat: int, frame: InputFrame) -> void:
	if not is_running():
		return
	for guest in guests:
		if guest.owns(seat):
			guest.fill_seat(seat, frame, replay.tick_count())
			return


func after_tick() -> void:
	if not is_running():
		return
	var count: int = replay.tick_count()
	var began: int = Time.get_ticks_usec()
	for guest in guests:
		if not guest.admitted:
			continue
		# Nothing asked it for a frame this tick (it has no seat): its link is read here.
		guest.read_for(count - 1)
		# Between ticks: the asks read while the tick's frames were built.
		guest.answer_asks()
		var until: int = mini(count, guest.sent_ticks + SEND_A_TICK)
		while guest.sent_ticks < until and guest.hears():
			guest.send_tick(_tick_message(guest.sent_ticks))
	stats.ticks = count
	stats.net_usec += Time.get_ticks_usec() - began
	var tick: int = count - 1
	if not areas.is_valid() or tick < _check_from:
		return
	began = Time.get_ticks_usec()
	var check: Dictionary[String, int] = checks.add(tick, areas.call())
	stats.hash_usec += Time.get_ticks_usec() - began
	if check.is_empty():
		return
	_kept[tick] = check
	if _kept.size() > MAX_CHECKS_KEPT:
		# The oldest goes (a dictionary keeps the order they were added in); a guest still to send
		# its check of that tick goes unchecked.
		for oldest: int in _kept:
			_kept.erase(oldest)
			for guest in guests:
				if guest.checked_to < oldest and guest.hears():
					guest.stats.unchecked += 1
			break


## Tick `tick`'s message: the newest tick's is made once, for every guest that is up to date.
func _tick_message(tick: int) -> PackedByteArray:
	if tick != _made_tick:
		_made_tick = tick
		_made = NetMessage.of_tick(tick, replay.tick_bytes(tick))
	return _made


## The guest whose check failed first (the earliest tick), or null.
func _parted() -> NetGuest:
	var first: NetGuest = null
	for guest in guests:
		if guest.parted_tick >= 0 and (first == null or guest.parted_tick < first.parted_tick):
			first = guest
	return first


## The guests' counters added up, with the host's own (a line for the screen, a log's row).
func totals() -> NetStats:
	var sum := NetStats.new()
	sum.ticks = stats.ticks
	sum.hash_usec = stats.hash_usec
	for guest in guests:
		var of: NetStats = guest.stats
		sum.sent += of.sent
		sum.sent_bytes += of.sent_bytes
		sum.read += of.read
		sum.read_bytes += of.read_bytes
		sum.stood_in += of.stood_in
		sum.late_frames += of.late_frames
		sum.checks += of.checks
		sum.mismatches += of.mismatches
		sum.unchecked += of.unchecked
		sum.net_usec += of.net_usec
	return sum
