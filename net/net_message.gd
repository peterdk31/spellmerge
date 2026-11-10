class_name NetMessage
extends RefCounted
## One message on the wire (netcode spike S2, docs/milestones/netcode-spike.md): everything two
## machines say to each other. A kind byte, the length of what follows (32 bits), then the kind's
## own bytes, and nothing after.
##
## | Kind | From | Holds |
## |---|---|---|
## | HEADER | host | the run's header (`Replay.header_bytes`), once, first |
## | TICK | host | a tick's number and its bytes (`Replay.tick_bytes`), every tick, in order |
## | FRAME | client | the host's tick a frame is for, and the frame (`InputFrame` bytes) |
## | HASHES | client | a tick, and each area's hash by name (the check, `NetChecks`) |
## | PARTED | host | a tick whose check failed, and the areas that differ (some of them) |
## | PING, PONG | client, host | a stamp, sent back as it came |
##
## The decoder is strict, as the frame's and the replay's are: every size is checked against the
## kind's limit before anything is read, a number is in range, a name is plain text, nothing is
## left over, and anything else rejects the whole message (`decode` says why). It checks the
## envelope; a header's, a tick's and a frame's own bytes are checked by `Replay` and `InputFrame`
## when the session hands them on. No `bytes_to_var`, no objects, no code, no path.
##
##     var bytes: PackedByteArray = NetMessage.of_tick(12, replay.tick_bytes(12))
##     var message := NetMessage.new()
##     if message.decode(bytes) == "" and message.kind == NetMessage.TICK:
##         replay.add_tick_bytes(message.body)

const HEADER: int = 1
const TICK: int = 2
const FRAME: int = 3
const HASHES: int = 4
const PARTED: int = 5
const PING: int = 6
const PONG: int = 7

## The envelope: the kind, then the length of the rest.
const HEAD_BYTES: int = 5
## The highest tick a message may name: a replay's limit, and a frame sent ahead of it.
const MAX_TICK: int = Replay.MAX_TICKS + 3600
## Limits, by what a message holds.
const MAX_HEADER: int = 512
const MAX_TICK_BYTES: int = 1 + Replay.SEATS * (2 + InputFrame.MAX_BYTES)
const MAX_NAME: int = 64
const MAX_AREAS: int = 2048
const MAX_PARTED: int = 16
## The longest message there is (a check of MAX_AREAS areas).
const MAX_BYTES: int = HEAD_BYTES + 6 + MAX_AREAS * (1 + MAX_NAME + 8)

var kind: int = 0
## TICK: the tick's number. FRAME: the host's tick the frame is for. HASHES, PARTED: the tick checked.
var tick: int = 0
## PING, PONG: the stamp (32 bits).
var stamp: int = 0
## HEADER: the header's bytes. TICK: the tick's. FRAME: the frame's.
var body: PackedByteArray = PackedByteArray()
## HASHES: each area's hash, by name.
var hashes: Dictionary[String, int] = {}
## PARTED: the areas that differ.
var names: PackedStringArray = PackedStringArray()


static func of_header(replay_header: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = _start(HEADER, replay_header.size())
	out.append_array(replay_header)
	return out


static func of_tick(number: int, tick_bytes: PackedByteArray) -> PackedByteArray:
	return _numbered(TICK, number, tick_bytes)


## `frame` for the host's tick `for_tick`.
static func of_frame(for_tick: int, frame_bytes: PackedByteArray) -> PackedByteArray:
	return _numbered(FRAME, for_tick, frame_bytes)


## The check of tick `number`: `area_hashes` by name (`SimHash.areas`). A name that is not plain
## text of 1 to MAX_NAME bytes, and any area past MAX_AREAS, is left out (the other machine then
## sees it missing).
static func of_hashes(number: int, area_hashes: Dictionary[String, int]) -> PackedByteArray:
	var out: PackedByteArray = _start(HASHES, 0)
	out.resize(HEAD_BYTES + 6)
	out.encode_u32(HEAD_BYTES, number)
	var count: int = 0
	for name: String in area_hashes:
		if count >= MAX_AREAS or not _is_name(name.to_utf8_buffer()):
			# The other machine will see it missing, and say the games parted there.
			push_warning("NetMessage: the area %s does not fit a check (its name, or more than %d areas), so it is left out." % [name, MAX_AREAS])
			continue
		_add_name(out, name)
		var at: int = out.size()
		out.resize(at + 8)
		out.encode_s64(at, area_hashes[name])
		count += 1
	out.encode_u16(HEAD_BYTES + 4, count)
	out.encode_u32(1, out.size() - HEAD_BYTES)
	return out


## The check of tick `number` failed for `areas` (the first MAX_PARTED of them are named).
static func of_parted(number: int, areas: PackedStringArray) -> PackedByteArray:
	var out: PackedByteArray = _start(PARTED, 0)
	out.resize(HEAD_BYTES + 5)
	out.encode_u32(HEAD_BYTES, number)
	var count: int = 0
	for name in areas:
		if count >= MAX_PARTED:
			break
		if _is_name(name.to_utf8_buffer()):
			_add_name(out, name)
			count += 1
	out[HEAD_BYTES + 4] = count
	out.encode_u32(1, out.size() - HEAD_BYTES)
	return out


static func of_ping(with_stamp: int) -> PackedByteArray:
	return _stamped(PING, with_stamp)


static func of_pong(with_stamp: int) -> PackedByteArray:
	return _stamped(PONG, with_stamp)


static func _start(of_kind: int, length: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(HEAD_BYTES)
	out[0] = of_kind
	out.encode_u32(1, length)
	return out


static func _numbered(of_kind: int, number: int, bytes: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = _start(of_kind, 4 + bytes.size())
	out.resize(HEAD_BYTES + 4)
	out.encode_u32(HEAD_BYTES, number)
	out.append_array(bytes)
	return out


static func _stamped(of_kind: int, with_stamp: int) -> PackedByteArray:
	var out: PackedByteArray = _start(of_kind, 4)
	out.resize(HEAD_BYTES + 4)
	out.encode_u32(HEAD_BYTES, with_stamp & 0xffffffff)
	return out


static func _add_name(out: PackedByteArray, name: String) -> void:
	var text: PackedByteArray = name.to_utf8_buffer()
	out.append(text.size())
	out.append_array(text)


## A name on the wire: 1 to MAX_NAME bytes of printable ASCII (an area's: "Combat", "actor 7").
static func _is_name(text: PackedByteArray) -> bool:
	if text.is_empty() or text.size() > MAX_NAME:
		return false
	for byte in text:
		if byte < 32 or byte > 126:
			return false
	return true


## Read `bytes` into this message: "" when they are one whole valid message, else why not (and the
## message is left empty, of kind 0).
func decode(bytes: PackedByteArray) -> String:
	_clear()
	var problem: String = _decode(bytes)
	if problem != "":
		_clear()
	return problem


func _clear() -> void:
	kind = 0
	tick = 0
	stamp = 0
	body = PackedByteArray()
	hashes = {}
	names = PackedStringArray()


func _decode(bytes: PackedByteArray) -> String:
	if bytes.size() < HEAD_BYTES:
		return "too short (%d bytes)" % bytes.size()
	if bytes.size() > MAX_BYTES:
		return "too long (%d bytes)" % bytes.size()
	var length: int = bytes.decode_u32(1)
	if length != bytes.size() - HEAD_BYTES:
		return "it says %d bytes and holds %d" % [length, bytes.size() - HEAD_BYTES]
	var of_kind: int = bytes[0]
	match of_kind:
		HEADER:
			if length < 1 or length > MAX_HEADER:
				return "a header of %d bytes" % length
			body = bytes.slice(HEAD_BYTES)
		TICK:
			if length < 5 or length > 4 + MAX_TICK_BYTES:
				return "a tick of %d bytes" % length
			var problem: String = _read_tick(bytes)
			if problem != "":
				return problem
			body = bytes.slice(HEAD_BYTES + 4)
		FRAME:
			if length < 4 + InputFrame.HEAD_BYTES or length > 4 + InputFrame.MAX_BYTES:
				return "a frame of %d bytes" % length
			var problem: String = _read_tick(bytes)
			if problem != "":
				return problem
			body = bytes.slice(HEAD_BYTES + 4)
		HASHES:
			var problem: String = _read_hashes(bytes, length)
			if problem != "":
				return problem
		PARTED:
			var problem: String = _read_parted(bytes, length)
			if problem != "":
				return problem
		PING, PONG:
			if length != 4:
				return "a stamp of %d bytes" % length
			stamp = bytes.decode_u32(HEAD_BYTES)
		_:
			return "unknown kind %d" % of_kind
	kind = of_kind
	return ""


func _read_tick(bytes: PackedByteArray) -> String:
	var number: int = bytes.decode_u32(HEAD_BYTES)
	if number > MAX_TICK:
		return "tick %d" % number
	tick = number
	return ""


func _read_hashes(bytes: PackedByteArray, length: int) -> String:
	if length < 6:
		return "a check of %d bytes" % length
	var problem: String = _read_tick(bytes)
	if problem != "":
		return problem
	var count: int = bytes.decode_u16(HEAD_BYTES + 4)
	if count > MAX_AREAS:
		return "%d areas" % count
	var at: int = HEAD_BYTES + 6
	for i in count:
		var end: int = _name_end(bytes, at)
		if end < 0 or end + 8 > bytes.size():
			return "area %d is cut short or no name" % i
		var name: String = bytes.slice(at + 1, end).get_string_from_ascii()
		if hashes.has(name):
			return "area %s twice" % name
		hashes[name] = bytes.decode_s64(end)
		at = end + 8
	if at != bytes.size():
		return "%d bytes left over" % (bytes.size() - at)
	return ""


func _read_parted(bytes: PackedByteArray, length: int) -> String:
	if length < 5:
		return "a parting of %d bytes" % length
	var problem: String = _read_tick(bytes)
	if problem != "":
		return problem
	var count: int = bytes[HEAD_BYTES + 4]
	if count > MAX_PARTED:
		return "%d areas parted" % count
	var at: int = HEAD_BYTES + 5
	for i in count:
		var end: int = _name_end(bytes, at)
		if end < 0:
			return "area %d is cut short or no name" % i
		names.append(bytes.slice(at + 1, end).get_string_from_ascii())
		at = end
	if at != bytes.size():
		return "%d bytes left over" % (bytes.size() - at)
	return ""


## Where the name at `at` (its length, then its text) ends, or -1 when there is no valid name.
static func _name_end(bytes: PackedByteArray, at: int) -> int:
	if at >= bytes.size():
		return -1
	var end: int = at + 1 + bytes[at]
	if end > bytes.size() or not _is_name(bytes.slice(at + 1, end)):
		return -1
	return end
