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
##
## Nothing here names a networking class (`NetSignalSocket` does).

## The room server's address: the one place the game is told it (the owner's deploy of
## `server/signal/`). "" until it is deployed: a build without it says so and connects nowhere.
const URL: String = ""

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
## The kinds a host takes, and a guest.
const FOR_HOST: Array[StringName] = [ROOM, GUEST, ANSWER, GONE, CLOSED]
const FOR_GUEST: Array[StringName] = [JOINED, OFFER, NO_ROOM, FULL, CLOSED]

const _BASE64: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

## The message last read: its kind (&"" when it was none), and what that kind holds.
var kind: StringName = &""
## ROOM: the room's code. OFFER, ANSWER: the machine's code (a `NetCode` text, not read yet).
var code: String = ""
## GUEST, ANSWER, GONE: the guest's id.
var id: int = 0


## Take the server's message `text`: true when it is one (this then holds it), else nothing is held.
func read(text: String) -> bool:
	kind = &""
	code = ""
	id = 0
	if text.length() > MAX_CHARS or not _read(text):
		kind = &""
		code = ""
		id = 0
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
	return false


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


static func _is_guest_id(text: String) -> bool:
	return text.length() == 1 and text >= "1" and text <= str(MAX_GUESTS)


# --- What the game says to the server -------------------------------------------

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
