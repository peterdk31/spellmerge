class_name NetHost
extends RefCounted
## The host's side of an online run (netcode spike S2; online lobby L3,
## docs/milestones/online-lobby.md): the host records its run and every recorded tick goes out to
## each guest machine as it is made; each guest's seats are virtual devices here whose frames come
## from that guest's link (`NetGuest`). The host never waits, for any of them.
##
## - **`add_guest`** takes a guest machine's link and the seats it plays (a bit each), before the
##   run: up to GUESTS machines, no seat given twice. Each guest is its own `NetGuest`, with its own
##   limits, checks and counters; a guest never hears of another.
## - **`start`** seats every guest's seats (virtual devices joined through the input layer, as pads
##   would be, so the frames service seats them and the recording knows), makes each seat's source
##   its guest's, starts the run recorded (`Frames.record`) and sends the header to every guest.
## - **`after_tick`**, called after every tick has stepped, sends the ticks recorded since to every
##   guest (each tick's message made once) and hashes the tick's part of the state; the host's
##   checks are kept for the guests' to be compared with (`NetGuest`), up to MAX_CHECKS_KEPT.
## - **`pump`**, before the run, reads every guest (their pings). In the run each guest's link is
##   read when its seats' frames are built. No `_process`, no thread.
## - **A guest gone** (its link closed, or refused): its seats leave and the others play on. All
##   gone, the run plays on here alone.
##
##     var host := NetHost.new(Frames, PlayerInput, Tick.state_areas)
##     host.add_guest(link, 1 << NetHost.SEAT)
##     host.start(&"sandbox_requested", 0)
##     ...  # after every tick: host.after_tick()

const FramesScript := preload("res://core/sim/frames.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

## The guest's seat in Host and Join by code (one guest machine, one seat).
const SEAT: int = 1
## The most guest machines.
const GUESTS: int = 3
## The host's checks kept until the guests' arrive (they play behind the host).
const MAX_CHECKS_KEPT: int = 32


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


func _init(frames_service: FramesScript, input_layer: InputManagerScript, state_areas: Callable = Callable()) -> void:
	frames = frames_service
	input = input_layer
	areas = state_areas
	for seat in Replay.SEATS:
		var source := Source.new()
		source.host = weakref(self)
		source.seat = seat
		_sources.append(source)


## A guest machine on `over`, playing `seats` (a bit each), before the run. Returns its
## `NetGuest`, or null (and the link is left as it is) when the run has started, there are GUESTS
## already, it plays no seat, seat 0 (the host's), or a seat another guest plays.
func add_guest(over: NetLink, seats: int) -> NetGuest:
	if replay != null or guests.size() >= GUESTS:
		return null
	if seats & 0x0f == 0 or seats & ~0x0e != 0 or seats & guest_seats() != 0:
		return null
	var guest := NetGuest.new(frames, input, over, seats, areas)
	guest.checks = checks
	guest.kept = _kept
	guests.append(guest)
	return guest


## The seats the guests play (a bit each).
func guest_seats() -> int:
	var mask: int = 0
	for guest in guests:
		mask |= guest.seats
	return mask


## Read what every guest sent (before the run: their pings).
func pump() -> void:
	for guest in guests:
		guest.pump()


## Start the run by `start_by` (one of `Replay.STARTS`) for seat `starter`, recorded, with every
## guest's seats seated, and send its header to each. Returns the replay it records into, or null
## (and nothing starts) when it has started already, there is no guest, a guest cannot be heard, or
## a guest's seat is held by a device of this machine.
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
	replay = frames.record(start_by, starter, run_seed)
	var header: PackedByteArray = NetMessage.of_header(replay.header_bytes())
	for guest in guests:
		guest.replay = replay
		guest.checks = checks
		guest.send(header)
	return replay


## End the session: every guest's seats leave, their links close. Returns the run recorded so far
## (null when none was started).
func stop() -> Replay:
	for guest in guests:
		guest.link.close()
	if replay == null:
		return null
	for guest in guests:
		for seat in Replay.SEATS:
			if guest.owns(seat):
				if frames.source_of(seat) == _sources[seat]:
					frames.set_source(seat, null)
				guest.seat_one(seat, false)
	if frames.is_recording():
		frames.stop_recording()
	return replay


## True while the run it started is recorded.
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
	# Each tick's message is made once, for every guest (all of them got the header at the start,
	# so all are at the same tick).
	while stats.ticks < count:
		var message: PackedByteArray = NetMessage.of_tick(stats.ticks, replay.tick_bytes(stats.ticks))
		for guest in guests:
			guest.send_tick(message)
		stats.ticks += 1
	if not areas.is_valid():
		return
	var tick: int = count - 1
	var began: int = Time.get_ticks_usec()
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
