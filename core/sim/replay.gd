class_name Replay
extends RefCounted
## A recorded run (online-ready N2, docs/milestones/online-ready.md): how it started and every
## seat's input frame at every tick, inputs only. Played back from the same start it gives the same
## game, tick for tick (the frames service records and plays one: `Frames.record`, `Frames.play`).
## A bug report can carry one (a later intake task); the determinism tests play the real game
## through one (tests/core/test_replay_game.gd).
##
## - **The header:** the build (`build`: its version and commit), the content (`content`: a hash of
##   every content id, `content_of`), the run's seed (`run_seed`, which `SimSeed` deals the seeds
##   nobody chose from), how it started (`start`, one of STARTS, and `starter`, the seat that
##   asked) and the seats joined at the start (`seats`, a bit per seat).
## - **The ticks:** per tick a byte of the seats with a frame, then each one's frame (its length,
##   then `InputFrame` bytes). Kept as bytes (`add_tick`, `read_tick`), so an hour of four seats is
##   a few megabytes and recording allocates no object per tick.
##
## Files live in `user://replays/` only (`save`, `open`), named by an id (letters, digits, `_`).
## The decoder is as strict as the frame's: every size, value and frame is checked when the
## bytes are read, and a bad file is rejected whole (`decode` says why). Nothing in it is ever
## code, a resource or a path.

const RegistryScript := preload("res://core/registry/registry.gd")

const MAGIC: PackedByteArray = [0x53, 0x4d, 0x52, 0x50]
## The file format's version.
const FORMAT: int = 1
const FOLDER: String = "user://replays/"
const EXTENSION: String = ".replay"
## The requests a run starts by (core/events): Play, the sandbox, the horde.
const STARTS: Array[StringName] = [&"play_requested", &"sandbox_requested", &"horde_requested"]
const SEATS: int = 4
## Limits: four hours at 60 ticks a second, and the file's bytes.
const MAX_TICKS: int = 60 * 60 * 60 * 4
const MAX_BYTES: int = 64 * 1024 * 1024
const MAX_BUILD: int = 64

var build: String = ""
var content: int = 0
var run_seed: int = 0
var start: StringName = &"sandbox_requested"
var starter: int = 0
var seats: int = 0

var _data: PackedByteArray = PackedByteArray()
## Where each tick starts in `_data`.
var _offsets: PackedInt32Array = PackedInt32Array()


## How many ticks it holds.
func tick_count() -> int:
	return _offsets.size()


## Append a tick: the frame of every seat whose bit is set in `mask` (`frames` by seat).
func add_tick(frames: Array[InputFrame], mask: int) -> void:
	_offsets.append(_data.size())
	_data.append(mask & 0x0f)
	for seat in SEATS:
		if mask & (1 << seat) == 0:
			continue
		var at: int = _data.size()
		_data.resize(at + 2)
		frames[seat].encode_into(_data)
		_data.encode_u16(at, _data.size() - at - 2)


## Read tick `tick` into `frames` (four, by seat): a seat with no frame that tick is cleared.
## Returns the seats with a frame (a bit each), or -1 for a tick it does not hold.
func read_tick(tick: int, frames: Array[InputFrame]) -> int:
	if tick < 0 or tick >= _offsets.size():
		return -1
	var at: int = _offsets[tick]
	var mask: int = _data[at]
	at += 1
	for seat in SEATS:
		frames[seat].seat = seat
		if mask & (1 << seat) == 0:
			frames[seat].clear()
			continue
		var size: int = _data.decode_u16(at)
		# Checked when it was read or written, so this cannot fail.
		frames[seat].decode(_data.slice(at + 2, at + 2 + size))
		at += 2 + size
	return mask


## The whole replay as bytes: the header, the tick count, the ticks.
func to_bytes() -> PackedByteArray:
	var out := PackedByteArray(MAGIC)
	out.append(FORMAT)
	var text: PackedByteArray = build.left(MAX_BUILD).to_ascii_buffer()
	out.append(text.size())
	out.append_array(text)
	var at: int = out.size()
	out.resize(at + 16)
	out.encode_s64(at, content)
	out.encode_s64(at + 8, run_seed)
	out.append(maxi(STARTS.find(start), 0))
	out.append(starter)
	out.append(seats & 0x0f)
	at = out.size()
	out.resize(at + 4)
	out.encode_u32(at, _offsets.size())
	out.append_array(_data)
	return out


## The replay in `bytes`, or null when they are not a valid one (`decode` says why).
static func from_bytes(bytes: PackedByteArray) -> Replay:
	var replay := Replay.new()
	return replay if replay.decode(bytes) == "" else null


## Read `bytes` into this replay: "" when they are one whole valid replay, else why not (and it
## is left empty).
func decode(bytes: PackedByteArray) -> String:
	var problem: String = _decode(bytes)
	if problem != "":
		build = ""
		content = 0
		run_seed = 0
		starter = 0
		seats = 0
		_data = PackedByteArray()
		_offsets = PackedInt32Array()
	return problem


func _decode(bytes: PackedByteArray) -> String:
	if bytes.size() > MAX_BYTES:
		return "too long (%d bytes)" % bytes.size()
	if bytes.size() < MAGIC.size() + 2 or bytes.slice(0, MAGIC.size()) != MAGIC:
		return "not a replay"
	if bytes[4] != FORMAT:
		return "format %d, not %d" % [bytes[4], FORMAT]
	var size: int = bytes[5]
	var at: int = 6
	if size > MAX_BUILD or at + size + 23 > bytes.size():
		return "the header is cut short"
	var text: PackedByteArray = bytes.slice(at, at + size)
	for byte in text:
		if byte < 32 or byte > 126:
			return "the build is not plain text"
	build = text.get_string_from_ascii()
	at += size
	content = bytes.decode_s64(at)
	run_seed = bytes.decode_s64(at + 8)
	at += 16
	if bytes[at] >= STARTS.size():
		return "unknown start %d" % bytes[at]
	start = STARTS[bytes[at]]
	if bytes[at + 1] >= SEATS:
		return "starter %d" % bytes[at + 1]
	starter = bytes[at + 1]
	if bytes[at + 2] > 0x0f:
		return "seats %d" % bytes[at + 2]
	seats = bytes[at + 2]
	var ticks: int = bytes.decode_u32(at + 3)
	at += 7
	if ticks > MAX_TICKS:
		return "%d ticks" % ticks
	_data = bytes.slice(at)
	_offsets = PackedInt32Array()
	_offsets.resize(ticks)
	var frame := InputFrame.new()
	var read: int = 0
	for tick in ticks:
		if read >= _data.size():
			return "tick %d is missing" % tick
		_offsets[tick] = read
		var mask: int = _data[read]
		if mask > 0x0f:
			return "tick %d: seats %d" % [tick, mask]
		read += 1
		for seat in SEATS:
			if mask & (1 << seat) == 0:
				continue
			if read + 2 > _data.size():
				return "tick %d: seat %d is cut short" % [tick, seat]
			var length: int = _data.decode_u16(read)
			if read + 2 + length > _data.size():
				return "tick %d: seat %d is cut short" % [tick, seat]
			var problem: String = frame.decode(_data.slice(read + 2, read + 2 + length))
			if problem != "":
				return "tick %d: seat %d: %s" % [tick, seat, problem]
			if frame.seat != seat:
				return "tick %d: seat %d holds seat %d's frame" % [tick, seat, frame.seat]
			read += 2 + length
	if read != _data.size():
		return "%d bytes left over" % (_data.size() - read)
	return ""


## Save it as `user://replays/<name>.replay` (`name`: letters, digits, `_`).
func save(name: String) -> Error:
	if name == "" or not InputFrame.is_id(name):
		return ERR_INVALID_PARAMETER
	var made: Error = DirAccess.make_dir_recursive_absolute(FOLDER)
	if made != OK:
		return made
	var file: FileAccess = FileAccess.open(FOLDER + name + EXTENSION, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(to_bytes())
	file.close()
	return OK


## The replay saved as `name` (`save`), or null when there is none or it is not a valid replay.
static func open(name: String) -> Replay:
	if name == "" or not InputFrame.is_id(name):
		return null
	var file: FileAccess = FileAccess.open(FOLDER + name + EXTENSION, FileAccess.READ)
	if file == null:
		return null
	var length: int = file.get_length()
	if length > MAX_BYTES:
		push_warning("Replay: %s is too long to be a replay (%d bytes)." % [name, length])
		return null
	var bytes: PackedByteArray = file.get_buffer(length)
	file.close()
	var replay := Replay.new()
	var problem: String = replay.decode(bytes)
	if problem != "":
		push_warning("Replay: %s is not a valid replay: %s." % [name, problem])
		return null
	return replay


## This build, as a replay names it: its version and commit (core/base/build_info.gd).
static func build_of() -> String:
	var text: String = BuildInfo.version()
	if BuildInfo.commit() != "":
		text += " " + BuildInfo.commit().left(12)
	return text.left(MAX_BUILD)


## A hash of the content `registry` holds (every folder and every id in it, in order): a replay
## of other content is another game. It does not see a changed number inside a file; with `build`
## (the commit) that is "the same nightly or the same stable".
static func content_of(registry: RegistryScript) -> int:
	if registry == null:
		return 0
	var context := HashingContext.new()
	context.start(HashingContext.HASH_MD5)
	for folder: StringName in registry.get_folders():
		context.update(String(folder).to_utf8_buffer())
		for id: StringName in registry.get_ids(folder):
			context.update(PackedByteArray([0]))
			context.update(String(id).to_utf8_buffer())
		context.update(PackedByteArray([1]))
	return context.finish().decode_s64(0)
