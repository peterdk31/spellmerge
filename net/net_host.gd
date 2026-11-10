class_name NetHost
extends NetSession
## The host's side of an online run (netcode spike S2, docs/milestones/netcode-spike.md; several
## seats a machine since online lobby L2, docs/milestones/online-lobby.md): the host records its
## run, each of the other machine's seats is a virtual device whose frames come from the link,
## and every recorded tick goes out. The host never waits.
##
## - **Seats are the host's to give.** The other machine asks for one for each of its players
##   (SEAT_ASK, naming the player by a number of its own, never a device). The host gives the
##   lowest seat nobody holds: a virtual device joins it through the input layer, as a pad would
##   (so the frames service seats it and the recording knows, at the same tick on every machine),
##   and the seat's frames come from this session. Every ask is answered with the LOBBY: which of
##   that machine's players holds which seat. With no seat free the answer gives none. **A seat
##   is only ever given between ticks** (an ask read while a tick's frames are being built waits
##   for `after_tick`), as a pad joins between ticks: given in the middle, a seat whose frame for
##   the tick is built already would be seated on the host a tick before the recording says so.
## - **`begin(run)`** joins a run that is recorded already (the hub, a while in): the header goes
##   out, then every tick recorded so far, at most SEND_A_TICK a tick, then each new one as it is
##   made. **`start`** starts a run recorded, with seat SEAT given to the other machine's first
##   player beforehand (the spike's Host and Join), and begins it.
## - **The client's frames** each name their seat and the host's tick they are for. When a
##   seat's frame is built for a tick, every frame that arrived for that tick or an earlier one
##   is used up: the walk, the aim and the buttons held are the newest's, the presses and the
##   commands are all of theirs, in order. **A frame that has not arrived** is stood in for by
##   the last one without its presses and commands (a button held stays held; a command never
##   applies twice), and its own presses and commands come with the next frame used. Commands
##   that do not fit the tick's frame (its count, its bytes) wait for the next.
## - **A seat is given back** when its player leaves (a LEAVE in its frame) or the other machine
##   is gone: the virtual device leaves through the input layer, so the wizard leaves as an
##   unplugged pad's does. A JOIN in a frame seats nobody: only an ask does.
## - **`after_tick`**, called after every tick has stepped, sends the ticks not sent yet and
##   hashes the tick's part of the state. The client's check is compared with the host's own of
##   the same tick; where they differ the client is told (`NetSession`: `parted_tick`). A run
##   joined in the middle of a check's window is checked from the next window on.
## - **The link is read** once a tick (when the first of the client's seats is asked for its
##   frame, or after the tick with none), and, before the run, by `pump` from whoever holds the
##   session. No `_process`, no thread.
##
## What the client sends is untrusted. Beyond the decoders, the host holds it to limits: MAX_READ
## messages a tick; for each seat MAX_QUEUED frames waiting for their tick and
## MAX_COMMANDS_WAITING commands not yet in a tick; no frame for a tick more than MAX_AHEAD ahead
## or before the one before it; a frame only for a seat that is that machine's (one for a seat
## it gave back a moment ago is dropped; any other closes the link); and one check per window, in
## order.
##
##     var host := NetHost.new(Frames, PlayerInput, link, Tick.state_areas)
##     host.begin(replay)    # the run Frames.record returned, or: host.start(&"sandbox_requested", 0)
##     ...  # after every tick: host.after_tick()

const InputManagerScript := preload("res://core/input/input_manager.gd")

## The seat `start` gives the client's first player beforehand.
const SEAT: int = 1
## The most messages read from the client in one tick.
const MAX_READ: int = 64
## The most client frames of a seat that wait for their tick, and how far ahead of the host's
## tick one may be for (ten seconds).
const MAX_QUEUED: int = 600
const MAX_AHEAD: int = 600
## The most commands of a seat's used-up frames that wait for a tick's frame with room.
const MAX_COMMANDS_WAITING: int = 64
## The bytes a tick's frame may come to with the client's commands in it: a frame's limit, less
## room for what the frames service adds (the seat's JOIN or LEAVE).
const FRAME_ROOM: int = InputFrame.MAX_BYTES - 64
## The host's checks kept until the client's arrive (the client plays behind the host).
const MAX_CHECKS_KEPT: int = 32
## The most ticks sent after one tick: a client that joined a run under way is sent what was
## recorded before at this pace, so its link never holds more than it reads.
const SEND_A_TICK: int = 240
## The most asks for a seat that wait to be answered (they are answered between ticks).
const MAX_ASKS_WAITING: int = 16


## One of the client's seats' source: the session itself, held weakly (the frames service holds
## the source, the session holds the frames service).
class Source:
	extends FrameSource
	var host: WeakRef = null
	var seat: int = 0

	func fill_frame(frame: InputFrame, _delta: float) -> void:
		var session: NetHost = host.get_ref() as NetHost if host != null else null
		if session != null:
			session.fill_seat(seat, frame)


## One seat the client holds: which of its players, and its frames on their way into ticks.
class Line:
	extends RefCounted
	var local: int = 0
	var source: Source = Source.new()
	## The frames that wait for their tick, in the order they came, and each one's tick.
	var queued: Array[InputFrame] = []
	var queued_for: PackedInt32Array = PackedInt32Array()
	## The last frame used (null: none yet).
	var last: InputFrame = null
	## Presses and commands of the frames used up, not yet in a tick's frame.
	var presses: int = 0
	var commands: Array[Array] = []


var input: InputManagerScript

## The client's seats, by seat (null: not the client's).
var _lines: Array[Line] = [null, null, null, null]
## Per seat: the tick it was last given back at (-1: never), so its last frames on the way are
## dropped, not refused.
var _freed_at: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
## The asks answered (0 to 255, then round again), and those read but not answered yet: each
## one's player, in the order they came.
var _answered: int = 0
var _asks: PackedInt32Array = PackedInt32Array()
## True while a tick's frames are being built (the link read from `fill_seat`): no seat is given.
var _building: bool = false
## The client's pings heard (whoever holds the session knows from them that the client is ready).
var pings_heard: int = 0
## Ticks sent to the client.
var _sent: int = 0
## The tick the newest frame received is for (they never go back).
var _newest_for: int = 0
## The run's tick count when the link was last read (once a tick).
var _pumped_at: int = -1
## The first tick hashed for the checks (a whole window from there on).
var _check_from: int = 0
## The host's own checks by tick, until the client's arrive, and the tick of the client's last.
var _kept: Dictionary[int, Dictionary] = {}
var _checked_to: int = -1


func _init(frames_service: FramesScript, input_layer: InputManagerScript, over: NetLink, state_areas: Callable = Callable()) -> void:
	super(frames_service, over, state_areas)
	input = input_layer
	max_read = MAX_READ


## Start the run by `start_by` (one of `Replay.STARTS`) for seat `starter`, recorded, with seat
## SEAT given to the client's first player, and begin it. Returns the replay it records into, or
## null (and nothing starts) when it has begun already, the link is closed, or seat SEAT is held
## by a device of this machine.
func start(start_by: StringName, starter: int = 0, run_seed: int = 0) -> Replay:
	if replay != null or not hears_client():
		return null
	if seat_of(0) < 0:
		if input.is_joined(SEAT):
			return null
		_give(SEAT, 0)
	var run: Replay = frames.record(start_by, starter, run_seed)
	return run if begin(run) else null


## Join the client to `run`, which the frames service records (from its first tick, or a while
## in): its header goes out, and its ticks from the first. False, and nothing happens, when a
## run was begun already, the link is closed or `run` is none.
func begin(run: Replay) -> bool:
	if replay != null or run == null or not hears_client():
		return false
	replay = run
	_sent = 0
	_check_from = ceili(float(run.tick_count()) / checks.every) * checks.every
	# The seats first: the client knows which are its own before the run seats anybody.
	_send_lobby()
	_send(NetMessage.of_header(run.header_bytes()))
	return true


## End the session: the client's seats leave, the link closes. The recording stops too, unless
## `keep_recording` (a run that plays on, and may be joined again). Returns the run so far (null
## when none was begun).
func stop(keep_recording: bool = false) -> Replay:
	link.close()
	for seat in Replay.SEATS:
		_take_back(seat)
	if replay != null and not keep_recording and frames.is_recording():
		frames.stop_recording()
	return replay


## True while the run it began is recorded.
func is_running() -> bool:
	return replay != null and frames.is_recording()


## True while the client can still be heard: the link open and not refused.
func hears_client() -> bool:
	return problem == "" and link.is_open()


## The seat the client's player `local` holds, or -1.
func seat_of(local: int) -> int:
	for seat in Replay.SEATS:
		if _lines[seat] != null and _lines[seat].local == local:
			return seat
	return -1


## The client's seats (a bit each).
func client_seats() -> int:
	var mask: int = 0
	for seat in Replay.SEATS:
		if _lines[seat] != null:
			mask |= 1 << seat
	return mask


## The client's seat `seat`'s frame for the tick being built (the frames service asks, through
## the seat's source; `frame` comes cleared).
func fill_seat(seat: int, frame: InputFrame) -> void:
	# Once a tick, by the first of the client's seats asked.
	if replay == null or _pumped_at != replay.tick_count():
		_pumped_at = replay.tick_count() if replay != null else -1
		_building = true
		pump()
		_building = false
	var line: Line = _lines[seat]
	if line == null or not is_running():
		return
	var tick: int = replay.tick_count()
	var fresh: bool = false
	while problem == "" and not line.queued.is_empty() and line.queued_for[0] <= tick:
		if line.queued_for[0] < tick:
			stats.late_frames += 1
		line.last = line.queued.pop_front()
		line.queued_for.remove_at(0)
		line.presses |= line.last.pressed_bits
		line.commands.append_array(line.last.commands)
		fresh = true
	if line.commands.size() > MAX_COMMANDS_WAITING:
		_refuse("%d commands waiting" % line.commands.size())
	if problem != "" or (not fresh and line.queued.is_empty() and not link.is_open()):
		# The client is gone: its seat leaves, as an unplugged pad's (the frames service writes
		# the LEAVE into this very frame).
		_take_back(seat)
		return
	if not fresh and line.last != null:
		stats.stood_in += 1
	if line.last == null:
		return
	frame.move = line.last.move
	frame.aim = line.last.aim
	frame.held_bits = line.last.held_bits
	frame.captured = line.last.captured
	frame.pressed_bits = line.presses
	line.presses = 0
	if _pass_commands(line, frame):
		_take_back(seat)


## The commands of `line`'s frames used up, into `frame`, in order, while they fit it (a frame's
## command count, FRAME_ROOM); the rest wait for the next tick. Returns true when the seat's
## player left (a LEAVE): the seat is then given back, and the input layer writes the LEAVE into
## this frame itself, which needs a place too (where it stands among the tick's commands does
## not matter: a tick's seats change before any of its commands apply, on the host and in the
## replay alike). A JOIN seats nobody (an ask does) and is dropped.
func _pass_commands(line: Line, frame: InputFrame) -> bool:
	var passed: int = 0
	var left: bool = false
	for command: Array in line.commands:
		if frame.commands.size() + (1 if left else 0) >= InputFrame.MAX_COMMANDS:
			break
		var name: StringName = command[0]
		passed += 1
		if name == InputFrame.JOIN:
			continue
		if name == InputFrame.LEAVE:
			left = true
			break
		frame.add_command(name, command.slice(1))
		if frame.to_bytes().size() > FRAME_ROOM:
			frame.commands.pop_back()
			# Alone in a frame and still too big, it could never go: it is dropped. Else it waits.
			if not frame.commands.is_empty():
				passed -= 1
			break
	if passed == line.commands.size():
		line.commands.clear()
	else:
		line.commands = line.commands.slice(passed)
	return left


func pump() -> bool:
	var drained: bool = super()
	if not _building:
		_answer_asks()
	return drained


func after_tick() -> void:
	if not is_running():
		return
	# With no seat of the client's, nothing asked for a frame this tick: the link is read here.
	if client_seats() == 0:
		pump()
	# Between ticks: the asks read while the tick's frames were built.
	_answer_asks()
	var began: int = Time.get_ticks_usec()
	var until: int = mini(replay.tick_count(), _sent + SEND_A_TICK)
	while _sent < until and hears_client():
		_send(NetMessage.of_tick(_sent, replay.tick_bytes(_sent)))
		_sent += 1
	stats.ticks = _sent
	stats.net_usec += Time.get_ticks_usec() - began
	var tick: int = replay.tick_count() - 1
	if not areas.is_valid() or tick < _check_from:
		return
	var check: Dictionary[String, int] = _check(tick)
	if check.is_empty():
		return
	_kept[tick] = check
	if _kept.size() > MAX_CHECKS_KEPT:
		# The oldest goes (a dictionary keeps the order they were added in).
		for oldest: int in _kept:
			_kept.erase(oldest)
			stats.unchecked += 1
			break


func _take(message: NetMessage) -> String:
	match message.kind:
		NetMessage.PING:
			pings_heard += 1
			_send(NetMessage.of_pong(message.stamp))
			return ""
		NetMessage.FRAME:
			return _take_frame(message)
		NetMessage.HASHES:
			return _take_check(message)
		NetMessage.SEAT_ASK:
			# At most one waiting for each of its players: more is a flood.
			if _asks.size() >= MAX_ASKS_WAITING:
				return "%d asks for a seat waiting" % _asks.size()
			_asks.append(message.local)
			return ""
	return "kind %d is not a client's to send" % message.kind


func _take_frame(message: NetMessage) -> String:
	if replay == null:
		return "a frame before the run"
	var frame := InputFrame.new()
	var why: String = frame.decode(message.body)
	if why != "":
		return "a frame: " + why
	if message.tick < _newest_for:
		return "a frame for tick %d after one for %d" % [message.tick, _newest_for]
	if message.tick > replay.tick_count() + MAX_AHEAD:
		return "a frame for tick %d at tick %d" % [message.tick, replay.tick_count()]
	_newest_for = message.tick
	var line: Line = _lines[frame.seat] if frame.seat >= 0 and frame.seat < Replay.SEATS else null
	if line == null:
		# A seat it gave back a moment ago: its last frames were on their way. Any other seat is
		# never the client's to play.
		if frame.seat >= 0 and frame.seat < Replay.SEATS and _freed_at[frame.seat] >= 0 and replay.tick_count() - _freed_at[frame.seat] <= MAX_AHEAD:
			return ""
		return "a frame of seat %d" % frame.seat
	if line.queued.size() >= MAX_QUEUED:
		return "%d frames waiting" % line.queued.size()
	line.queued.append(frame)
	line.queued_for.append(message.tick)
	return ""


## The asks read are answered, in order: each player the lowest seat that nobody holds, if it has
## none yet, and the lobby, given a seat or not. Never while a tick's frames are being built.
func _answer_asks() -> void:
	if _asks.is_empty() or problem != "":
		_asks.clear()
		return
	for local in _asks:
		_answered = (_answered + 1) & 0xff
		if seat_of(local) < 0:
			for seat in Replay.SEATS:
				if not input.is_joined(seat):
					_give(seat, local)
					break
		_send_lobby()
	_asks.clear()


## The client's check of a tick: one per window, in order, of a tick the host has played.
func _take_check(message: NetMessage) -> String:
	if replay == null or message.tick >= replay.tick_count():
		return "a check of tick %d, not played yet" % message.tick
	if message.tick <= _checked_to or posmod(message.tick, checks.every) != checks.every - 1:
		return "a check of tick %d after one of %d" % [message.tick, _checked_to]
	_checked_to = message.tick
	if not _kept.has(message.tick):
		# The host's own went already: the client is far behind.
		stats.unchecked += 1
		return ""
	var mine: Dictionary[String, int] = _kept[message.tick]
	_kept.erase(message.tick)
	stats.checks += 1
	var differing: PackedStringArray = NetChecks.parting(mine, message.hashes)
	if differing.is_empty():
		return ""
	stats.mismatches += 1
	if parted_tick < 0:
		_part(message.tick, differing)
		_send(NetMessage.of_parted(message.tick, differing))
	return ""


## Seat `seat` is the client's player `local`'s: a virtual device joins it through the input
## layer, and its frames come from here.
func _give(seat: int, local: int) -> void:
	if input.add_virtual_device(seat) == InputManagerScript.NO_DEVICE:
		return
	var line := Line.new()
	line.local = local
	line.source.host = weakref(self)
	line.source.seat = seat
	_lines[seat] = line
	_freed_at[seat] = -1
	frames.set_source(seat, line.source)


## The client's seat `seat` is given back (its player left, or the client is gone): its virtual
## device leaves, and the client is told.
func _take_back(seat: int) -> void:
	var line: Line = _lines[seat]
	if line == null:
		return
	_lines[seat] = null
	_freed_at[seat] = replay.tick_count() if replay != null else 0
	if frames.source_of(seat) == line.source:
		frames.set_source(seat, null)
	if input.is_joined(seat) and InputManagerScript.is_virtual(input.device_of(seat)):
		input.leave(seat)
	_send_lobby()


## Which of the client's players holds which seat, and the asks answered so far.
func _send_lobby() -> void:
	if not hears_client():
		return
	var holders := PackedByteArray([NetMessage.NOBODY, NetMessage.NOBODY, NetMessage.NOBODY, NetMessage.NOBODY])
	for seat in Replay.SEATS:
		if _lines[seat] != null:
			holders[seat] = _lines[seat].local
	_send(NetMessage.of_lobby(_answered, holders))
