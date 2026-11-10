class_name NetPressProbe
extends RefCounted
## Times the client's presses (netcode spike S2 and S5, docs/milestones/netcode-spike.md): from
## the physics step a press was sent to the host to the step the host's tick carrying it ran
## here, the input delay a player feels. A measure only: it reads the replay, and changes nothing.
##
## Two presses of one staff sent before the first came back count as one.

var stats: NetStats
var seat: int
## The ticks of the replay looked through.
var _seen: int = 0
## Per staff: the step its press was sent, or -1 with none waiting to come back.
var _pressed_at: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1])
var _played: Array[InputFrame] = []


func _init(into: NetStats, of_seat: int) -> void:
	stats = into
	seat = of_seat
	for i in Replay.SEATS:
		_played.append(InputFrame.new())


## The seat's frame `frame` is sent in physics step `step`.
func sent(frame: InputFrame, step: int) -> void:
	for staff in InputFrame.STAFFS:
		if frame.is_pressed(staff) and _pressed_at[staff] < 0:
			_pressed_at[staff] = step
			stats.presses_sent += 1


## `replay` was played up to `tick` (not including it) by the step before `step`: the seat's
## presses in the ticks not looked through yet are timed.
func played(replay: Replay, tick: int, step: int) -> void:
	while _seen < tick:
		replay.read_tick(_seen, _played)
		_seen += 1
		var pressed: int = _played[seat].pressed_bits
		for staff in InputFrame.STAFFS:
			if pressed & (1 << staff) != 0 and _pressed_at[staff] >= 0:
				stats.add_press(step - 1 - _pressed_at[staff])
				_pressed_at[staff] = -1
