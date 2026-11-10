class_name NetGuest
extends NetSession
## One guest machine as the host sees it (online lobby L3, docs/milestones/online-lobby.md): its
## link, the seats the host gave it, the frames it sent for them, its limits, its checks and its
## counters. The host (`NetHost`) holds one for each guest machine, up to three, and the recording
## they all play; a guest knows nothing of the others.
##
## - **Its frames** each name the host's tick they are for and one of its seats (a FRAME a seat a
##   step). When a seat's frame is built for a tick, every frame of that seat that arrived for that
##   tick or an earlier one is used up: the walk, the aim and the buttons held are the newest's, the
##   presses and the commands are all of theirs, in order. **A frame that has not arrived** is stood
##   in for by the last one without its presses and commands (a button held stays held; a command
##   never applies twice), and its own presses and commands come with the next frame used. A JOIN
##   or LEAVE in a guest's frame is done here through the input layer, never passed on in the frame.
##   Commands that do not fit the tick's frame (its count, its bytes) wait for the next.
## - **The link is read** once a tick, when the first of its seats' frames is built, and before the
##   run by `pump` from whoever holds the host. No `_process`, no thread.
## - **Its check** of a tick is compared with the host's own of that tick (`kept`, the host's);
##   where they differ the guest is told and the parting kept here (`parted_tick`).
## - **The guest gone** (the link closed and all it sent used, or refused): its seats leave, as a
##   pad pulled out would, each when its own frame is next built (so its LEAVE is in that seat's
##   frame of the tick it left in); the others play on.
##
## What a guest sends is untrusted. Beyond the decoders it is held, each guest on its own, to:
## MAX_READ messages a tick, MAX_QUEUED frames waiting for their tick (all its seats together), none for a tick more
## than MAX_AHEAD ahead or before the one before it, none for a seat that is not its own,
## MAX_COMMANDS_WAITING commands a seat not yet in a tick, and one check per window, in order.

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

var input: InputManagerScript
## The seats the host gave this machine (a bit each). Read only: the host sets it.
var seats: int = 0
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


func _init(frames_service: FramesScript, input_layer: InputManagerScript, over: NetLink, on_seats: int, state_areas: Callable = Callable()) -> void:
	super(frames_service, over, state_areas)
	input = input_layer
	seats = on_seats & 0x0f
	max_read = MAX_READ


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
		seat_one(seat, false)
		return
	if _read_at != tick:
		_read_at = tick
		pump()
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
		seat_one(seat, false)
		return
	if not fresh and _last[seat] != null:
		stats.stood_in += 1
	var last_used: InputFrame = _last[seat]
	if last_used == null:
		return
	frame.move = last_used.move
	frame.aim = last_used.aim
	frame.held_bits = last_used.held_bits
	frame.captured = last_used.captured
	frame.pressed_bits = _presses[seat]
	_presses[seat] = 0
	_pass_commands(seat, frame)


## True when nothing this guest sent waits to be used, for any of its seats.
func _all_used() -> bool:
	for seat in Replay.SEATS:
		if not _queued[seat].is_empty():
			return false
	return true


## The commands of seat `seat`'s frames used up, into `frame`, in order, while they fit it (a
## frame's command count, FRAME_ROOM); the rest wait for the next tick. A JOIN or LEAVE is done
## through the input layer, which then writes it into this frame itself: it needs a place too, and
## where it stands among the tick's commands does not matter (a tick's seats change before any of
## its commands apply, on the host and in the replay alike).
func _pass_commands(seat: int, frame: InputFrame) -> void:
	var waiting: Array = _commands[seat]
	var passed: int = 0
	var seatings: int = 0
	for command: Array in waiting:
		if frame.commands.size() + seatings >= InputFrame.MAX_COMMANDS:
			break
		var name: StringName = command[0]
		passed += 1
		if name == InputFrame.JOIN or name == InputFrame.LEAVE:
			seat_one(seat, name == InputFrame.JOIN)
			seatings += 1
			continue
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
			_send(NetMessage.of_pong(message.stamp))
			return ""
		NetMessage.FRAME:
			return _take_frame(message)
		NetMessage.HASHES:
			return _take_check(message)
	return "kind %d is not a guest's to send" % message.kind


func _take_frame(message: NetMessage) -> String:
	if replay == null:
		return "a frame before the run"
	var frame := InputFrame.new()
	var why: String = frame.decode(message.body)
	if why != "":
		return "a frame: " + why
	var seat: int = frame.seat
	if not owns(seat):
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
	if replay == null or message.tick >= replay.tick_count():
		return "a check of tick %d, not played yet" % message.tick
	if message.tick <= checked_to or posmod(message.tick, checks.every) != checks.every - 1:
		return "a check of tick %d after one of %d" % [message.tick, checked_to]
	checked_to = message.tick
	if not kept.has(message.tick):
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
