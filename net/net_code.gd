class_name NetCode
extends RefCounted
## A code two players swap by hand (netcode spike S4, docs/milestones/netcode-spike.md): how one
## machine is reached, as text to copy and paste. It holds a WebRTC session description (an offer:
## the host's; an answer: the joining machine's) and that machine's network candidates, gathered
## before the code is shown, so one code each way is enough.
##
## **A pasted code is untrusted text.** `read` checks it strictly before anything is handed to
## WebRTC: its length, its prefix, its alphabet, then every line of what it unpacks to (plain
## printable text only, a description's lines `x=...`, a candidate's three fields), each with a
## limit. It makes no object and follows no path or address but the candidates', which are the
## point of it. Nothing here names a networking class.
##
## The text is `PREFIX` and the base64 of these lines:
##
##     o                       (an offer; `a`: an answer)
##     v=0                     (the description, a line each)
##     ...
##     ~0<tab>0<tab>candidate:1 1 UDP ...   (a candidate: its media id, its line index, its text)

const OFFER: String = "offer"
const ANSWER: String = "answer"
## What every code starts with (the 1: this form of it).
const PREFIX: String = "SM1."
## The most characters a code has, and the most lines and candidates it unpacks to.
const MAX_CHARS: int = 8192
const MAX_LINES: int = 128
const MAX_LINE: int = 512
const MAX_CANDIDATES: int = 32
const MAX_MID: int = 16
const MAX_LINE_INDEX: int = 15
const _BASE64: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
const _CANDIDATE_MARK: String = "~"
## The lines a data channel's description must hold (each by how it starts).
const NEEDED_LINES: PackedStringArray = ["m=", "a=ice-ufrag:", "a=ice-pwd:", "a=fingerprint:", "a=setup:"]
const _CANDIDATE_TYPES: PackedStringArray = ["host", "srflx", "prflx", "relay"]

## OFFER or ANSWER.
var type: String = ""
## The session description, its lines ended by CR LF as WebRTC gives and takes them.
var sdp: String = ""
## The candidates: each one's media id, line index and text.
var mids: PackedStringArray = PackedStringArray()
var indexes: PackedInt32Array = PackedInt32Array()
var names: PackedStringArray = PackedStringArray()


## Add a candidate of this machine's. False (and it is left out) when it would not pass `read`
## on the other machine, or there are MAX_CANDIDATES already. A relay's address comes last and
## is the one that always gets through, so with the code full it takes the place of the last
## address on the machine's own network (a machine of many networks has plenty).
func add_candidate(mid: String, index: int, name: String) -> bool:
	if _candidate_problem(mid, index, name) != "":
		return false
	if mids.size() >= MAX_CANDIDATES:
		var given_up: int = -1
		if _type_of(name) == "relay":
			for at in range(names.size() - 1, -1, -1):
				if _type_of(names[at]) == "host":
					given_up = at
					break
		if given_up < 0:
			return false
		mids[given_up] = mid
		indexes[given_up] = index
		names[given_up] = name
		return true
	mids.append(mid)
	indexes.append(index)
	names.append(name)
	return true


## How many of the candidates are addresses on the machine's own network (`host`).
func own_count() -> int:
	return _addresses(["host"]).size()


## The addresses the machine is seen at from outside its network (what a STUN server told it, or
## the other machine saw): the `srflx` and `prflx` candidates. Two machines that share one are
## behind the same router. (A relay's are not: one relay's address may be every machine's.)
func seen_at() -> PackedStringArray:
	return _addresses(["srflx", "prflx"])


## How many of the candidates are addresses on a relay (`relay`).
func relay_count() -> int:
	return _addresses(["relay"]).size()


## The addresses of the candidates of these types.
func _addresses(types: PackedStringArray) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for name: String in names:
		if types.has(_type_of(name)):
			found.append(name.substr(name.find("candidate:") + 10).split(" ", false)[4])
	return found


## The type of a candidate that passed `_candidate_problem`: host, srflx, prflx or relay.
static func _type_of(name: String) -> String:
	return name.substr(name.find("candidate:") + 10).split(" ", false)[7]


## The code as text, or "" when it is not one `read` would take (no description yet, or too long).
func to_text() -> String:
	if type != OFFER and type != ANSWER:
		return ""
	var lines: PackedStringArray = PackedStringArray(["o" if type == OFFER else "a"])
	for line: String in sdp.split("\n", false):
		lines.append(line.strip_edges())
	for at in mids.size():
		lines.append("%s%s\t%d\t%s" % [_CANDIDATE_MARK, mids[at], indexes[at], names[at]])
	var text: String = PREFIX + Marshalls.raw_to_base64("\n".join(lines).to_ascii_buffer())
	return text if NetCode.new().read(text) == "" else ""


## Take the pasted text `text`: "" when it is a code (this then holds it), else why it is not.
## White space anywhere in it is dropped first (a chat may wrap a long line).
func read(text: String) -> String:
	_clear()
	var why: String = _read(text)
	if why != "":
		_clear()
	return why


func _clear() -> void:
	type = ""
	sdp = ""
	mids.clear()
	indexes.clear()
	names.clear()


func _read(text: String) -> String:
	if text.length() > MAX_CHARS * 2:
		return "it is too long to be a code"
	var packed: String = ""
	for part: String in text.split("\n", false):
		packed += part.replace(" ", "").replace("\t", "").replace("\r", "")
	if packed.length() > MAX_CHARS:
		return "it is too long to be a code"
	if not packed.begins_with(PREFIX):
		return "it is not a code of this game (a code starts with %s)" % PREFIX
	packed = packed.substr(PREFIX.length())
	if packed.is_empty() or packed.length() % 4 != 0:
		return "a part of the code is missing"
	# Padding only at the very end (the engine's decoder logs an error for any other).
	var body: int = packed.length()
	while body > packed.length() - 2 and packed[body - 1] == "=":
		body -= 1
	for at in body:
		if _BASE64.find(packed[at]) < 0:
			return "it has a character no code has"
	var raw: PackedByteArray = Marshalls.base64_to_raw(packed)
	if raw.is_empty():
		return "a part of the code is missing"
	for byte in raw:
		if byte != 0x0a and byte != 0x09 and (byte < 0x20 or byte > 0x7e):
			return "it is not a code"
	var lines: PackedStringArray = raw.get_string_from_ascii().split("\n")
	if lines.size() < 2 or lines.size() > MAX_LINES:
		return "it is not a code"
	if lines[0] != "o" and lines[0] != "a":
		return "it is not a code"
	var description: PackedStringArray = PackedStringArray()
	for at in range(1, lines.size()):
		var line: String = lines[at]
		if line.is_empty() or line.length() > MAX_LINE:
			return "it is not a code"
		if line.begins_with(_CANDIDATE_MARK):
			var fields: PackedStringArray = line.substr(1).split("\t")
			if fields.size() != 3 or not fields[1].is_valid_int() or fields[1].length() > 2:
				return "it is not a code"
			if mids.size() >= MAX_CANDIDATES or _candidate_problem(fields[0], int(fields[1]), fields[2]) != "":
				return "it is not a code"
			mids.append(fields[0])
			indexes.append(int(fields[1]))
			names.append(fields[2])
		else:
			# A description's line: a lower-case letter, "=", its value; none after a candidate.
			if not mids.is_empty() or line.length() < 3 or line[1] != "=" or line[0] < "a" or line[0] > "z" or line.contains("\t"):
				return "it is not a code"
			description.append(line)
	if description.is_empty() or description[0] != "v=0":
		return "it is not a code"
	# What a data channel's description always holds, once each where it must be one: without
	# them WebRTC refuses it (and logs an engine error).
	for needed: String in NEEDED_LINES:
		var found: int = 0
		for line in description:
			if line.begins_with(needed):
				found += 1
		if found == 0 or (needed == "m=" and found != 1):
			return "it is not a code"
	for line in description:
		if line.begins_with("m=") and not line.begins_with("m=application "):
			return "it is not a code"
	type = OFFER if lines[0] == "o" else ANSWER
	sdp = "\r\n".join(description) + "\r\n"
	return ""


static func _candidate_problem(mid: String, index: int, name: String) -> String:
	if mid.is_empty() or mid.length() > MAX_MID or index < 0 or index > MAX_LINE_INDEX:
		return "a candidate's place"
	for at in mid.length():
		var c: String = mid[at]
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")):
			return "a candidate's media id"
	if name.length() > MAX_LINE - MAX_MID - 8 or not (name.begins_with("candidate:") or name.begins_with("a=candidate:")):
		return "a candidate's text"
	for at in name.length():
		var code: int = name.unicode_at(at)
		if code < 0x20 or code > 0x7e:
			return "a candidate's text"
	# candidate:<foundation> <component> <transport> <priority> <address> <port> typ <type> ...
	var fields: PackedStringArray = name.substr(name.find("candidate:") + 10).split(" ", false)
	if fields.size() < 8 or fields[6] != "typ" or not _CANDIDATE_TYPES.has(fields[7]):
		return "a candidate's form"
	if not fields[1].is_valid_int() or not fields[3].is_valid_int() or not fields[5].is_valid_int():
		return "a candidate's numbers"
	if int(fields[5]) < 0 or int(fields[5]) > 65535 or (fields[2].to_lower() != "udp" and fields[2].to_lower() != "tcp"):
		return "a candidate's port or transport"
	if not _is_address(fields[4]):
		return "a candidate's address"
	return ""


## An address a candidate may name: an IP address written out, or the made-up `.local` name a
## browser gives its own address (hex digits and dashes). Never another host's name: nothing a
## pasted code says is looked up on the internet.
static func _is_address(text: String) -> bool:
	if text.is_valid_ip_address():
		return true
	if not text.ends_with(".local") or text.length() > 64:
		return false
	var label: String = text.trim_suffix(".local")
	if label.is_empty():
		return false
	for at in label.length():
		var c: String = label[at]
		if not ((c >= "0" and c <= "9") or (c >= "a" and c <= "f") or (c >= "A" and c <= "F") or c == "-"):
			return false
	return true
