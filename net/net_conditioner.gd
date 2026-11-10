class_name NetConditioner
extends NetLink
## A link made worse on purpose (netcode spike S2, docs/milestones/netcode-spike.md): what this
## end sends reaches the link inside it late. Wrap both ends for a round trip.
##
## - **Delay and jitter:** each message waits `delay_ms`, plus up to `jitter_ms` more (its own
##   draw).
## - **Loss:** the link is reliable and ordered, so a lost packet is not gone: it is sent again
##   after `resend_ms` (lost again with the same chance), and everything behind it waits for it.
##   That is what loss costs on a reliable channel, and what the grid measures.
## - **Order:** a message never passes the one before it.
## - **Seeded:** the same seed, clock and sends give the same arrivals.
##
## It runs on the clock it is given (`clock`: milliseconds, any number): a test's steps, or real
## time in the game. It moves what is due whenever this end is called (`send`, `read`,
## `is_open`), so an end that is read every physics step is at most a step late.
##
##     var ends: Array[NetLoopback] = NetLoopback.pair()
##     var slow := NetConditioner.new(ends[0], func() -> float: return steps * 1000.0 / 60.0)
##     slow.delay_ms = 50.0

var inner: NetLink
var clock: Callable
## One way, in milliseconds.
var delay_ms: float = 0.0
var jitter_ms: float = 0.0
## The chance (0 to 1) a message is lost on its way, each time it is sent.
var loss: float = 0.0
## How long until a lost message is sent again.
var resend_ms: float = 200.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## The messages on their way, in order, and when each is due.
var _held: Array[PackedByteArray] = []
var _due: PackedFloat64Array = PackedFloat64Array()


func _init(link: NetLink, on_clock: Callable, with_seed: int = 1) -> void:
	inner = link
	clock = on_clock
	_rng.seed = with_seed


func send(bytes: PackedByteArray) -> void:
	if bytes.is_empty() or not inner.is_open():
		return
	var due: float = _now() + maxf(delay_ms, 0.0)
	if jitter_ms > 0.0:
		due += _rng.randf() * jitter_ms
	if loss > 0.0:
		# Never certain: a link that loses everything is a closed one.
		var chance: float = minf(loss, 0.95)
		while _rng.randf() < chance:
			due += resend_ms
	_held.append(bytes)
	_due.append(due)
	_move()


func read() -> PackedByteArray:
	_move()
	return inner.read()


func is_open() -> bool:
	_move()
	return inner.is_open()


## Closes the link; what was still on its way is lost.
func close() -> void:
	_held.clear()
	_due.clear()
	inner.close()


## How many messages are on their way.
func waiting() -> int:
	return _held.size()


func _now() -> float:
	return float(clock.call()) if clock.is_valid() else 0.0


## Hands the link every message that is due, from the front: one not due yet holds back those
## behind it (the order is kept, as on a reliable channel).
func _move() -> void:
	if _held.is_empty():
		return
	var now: float = _now()
	var moved: int = 0
	while moved < _held.size() and _due[moved] <= now:
		inner.send(_held[moved])
		moved += 1
	if moved == _held.size():
		_held.clear()
		_due.clear()
	elif moved > 0:
		_held = _held.slice(moved)
		_due = _due.slice(moved)
