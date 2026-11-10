class_name NetLoopback
extends NetLink
## A link inside one process (netcode spike S2): two ends, what one sends the other reads at once,
## in order. For the tests and the measured grid; no network.
##
##     var ends: Array[NetLoopback] = NetLoopback.pair()
##     ends[0].send(bytes)
##     ends[1].read()   # bytes

## The most messages that wait unread at one end: past it the link closes (nobody is reading).
const MAX_WAITING: int = 8192

var _inbox: Array[PackedByteArray] = []
## The next of `_inbox` to read.
var _next: int = 0
## The other end (weak: the two would keep each other alive).
var _peer: WeakRef = null
var _open: bool = true


## The two ends of a new link.
static func pair() -> Array[NetLoopback]:
	var a := NetLoopback.new()
	var b := NetLoopback.new()
	a._peer = weakref(b)
	b._peer = weakref(a)
	return [a, b]


func send(bytes: PackedByteArray) -> void:
	if not _open or bytes.is_empty():
		return
	var peer: NetLoopback = _peer.get_ref() as NetLoopback if _peer != null else null
	if peer == null or peer.waiting() >= MAX_WAITING:
		close()
		return
	peer._inbox.append(bytes)


func read() -> PackedByteArray:
	if _next >= _inbox.size():
		return PackedByteArray()
	var bytes: PackedByteArray = _inbox[_next]
	_next += 1
	if _next >= _inbox.size():
		_inbox.clear()
		_next = 0
	return bytes


## How many messages wait unread here.
func waiting() -> int:
	return _inbox.size() - _next


func is_open() -> bool:
	return _open


func close() -> void:
	_open = false
	var peer: NetLoopback = _peer.get_ref() as NetLoopback if _peer != null else null
	if peer != null:
		peer._open = false
