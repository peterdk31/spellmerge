class_name RunUnlocks
extends RefCounted
## The save flags a run plays by (run generation RG6, docs/milestones/run-generation.md, "Meta
## progression (RG6)"): what the host's save has unlocked, as the run's start takes it. Plain data
## that knows no save and no rule: the flags, sorted, each once.
##
## The game says which flags are set now (`Frames.set_unlocks_source`, given by the Run area from
## this machine's save, and only the flags some run's rule change names), the frames service writes
## them into the header of a recording it begins (core/sim/replay.gd), and a run that starts takes
## them (`Frames.next_run_unlocks`, `Sim.unlocks`, set by the Tick's `begin_run`): a replay's
## while one records or plays, so a replay, and every machine playing the host's recording, plays
## by the host's save; a guest's own save changes nothing. The Run area changes the run's rules by
## them (`RunDefinition.changed_by`).
##
## The bytes: a byte of count, then each flag: a byte of length and its text. Read as strictly as a
## frame: plain ids (letters, digits, `_`), in order and each once, within the limits; nothing is
## changed by bytes it refuses.

## The most flags, the longest flag, and the most bytes in all.
const MAX_FLAGS: int = 64
const MAX_FLAG: int = 48
const MAX_BYTES: int = 1 + MAX_FLAGS * (1 + MAX_FLAG)

## The flags, sorted (by `String` order), each once.
var flags: Array[StringName] = []
## Where the last `decode_at` stopped reading (scratch).
var read_to: int = 0


## The unlocks of `list` (any order, repeats kept once), leaving out what is not a flag.
static func of(list: Array[StringName]) -> RunUnlocks:
	var made := RunUnlocks.new()
	for flag: StringName in list:
		made.add(flag)
	return made


## True for a text a flag may be: 1 to MAX_FLAG letters, digits and `_`.
static func is_flag(flag: StringName) -> bool:
	var text: String = String(flag)
	if text.is_empty() or text.length() > MAX_FLAG:
		return false
	for at in text.length():
		var code: int = text.unicode_at(at)
		if not ((code >= 97 and code <= 122) or (code >= 65 and code <= 90) or (code >= 48 and code <= 57) or code == 95):
			return false
	return true


## One more flag, in its place. Returns false, adding nothing, for what is not a flag, one it has,
## or one past MAX_FLAGS.
func add(flag: StringName) -> bool:
	if not is_flag(flag) or has(flag) or flags.size() >= MAX_FLAGS:
		return false
	var at: int = 0
	while at < flags.size() and String(flags[at]) < String(flag):
		at += 1
	flags.insert(at, flag)
	return true


## True when `flag` is set.
func has(flag: StringName) -> bool:
	return flags.has(flag)


func is_empty() -> bool:
	return flags.is_empty()


func copy() -> RunUnlocks:
	var made := RunUnlocks.new()
	made.flags = flags.duplicate()
	return made


func equals(other: RunUnlocks) -> bool:
	return other != null and other.flags == flags


## Append the flags to `out` (a replay's header): a byte of count, then each flag's length and text.
func encode_into(out: PackedByteArray) -> void:
	out.append(flags.size())
	for flag: StringName in flags:
		var text: PackedByteArray = String(flag).to_ascii_buffer()
		out.append(text.size())
		out.append_array(text)


## Read the flags from `bytes` at `at`: "" when they are whole and valid (in order, each once; they
## end at `read_to`), else why not (and nothing is changed).
func decode_at(bytes: PackedByteArray, at: int) -> String:
	if at < 0 or at >= bytes.size():
		return "the unlocks are cut short"
	var count: int = bytes[at]
	at += 1
	if count > MAX_FLAGS:
		return "%d unlocks" % count
	var read: Array[StringName] = []
	for i in count:
		if at >= bytes.size():
			return "the unlocks are cut short"
		var size: int = bytes[at]
		at += 1
		if size < 1 or size > MAX_FLAG or at + size > bytes.size():
			return "an unlock of %d bytes" % size
		var text: PackedByteArray = bytes.slice(at, at + size)
		at += size
		for byte in text:
			if byte > 126:
				return "an unlock that is not a flag"
		var flag := StringName(text.get_string_from_ascii())
		if not is_flag(flag):
			return "an unlock that is not a flag"
		if not read.is_empty() and String(read[-1]) >= String(flag):
			return "the unlocks out of order"
		read.append(flag)
	flags = read
	read_to = at
	return ""


func _to_string() -> String:
	return "RunUnlocks(%s)" % ", ".join(PackedStringArray(flags))
