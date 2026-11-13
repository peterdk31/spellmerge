class_name Replay
extends RefCounted
## A recorded run (online-ready N2, docs/milestones/online-ready.md): how it started and every
## seat's input frame at every tick, inputs only. Played back from the same start it gives the same
## game, tick for tick (the frames service records and plays one: `Frames.record`, `Frames.play`).
## A bug report can carry one (a later intake task); the determinism tests play the real game
## through one (tests/core/test_replay_game.gd).
##
## - **The header:** the build (`build`: its version and commit), the content (`content`: a hash of
##   every content id, `content_of`), the run's seed (`run_seed`: the runs it starts deal theirs
##   from it, core/sim/replay_tape.gd), how it started (`start`, one of STARTS, and `starter`, the seat that
##   asked), the seats joined at the start (`seats`, a bit per seat) and the run's rules (`rules`:
##   the shot cap, the step budgets; core/sim/session_rules.gd, online-ready N11),
##   so it plays the same on a machine whose own settings are others, and what the run takes along
##   from the play before it (`carry`: each seat's staffs and their cards; core/sim/run_carry.gd, online lobby).
## - **The ticks:** per tick a byte of the seats with a frame (a bit each), then each seat's frame
##   (its length, then `InputFrame` bytes). The game's stops need no mark: they are its state
##   (online-ready N4), so a replay stands still where the recording did. Kept as bytes (`add_tick`, `read_tick`), so an hour of four seats is
##   a few megabytes and recording allocates no object per tick.
##
## Files live in `user://replays/` only (`save`, `open`), named by an id (letters, digits, `_`).
## The decoder is as strict as the frame's: every size, value and frame is checked when the
## bytes are read, and a bad file is rejected whole (`decode` says why). Nothing in it is ever
## code, a resource or a path.
##
## **A replay that grows while it plays** (netcode spike S1, docs/milestones/netcode-spike.md): the
## header alone (`header_bytes`, read back by `decode` as a replay of no ticks), then its ticks one
## by one (`tick_bytes` out, `add_tick_bytes` in, each checked by the same decoder as a file's).
## The online client plays one so (`Frames.play_live`).

const RegistryScript := preload("res://core/registry/registry.gd")

const MAGIC: PackedByteArray = [0x53, 0x4d, 0x52, 0x50]
## The file format's version (2: the run's rules in the header, N11; 3: no "paused" bit in a
## tick's byte, the stops being state, N4; 4: no horde, its start, cap and commands gone; 5: what
## the run takes along, after the rules; 6: each carried staff's own id after its cards). A replay
## of another format is refused.
const FORMAT: int = 6
const FOLDER: String = "user://replays/"
const EXTENSION: String = ".replay"
## The requests a run starts by (core/events): a run of waves, the sandbox, the hub (online-lobby
## L1; the main menu's Play). A new one goes at the end, so the replays made before keep their start.
const STARTS: Array[StringName] = [&"play_requested", &"sandbox_requested", &"hub_requested"]
const SEATS: int = 4
## Limits: four hours at 60 ticks a second, and the file's bytes.
const MAX_TICKS: int = 60 * 60 * 60 * 4
const MAX_BYTES: int = 64 * 1024 * 1024
const MAX_BUILD: int = 64
## The most bytes a header takes (`header_bytes`): magic, format, the build, content and seed, start,
## starter and seats, the rules, what is carried at its most, the tick count.
const MAX_HEADER_BYTES: int = 4 + 1 + 1 + MAX_BUILD + 16 + 3 + SessionRules.BYTES + RunCarry.MAX_BYTES + 4

var build: String = ""
var content: int = 0
var run_seed: int = 0
var start: StringName = &"sandbox_requested"
var starter: int = 0
var seats: int = 0
## The rules the run played by (`Frames.record` takes this machine's; the runs it plays take them).
var rules: SessionRules = SessionRules.defaults()
## What the run takes along from the play before it (`Frames.record` asks the game; the run it starts
## takes it, `Frames.next_run_carry`).
var carry: RunCarry = RunCarry.new()

var _data: PackedByteArray = PackedByteArray()
## Where each tick starts in `_data`.
var _offsets: PackedInt32Array = PackedInt32Array()
## Where the last tick `_check_tick` read ends in the bytes it read (scratch).
var _checked_to: int = 0
## The frame the decoder reads each tick's frames into, to check them (scratch).
var _check_frame: InputFrame = InputFrame.new()


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
	var mask: int = _data[at] & 0x0f
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


## Tick `tick`'s bytes (the seats' byte, then each seat's frame), as `add_tick_bytes` takes them;
## empty for a tick it does not hold.
func tick_bytes(tick: int) -> PackedByteArray:
	if tick < 0 or tick >= _offsets.size():
		return PackedByteArray()
	var end: int = _offsets[tick + 1] if tick + 1 < _offsets.size() else _data.size()
	return _data.slice(_offsets[tick], end)


## Append a tick from its bytes (`tick_bytes` of another replay): "" when they are one whole valid
## tick, else why not (and nothing is added). Checked as a file's ticks are, and within the same
## limits.
func add_tick_bytes(bytes: PackedByteArray) -> String:
	if _offsets.size() >= MAX_TICKS:
		return "%d ticks" % (_offsets.size() + 1)
	if _data.size() + bytes.size() > MAX_BYTES:
		return "too long (%d bytes)" % (_data.size() + bytes.size())
	var problem: String = _check_tick(bytes, 0, _offsets.size())
	if problem != "":
		return problem
	if _checked_to != bytes.size():
		return "tick %d: %d bytes left over" % [_offsets.size(), bytes.size() - _checked_to]
	_offsets.append(_data.size())
	_data.append_array(bytes)
	return ""


## The header alone as bytes (a replay of no ticks, as `decode` reads it): what an online client is
## sent before the ticks.
func header_bytes() -> PackedByteArray:
	return _encode(false)


## The seats seated before tick `tick` plays (a bit each): the header's, then each JOIN and LEAVE
## of the ticks before it (a replay sought, `Frames.seek`).
func seats_at(tick: int) -> int:
	var mask: int = seats & 0x0f
	var frames: Array[InputFrame] = []
	for seat in SEATS:
		frames.append(InputFrame.new())
	for at in mini(tick, _offsets.size()):
		read_tick(at, frames)
		for seat in SEATS:
			for command: Array in frames[seat].commands:
				if command[0] == InputFrame.JOIN:
					mask |= 1 << seat
				elif command[0] == InputFrame.LEAVE:
					mask &= ~(1 << seat)
	return mask


## The whole replay as bytes: the header, the tick count, the ticks.
func to_bytes() -> PackedByteArray:
	return _encode(true)


## The header, then the tick count and the ticks (`ticks`) or a count of none.
func _encode(ticks: bool) -> PackedByteArray:
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
	rules.encode_into(out)
	carry.encode_into(out)
	at = out.size()
	out.resize(at + 4)
	out.encode_u32(at, _offsets.size() if ticks else 0)
	if ticks:
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
		rules = SessionRules.defaults()
		carry = RunCarry.new()
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
	# The fixed part: 16 bytes of content and seed, 3 of start, starter and seats, the rules, a byte
	# at least of what is carried, 4 of tick count.
	if size > MAX_BUILD or at + size + 24 + SessionRules.BYTES > bytes.size():
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
	at += 3
	var read_rules := SessionRules.new()
	var rules_problem: String = read_rules.decode_at(bytes, at)
	if rules_problem != "":
		return rules_problem
	rules = read_rules
	at += SessionRules.BYTES
	var read_carry := RunCarry.new()
	var carry_problem: String = read_carry.decode_at(bytes, at)
	if carry_problem != "":
		return carry_problem
	carry = read_carry
	at = read_carry.read_to
	if at + 4 > bytes.size():
		return "the header is cut short"
	var ticks: int = bytes.decode_u32(at)
	at += 4
	if ticks > MAX_TICKS:
		return "%d ticks" % ticks
	_data = bytes.slice(at)
	_offsets = PackedInt32Array()
	_offsets.resize(ticks)
	var read: int = 0
	for tick in ticks:
		_offsets[tick] = read
		var problem: String = _check_tick(_data, read, tick)
		if problem != "":
			return problem
		read = _checked_to
	if read != _data.size():
		return "%d bytes left over" % (_data.size() - read)
	return ""


## Check the tick (number `tick`) that starts at `at` in `data`: "" when it is one whole valid tick
## (it ends at `_checked_to`), else why not.
func _check_tick(data: PackedByteArray, at: int, tick: int) -> String:
	var read: int = at
	if read >= data.size():
		return "tick %d is missing" % tick
	var mask: int = data[read]
	if mask > 0x0f:
		return "tick %d: seats %d" % [tick, mask]
	read += 1
	for seat in SEATS:
		if mask & (1 << seat) == 0:
			continue
		if read + 2 > data.size():
			return "tick %d: seat %d is cut short" % [tick, seat]
		var length: int = data.decode_u16(read)
		if read + 2 + length > data.size():
			return "tick %d: seat %d is cut short" % [tick, seat]
		var problem: String = _check_frame.decode(data.slice(read + 2, read + 2 + length))
		if problem != "":
			return "tick %d: seat %d: %s" % [tick, seat, problem]
		if _check_frame.seat != seat:
			return "tick %d: seat %d holds seat %d's frame" % [tick, seat, _check_frame.seat]
		read += 2 + length
	_checked_to = read
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
