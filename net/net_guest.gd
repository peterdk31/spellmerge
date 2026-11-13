class_name NetGuest
extends NetSession
## One guest machine as the host sees it (online lobby L3, docs/milestones/online-lobby.md): its
## link, the seats the host gave it, the frames it sent for them, its limits, its checks and its
## counters. The host (`NetHost`) holds one for each guest machine, up to three, and the recording
## they all play; a guest knows nothing of the others.
##
## - **Its seats are the host's to give** (online lobby L2): it asks for one for each of its
##   players (SEAT_ASK, naming the player by a number of its own, never a device) and is given
##   the lowest seat nobody holds: a virtual device joins it through the input layer, as a pad
##   would (so the frames service seats it and the recording says so at one tick for every
##   machine), and the seat's frames come from here. Every ask is answered with the LOBBY: which
##   of its players holds which seat; with no seat free the answer gives none. **A seat is only
##   given between ticks** (`answer_asks`, the host's to call): given while a tick's frames are
##   built, a seat whose frame of that tick is built already would be seated on the host a tick
##   before the recording says so. A seat is given back when its player leaves (a LEAVE in its
##   frame) or the guest is gone; a JOIN in a frame seats nobody.
## - **Its frames** each name the host's tick they are for and one of its seats (a FRAME a seat a
##   step). When a seat's frame is built for a tick, every frame of that seat that arrived for that
##   tick or an earlier one is used up: the walk, the aim and the buttons held are the newest's, the
##   presses and the commands are all of theirs, in order. **A frame that has not arrived** is stood
##   in for by the last one without its presses and commands (a button held stays held; a command
##   never applies twice), and its own presses and commands come with the next frame used.
##   Commands that do not fit the tick's frame (its count, its bytes) wait for the next.
## - **The link is read** once a tick, when the first of its seats' frames is built, and before the
##   run by `pump` from whoever holds the host. No `_process`, no thread.
## - **A run begun anew** (`rebegin`: the party back in its hub): the guest is sent the new
##   recording's header and its ticks from the first. What it sent for the recording before (its
##   frames, its checks, on their way or sent before it has played that far) is dropped, not
##   refused: the guest says when it plays the new one (RUN, the number of headers it has taken),
##   and only from then is what it sends used.
## - **Its check** of a tick is compared with the host's own of that tick (`kept`, the host's);
##   where they differ the guest is told and the parting kept here (`parted_tick`).
## - **The guest gone** (the link closed and all it sent used, or refused): its seats leave, as a
##   pad pulled out would, each when its own frame is next built (so its LEAVE is in that seat's
##   frame of the tick it left in); the others play on.
##
## What a guest sends is untrusted. Beyond the decoders it is held, each guest on its own, to:
## MAX_READ messages a tick, MAX_QUEUED frames waiting for their tick (all its seats together), none for a tick more
## than MAX_AHEAD ahead or before the one before it, none for a seat that is not its own (one for
## a seat it gave back within MAX_AHEAD ticks is dropped: it was on its way),
## MAX_COMMANDS_WAITING commands a seat not yet in a tick, MAX_ASKS_WAITING asks for a seat not
## yet answered, and one check per window, in order.

const InputManagerScript := preload("res://core/input/input_manager.gd")

## The most messages read from a guest in one tick (its seats' frames, its pings, its checks).
const MAX_READ: int = 64
## The most frames that wait for their tick, all the guest's seats together (as many seats, as
## much memory as one seat had), and how far ahead of the host's tick one may be for (ten seconds).
const MAX_QUEUED: int = 600
const MAX_AHEAD: int = 600
## The most commands of a seat's used-up frames that wait for a tick's frame with room.
const MAX_COMMANDS_WAITING: int = 64
## The bytes a tick's frame may come to with the guest's commands in it: a frame's limit, less
## room for what the frames service adds (the seat's JOIN or LEAVE).
const FRAME_ROOM: int = InputFrame.MAX_BYTES - 64
## The most asks for a seat that wait to be answered (they are answered between ticks).
const MAX_ASKS_WAITING: int = 16
const NOBODY: int = NetMessage.NOBODY

var input: InputManagerScript
## The seats the host gave this machine (a bit each). Read only: `give` and `take_back` set it.
var seats: int = 0
## Per seat: which of this machine's players holds it (0 to 3; NOBODY: not this machine's).
var holders: PackedByteArray = PackedByteArray([NOBODY, NOBODY, NOBODY, NOBODY])
## The host's sources by seat (the frames service asks them for a seat's frames): a seat given
## to this machine gets its own.
var sources: Array[FrameSource] = []
## True once the host joined this machine to its run (its header went out).
var admitted: bool = false
## The first tick the host's checks are whole from (a run joined in the middle of a window).
var check_from: int = 0
## This machine's pings heard (whoever holds the host knows from them that it is ready).
var pings_heard: int = 0
## The physics steps its holder has waited for it to be ready (the holder counts, and has the limit).
var waited: int = 0
## The headers sent to it (the recordings it was joined to), and the one it says it plays (RUN;
## the first needs no saying). Its frames and checks are used while the two are the same.
var headers_sent: int = 0
var plays_run: int = 1
## The host's own checks by tick (the host's dictionary, shared), and the tick of this guest's last.
var kept: Dictionary[int, Dictionary] = {}
var checked_to: int = -1
## Ticks sent to this guest.
var sent_ticks: int = 0

## Per seat: the frames that wait for their tick, in the order they came, and each one's tick.
var _queued: Array[Array] = [[], [], [], []]
var _queued_for: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
## Per seat: the tick the newest frame received is for (they never go back).
var _newest_for: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## Per seat: the last frame used (null: none yet, or the guest is gone).
var _last: Array[InputFrame] = [null, null, null, null]
## Per seat: presses and commands of the frames used up, not yet in a tick's frame.
var _presses: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _commands: Array[Array] = [[], [], [], []]
## The frames waiting in all the queues.
var _waiting: int = 0
## The host's tick this guest's link was last read in (-1: none).
var _read_at: int = -1
## True once the guest is gone and its seats have left.
var _gone: bool = false
## Per seat: the tick it was last given back at (-1: never), so its last frames on the way are
## dropped, not refused.
var _freed_at: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
## The asks answered (0 to 255, then round again), and those read but not answered yet: each
## one's player, in the order they came.
var _answered: int = 0
var _asks: PackedInt32Array = PackedInt32Array()


func _init(frames_service: FramesScript, input_layer: InputManagerScript, over: NetLink, on_seats: int, state_areas: Callable = Callable()) -> void:
	super(frames_service, over, state_areas)
	input = input_layer
	max_read = MAX_READ
	# Seats named beforehand are its first players', in order (seated when the run starts).
	var player: int = 0
	for seat in Replay.SEATS:
		if on_seats & (1 << seat) != 0:
			seats |= 1 << seat
			holders[seat] = player
			player += 1


## True while this guest can still be heard: the link open and not refused.
func hears() -> bool:
	return problem == "" and link.is_open()


func owns(seat: int) -> bool:
	return seat >= 0 and seats & (1 << seat) != 0


## Seat `seat`'s frame for the host's tick `tick` (the host asks, through the seat's source;
## `frame` comes cleared).
func fill_seat(seat: int, frame: InputFrame, tick: int) -> void:
	if not owns(seat):
		return
	if _gone:
		take_back(seat)
		return
	if _read_at != tick:
		read_for(tick)
		# What it read may have given the seat back (never given one: that waits for the tick's end).
		if not owns(seat):
			return
	var fresh: bool = false
	var queued: Array = _queued[seat]
	var queued_for: PackedInt32Array = _queued_for[seat]
	while problem == "" and not queued.is_empty() and queued_for[0] <= tick:
		if queued_for[0] < tick:
			stats.late_frames += 1
		var last: InputFrame = queued.pop_front()
		queued_for.remove_at(0)
		_waiting -= 1
		_last[seat] = last
		_presses[seat] |= last.pressed_bits
		_commands[seat].append_array(last.commands)
		fresh = true
	if _commands[seat].size() > MAX_COMMANDS_WAITING:
		_refuse("%d commands waiting for seat %d" % [_commands[seat].size(), seat])
	if problem != "" or (not fresh and queued.is_empty() and not link.is_open() and _all_used()):
		_drop_all()
		take_back(seat)
		return
	if not fresh and _last[seat] != null:
		stats.stood_in += 1
	var last_used: InputFrame = _last[seat]
	if last_used == null:
		# No frame of its own in this recording yet; a leave kept from before still holds.
		if _commands[seat].has([InputFrame.LEAVE]):
			_commands[seat].clear()
			take_back(seat)
		return
	frame.move = last_used.move
	frame.aim = last_used.aim
	frame.held_bits = last_used.held_bits
	frame.captured = last_used.captured
	frame.pressed_bits = _presses[seat]
	_presses[seat] = 0
	if _pass_commands(seat, frame):
		take_back(seat)


## Read the link for the host's tick `tick`, unless it was read for it already (once a tick: when
## the first of its seats' frames is built, or by the host after a tick that asked it for none).
func read_for(tick: int) -> void:
	if _read_at != tick:
		_read_at = tick
		pump()


## True when nothing this guest sent waits to be used, for any of its seats.
func _all_used() -> bool:
	for seat in Replay.SEATS:
		if not _queued[seat].is_empty():
			return false
	return true


## The commands of seat `seat`'s frames used up, into `frame`, in order, while they fit it (a
## frame's command count, FRAME_ROOM); the rest wait for the next tick. Returns true when the
## seat's player left (a LEAVE): the seat is then given back, and the input layer writes the LEAVE
## into this frame itself, which needs a place too (where it stands among the tick's commands does
## not matter: a tick's seats change before any of its commands apply, on the host and in the
## replay alike). What came behind the leave goes with the seat. A JOIN seats nobody (an ask does)
## and is dropped.
func _pass_commands(seat: int, frame: InputFrame) -> bool:
	var waiting: Array = _commands[seat]
	var passed: int = 0
	var left: bool = false
	for command: Array in waiting:
		if frame.commands.size() >= InputFrame.MAX_COMMANDS:
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
	if passed == waiting.size():
		waiting.clear()
	else:
		_commands[seat] = waiting.slice(passed)
	return left


## The guest is gone: nothing of its is used again. Each of its seats leaves when its own frame is
## built (this tick's or the next's), so the LEAVE is in that seat's frame of the tick it left in,
## on the host and in the recording alike.
func _drop_all() -> void:
	_gone = true
	_waiting = 0
	for seat in Replay.SEATS:
		_last[seat] = null
		_presses[seat] = 0
		_commands[seat].clear()
		_queued[seat].clear()
		_queued_for[seat].clear()


## True once this guest is gone from the run (its seats left).
func is_gone() -> bool:
	return _gone


## Seat `seat`'s virtual device joins (`on`) or leaves, through the input layer. A seat held by a
## device of the host's machine is never touched.
func seat_one(seat: int, on: bool) -> void:
	if on and not input.is_joined(seat):
		input.add_virtual_device(seat)
	elif not on and input.is_joined(seat) and InputManagerScript.is_virtual(input.device_of(seat)):
		input.leave(seat)


## The run began anew, recorded into `run`: its header goes out, its ticks follow from the first,
## and nothing this guest sent for the recording before is used (its seats stand until it says it
## plays the new one). The host calls it between ticks, for a guest in the run.
func rebegin(run: Replay) -> void:
	replay = run
	sent_ticks = 0
	stats.ticks = 0
	check_from = 0
	checked_to = -1
	_read_at = -1
	_waiting = 0
	for seat in Replay.SEATS:
		# A player who left just before: that is no input of the recording before, and still holds.
		var left: bool = _commands[seat].has([InputFrame.LEAVE])
		for frame: InputFrame in _queued[seat]:
			left = left or frame.commands.has([InputFrame.LEAVE])
		_queued[seat].clear()
		_queued_for[seat].clear()
		_newest_for[seat] = 0
		_last[seat] = null
		_presses[seat] = 0
		_commands[seat].clear()
		_freed_at[seat] = -1
		if left and owns(seat):
			_commands[seat].append([InputFrame.LEAVE])
	send_header()


## The run's header goes out: one more recording this guest is joined to.
func send_header() -> void:
	headers_sent += 1
	send(NetMessage.of_header(replay.header_bytes()))


## Seat `seat` is this machine's player `local`'s: a virtual device joins it through the input
## layer, and its frames come from here. Between ticks only (see the top). False, and nothing
## changes, when somebody holds the seat.
func give(seat: int, local: int) -> bool:
	if seat < 0 or seat >= Replay.SEATS or owns(seat) or input.is_joined(seat):
		return false
	seat_one(seat, true)
	if not input.is_joined(seat):
		return false
	seats |= 1 << seat
	holders[seat] = local
	_freed_at[seat] = -1
	if seat < sources.size():
		frames.set_source(seat, sources[seat])
	return true


## Seat `seat` is given back (its player left, or the guest is gone): its virtual device leaves,
## nothing sent for it is used, and the guest is told. Inside a tick only for the seat whose
## frame is being built (its LEAVE is then in that frame); any seat between ticks.
func take_back(seat: int) -> void:
	if not owns(seat):
		return
	seats &= ~(1 << seat)
	holders[seat] = NOBODY
	_freed_at[seat] = replay.tick_count() if replay != null else 0
	_waiting -= _queued[seat].size()
	_queued[seat].clear()
	_queued_for[seat].clear()
	_last[seat] = null
	_presses[seat] = 0
	_commands[seat].clear()
	if seat < sources.size() and frames.source_of(seat) == sources[seat]:
		frames.set_source(seat, null)
	seat_one(seat, false)
	send_lobby()


## The seat this machine's player `local` holds, or -1.
func seat_of(local: int) -> int:
	return holders.find(local) if local != NOBODY else -1


## The asks read are answered, in order: each player the lowest seat that nobody holds, if it has
## none yet, and the lobby, given a seat or not. The host calls it between ticks, never while a
## tick's frames are built.
func answer_asks() -> void:
	if _asks.is_empty():
		return
	if not hears():
		_asks.clear()
		return
	for local in _asks:
		_answered = (_answered + 1) & 0xff
		var held: int = seat_of(local)
		if held < 0:
			for seat in Replay.SEATS:
				if give(seat, local):
					break
		elif not input.is_joined(held):
			# Its seat was named beforehand and the run began without seating it: seated now.
			seat_one(held, true)
			if held < sources.size():
				frames.set_source(held, sources[held])
		send_lobby()
	_asks.clear()


## Which of this machine's players holds which seat, and the asks answered so far.
func send_lobby() -> void:
	if hears():
		_send(NetMessage.of_lobby(_answered, holders))


## The run's next tick goes out (its TICK message, made once by the host for every guest).
func send_tick(message: PackedByteArray) -> void:
	if not hears():
		return
	var began: int = Time.get_ticks_usec()
	_send(message)
	sent_ticks += 1
	stats.ticks = sent_ticks
	stats.net_usec += Time.get_ticks_usec() - began


func send(bytes: PackedByteArray) -> void:
	if hears():
		_send(bytes)


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
		NetMessage.RUN:
			# The next one, and one it was sent: never ahead of the host. (The number on the wire
			# is a byte, round again after 255; the count here is not.)
			if message.run != (plays_run + 1) & 0xff or plays_run + 1 > headers_sent:
				return "it says it plays recording %d after %d of %d" % [message.run, plays_run, headers_sent]
			plays_run += 1
			return ""
		NetMessage.SEAT_ASK:
			if _asks.size() >= MAX_ASKS_WAITING:
				return "%d asks for a seat waiting" % _asks.size()
			_asks.append(message.local)
			return ""
	return "kind %d is not a guest's to send" % message.kind


func _take_frame(message: NetMessage) -> String:
	if replay == null:
		return "a frame before the run"
	var frame := InputFrame.new()
	var why: String = frame.decode(message.body)
	if why != "":
		return "a frame: " + why
	var seat: int = frame.seat
	# Of the recording before (the run began anew since): on its way, or sent before the guest
	# played that far. Dropped, but for its player's leave, which is no input of that recording:
	# the seat is given back when its frame is next built.
	if plays_run != headers_sent:
		if owns(seat) and frame.commands.has([InputFrame.LEAVE]) and not _commands[seat].has([InputFrame.LEAVE]):
			_commands[seat].append([InputFrame.LEAVE])
		return ""
	if not owns(seat):
		# A seat it gave back a moment ago: its last frames were on their way. Any other seat is
		# never this machine's to play.
		if seat >= 0 and seat < Replay.SEATS and _freed_at[seat] >= 0 and replay.tick_count() - _freed_at[seat] <= MAX_AHEAD:
			return ""
		return "a frame of seat %d" % seat
	if message.tick < _newest_for[seat]:
		return "a frame for tick %d after one for %d" % [message.tick, _newest_for[seat]]
	if message.tick > replay.tick_count() + MAX_AHEAD:
		return "a frame for tick %d at tick %d" % [message.tick, replay.tick_count()]
	if _waiting >= MAX_QUEUED:
		return "%d frames waiting" % _waiting
	_waiting += 1
	_newest_for[seat] = message.tick
	_queued[seat].append(frame)
	_queued_for[seat].append(message.tick)
	return ""


## The guest's check of a tick: one per window, in order, of a tick the host has played.
func _take_check(message: NetMessage) -> String:
	if replay != null and plays_run != headers_sent:
		return ""
	if replay == null or message.tick >= replay.tick_count():
		return "a check of tick %d, not played yet" % message.tick
	if message.tick <= checked_to or posmod(message.tick, checks.every) != checks.every - 1:
		return "a check of tick %d after one of %d" % [message.tick, checked_to]
	checked_to = message.tick
	if message.tick < check_from or not kept.has(message.tick):
		# The host's own went already: the guest is far behind.
		stats.unchecked += 1
		return ""
	var mine: Dictionary[String, int] = kept[message.tick]
	stats.checks += 1
	var differing: PackedStringArray = NetChecks.parting(mine, message.hashes)
	if differing.is_empty():
		return ""
	stats.mismatches += 1
	if parted_tick < 0:
		_part(message.tick, differing)
		_send(NetMessage.of_parted(message.tick, differing))
	return ""
