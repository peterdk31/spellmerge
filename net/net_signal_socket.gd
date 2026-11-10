class_name NetSignalSocket
extends RefCounted
## The WebSocket to the room server (online lobby L2, docs/milestones/online-lobby.md, Part 1):
## whole text messages out and in, polled when it is read, as `NetRtcLink` is. `NetSignalHandshake`
## knows only this; the tests give it one of their own.
##
## - **Nothing connects until `open`** (a host opened the altar, or a player pressed Join online),
##   and only to the address it is handed, which is `NetSignal.URL` in the game.
## - **What arrives is untrusted:** a packet that is not text, is empty, is longer than
##   `NetSignal.MAX_CHARS`, or holds anything but plain printable characters closes the socket,
##   as do MAX_WAITING messages nobody read. The messages themselves are `NetSignal`'s to read.
## - **No clock, no thread:** it moves when it is polled.
##
## The only script that names the engine's WebSocket class.

const CONNECTING: int = 0
const OPEN: int = 1
const CLOSED: int = 2

## Messages that may wait unread, and packets taken in one poll.
const MAX_WAITING: int = 64
const MAX_PACKETS_A_POLL: int = 16
## Seconds between the pings that keep an idle socket open.
const HEARTBEAT_S: float = 25.0

var _peer: WebSocketPeer = null
var _inbox: PackedStringArray = PackedStringArray()
var _closed: bool = false


## Connect to `url` (ws:// or wss://). "" when it began, else why it cannot.
func open(url: String) -> String:
	if _peer != null or _closed:
		return "it has begun already"
	if not (url.begins_with("wss://") or url.begins_with("ws://")):
		return "this build has no room server's address"
	_peer = WebSocketPeer.new()
	# A message is at most MAX_CHARS; the buffers hold a few of them and no more.
	_peer.inbound_buffer_size = NetSignal.MAX_CHARS * 4
	_peer.outbound_buffer_size = NetSignal.MAX_CHARS * 4
	_peer.max_queued_packets = MAX_WAITING
	# A room may stand open for minutes with nothing said: a ping now and then keeps the routers
	# between from dropping it (a browser sends none; its socket is the browser's to keep).
	_peer.heartbeat_interval = HEARTBEAT_S
	if _peer.connect_to_url(url) != OK:
		_closed = true
		return "the room server's address is not one"
	return ""


## CONNECTING, OPEN or CLOSED (closed by either side, never opened, or refused here).
func state() -> int:
	if _closed or _peer == null:
		return CLOSED
	match _peer.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			return CONNECTING
		WebSocketPeer.STATE_OPEN:
			return OPEN
	# Closing: nothing more is said or taken.
	return CLOSED


## Move on: called every physics step by whoever holds it.
func poll() -> void:
	if _closed or _peer == null:
		return
	_peer.poll()
	var taken: int = 0
	while taken < MAX_PACKETS_A_POLL and _peer.get_available_packet_count() > 0:
		taken += 1
		var bytes: PackedByteArray = _peer.get_packet()
		if not _peer.was_string_packet() or not _is_plain(bytes) or _inbox.size() >= MAX_WAITING:
			close()
			return
		_inbox.append(bytes.get_string_from_ascii())
	if _peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		_closed = true


## Send one message. Dropped unless the socket is open.
func send(text: String) -> void:
	if text != "" and text.length() <= NetSignal.MAX_CHARS and state() == OPEN:
		_peer.send_text(text)


## The next message that arrived, "" when none waits. What arrived before it closed can still be read.
func read() -> String:
	if _inbox.is_empty():
		return ""
	var text: String = _inbox[0]
	_inbox.remove_at(0)
	return text


func close() -> void:
	if _peer != null and not _closed:
		_peer.close()
	_closed = true
	_inbox.clear()


## True for a message's bytes: some, not too many, each a plain printable character.
static func _is_plain(bytes: PackedByteArray) -> bool:
	if bytes.is_empty() or bytes.size() > NetSignal.MAX_CHARS:
		return false
	for byte in bytes:
		if byte < 0x20 or byte > 0x7e:
			return false
	return true
