class_name NetRtcLink
extends NetLink
## A link over a WebRTC data channel (netcode spike S4, docs/milestones/netcode-spike.md): one
## channel, ordered and reliable. `NetRtc` makes it once the channel is open and hands it over;
## the sessions know it only as a `NetLink`.
##
## - **No clock, no thread:** the peer is polled when the link is read or asked whether it is
##   open, which the sessions do every physics step.
## - **A message is split** into packets of at most CHUNK bytes and joined again on the other
##   side: browsers and the extension differ in the largest packet a channel takes, and a hash
##   check in a crowd is larger than the smallest of them. Each packet starts with one byte: 1
##   when more of the message follows, 0 on its last.
## - **What arrives is untrusted** like everything else on the wire: a packet that is text, empty,
##   too long, or marked otherwise, a message past `NetMessage.MAX_BYTES`, or MAX_WAITING messages
##   (or MAX_WAITING_BYTES) nobody read close the link. The messages themselves are the sessions' to decode.
## - **Nobody reading:** more than MAX_BUFFERED bytes waiting to leave close it too.

## The most bytes of a message in one packet (16 kB is what every WebRTC stack takes).
const CHUNK: int = 16000
const MAX_WAITING: int = 8192
const MAX_BUFFERED: int = 4 * 1024 * 1024
## The most bytes of whole messages that wait unread, and the most packets taken in one poll (the
## rest wait in the channel for the next: a peer that sent a flood while nobody read cannot make
## one poll long).
const MAX_WAITING_BYTES: int = 8 * 1024 * 1024
const MAX_PACKETS_A_POLL: int = 1024
const _MORE: int = 1
const _LAST: int = 0

var _peer: WebRTCPeerConnection
var _channel: WebRTCDataChannel
var _inbox: Array[PackedByteArray] = []
## The next of `_inbox` to read.
var _next: int = 0
## The packets so far of a message still arriving.
var _partial: PackedByteArray = PackedByteArray()
## Bytes of the whole messages that wait unread.
var _waiting_bytes: int = 0
var _open: bool = true


## Over `channel` of `peer`, which is open.
func _init(peer: WebRTCPeerConnection, channel: WebRTCDataChannel) -> void:
	_peer = peer
	_channel = channel
	_channel.write_mode = WebRTCDataChannel.WRITE_MODE_BINARY


func send(bytes: PackedByteArray) -> void:
	if bytes.is_empty() or not is_open():
		return
	if bytes.size() > NetMessage.MAX_BYTES or _channel.get_buffered_amount() > MAX_BUFFERED:
		close()
		return
	var at: int = 0
	while at < bytes.size():
		var end: int = mini(at + CHUNK, bytes.size())
		var packet: PackedByteArray = PackedByteArray([_MORE if end < bytes.size() else _LAST])
		packet.append_array(bytes.slice(at, end))
		if _channel.put_packet(packet) != OK:
			close()
			return
		at = end


func read() -> PackedByteArray:
	if _next >= _inbox.size():
		_poll()
		if _next >= _inbox.size():
			return PackedByteArray()
	var bytes: PackedByteArray = _inbox[_next]
	_waiting_bytes -= bytes.size()
	_next += 1
	if _next >= _inbox.size():
		_inbox.clear()
		_next = 0
	return bytes


func is_open() -> bool:
	if _open:
		_poll()
	return _open


func close() -> void:
	if not _open:
		return
	_open = false
	_channel.close()
	_peer.close()


## What arrived since the last poll joins the messages waiting; the channel gone, the link is closed
## (what arrived before can still be read).
func _poll() -> void:
	if not _open:
		return
	_peer.poll()
	var taken: int = 0
	while taken < MAX_PACKETS_A_POLL and _channel.get_available_packet_count() > 0:
		taken += 1
		var packet: PackedByteArray = _channel.get_packet()
		if not take_packet(packet, _channel.was_string_packet()):
			return
	if _channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		close()


## One packet off the channel (`text`: it came as text) joins the message it is part of. False,
## and the link closes, when it is out of form or a limit is passed. `_poll` calls it; tests hand
## it what a hostile peer could send.
func take_packet(packet: PackedByteArray, text: bool) -> bool:
	if not _open:
		return false
	if text or packet.size() < 2 or packet.size() > CHUNK + 1 or packet[0] > _MORE:
		close()
		return false
	_partial.append_array(packet.slice(1))
	if _partial.size() > NetMessage.MAX_BYTES or _inbox.size() - _next >= MAX_WAITING or _waiting_bytes + _partial.size() > MAX_WAITING_BYTES:
		close()
		return false
	if packet[0] == _LAST:
		_inbox.append(_partial)
		_waiting_bytes += _partial.size()
		_partial = PackedByteArray()
	return true
