class_name NetSignalHandshake
extends NetHandshake
## The handshake through the room server (online lobby L2, docs/milestones/online-lobby.md,
## Part 1): what the players did by copy and paste (`NetRtc`'s two codes) the server carries, so
## a player only says or types a room's five characters. The codes, their checks and the link
## are the inner handshake's as they were (`NetRtc`, one for each other machine); this only
## hands its codes to the server and the server's to it.
##
## - **The host** calls `offer`: the socket to the server opens, a room is asked for, and
##   `code()` is the room's code once the server gave it. For every guest the server names, an
##   inner handshake makes its offer, which goes to that guest through the server, and takes
##   the answer that comes back. `link()` is there once a guest's machine was found (the first;
##   `next_link()` hands them over one by one). The room stays open for more until `close`.
## - **A joining machine** `take`s the room code a player typed. It joins the room, takes the
##   host's offer, sends its answer, and `link()` is the link to the host. Its socket closes
##   then: the server's part is done. `code()` stays "": it has nothing to hand over by hand.
## - **Nothing connects anywhere before `offer` or `take`,** and then only to the room server
##   (the address given, `NetSignal.URL` in the game) and what the inner handshake talks to.
## - **A relay the server hands over** (`NetSignal.RELAY`, sent before each join is told) goes to
##   the inner handshakes made after it, as a TURN server beside STUN: WebRTC uses it only where
##   the two machines find no direct way. The host keeps the last one for every guest after it
##   (a join past the server's limit comes with none, and the host's own still helps). With none,
##   the machines link directly or not at all, as by hand; so too with one that is out of form.
## - **What the server says is untrusted:** only `NetSignal`'s forms are taken, only the kinds
##   this side is sent, only in an order that makes sense; anything else ends the handshake
##   (`problem`). A code it hands over is checked by the inner handshake exactly as a pasted one
##   (`NetCode.read`): one that is refused costs a host that guest, and a joining machine the try.
## - **The clock is given** (milliseconds; the engine's unless told), as `NetRtc`'s is.
##
## Names no networking class: the socket is `NetSignalSocket`'s, the link `NetRtc`'s.

## The server answers the connection, and then a room's opening or joining, within this long each.
const CONNECT_MS: int = 10000
## A joining machine holds a link this long after it joined the room, or gives up.
const JOIN_MS: int = 30000
## A guest that has not become a link this long after the server named it is let go (a host).
const GUEST_MS: int = 60000
## Messages taken in one poll.
const MAX_READ: int = 16

## The time in milliseconds (a test's own; the engine's clock otherwise).
var clock: Callable = Callable()
## Makes an inner handshake (a `NetHandshake`) from the relay given (a `NetRelay`, or null);
## invalid: WebRTC's (`NetRtc`). Tests give their own.
var rtc_maker: Callable = Callable()

var _url: String
var _socket: NetSignalSocket
var _message: NetSignal = NetSignal.new()
var _hosting: bool = false
var _problem: NetWhy = null
## When the socket was opened, and when `open` or `join` was said on it (-1: not yet).
var _opened_at: int = -1
var _said_at: int = -1
## The host: its room's code; a joining machine: the room it asked for.
var _room: String = ""
var _room_given: bool = false
## The relay the server handed over last (`NetSignal.relay`), for the inner handshakes made after it.
var _relay: NetRelay = null
## The host's guests on their way to a link, by the server's id: the inner handshake, whether its
## offer was sent, and when the server named the guest.
var _guests: Dictionary[int, NetHandshake] = {}
var _offered: Dictionary[int, bool] = {}
## The guests whose answer was taken: they look for this machine now, with no more use of the server.
var _answered_by: Dictionary[int, bool] = {}
var _named_at: Dictionary[int, int] = {}
## The links not handed over by `next_link` yet (the host's), and the first ever made.
var _links: Array[NetLink] = []
var _first: NetLink = null
## A joining machine: when it was put in the room (-1: not yet), its inner handshake, whether its
## answer was sent.
var _joined_at: int = -1
var _rtc: NetHandshake = null
var _answered: bool = false


## `url`: the room server's address. `socket`: the tests' own (none: a WebSocket).
func _init(url: String = NetSignal.URL, socket: NetSignalSocket = null) -> void:
	_url = url
	_socket = socket if socket != null else NetSignalSocket.new()


func offer() -> NetWhy:
	if _opened_at >= 0:
		return NetWhy.new(OnlineWhy.NOT_NOW, "it has begun already")
	_hosting = true
	return _open()


## A room's code, as a player typed it.
func takes(typed: String) -> bool:
	return NetSignal.typed_room_code(typed) != ""


## A joining machine: `code` is the room code as a player typed it. (A host is given nothing by
## hand: the server brings the answers.)
func take(code: String) -> NetWhy:
	if _problem != null:
		return _problem
	if _hosting:
		return NetWhy.new(OnlineWhy.NOT_NOW, "the room's server brings the other machine's code")
	if _opened_at >= 0:
		return NetWhy.new(OnlineWhy.NOT_NOW, "a code was given already")
	var room: String = NetSignal.typed_room_code(code)
	if room == "":
		return NetWhy.new(OnlineWhy.BAD_ROOM_CODE, "a room's code is %d letters and digits" % NetSignal.CODE_LENGTH, {OnlineWhy.LENGTH: NetSignal.CODE_LENGTH})
	_room = room
	return _open()


## The host's room code once the server gave it; "" on a joining machine.
func code() -> String:
	return _room if _hosting and _room_given else ""


func poll() -> void:
	if _opened_at < 0 or _problem != null:
		return
	# A joining machine that holds its link has closed its socket: the server's part is done.
	if _hosting or _first == null:
		_poll_server()
	if _problem != null:
		return
	if _hosting:
		_poll_guests()
	else:
		_poll_host()


func link() -> NetLink:
	return _first


## The next link not handed over yet, or null: the host's, one for each guest machine in the
## order they were found; a joining machine's one link, once.
func next_link() -> NetLink:
	return _links.pop_front() if not _links.is_empty() else null


func problem() -> NetWhy:
	return _problem


func close() -> void:
	if _problem == null:
		_problem = NetWhy.new(OnlineWhy.NOT_NOW, "given up")
	_let_go()


func _open() -> NetWhy:
	var why: String = _socket.open(NetSignal.asking_relays(_url))
	if why != "":
		return _fail(OnlineWhy.NO_SERVER, why)
	_opened_at = _now()
	return null


## The socket moved on and what the server said heard.
func _poll_server() -> void:
	_socket.poll()
	var state: int = _socket.state()
	if _said_at < 0:
		if state == NetSignalSocket.OPEN:
			_socket.send(NetSignal.open() if _hosting else NetSignal.join(_room))
			_said_at = _now()
		elif state == NetSignalSocket.CLOSED or _now() - _opened_at >= CONNECT_MS:
			_fail(OnlineWhy.NO_SERVER, "the room server could not be reached")
		return
	for at in MAX_READ:
		var text: String = _socket.read()
		if text == "":
			break
		var mine: Array[StringName] = NetSignal.FOR_HOST if _hosting else NetSignal.FOR_GUEST
		if text.begins_with(NetSignal.RELAY_HEAD) and not _message.read(text):
			# A relay this game cannot read is no relay: the machines may still link directly.
			continue
		if not _message.read(text) or not mine.has(_message.kind) or not _hear():
			_fail(OnlineWhy.SERVER_FAILED, "the room server said something that is no message of its")
		if _problem != null:
			return
	var answered: bool = _room_given if _hosting else _joined_at >= 0
	if state == NetSignalSocket.CLOSED:
		if answered:
			_fail(OnlineWhy.ROOM_CLOSED, "the room is closed")
		else:
			_fail(OnlineWhy.SERVER_FAILED, "the room server closed the connection")
	elif not answered and _now() - _said_at >= CONNECT_MS:
		_fail(OnlineWhy.NO_SERVER, "the room server did not answer")


## One message of the server's taken (`_message`). False when it makes no sense now.
func _hear() -> bool:
	match _message.kind:
		NetSignal.ROOM:
			if _room_given:
				return false
			_room = _message.code
			_room_given = true
		NetSignal.GUEST:
			# The server gives an id again once its guest left; one still linking here (it left
			# the server with its link) lets the newcomer wait its turn: the server names it
			# anew when it asks again.
			if not _room_given or (_guests.has(_message.id) and not _answered_by.has(_message.id)):
				return false
			if _guests.has(_message.id):
				return true
			var inner: NetHandshake = _make_rtc()
			var why: NetWhy = inner.offer()
			if why != null:
				# This machine cannot link at all: no guest will fare better.
				_keep(why)
				return true
			_guests[_message.id] = inner
			_offered[_message.id] = false
			_named_at[_message.id] = _now()
		NetSignal.ANSWER:
			# An answer for nobody (a guest let go a moment ago) is nothing.
			var inner: NetHandshake = _guests.get(_message.id)
			if inner != null and _offered[_message.id]:
				if inner.take(_message.code) != null:
					_drop(_message.id)
				else:
					_answered_by[_message.id] = true
		NetSignal.GONE:
			# A guest that answered leaves the server as soon as it holds its link, which may be
			# a moment before this machine holds its own: it is not gone. The inner handshake
			# gives up by itself if no link comes.
			if not _answered_by.has(_message.id):
				_drop(_message.id)
		NetSignal.JOINED:
			if _joined_at >= 0:
				return false
			_joined_at = _now()
		NetSignal.OFFER:
			if _joined_at < 0 or _rtc != null:
				return false
			_rtc = _make_rtc()
			var why: NetWhy = _rtc.take(_message.code)
			if why != null:
				# What it says of a pasted code is not for a player who typed a room's.
				_fail(why.name if why.name == OnlineWhy.CANNOT_LINK or why.name == OnlineWhy.SETUP_FAILED else OnlineWhy.HOST_CODE_REFUSED, "the host's code was not taken: %s" % why.text)
		NetSignal.NO_ROOM:
			_fail(OnlineWhy.NO_ROOM, "no room has the code %s" % _room, {OnlineWhy.ROOM: _room})
		NetSignal.FULL:
			_fail(OnlineWhy.ROOM_FULL, "the room %s is full" % _room, {OnlineWhy.ROOM: _room})
		NetSignal.CLOSED:
			_fail(OnlineWhy.ROOM_CLOSED, "the host closed the room" if not _hosting else "the room is closed")
		NetSignal.RELAY:
			# The host's comes before each guest it names; a joining machine's before `joined`.
			if (_hosting and not _room_given) or (not _hosting and _joined_at >= 0):
				return false
			_relay = _message.relay
	return true


## The host: each guest's inner handshake moves on; its offer goes out once made, and its link
## is kept once there.
func _poll_guests() -> void:
	for id: int in _guests.keys():
		var inner: NetHandshake = _guests[id]
		inner.poll()
		if inner.problem() != null or _now() - _named_at[id] >= GUEST_MS:
			_drop(id)
		elif inner.link() != null:
			_links.append(inner.link())
			if _first == null:
				_first = inner.link()
			_forget(id)
		elif not _offered[id] and inner.code() != "":
			var text: String = NetSignal.offer(id, inner.code())
			if text == "":
				_drop(id)
			else:
				_socket.send(text)
				_offered[id] = true


## A joining machine: its inner handshake moves on; its answer goes out once made, and with the
## link there the server's part is done.
func _poll_host() -> void:
	if _first != null:
		return
	if _rtc != null:
		_rtc.poll()
		if _rtc.problem() != null:
			_keep(_rtc.problem())
			return
		if _rtc.link() != null:
			_first = _rtc.link()
			_links.append(_first)
			_socket.send(NetSignal.bye())
			_socket.close()
			return
		if not _answered and _rtc.code() != "":
			var text: String = NetSignal.answer(_rtc.code())
			if text == "":
				_fail(OnlineWhy.SETUP_FAILED, "this machine's code could not be made")
				return
			_socket.send(text)
			_answered = true
	if _joined_at >= 0 and _now() - _joined_at >= JOIN_MS:
		_fail(OnlineWhy.HOST_NOT_FOUND, "the host's machine was not found in time")


func _make_rtc() -> NetHandshake:
	var inner: NetHandshake = rtc_maker.call(_relay) as NetHandshake if rtc_maker.is_valid() else null
	if inner == null:
		var rtc := NetRtc.new(NetRtc.STUN, _relay)
		rtc.clock = clock
		inner = rtc
	return inner


## A guest on its way is let go (it left, its code was refused, it took too long).
func _drop(id: int) -> void:
	if _guests.has(id):
		_guests[id].close()
		_forget(id)


func _forget(id: int) -> void:
	_guests.erase(id)
	_offered.erase(id)
	_answered_by.erase(id)
	_named_at.erase(id)


func _fail(named: StringName, in_words: String, facts: Dictionary = {}) -> NetWhy:
	return _keep(NetWhy.new(named, in_words, facts))


## The handshake failed for `why` (the first reason stands).
func _keep(why: NetWhy) -> NetWhy:
	if _problem == null:
		_problem = why
		_let_go()
	return why


## The socket and every handshake still on its way are closed. A link made is its holder's.
func _let_go() -> void:
	_socket.close()
	for id: int in _guests.keys():
		_drop(id)
	if _rtc != null and _first == null:
		_rtc.close()


func _now() -> int:
	return int(clock.call()) if clock.is_valid() else Time.get_ticks_msec()
