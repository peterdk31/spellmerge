class_name NetSignal
extends RefCounted
## What the game and the room server say to each other (online lobby L2,
## docs/milestones/online-lobby.md, Part 1; the server is `server/signal/`): small messages as
## text, each of one fixed form. The server only carries two machines' codes (`NetCode`s) between
## them by a room code of five characters; it never sees the game.
##
## **What the server sends is untrusted text.** `read` takes only the forms below, written
## exactly as the server writes them: these keys in this order, no space, nothing more. Nothing
## is parsed as an open object, and nothing a message says is looked up, loaded or run: a room
## code is five characters of ALPHABET, a guest's id is one digit, and a machine's code is only
## checked here for its prefix and alphabet, then handed to `NetCode.read` (by `NetRtc.take`) and
## nowhere else.
##
##     {"t":"room","code":"KQ7RM"}          to the host: its room's code
##     {"t":"guest","id":1}                 to the host: a guest is here
##     {"t":"answer","id":1,"code":"SM1."}  to the host: that guest's code
##     {"t":"gone","id":1}                  to the host: that guest went away
##     {"t":"joined"}                       to a guest: it is in the room
##     {"t":"offer","code":"SM1."}          to a guest: the host's code for it
##     {"t":"no_room"}                      to a guest: no room has that code
##     {"t":"full"}                         to a guest: the room has its three guests
##     {"t":"closed"}                       to either: the room is closed
##     {"t":"relay","urls":["turn:a.b:3478?transport=udp"],"username":"u","credential":"p"}
##                                          to either: a relay for the link about to be made,
##                                          before `guest` (the host) or `joined` (a guest)
##
## A relay (a TURN server, which carries a link two machines cannot make directly) is checked
## as closely as the rest: one to MAX_RELAY_URLS addresses, each `turn:` or `turns:`, a name of
## letters, digits and dots, a port (never 53, which browsers block) and `?transport=udp|tcp`; a
## user name and a password of MAX_RELAY_WORD characters at most, of a credential's alphabet.
## It is held as a `NetRelay`, for whoever links the machines. The server sends one only to a
## machine that asked in its address (`asking_relays`): a game from before relays takes none.
##
## Nothing here names a networking class (`NetSignalSocket` does).

## The room server's address: the one place the game is told it (the owner's deploy of
## `server/signal/`, 2026-11-10). With "" here a build says so and connects nowhere.
const URL: String = "wss://spellmerge-signal.peterdk31.workers.dev/room"

## The characters of a room code: letters and digits that are not misread for one another.
const ALPHABET: String = "2346789ABCDEFGHJKMNPQRTWXYZ"
const CODE_LENGTH: int = 5
## A room's guests are 1 to this.
const MAX_GUESTS: int = 3
## The most characters of a message, either way (the server's own limit).
const MAX_CHARS: int = 16384

## What the server says (`kind` after `read`).
const ROOM: StringName = &"room"
const GUEST: StringName = &"guest"
const ANSWER: StringName = &"answer"
const GONE: StringName = &"gone"
const JOINED: StringName = &"joined"
const OFFER: StringName = &"offer"
const NO_ROOM: StringName = &"no_room"
const FULL: StringName = &"full"
const CLOSED: StringName = &"closed"
const RELAY: StringName = &"relay"
## The kinds a host takes, and a guest.
const FOR_HOST: Array[StringName] = [ROOM, GUEST, ANSWER, GONE, CLOSED, RELAY]
const FOR_GUEST: Array[StringName] = [JOINED, OFFER, NO_ROOM, FULL, CLOSED, RELAY]
## A relay's most addresses, and the most characters of its user name or password.
const MAX_RELAY_URLS: int = 8
const MAX_RELAY_WORD: int = 256

## How every relay message starts: one that is not read past this is no relay, and nothing worse.
const RELAY_HEAD: String = '{"t":"relay",'

const _BASE64: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
## The characters of a relay's user name and password, and of a label of its server's name.
const _RELAY_WORD: String = _BASE64 + "=_.:-"
const _NAME_LABEL: String = "abcdefghijklmnopqrstuvwxyz0123456789-"

## The message last read: its kind (&"" when it was none), and what that kind holds.
var kind: StringName = &""
## ROOM: the room's code. OFFER, ANSWER: the machine's code (a `NetCode` text, not read yet).
var code: String = ""
## GUEST, ANSWER, GONE: the guest's id.
var id: int = 0
## RELAY: the relay (null with any other kind).
var relay: NetRelay = null


## Take the server's message `text`: true when it is one (this then holds it), else nothing is held.
func read(text: String) -> bool:
	kind = &""
	code = ""
	id = 0
	relay = null
	if text.length() > MAX_CHARS or not _read(text):
		kind = &""
		code = ""
		id = 0
		relay = null
		return false
	return true


func _read(text: String) -> bool:
	for plain: StringName in [JOINED, NO_ROOM, FULL, CLOSED]:
		if text == '{"t":"%s"}' % plain:
			kind = plain
			return true
	var inner: String = _between(text, '{"t":"room","code":"', '"}')
	if is_room_code(inner):
		kind = ROOM
		code = inner
		return true
	for numbered: StringName in [GUEST, GONE]:
		inner = _between(text, '{"t":"%s","id":' % numbered, "}")
		if _is_guest_id(inner):
			kind = numbered
			id = int(inner)
			return true
	inner = _between(text, '{"t":"offer","code":"', '"}')
	if is_net_code(inner):
		kind = OFFER
		code = inner
		return true
	# {"t":"answer","id":N,"code":"..."}: the id is one digit.
	inner = _between(text, '{"t":"answer","id":', '"}')
	if inner.length() > 9 and _is_guest_id(inner.substr(0, 1)) and inner.substr(1, 9) == ',"code":"' and is_net_code(inner.substr(10)):
		kind = ANSWER
		id = int(inner.substr(0, 1))
		code = inner.substr(10)
		return true
	# {"t":"relay","urls":["A","B"],"username":"U","credential":"P"}
	inner = _between(text, '{"t":"relay","urls":["', '"}')
	var halves: PackedStringArray = inner.split('"],"username":"')
	if halves.size() != 2:
		return false
	var words: PackedStringArray = halves[1].split('","credential":"')
	var urls: PackedStringArray = halves[0].split('","')
	if words.size() != 2 or not is_relay_word(words[0]) or not is_relay_word(words[1]) or urls.size() > MAX_RELAY_URLS:
		return false
	for url: String in urls:
		if not is_relay_url(url):
			return false
	kind = RELAY
	relay = NetRelay.new(urls, words[0], words[1])
	return true


## What `text` holds between `head` and `tail`, or "" when it does not start and end with them.
static func _between(text: String, head: String, tail: String) -> String:
	if text.length() <= head.length() + tail.length() or not text.begins_with(head) or not text.ends_with(tail):
		return ""
	return text.substr(head.length(), text.length() - head.length() - tail.length())


## True for a room's code as the server makes them.
static func is_room_code(text: String) -> bool:
	if text.length() != CODE_LENGTH:
		return false
	for at in text.length():
		if ALPHABET.find(text[at]) < 0:
			return false
	return true


## A room code as a player typed it: without its spaces and in capitals. "" when it is none.
static func typed_room_code(text: String) -> String:
	if text.length() > CODE_LENGTH * 4:
		return ""
	var typed: String = text.replace(" ", "").replace("\t", "").replace("\n", "").replace("\r", "").replace("-", "").to_upper()
	return typed if is_room_code(typed) else ""


## True for text that may be a machine's code: `NetCode`'s prefix, then its alphabet, within its
## length. Whether it is one is `NetCode.read`'s to say.
static func is_net_code(text: String) -> bool:
	if text.length() > NetCode.MAX_CHARS or text.length() <= NetCode.PREFIX.length() or not text.begins_with(NetCode.PREFIX):
		return false
	var body: int = text.length()
	while body > text.length() - 2 and text[body - 1] == "=":
		body -= 1
	if body <= NetCode.PREFIX.length():
		return false
	for at in range(NetCode.PREFIX.length(), body):
		if _BASE64.find(text[at]) < 0:
			return false
	return true


## True for a relay's address as the server sends it: `turn:` or `turns:`, a name of two labels
## or more (an IPv4 address is one), a port from 1 to 65535 but 53, and `?transport=udp` or `?transport=tcp`.
static func is_relay_url(text: String) -> bool:
	var rest: String = ""
	if text.begins_with("turn:"):
		rest = text.substr(5)
	elif text.begins_with("turns:"):
		rest = text.substr(6)
	else:
		return false
	var asked: int = rest.find("?transport=")
	if asked < 0 or not rest.substr(asked + 11) in ["udp", "tcp"]:
		return false
	var where: String = rest.substr(0, asked)
	var colon: int = where.rfind(":")
	var port: String = where.substr(colon + 1)
	if colon < 0 or port.length() < 1 or port.length() > 5:
		return false
	for digit: String in port:
		if digit < "0" or digit > "9":
			return false
	if int(port) < 1 or int(port) > 65535 or int(port) == 53:
		return false
	var labels: PackedStringArray = where.substr(0, colon).split(".")
	if labels.size() < 2:
		return false
	for label: String in labels:
		if label.is_empty():
			return false
		for at in label.length():
			if _NAME_LABEL.find(label[at]) < 0:
				return false
	return true


## True for a relay's user name or password.
static func is_relay_word(text: String) -> bool:
	if text.is_empty() or text.length() > MAX_RELAY_WORD:
		return false
	for at in text.length():
		if _RELAY_WORD.find(text[at]) < 0:
			return false
	return true


static func _is_guest_id(text: String) -> bool:
	return text.length() == 1 and text >= "1" and text <= str(MAX_GUESTS)


# --- What the game says to the server -------------------------------------------

## The server's address `url` as a game that takes relay messages connects to it: the server
## sends them to no other (a server from before relays does not look at it).
static func asking_relays(url: String) -> String:
	return url + ("&" if url.contains("?") else "?") + "relay=1"


## A host: make me a room.
static func open() -> String:
	return '{"t":"open"}'


## A guest: put me in this room. "" when `room` is no room code.
static func join(room: String) -> String:
	return '{"t":"join","code":"%s"}' % room if is_room_code(room) else ""


## The host's code for guest `guest`. "" when either is not what it must be.
static func offer(guest: int, net_code: String) -> String:
	if guest < 1 or guest > MAX_GUESTS or not is_net_code(net_code):
		return ""
	return '{"t":"offer","id":%d,"code":"%s"}' % [guest, net_code]


## A guest's code for the host. "" when it is none.
static func answer(net_code: String) -> String:
	return '{"t":"answer","code":"%s"}' % net_code if is_net_code(net_code) else ""


## Leaving.
static func bye() -> String:
	return '{"t":"bye"}'
