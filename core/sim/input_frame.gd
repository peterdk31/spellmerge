class_name InputFrame
extends RefCounted
## One seat's input for one tick (online-ready N2, docs/milestones/online-ready.md): what the
## simulation takes from a person, a bot, a replay and later the network, all alike. Its seat's
## `PlayerController` builds the actor's intent from it, never from a device.
##
## - `move`: the walk, a signed byte per axis (-127 to 127; `set_move`, `move_vector`).
## - `aim`: an angle in 1/65,536 of a turn (0 is +x, a quarter turn is +y), or AIM_KEEP: keep the
##   aim the actor has (`set_aim`, `aim_vector`).
## - `held_bits`, `pressed_bits`: bit `staff` (0-3) while that staff's button is down, and when it
##   went down since the last frame (a fresh press; the press buffer is the simulation's).
## - `captured`: an overlay of this seat is open (its builder): the walk stops and nothing casts.
## - `commands`: what the seat asked for this tick, applied at its start: the HUD's requests the
##   simulation hears (`COMMAND_NAMES`, each `[name, args...]` without the seat: a frame only
##   speaks for its own seat) and its device joining and leaving (JOIN, LEAVE).
##
## `to_bytes` / `from_bytes` are its wire and file form. The decoder is strict: every size is
## checked, every value is in range, a text is an id (letters, digits, `_`), nothing is left over,
## and anything else rejects the whole frame (`decode` says why). No `bytes_to_var`, no objects.
##
##     var frame := InputFrame.new()
##     frame.seat = 1
##     frame.set_move(Vector2(0.5, -1.0))
##     frame.set_aim(Vector2.DOWN)
##     frame.press(0)
##     frame.add_command(&"staff_change_requested", [2, 0, &"fire"])
##     var back: InputFrame = InputFrame.from_bytes(frame.to_bytes())   # null if rejected

## The format's version, the frame's first byte (2: the horde's commands gone, the kinds after
## them renumbered).
const VERSION: int = 2
const SEATS: int = 4
const STAFFS: int = 4
## A move axis of 1.0 is this byte.
const MOVE_MAX: int = 127
## An aim angle's steps in a turn.
const AIM_STEPS: int = 65536
## `aim` for "keep the aim the actor has".
const AIM_KEEP: int = -1
## The flags byte.
const FLAG_CAPTURED: int = 1
const FLAG_AIM_KEEP: int = 2
const FLAGS_KNOWN: int = FLAG_CAPTURED | FLAG_AIM_KEEP
## The fixed part: version, seat, flags, buttons, move x, move y, aim (2), command count.
const HEAD_BYTES: int = 9
## Limits the decoder holds a frame to.
const MAX_COMMANDS: int = 16
const MAX_TEXT: int = 64
const MAX_LIST: int = 64
const MAX_BYTES: int = 16384

## A seat's device joined or left (`device_joined`, `device_left`): in a frame so a replay (and
## later the network) knows the tick it happened.
const JOIN: StringName = &"join"
const LEAVE: StringName = &"leave"
## The commands, by kind (the byte on the wire), and the shape of each one's arguments after the
## seat: `i` an int (32 bits), `s` an id (a StringName), `S` a list of ids. The HUD's requests are
## the `*_requested` events of core/events the simulation hears (`EventsScript.COMMANDS`, the same
## names); a kind is only ever added at the end.
const COMMAND_NAMES: Array[StringName] = [
	JOIN, LEAVE,
	&"staff_change_requested", &"card_move_requested", &"staff_cards_requested",
	&"sandbox_action_requested", &"sandbox_spawn_requested",
	&"reward_pick_requested", &"door_vote_requested",
	&"shot_cap_requested",
	&"pause_requested",
]
const COMMAND_SHAPES: PackedStringArray = [
	"", "",
	"iis", "iiii", "iS",
	"s", "si",
	"i", "i",
	"i",
	"i",
]

var seat: int = 0
var move: Vector2i = Vector2i.ZERO
var aim: int = AIM_KEEP
var held_bits: int = 0
var pressed_bits: int = 0
var captured: bool = false
## This tick's commands, each `[name, args...]` (see the class doc).
var commands: Array[Array] = []


## Nothing wanted: no walk, keep the aim, no button, no command (the seat stays).
func clear() -> void:
	move = Vector2i.ZERO
	aim = AIM_KEEP
	held_bits = 0
	pressed_bits = 0
	captured = false
	if not commands.is_empty():
		commands.clear()


## The walk `direction` (length 0 to 1), quantised to a byte per axis.
func set_move(direction: Vector2) -> void:
	move = Vector2i(_axis(direction.x), _axis(direction.y))


static func _axis(value: float) -> int:
	if is_nan(value):
		return 0
	return clampi(roundi(clampf(value, -1.0, 1.0) * MOVE_MAX), -MOVE_MAX, MOVE_MAX)


## The walk the simulation takes: the bytes back as a vector, no longer than 1.
func move_vector() -> Vector2:
	return Vector2(float(move.x) / MOVE_MAX, float(move.y) / MOVE_MAX).limit_length(1.0)


## Aim along `direction` (any length), quantised to 1/65,536 of a turn; ZERO (or not finite)
## keeps the aim the actor has.
func set_aim(direction: Vector2) -> void:
	if direction == Vector2.ZERO or not direction.is_finite():
		aim = AIM_KEEP
		return
	aim = posmod(roundi(DMath.angle(direction) / TAU * AIM_STEPS), AIM_STEPS)


## The aim the simulation takes: a unit vector, or ZERO to keep the actor's aim. (Engine trig:
## N7 moves it to DMath.)
func aim_vector() -> Vector2:
	if aim == AIM_KEEP:
		return Vector2.ZERO
	return DMath.from_angle(float(aim) * TAU / AIM_STEPS)


## Staff `staff` (0-3) went down since the last frame.
func press(staff: int) -> void:
	if staff >= 0 and staff < STAFFS:
		pressed_bits |= 1 << staff


## Staff `staff`'s button is down (`on`) or up.
func hold(staff: int, on: bool) -> void:
	if staff >= 0 and staff < STAFFS:
		if on:
			held_bits |= 1 << staff
		else:
			held_bits &= ~(1 << staff)


func is_pressed(staff: int) -> bool:
	return staff >= 0 and staff < STAFFS and (pressed_bits & (1 << staff)) != 0


func is_held(staff: int) -> bool:
	return staff >= 0 and staff < STAFFS and (held_bits & (1 << staff)) != 0


## Add the command `name` with `args` (its arguments after the seat). False, and nothing is added,
## for a name that is no command, arguments of the wrong shape, an id that is not one, or a full
## frame: what the decoder would reject is never written.
func add_command(name: StringName, args: Array = []) -> bool:
	var kind: int = COMMAND_NAMES.find(name)
	if kind < 0 or commands.size() >= MAX_COMMANDS:
		return false
	var shape: String = COMMAND_SHAPES[kind]
	if args.size() != shape.length():
		return false
	var command: Array = [name]
	for at in shape.length():
		var value: Variant = args[at]
		match shape[at]:
			"i":
				if typeof(value) != TYPE_INT or int(value) < -2147483648 or int(value) > 2147483647:
					return false
				command.append(int(value))
			"s":
				if not (value is StringName or value is String) or not is_id(String(value)):
					return false
				command.append(StringName(value))
			"S":
				if not (value is Array) or (value as Array).size() > MAX_LIST:
					return false
				var ids: Array[StringName] = []
				for item: Variant in value:
					if not (item is StringName or item is String) or not is_id(String(item)):
						return false
					ids.append(StringName(item))
				command.append(ids)
	commands.append(command)
	return true


## True for a text a command may carry: up to MAX_TEXT bytes of letters, digits and `_` (an id;
## empty is one, the "nothing" of an emptied slot). Never a path or anything else.
static func is_id(text: String) -> bool:
	if text.length() > MAX_TEXT:
		return false
	for at in text.length():
		var code: int = text.unicode_at(at)
		var ok: bool = (code >= 97 and code <= 122) or (code >= 65 and code <= 90) or (code >= 48 and code <= 57) or code == 95
		if not ok:
			return false
	return true


## Become a copy of `other` (its commands too).
func copy_from(other: InputFrame) -> void:
	seat = other.seat
	move = other.move
	aim = other.aim
	held_bits = other.held_bits
	pressed_bits = other.pressed_bits
	captured = other.captured
	commands.clear()
	for command in other.commands:
		commands.append(command.duplicate(true))


## The frame's bytes (see `encode_into`).
func to_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	encode_into(out)
	return out


## Append the frame's bytes to `out`: the head (HEAD_BYTES), then each command's kind and
## arguments (an int as 4 bytes, little-endian; an id as its length and UTF-8 bytes; a list as its
## count and ids).
func encode_into(out: PackedByteArray) -> void:
	var at: int = out.size()
	out.resize(at + HEAD_BYTES)
	var flags: int = (FLAG_CAPTURED if captured else 0) | (FLAG_AIM_KEEP if aim == AIM_KEEP else 0)
	out[at] = VERSION
	out[at + 1] = seat
	out[at + 2] = flags
	out[at + 3] = (held_bits & 0x0f) | ((pressed_bits & 0x0f) << 4)
	out.encode_s8(at + 4, move.x)
	out.encode_s8(at + 5, move.y)
	out.encode_u16(at + 6, 0 if aim == AIM_KEEP else aim)
	out[at + 8] = commands.size()
	for command in commands:
		var kind: int = COMMAND_NAMES.find(command[0])
		out.append(kind)
		var shape: String = COMMAND_SHAPES[kind]
		for arg in shape.length():
			var value: Variant = command[arg + 1]
			match shape[arg]:
				"i":
					var size: int = out.size()
					out.resize(size + 4)
					out.encode_s32(size, int(value))
				"s":
					_encode_id(out, value)
				"S":
					var ids: Array = value
					out.append(ids.size())
					for id: Variant in ids:
						_encode_id(out, id)


static func _encode_id(out: PackedByteArray, id: Variant) -> void:
	var bytes: PackedByteArray = String(id).to_utf8_buffer()
	out.append(bytes.size())
	out.append_array(bytes)


## The frame in `bytes`, or null when it is not a valid frame (`decode` says why).
static func from_bytes(bytes: PackedByteArray) -> InputFrame:
	var frame := InputFrame.new()
	return frame if frame.decode(bytes) == "" else null


## Read `bytes` into this frame: "" when they are one whole valid frame, else why not (and the
## frame is left cleared).
func decode(bytes: PackedByteArray) -> String:
	clear()
	var problem: String = _decode(bytes)
	if problem != "":
		clear()
	return problem


func _decode(bytes: PackedByteArray) -> String:
	if bytes.size() < HEAD_BYTES:
		return "too short (%d bytes)" % bytes.size()
	if bytes.size() > MAX_BYTES:
		return "too long (%d bytes)" % bytes.size()
	if bytes[0] != VERSION:
		return "version %d, not %d" % [bytes[0], VERSION]
	if bytes[1] >= SEATS:
		return "seat %d" % bytes[1]
	var flags: int = bytes[2]
	if flags & ~FLAGS_KNOWN != 0:
		return "unknown flags %d" % flags
	var x: int = bytes.decode_s8(4)
	var y: int = bytes.decode_s8(5)
	if x < -MOVE_MAX or y < -MOVE_MAX:
		return "move out of range"
	var angle: int = bytes.decode_u16(6)
	if flags & FLAG_AIM_KEEP != 0 and angle != 0:
		return "an aim beside keep"
	var count: int = bytes[8]
	if count > MAX_COMMANDS:
		return "%d commands" % count
	seat = bytes[1]
	captured = flags & FLAG_CAPTURED != 0
	held_bits = bytes[3] & 0x0f
	pressed_bits = bytes[3] >> 4
	move = Vector2i(x, y)
	aim = AIM_KEEP if flags & FLAG_AIM_KEEP != 0 else angle
	var at: int = HEAD_BYTES
	for i in count:
		if at >= bytes.size():
			return "command %d is missing" % i
		var kind: int = bytes[at]
		at += 1
		if kind >= COMMAND_NAMES.size():
			return "unknown command %d" % kind
		var shape: String = COMMAND_SHAPES[kind]
		var command: Array = [COMMAND_NAMES[kind]]
		for arg in shape.length():
			match shape[arg]:
				"i":
					if at + 4 > bytes.size():
						return "command %d is cut short" % i
					command.append(bytes.decode_s32(at))
					at += 4
				"s":
					var read: Array = _decode_id(bytes, at)
					if read.is_empty():
						return "command %d has a bad id" % i
					command.append(read[0])
					at = read[1]
				"S":
					if at >= bytes.size() or bytes[at] > MAX_LIST:
						return "command %d has a bad list" % i
					var size: int = bytes[at]
					at += 1
					var ids: Array[StringName] = []
					for item in size:
						var read: Array = _decode_id(bytes, at)
						if read.is_empty():
							return "command %d has a bad id" % i
						ids.append(read[0])
						at = read[1]
					command.append(ids)
		commands.append(command)
	if at != bytes.size():
		return "%d bytes left over" % (bytes.size() - at)
	return ""


## The id at `at` and where the next value starts, or [] when there is no valid id there.
static func _decode_id(bytes: PackedByteArray, at: int) -> Array:
	if at >= bytes.size():
		return []
	var size: int = bytes[at]
	if size > MAX_TEXT or at + 1 + size > bytes.size():
		return []
	var raw: PackedByteArray = bytes.slice(at + 1, at + 1 + size)
	# ASCII only: every byte a letter, digit or `_` (so the text is its own UTF-8).
	for byte in raw:
		var ok: bool = (byte >= 97 and byte <= 122) or (byte >= 65 and byte <= 90) or (byte >= 48 and byte <= 57) or byte == 95
		if not ok:
			return []
	return [StringName(raw.get_string_from_ascii()), at + 1 + size]
