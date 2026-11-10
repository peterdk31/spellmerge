class_name NetHost
extends NetSession
## The host's side of an online run (netcode spike S2, docs/milestones/netcode-spike.md): the host
## records its run, the client's seat is a virtual device whose frames come from the link, and
## every recorded tick goes out as it is made. The host never waits.
##
## - **`start`** seats the client (a virtual device on seat SEAT, joined through the input layer as
##   a pad would be, so the frames service seats it and the recording knows), makes the session's
##   source the seat's `FrameSource`, starts the run recorded (`Frames.record`) and sends its header.
## - **The client's frames** each name the host's tick they are for. When the seat's frame is
##   built for a tick, every frame that arrived for that tick or an earlier one is used up: the
##   walk, the aim and the buttons held are the newest's, the presses and the commands are all of
##   theirs, in order. **A frame that has not arrived** is stood in for by the last one without
##   its presses and commands (a button held stays held; a command never applies twice), and its
##   own presses and commands come with the next frame used. A JOIN or LEAVE in a client's frame
##   (its device left or joined) is done here through the input layer, never passed on in the
##   frame. Commands that do not fit the tick's frame (its count, its bytes) wait for the next.
## - **`after_tick`**, called after every tick has stepped, sends the ticks recorded since and
##   hashes the tick's part of the state. The client's check is compared with the host's own of
##   the same tick; where they differ the client is told (`NetSession`: `parted_tick`).
## - **The link is read** only when the frames service asks for the seat's frame (once a tick),
##   and, before the run, by `pump` from whoever holds the session. No `_process`, no thread.
## - **The client gone** (the link closed, or refused): the seat's frames are empty from then on
##   and the host plays on.
##
## What the client sends is untrusted. Beyond the decoders, the host holds it to limits: MAX_READ
## messages a tick, MAX_QUEUED frames waiting for their tick, none for a tick more than MAX_AHEAD
## ahead or before the one before it, MAX_COMMANDS_WAITING commands not yet in a tick, and one
## check per window, in order.
##
##     var host := NetHost.new(Frames, PlayerInput, link, Tick.state_areas)
##     host.start(&"sandbox_requested", 0)
##     ...  # after every tick: host.after_tick()

const InputManagerScript := preload("res://core/input/input_manager.gd")

## The client's seat.
const SEAT: int = 1
## The most messages read from the client in one tick.
const MAX_READ: int = 64
## The most client frames that wait for their tick, and how far ahead of the host's tick one may
## be for (ten seconds).
const MAX_QUEUED: int = 600
const MAX_AHEAD: int = 600
## The most commands of used-up frames that wait for a tick's frame with room.
const MAX_COMMANDS_WAITING: int = 64
## The bytes a tick's frame may come to with the client's commands in it: a frame's limit, less
## room for what the frames service adds (the seat's JOIN or LEAVE).
const FRAME_ROOM: int = InputFrame.MAX_BYTES - 64
## The host's checks kept until the client's arrive (the client plays behind the host).
const MAX_CHECKS_KEPT: int = 32


## The client's seat's source: the session itself, held weakly (the frames service holds the
## source, the session holds the frames service).
class Source:
	extends FrameSource
	var host: WeakRef = null

	func fill_frame(frame: InputFrame, _delta: float) -> void:
		var session: NetHost = host.get_ref() as NetHost if host != null else null
		if session != null:
			session.fill_seat(frame)


var input: InputManagerScript

var _source: Source = Source.new()
## Ticks sent to the client.
var _sent: int = 0
## The client's frames that wait for their tick, in the order they came, and each one's tick.
var _queued: Array[InputFrame] = []
var _queued_for: PackedInt32Array = PackedInt32Array()
## The tick the newest frame received is for (they never go back).
var _newest_for: int = 0
## The last client frame used (null: none yet, or the client is gone).
var _last: InputFrame = null
## Presses and commands of the frames used up, not yet in a tick's frame.
var _presses: int = 0
var _commands: Array[Array] = []
## The host's own checks by tick, until the client's arrive, and the tick of the client's last.
var _kept: Dictionary[int, Dictionary] = {}
var _checked_to: int = -1


func _init(frames_service: FramesScript, input_layer: InputManagerScript, over: NetLink, state_areas: Callable = Callable()) -> void:
	super(frames_service, over, state_areas)
	input = input_layer
	max_read = MAX_READ
	_source.host = weakref(self)


## Start the run by `start_by` (one of `Replay.STARTS`) for seat `starter`, recorded, with the
## client seated, and send its header. Returns the replay it records into, or null (and nothing
## starts) when it has started already, the link is closed, or the client's seat is held by a
## device of this machine.
func start(start_by: StringName, starter: int = 0, run_seed: int = 0) -> Replay:
	if replay != null or not hears_client():
		return null
	if input.is_joined(SEAT) and not InputManagerScript.is_virtual(input.device_of(SEAT)):
		return null
	_seat(true)
	frames.set_source(SEAT, _source)
	replay = frames.record(start_by, starter, run_seed)
	_send(NetMessage.of_header(replay.header_bytes()))
	return replay


## End the session: the client's seat leaves, the link closes. Returns the run recorded so far
## (null when none was started).
func stop() -> Replay:
	link.close()
	if replay == null:
		return null
	if frames.source_of(SEAT) == _source:
		frames.set_source(SEAT, null)
	_seat(false)
	if frames.is_recording():
		frames.stop_recording()
	return replay


## True while the run it started is recorded.
func is_running() -> bool:
	return replay != null and frames.is_recording()


## True while the client can still be heard: the link open and not refused.
func hears_client() -> bool:
	return problem == "" and link.is_open()


## The client's seat's frame for the tick being built (the frames service asks, through the
## seat's source; `frame` comes cleared).
func fill_seat(frame: InputFrame) -> void:
	pump()
	if not is_running():
		return
	var tick: int = replay.tick_count()
	var fresh: bool = false
	while problem == "" and not _queued.is_empty() and _queued_for[0] <= tick:
		if _queued_for[0] < tick:
			stats.late_frames += 1
		_last = _queued.pop_front()
		_queued_for.remove_at(0)
		_presses |= _last.pressed_bits
		_commands.append_array(_last.commands)
		fresh = true
	if _commands.size() > MAX_COMMANDS_WAITING:
		_refuse("%d commands waiting" % _commands.size())
	if problem != "" or (not fresh and _queued.is_empty() and not link.is_open()):
		_drop_client()
	elif not fresh and _last != null:
		stats.stood_in += 1
	if _last == null:
		return
	frame.move = _last.move
	frame.aim = _last.aim
	frame.held_bits = _last.held_bits
	frame.captured = _last.captured
	frame.pressed_bits = _presses
	_presses = 0
	_pass_commands(frame)


## The commands of the frames used up, into `frame`, in order, while they fit it (a frame's
## command count, FRAME_ROOM); the rest wait for the next tick. A JOIN or LEAVE is done through
## the input layer, which then writes it into this frame itself: it needs a place too, and where
## it stands among the tick's commands does not matter (a tick's seats change before any of its
## commands apply, on the host and in the replay alike).
func _pass_commands(frame: InputFrame) -> void:
	var passed: int = 0
	var seatings: int = 0
	for command: Array in _commands:
		if frame.commands.size() + seatings >= InputFrame.MAX_COMMANDS:
			break
		var name: StringName = command[0]
		passed += 1
		if name == InputFrame.JOIN or name == InputFrame.LEAVE:
			_seat(name == InputFrame.JOIN)
			seatings += 1
			continue
		frame.add_command(name, command.slice(1))
		if frame.to_bytes().size() > FRAME_ROOM:
			frame.commands.pop_back()
			# Alone in a frame and still too big, it could never go: it is dropped. Else it waits.
			if not frame.commands.is_empty():
				passed -= 1
			break
	if passed == _commands.size():
		_commands.clear()
	else:
		_commands = _commands.slice(passed)


## The client is gone: nothing of its is used again, and its wizard stands.
func _drop_client() -> void:
	_last = null
	_presses = 0
	_commands.clear()
	_queued.clear()
	_queued_for.clear()


func after_tick() -> void:
	if not is_running():
		return
	var began: int = Time.get_ticks_usec()
	while _sent < replay.tick_count():
		_send(NetMessage.of_tick(_sent, replay.tick_bytes(_sent)))
		_sent += 1
	stats.ticks = _sent
	stats.net_usec += Time.get_ticks_usec() - began
	if not areas.is_valid():
		return
	var tick: int = _sent - 1
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
			_send(NetMessage.of_pong(message.stamp))
			return ""
		NetMessage.FRAME:
			return _take_frame(message)
		NetMessage.HASHES:
			return _take_check(message)
	return "kind %d is not a client's to send" % message.kind


func _take_frame(message: NetMessage) -> String:
	if replay == null:
		return "a frame before the run"
	var frame := InputFrame.new()
	var why: String = frame.decode(message.body)
	if why != "":
		return "a frame: " + why
	if frame.seat != SEAT:
		return "a frame of seat %d" % frame.seat
	if message.tick < _newest_for:
		return "a frame for tick %d after one for %d" % [message.tick, _newest_for]
	if message.tick > replay.tick_count() + MAX_AHEAD:
		return "a frame for tick %d at tick %d" % [message.tick, replay.tick_count()]
	if _queued.size() >= MAX_QUEUED:
		return "%d frames waiting" % _queued.size()
	_newest_for = message.tick
	_queued.append(frame)
	_queued_for.append(message.tick)
	return ""


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


## The client's virtual device joins seat SEAT (`on`) or leaves it, through the input layer.
func _seat(on: bool) -> void:
	if on and not input.is_joined(SEAT):
		input.add_virtual_device(SEAT)
	elif not on and input.is_joined(SEAT) and InputManagerScript.is_virtual(input.device_of(SEAT)):
		input.leave(SEAT)
